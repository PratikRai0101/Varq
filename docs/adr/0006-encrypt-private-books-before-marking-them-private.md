# Encrypt private books before marking them private

**Status:** Accepted

## Context

`Book.isPrivate` is a user-facing promise. Setting it before encrypting the managed library copy would leave plaintext readable from the app container and create an unsafe partial state.

## Decision

Coordinate the mark-private UI and encryption as one rollback-capable workflow. File replacement is atomic, but filesystem, Keychain, and SwiftData operations do not share a transaction:

1. Generate a unique symmetric key per book.
2. Store it in Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and biometric access control.
3. Encrypt the managed library file with AES-GCM into a temporary sibling file.
4. Atomically replace the plaintext managed file with the encrypted file.
5. Set `Book.isPrivate = true` only after the replacement succeeds and save SwiftData.

Opening a private book authenticates through `BiometricGateService`, retrieves its key, decrypts the managed ciphertext into a session temporary directory, and removes that plaintext at reader close. It is never copied back into the managed library.

If marking private fails before the database save, Varq restores the original plaintext and public flag when rollback succeeds. A failed file rollback keeps the in-memory private flag and its key rather than presenting encrypted content as public. If decryption succeeds but removing the key fails, the flag is public and the cleanup failure is reported. Both the original failure and any rollback failure are surfaced; rollback is not silently assumed to succeed.

Unmarking private authenticates, decrypts the managed file, and saves the public flag before removing its Keychain key. If saving fails, the flag is restored and the managed file is re-encrypted with the retained key. If re-encryption also fails, both errors are reported and the key is retained for recovery. A key-removal failure after a successful save leaves the book public and reports that cleanup remains incomplete.

These guarantees cover synchronous operation failures while the app is running. They do not provide crash recovery or recovery from failed filesystem rollback. A persistent operation journal and startup reconciliation remain required follow-up work.

## Consequences

- Successful protection changes keep the private flag consistent with the managed file. A failed rollback is reported as needing recovery, not treated as a completed protection change.
- Reader URL plumbing must become session-aware before private books are opened.
- Private-book operations require integration tests for save, rollback, and key-cleanup failures and a manual security review before release.
- Private-book persistence exposes an injectable save boundary so failure paths can be tested with real encryption and SwiftData models without requiring a damaged database.
