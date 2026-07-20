# Store imports in the managed library

**Status:** Accepted

Varq copies every imported book into its managed library and persists only that copy's relative path. Security-scoped access is used transiently while importing, not stored for later use; this prevents an original file being moved or deleted from breaking a library entry and keeps all subsequent book access inside the App Sandbox.

## Considered options

- Persist a security-scoped bookmark for the original file: rejected because Varq already owns a managed copy and external-file availability would still be fragile.
