# Encrypt private books before marking them private

**Status:** Accepted

## Context

`Book.isPrivate` is a user-facing promise. Setting it before encrypting the managed library copy would leave plaintext readable from the app container and create an unsafe partial state.

## Decision

Treat the mark-private UI and encryption as one atomic workflow:

1. Generate a unique symmetric key per book.
2. Store it in Keychain with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and biometric access control.
3. Encrypt the managed library file with AES-GCM into a temporary sibling file.
4. Atomically replace the plaintext managed file with the encrypted file.
5. Set `Book.isPrivate = true` only after the replacement succeeds and save SwiftData.

Opening a private book authenticates through `BiometricGateService`, retrieves its key, decrypts the managed ciphertext into a session temporary directory, and removes that plaintext at reader close. It is never copied back into the managed library.

If any step fails, the workflow leaves `isPrivate` false and preserves or restores the original plaintext file. Unmarking private performs the inverse operation only after authentication.

## Consequences

- A private flag cannot exist without a protected managed file.
- Reader URL plumbing must become session-aware before private books are opened.
- Private-book operations require integration tests for rollback paths and a manual security review before release.
