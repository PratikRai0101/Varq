# Journal managed-book imports

**Status:** Accepted

## Context

A managed copy and a SwiftData `Book` cannot be created in one atomic transaction. Previously interrupted copies could leave untracked files, and failed database saves attempted another best-effort save and silently ignored file cleanup errors. Importing metadata and hashes from a separately changing original could also produce an inconsistent saved book.

## Decision

`ImportService` writes a versioned, checksummed ownership record before creating a managed copy. Records live at `Library/.book-imports/<book ID>/record.json` and contain only version, preassigned book ID, supported format, SHA-256 source hash, and checksum. Filenames are derived from the ID and format, not accepted as arbitrary paths. Directories are `0700`, record files `0600`; managed public books remain protected by the containing sandbox-owned directory. No external path, title, text, or key is stored in the record.

1. Hold transient source access (and the enclosing folder grant for folder batches), hash the original, and write the record before copying.
2. Copy into the managed filename and verify its hash against the record. Parse metadata from that verified snapshot, with the original display filename retained only as a metadata fallback. Changed/partial copies are not guessed at or silently deleted.
3. `ImportViewModel` saves pending caller edits before touching files. Each insertion uses a fresh autosave-disabled context, the recorded book ID, and committed-row duplicate detection. Failed insertion contexts are discarded; never roll back the caller or save a deletion of the temporary book in its context.
4. After insertion commits, keep the verified file and finish journal cleanup. A thrown save triggers a fresh committed-row check before abandonment: any reference by ID or path preserves the copy for reconciliation. Only known row absence permits duplicate/failed-insertion cleanup.
5. Abandonment verifies the copy, moves it to the transaction's `payload`, then atomically renames the transaction directory to `.completed-<book ID>` before recursive deletion. Successful insertion uses the same marker for metadata-only cleanup. Interrupted recursive deletion can therefore resume even if `record.json` has already disappeared.

Parser/copy failures also attempt verified cleanup and report both operation and cleanup errors. A cleanup failure after a successful save never undoes that save or deletes its referenced file. The immutable filesystem journal adapter can be used by the import actor and startup recovery; the app serializes access rather than advertising independent-process transactions.

## Recovery and coordination

The app-shared `PrivateBookViewModel` reconciles imports against fresh committed-row snapshots before deletion and protection recovery. A single matching public row (ID, filename, and hash) retains the verified file. Row absence removes only the verified transaction-owned copy. Conflicting ownership, private flags, corrupt metadata/checksums, unsupported versions, unknown entries, unsafe paths, or changed/missing committed content preserve unresolved artifacts and keep library/import/export access blocked.

Only `.book-imports` is scanned. Unmarked legacy managed files are not swept. Empty UUID allocation directories with no matching committed row may be removed; incomplete nonempty records remain unresolved. Completed markers validate their known entries and cannot discard a payload if its book ID survives.

One `ImportViewModel` serializes file, folder, and dropped-file batches. Overlapping requests are explicitly reported as busy, without resetting the active batch's results. Any pending recovery halts the remainder of a batch and immediately closes the shared gate via the app's recovery callback; dismissing the per-file alert cannot dismiss that diagnosis. After successful recovery, the next batch checks the journal and clears its local recovery state.

The app wires an import-activity check into the recovery gate. Another window's startup task or Retry must not classify an in-flight import as a crash. This coordination covers the normal shared app instance; no new entitlements, bookmarks, or external filesystem permissions are added.

## Limits and verification

- These are process-interruption guarantees at recorded boundaries, not fsync/power-loss or disk-failure guarantees, secure erasure, or protection against malicious sandbox rewriting. Checksums detect accidental corruption, not authenticity.
- Unknown partial copies deliberately block recovery. Retry does not invent their contents or delete unrecognized bytes. An operator must preserve and inspect the artifacts and restore a demonstrably matching copy/state before retrying; automatic reconstruction from an external original is not performed.
- Independent app processes or external filesystem mutation during validation are not transaction guarantees. Legacy orphan cleanup and database migrations remain separate work.
- Unit tests simulate restart boundaries and injected copy/save/cleanup failures with real permissively licensed EPUB/PDF fixtures. They cover committed-row reconciliation, false-success uncertainty, artifact/unknown-state preservation, busy batches, and a second window's recovery task during a paused copy. They do not prove actual force-quit timing or the normal app's chooser grant.

**Manual before release:** Import nested public EPUB/PDF/CBZ fixtures in the signed app. Force quit after record creation, during copy, after copy but before insertion save, after save but before journal cleanup, and during cleanup. Relaunch: recognize clean absent-row states, retain committed copies, and block unknown partial content without touching originals or unrelated artifacts. Open another window during import and confirm it does not reconcile the active transaction. Trigger a save/cleanup failure and verify every window blocks, dismiss the alert, repair the known failure and Retry. Verify overlapping selections get a clear busy result, and pending edits/notes on other books remain intact. Record outstanding manual checks separately from unit/UI launch-suite results.
