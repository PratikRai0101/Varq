# Signed private-reader cleanup verification

Run from the repository root on a Mac with Xcode and working development signing:

```sh
scripts/verify-private-reader-cleanup.sh
```

The script first builds Varq normally. It needs a wildcard Mac development profile containing that build's signing certificate. If automatic signing reports a stale certificate/profile mismatch, refresh provisioning with `xcodebuild -scheme Varq -destination 'platform=macOS' -allowProvisioningUpdates build`, then retry. The verification script itself does not refresh provisioning, create certificates, change teams, or alter entitlements in the project.

## What it verifies

The script builds a separate, verification-only app (`dev.pratikrai.Varq.ReaderSessionVerification`) from the current production `ReaderSessionStorageService`, `PrivateBookCryptoService`, `EpubPublicationService`, and `CbzPublicationService`. It uses the project's existing ZIPFoundation checkout and bundles the repository's original, permissively licensed EPUB/PDF/CBZ fixtures. It never launches or kills the normal Varq app and cannot touch its library through the verification app's sandbox.

Every probe invocation must receive a sandbox permission-denied error when reading a host-created canary outside its container. This prevents an accidentally unsandboxed run from passing. A negative-control run with the sandbox entitlement removed was confirmed to fail before reader storage is touched.

1. Start two independently signed, sandboxed processes. Each generates in-memory AES-GCM keys, encrypts three managed fixture copies, decrypts them into leased reader directories, and extracts the EPUB and CBZ using the production services. PDFKit must open the decrypted PDF.
2. Run cleanup in a third sandboxed process. Both live readers' directories and plaintext hashes must survive; all managed ciphertext hashes must remain unchanged.
3. Send `SIGKILL` to only the first verification process and relaunch cleanup. Every decrypted copy and complete extraction directory from that owner must disappear. The second process's files must remain intact; neither managed ciphertext may change.
4. Kill the second verification process and relaunch cleanup. Its abandoned files must also disappear. Delete the isolated run's managed fixtures and evidence.

For the normal signed Xcode suite, a serial run avoids overlapping test runners and UI activation timeouts observed during parallel verification:

```sh
xcodebuild -scheme Varq -destination 'platform=macOS' -parallel-testing-enabled NO test
```

The expected final line from the probe is:

```text
PASS: signed sandbox forced-quit cleanup verification
```

The script kills only its own recorded child PIDs. Cleanup runs on exit, including after failures. Failures retain the temporary build/log artifacts and print their location; successful runs remove them unless `VARQ_KEEP_VERIFICATION_ARTIFACTS=1` is set. An interrupted verification may leave fixture-only data in the verification app's container; a subsequent run sweeps abandoned leased owners. This is not user-library data.

## Coverage limits and remaining manual checks

This validates the signed sandbox and process-interruption storage boundary, not the entire UI authentication workflow. Keys are generated in memory for fixtures; the probe neither bypasses nor exercises production Touch ID/password authentication. Real-Keychain and UI launch tests are covered separately by the normal signed Xcode suite.

Before release, manually open private EPUB/PDF/CBZ books in the normal signed app, authenticate normally, force quit, and relaunch. Confirm reading-position restoration and rendering after cleanup. Protection-journal interruption, recovery diagnostics/retry, and blocking across two real production UI windows are now separately verified in `protection-recovery.md`. This reader-session probe does not cover those paths or replace the remaining manual authentication smoke checks.

Legacy unmarked temporary folders, malicious sandbox rewriting, OS-managed caches, secure erasure, and disk/power failure remain outside the storage guarantee documented in ADR 0006.
