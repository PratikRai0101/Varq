# Encrypt private books before marking them private

**Status:** Accepted

## Context

`Book.isPrivate` is a user-facing promise. Setting it before encrypting the managed library copy would leave plaintext readable from the app container and create an unsafe partial state.

## Decision

Coordinate the mark-private UI and encryption as one rollback-capable workflow. File replacement is atomic, but filesystem, Keychain, and SwiftData operations do not share a transaction:

1. Generate a unique symmetric key per book and prepare AES-GCM ciphertext in memory.
2. Write a versioned recovery record before changing Keychain or the managed file. Record the book ID, managed filename, original private flag, and SHA-256 hashes of both file states; include a checksum of the metadata.
3. Store the key in Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and biometric access control.
4. Stage ciphertext in the tracked recovery directory and atomically replace the plaintext managed file, retaining the replacement's restrictive permissions.
5. Set `Book.isPrivate = true` only after replacement succeeds and save SwiftData.
6. Atomically rename the transaction directory to a completed marker, then remove it. A cleanup error does not roll back a successful database save.

Opening a private book authenticates through `BiometricGateService`, retrieves its key, decrypts the managed ciphertext into a session temporary directory, and removes that plaintext at reader close. It is never copied back into the managed library.

If marking private fails before the database save, Varq restores the original plaintext and public flag when rollback succeeds. A failed file rollback keeps the in-memory private flag and its key rather than presenting encrypted content as public. If decryption succeeds but removing the key fails, the flag is public and the cleanup failure is reported. Both the original failure and any rollback failure are surfaced; rollback is not silently assumed to succeed.

Unmarking private authenticates and prepares plaintext in memory. It journals the change before replacing the managed file, then saves the public flag before removing its Keychain key. If saving fails, the flag and exact original ciphertext are restored; the original bytes keep the journal's hashes valid during rollback. If restoring the file also fails, both errors are reported and the key is retained for recovery. A key-removal failure after a successful save leaves the book public and reports that cleanup remains incomplete.

## Restart recovery

`PrivateBookRecoveryJournalService` owns `Library/.private-book-recovery/<book ID>/record.json` and a tracked `replacement` file. Transaction directories use owner-only permissions (`0700`); metadata and replacement files use `0600`. The record contains neither keys nor book text. Unprotect can temporarily stage plaintext, but there is no extra original plaintext backup.

Before enabling the library, the app-shared `PrivateBookViewModel` reads pending records and compares each managed file with the recorded original/changed hashes. It adopts whichever verified state exists, saves the matching flag, and only then removes an unused key for a public file and completes the journal. Encrypted files retain their keys. This reconciliation does not authenticate or decrypt books, so startup does not prompt for Touch ID.

An uncommitted replacement is removed only after verifying the managed copy. `.completed-<book ID>` directory names are atomic completion markers, allowing restart to finish interrupted recursive cleanup even if the record itself has already been deleted. Empty transaction directories left before record creation can also be removed safely.

Save or key-cleanup failures retain pending recovery state for retry. Missing files, unknown content hashes, damaged/unsupported records, unsafe paths, and missing library entries block reading, library mutations, and exports in all windows. When the managed source is missing or unrecognized, staging is preserved rather than discarded. The recovery screen keeps its diagnosis when an alert is dismissed.

## Reader-session cleanup

`ReaderSessionStorageService` allocates decrypted book copies and EPUB/CBZ extraction trees under the sandbox temporary directory's `Varq/ReaderSessions` namespace. The shared storage service holds an exclusive kernel lease on `<owner UUID>/lease.lock` for the application process lifetime. Directories use `0700`; leases and decrypted book files use `0600`. No key or book identifier is written into lease metadata. Default EPUB views use a nonpersistent WebKit website data store.

Before journal reconciliation or library access, startup attempts cleanup under a nonblocking coordinator lock. It skips owners whose leases are held, including other running app processes. After acquiring a stale owner's lease, it atomically renames that directory to `.discarded-<UUID>` before recursive deletion; the marker permits retry even if the lease file has already been removed. Empty owners left before lease creation are safe to remove because creation is serialized and no book content is written before acquiring the lease.

Unknown entries, missing leases in nonempty directories, unsafe paths, and I/O failures preserve unresolved artifacts and block startup through the existing shared recovery screen. Reader-close deletion failures remain tracked and are retried before more temporary files can be allocated. Renderer close remains nonthrowing; a failed release is reported by the next allocation or startup cleanup rather than silently forgotten. Legacy UUID directories outside this new owned namespace lack reliable ownership markers and are deliberately not bulk-deleted.

The repeatable signed-sandbox forced-quit probe and its remaining UI/authentication coverage limits are documented in `docs/verification/private-reader-cleanup.md`.

## Limits

- File replacement and journal completion markers are atomic operations, not a single transaction across filesystem, Keychain, and SwiftData. Recovery covers app-process termination at journaled boundaries; it is not a guarantee against disk failure or sudden power loss.
- The unkeyed metadata checksum detects accidental damage, not malicious rewriting by an attacker with access to the app sandbox.
- Deleted or unrecognized content is not reconstructed automatically, and unjournaled legacy inconsistencies are not inferred from filenames or extensions.
- Reader-session cleanup is separate from protection-transition recovery. It covers process interruption for files created in the leased namespace, not legacy unmarked files, malicious sandbox rewriting, secure erasure, OS-managed caches, disk failure, or sudden power loss.

## Consequences

- Successful protection changes keep the private flag consistent with the managed file. A failed rollback is reported as needing recovery, not treated as a completed protection change.
- Reader URL plumbing and archive extraction must remain session-aware; new reader caches must use the leased storage allocator rather than arbitrary temporary directories.
- Private-book operations require integration tests for save, rollback, key-cleanup, and restart boundaries, plus a signed sandboxed manual security review before release.
- Private-book persistence exposes an injectable save boundary so failure paths can be tested with real encryption and SwiftData models without requiring a damaged database.
