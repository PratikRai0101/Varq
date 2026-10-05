# Signed EPUB HTTP/HTTPS isolation verification

From the repository root:

```sh
scripts/verify-epub-network-isolation.sh
```

Requires macOS, Xcode, Python 3, OpenSSL, and working development signing with the existing wildcard profile. No third-party Python modules, UI automation permission, external endpoint, provisioning changes, or installed certificate are required.

## What runs

The script builds Varq normally, then compiles the current production `EpubWebRenderer`, `EpubWebIsolationService`, publication parser, private-session/crypto/storage services, reader contracts, models, and design tokens into a separate native application: `dev.pratikrai.Varq.EpubNetworkVerification`. It uses the existing ZIPFoundation checkout, the existing signing identity/profile, and App Sandbox with outbound networking already present in Varq. It never launches, kills, or reads the ordinary Varq application/library and does not change shipping code, entitlements, ATS policy, or system trust settings.

Two host-side servers bind only to `127.0.0.1` on dynamically allocated ports: HTTP and HTTPS. They record request method, scheme, and path in JSON lines. The script generates three original adversarial EPUBs with identical content and distinct `control`, `public`, and `private` URL prefixes. No copyrighted book, font, or illustration is used. The tiny embedded font contains an original rectangular A glyph; fixture generation needs only Python's standard library.

The signed app hosts real WebKit views in native windows. The public path opens an EPUB normally. The private path encrypts its managed fixture, obtains a decrypted reader URL through the production `PrivateBookSessionService`, and opens that URL through the same production renderer. The fixture key-store adapter supplies in-memory keys without authentication; the probe neither retrieves real private-book keys nor simulates a Touch ID approval.

## Controls that prevent false passes

- **Sandbox:** Every signed probe invocation must receive an outside-container canary read-denial error. An otherwise signed control without App Sandbox must fail specifically because it can read that canary, before any reader work.
- **Real HTTP and HTTPS availability:** An unhardened WebKit view must reach all 19 resource/action request classes on each server. A missing positive-control request makes the whole command fail, even if hardened request counts are zero.
- **TLS cannot mask missing isolation:** A verification-only navigation delegate trusts only the exact ephemeral DER certificate bundled for `127.0.0.1`. All hardened navigation decisions and completion/failure callbacks are forwarded unchanged to the real `EpubWebRenderer`. Both unhardened and hardened views use this identical certificate pin. There is no system trust installation, general certificate-error override, or shipping delegate change.
- **ATS cannot mask missing isolation:** The verification bundle deliberately permits arbitrary WebKit transport loads. The production app's plist is untouched. Resource rules/navigation policy—not ATS rejection—must prevent the controlled loads.
- **Red-capable observer:** After saving the passing request log, the app deliberately opens the public/private fixtures in unhardened views. The same server checker must then fail specifically for observed public/private requests. The script fails if that deliberately leaky run is accepted.

## Checked request classes

Each server must observe these in the unhardened control:

1. Remote stylesheet and its nested CSS import.
2. Remote font referenced by that stylesheet.
3. A remote import, font, and background image referenced directly by an otherwise local stylesheet. This verifies those loads independently of blocking the top-level remote stylesheet.
4. Remote image and image redirect/redirect target.
5. Remote script and script-originated image beacon.
6. Inline-script and body-event image beacons.
7. Remote frame and its nested image beacon.
8. External frame-targeted and main-frame links.
9. Form submission with fixture-only text.
10. Main-frame meta-refresh navigation from two local spine chapters, one per scheme.

Together these produce 19 distinct endpoint classes per transport. For hardened public and private paths, **zero requests with either fixture prefix may reach either server**. The checker includes query strings and methods in retained evidence; neither fixture contains user text.

The probe also attempts remote new-window links, a `javascript:` URL, and an outside-root file link. These must leave the current spine URL unchanged. Known note IDs must still activate through the native note handler.

## Offline reader checks

For both public and private paths:

- Inline, local-file, remote, event-handler, and URL author scripts must not mutate the fixture DOM.
- Local CSS and a nested local CSS import apply correctly.
- The original local font loads; local and data-URL images decode.
- Trusted chapter-text extraction and pagination styling work.
- Highlight insertion and known-note activation work.
- Forward/back pagination and local chapter navigation work; meta redirects do not escape.
- Close/reopen and viewport reflow retain readable local content.
- The private managed ciphertext remains byte-for-byte unchanged; session close removes its decrypted reader copy.

Interactions are driven through the trusted client content world and production renderer APIs, not the SwiftUI toolbar or physical mouse/keyboard events. The probe uses the renderer's injected WebKit-view constructor, not the shipping `ReaderWebView` context-menu subclass. It therefore does not claim end-to-end context-menu, library, or authentication coverage.

## Recorded result

Verified on **2026-10-05**, macOS **27.0 (26A428)** and Xcode **27.0 (27A266a)**:

```text
PASS: unsandboxed negative control rejected
PASS: public offline assets, navigation, annotations, reflow, and session cleanup
PASS: private offline assets, navigation, annotations, reflow, and session cleanup
PASS: unhardened HTTP control observed all 19 request classes
PASS: unhardened HTTPS control observed all 19 request classes
PASS: zero public/private EPUB HTTP/HTTPS requests reached either server
PASS: deliberate unhardened public/private leak control makes the observer fail
PASS: signed sandbox EPUB HTTP/HTTPS isolation verification
```

The retained passing log had 49 control requests per transport, and no public/private requests. The deliberate leak run subsequently produced 49 requests for each public/private prefix per transport; the checker rejected it. Raw request counts can vary with scheduling/reloads—the assertion is all required positive classes plus zero hardened requests, not these exact counts.

Also passed:

```sh
bash -n scripts/verify-epub-network-isolation.sh
xcodebuild -scheme Varq -destination 'platform=macOS' build
xcodebuild -scheme Varq -destination 'platform=macOS' -parallel-testing-enabled NO test
```

The full suite passed 219 Swift Testing tests and four XCTest UI tests.

## Artifacts, cleanup, and limits

Set `VARQ_KEEP_VERIFICATION_ARTIFACTS=1` to retain the temporary signing/build logs, probe output, generated original books, temporary TLS certificate/key, and request evidence. `isolated-requests.jsonl` contains only the passing run; `requests.jsonl` additionally includes the deliberate leak control. `leak-verdict.log` records its expected rejection. Failures also retain artifacts and print their location.

The script terminates only its recorded probe/watchdog/server PIDs. Ordinary successful exit removes generated reader/session files and host artifacts. A watchdog/SIGKILL or forcibly interrupted orchestrator may leave fixture-only files in the dedicated verification container; these are not user-library data, and this network check does not promise crash cleanup of its own arbitrary harness directory. Production leased-reader crash cleanup is separately verified in `private-reader-cleanup.md`.

This observes HTTP/HTTPS requests to controlled loopback endpoints. It does not measure every DNS lookup, speculative connection, macOS/WebKit background operation, arbitrary destination/protocol, engine exploit, secure erasure, or power/disk failure. Archive path/size validation remains a separate boundary.

**Remaining release smoke checks:** Use the normal signed app with representative legitimate EPUBs to check layout and real mouse/keyboard/context-menu interactions. Exercise private books with genuine Touch ID/password authentication and cancellation. Remote-only or script-dependent content must not acquire an online fallback. These manual user-experience checks are not claimed by the automated signed production-reader harness; its controlled HTTP/HTTPS fixture inspection is complete.
