# Signed protection-change recovery and two-window verification

Run from the repository root:

```sh
scripts/verify-protection-recovery.sh
```

Requires Xcode, working development signing with the existing wildcard profile, and Accessibility/Automation permission for the invoking terminal or agent to control System Events. The script does not create certificates, refresh provisioning, change project entitlements, or grant UI automation permissions. Do not run concurrent copies: the verification bundle identifier intentionally has one isolated container.

## Isolation and pass/fail signal

The script builds Varq, copies the production application into a temporary bundle, and signs that copy as `dev.pratikrai.Varq.ProtectionVerification`. A verification-only executable with the same identifier/signature uses that isolated container. It compiles the current production SwiftData models, `PrivateBookViewModel`, and crypto, Keychain, protection-journal, reader-session, deletion, and import-recovery services without modifying their source. Neither verification source is linked into a shipping target.

Every probe invocation must receive a permission-denied error when reading a host-created canary outside its container. A separately signed negative control without the sandbox entitlement must fail specifically because it can read that canary, before accessing a database or library. The UI copy is also signed with App Sandbox; its entitlements are narrower than the shipping app's. It is launched through LaunchServices with saved-window restoration disabled.

The regular Varq application is never launched or killed. Only recorded verification PIDs are terminated. Fixture books use newly generated UUIDs; cleanup removes only keys belonging to fixture rows in this dedicated container. Keys are stored with the production Keychain service and access control. Existence checks request no secret data and disable authentication UI. The query explicitly selects the data-protection Keychain: a matched protected item may return `errSecInteractionNotAllowed` for an attributes-only request, whereas a nonexistent UUID must return `errSecItemNotFound`. Both positive and nonexistent-item controls run before interruption.

## Crash-boundary coverage

The probe constructs fixture-only interruption states with the production journal, atomic replacement, AES-GCM, Keychain storage/removal, and on-disk SwiftData APIs. It flushes a `READY` marker, then the script sends `SIGKILL`. A fresh process uses the production recovery view model; a second fresh recovery process checks idempotency. Each checks exact managed-file hash, committed private flag, expected Keychain retention/removal, and removal of journal/staging/completion artifacts.

| Interrupted boundary | Recovered flag | Key |
| --- | --- | --- |
| Protect: record written, before key storage | Public | Absent |
| Protect: key stored, before file replacement | Public | Removed |
| Protect: ciphertext replaced, before database save | Private | Retained |
| Protect: private flag saved, before journal cleanup | Private | Retained |
| Unprotect: record written, before replacement | Private | Retained |
| Unprotect: plaintext staged, before replacement | Private | Retained; staged plaintext removed |
| Unprotect: plaintext replaced, before database save | Public | Removed |
| Unprotect: public flag saved, before key deletion | Public | Removed |
| Unprotect: key deleted, before journal cleanup | Public | Absent |

These are deterministically prepared process-termination states, not timing-dependent attempts to kill the production UI inside an authentication callback. The fixture is the repository's first-party `minimal.epub`; the protection transaction itself is format-independent. Unprotect preparation uses known fixture plaintext without retrieving an authenticated key. There is no key written into the evidence files.

## Real two-window checks

1. Prepare an interrupted protection change, then replace its managed payload with unknown fixture bytes and kill the producer.
2. Verify recovery refuses to guess: the bytes, original database flag, Keychain item, and blocking diagnosis survive. Dismissing the error does not clear the diagnosis.
3. Launch the separately signed **production UI copy**. Its real `LibraryView` must display the recovery heading without the library toolbar.
4. Use File → New Window. Both real windows must show recovery rather than the library. Retry while the content remains unknown must leave both blocked.
5. Restore only the fixture's recorded, hash-verified ciphertext. Click Retry in one window. Both windows must replace recovery with the library toolbar, proving the app-shared recovery model releases both gates.
6. Terminate the isolated UI and inspect the committed database/file/key/journal state from a fresh probe. Run recovery again to check idempotency.

The AX checks use the recovery heading and library-toolbar presence because this SDK exposes some SwiftUI button labels as attributed AX descriptions not readable by System Events. The driver clicks only the sole button inside the recovery content group, after confirming that screen. It reacquires window references when titles change.

## Recorded result

Verified on **2026-10-04**, macOS **27.0 (26A428)**, Xcode **27.0 (27A266a)**:

```text
PASS: unsandboxed negative control rejected before accessing verification data
[all nine interruption boundaries pass twice]
PASS: both real windows block library access and failed Retry stays blocked
PASS: successful Retry in one real window releases both libraries
PASS: UI recovery persisted the expected state
PASS: signed sandbox protection interruption recovery and two-window UI blocking/retry
```

Also passed:

```sh
bash -n scripts/verify-protection-recovery.sh
xcodebuild -scheme Varq -destination 'platform=macOS' build
xcodebuild -scheme Varq -destination 'platform=macOS' -parallel-testing-enabled NO test
```

The full suite included 219 Swift Testing tests and four XCTest UI tests. Existing recovery tests cover injected save/key-cleanup errors and retry paths beyond the process-boundary probe.

Failures retain build, signing, probe, and UI logs. Successful runs remove temporary artifacts unless `VARQ_KEEP_VERIFICATION_ARTIFACTS=1` is set. The fixture database/container may remain, but fixture rows, managed files, transaction staging, and keys are removed by reset. If the orchestrating script itself is forcibly killed, a verification process or fixture may remain; stop only the dedicated verification application before retrying. The script refuses to prepare a new fixture over existing book rows rather than absorbing unknown state.

## Remaining release smoke checks and limits

Manually authenticate a private EPUB/PDF/CBZ in the normal signed app, read it, force quit, relaunch, and verify rendering/position restoration. Exercise mark/unmark with genuine Touch ID/password prompts and cancel authentication. This probe verifies storage/recovery and real two-window gates, not the authentication experience or key retrieval/decryption across a biometric prompt. It does not bypass authentication, promise secure erasure, test arbitrary power/disk failures, or test simultaneous independent app instances editing the same library. Separate reader-session cleanup coverage lives in `private-reader-cleanup.md`; EPUB network inspection remains in ADR 0012.
