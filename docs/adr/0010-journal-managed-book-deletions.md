# Journal managed-book deletions

**Status:** Accepted

## Context

Deleting a SwiftData `Book` cascades to notes, highlights, and progress. Removing its managed file and private Keychain key is not part of that database transaction. Previously the view ignored both save and file-removal errors, so metadata could disappear while file cleanup failed, or a failed save could still be followed by irreversible file removal.

## Decision

`LibraryViewModel` orchestrates deletion through `BookDeletionService`:

1. Save pending edits in the caller's context before changing files. If this fails, leave the book, artifacts, file, and unrelated edits intact.
2. Fetch the committed book in a separate, autosave-disabled `ModelContext`. Reject duplicate IDs, shared managed-file paths, unsafe paths, and unresolved protection changes.
3. Write a checksummed version-1 record at `Library/.book-deletions/<book ID>/record.json`. Record only the book ID, managed filename, private flag, and SHA-256 file hash. Use `0700` directories and `0600` metadata; the payload is protected by its containing directory.
4. Move the exact managed file to the transaction's `payload` on the same filesystem. The journal is written first; a crash before the move leaves a recognizable original-file state.
5. Delete the isolated database book and save, allowing normal cascade rules to remove its reading artifacts. On save failure, discard that isolated context and restore the verified file. Never roll back the caller's context. Explicit isolated-context rollback was found to crash SwiftData's related-model snapshot creation on the development SDK; the preservation tests cover discarding it instead.
6. Only after the database save commits, verify the payload, remove a private key if applicable, atomically rename the transaction directory to `.completed-<book ID>`, then recursively remove it. Post-save cleanup errors never recreate an already-deleted book; they retain recovery state and are reported as incomplete cleanup.

## Restart and failure recovery

Before enabling the library, the app-shared `PrivateBookViewModel` reconciles deletion records against committed rows in a fresh context, before protection-journal recovery. A surviving matching book means the file must be restored. An absent book means the user-requested deletion committed and cleanup must finish. A conflicting ID, filename, private flag, unknown content hash, damaged record, unsafe path, or I/O failure preserves unresolved artifacts and keeps the shared library/import/export gate closed.

Runtime rollback or cleanup failures also close that shared gate across windows. Dismissing the deletion alert cannot dismiss the recovery diagnosis; Retry re-runs reconciliation. Completion markers allow recursive cleanup to resume even after metadata has been removed. A completed marker containing a payload is preserved if its book ID still survives.

No deletion recovery decrypts files or requests book keys. Key removal is idempotent through the Keychain adapter. Private ciphertext and its key remain intact until database deletion has committed. Missing managed files are reported rather than silently erasing their notes and progress.

## Limits

- Filesystem, SwiftData, and Keychain still do not share one atomic transaction. The guarantee covers app-process interruption at recorded boundaries, not sudden power loss, disk failure, secure erasure, or malicious rewriting of the sandbox. The checksum is not authentication.
- Calls are synchronous on MainActor within the normal single application process. Concurrent mutations of the same library by independent app processes are not an advertised transaction guarantee.
- Active reader-session caches remain governed by reader close and leased-session cleanup; deletion does not promise immediate secure erasure of memory or open-reader copies. Verify the normal app's open-reader behavior before release.
- Simulated restart/failure tests cover the service and ViewModel boundaries. Signed UI force-quit checks around database commit, recovery diagnostics, and multiple windows remain release verification work; basic UI launch tests alone do not certify these flows.

## Manual UI verification

Delete public and private fixture books and confirm their cards, notes, highlights, and progress disappear without changing other books. Test an unavailable managed file and confirm the book remains with a visible error. Interrupt a staged deletion before and after database save; relaunch and confirm restore versus cleanup follows the committed row, without authentication. Trigger cleanup failure, confirm every window blocks library access, dismiss the alert, then retry after repairing the failure. Check deletion while another window has that book open and record any reader/progress-save issue separately.
