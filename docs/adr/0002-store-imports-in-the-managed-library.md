# Store imports in the managed library

**Status:** Accepted

Varq copies every imported book into its managed library and persists only that copy's relative path. Security-scoped access is used transiently while importing, not stored for later use; this prevents an original file being moved or deleted from breaking a library entry and keeps all subsequent book access inside the App Sandbox.

## Folder imports

`FolderImportService.withBooks` holds the chosen folder's transient security-scoped grant through both recursive discovery and all awaited child imports. Child URLs cannot be assumed to carry their own grant. A false `startAccessingSecurityScopedResource` result does not by itself mean access was denied (sandbox-owned files may require no grant); filesystem errors determine whether discovery can proceed. Only successful starts are balanced with stops, including when discovery or the batch callback throws.

Discovery accepts regular EPUB/PDF/CBZ files and reports unreadable branches while continuing with readable siblings. It does not follow symbolic-link files or directories, including a linked root. Those skipped links are reported rather than silently broadening the folder grant. Directories named like books are not treated as book files. Hidden files remain subject to the same rules; no external original is moved or removed. Candidate paths are sorted for repeatable batch order.

`ImportViewModel` appends discovery failures to per-file parse/duplicate/save errors after the batch completes; readable books can succeed independently. The folder picker selects exactly one directory, not an arbitrary first item from a multi-selection. No new entitlements or persistent external-file bookmarks are needed.

Folder discovery covers access lifetime and partial failures, not crash-safe persistence or filesystem races caused by external mutation. `ImportViewModel` now serializes batches and coordinates journaled copy/save/cleanup recovery separately; see `docs/adr/0011-journal-managed-book-imports.md`. Unit tests use real, permissively licensed EPUB fixtures and injected OS enumeration failures. They do not certify a system folder chooser's grant in the signed sandbox; that remains a manual check.

**Manual verification:** In the signed app, choose a folder outside the app container with nested EPUB/PDF/CBZ files; confirm every readable book imports and reopening uses only managed copies. Include a duplicate, malformed book, unreadable branch, and symbolic links to external books/folders; confirm readable siblings import, failures appear together, and external sources remain unchanged. Verify the folder picker cannot select files or multiple folders. Test an empty folder and a folder removed or made unreadable before discovery. Actual permission/grant behavior needs this system-chooser check, not just fixture unit tests.

## Considered options

- Persist a security-scoped bookmark for the original file: rejected because Varq already owns a managed copy and external-file availability would still be fragile.
