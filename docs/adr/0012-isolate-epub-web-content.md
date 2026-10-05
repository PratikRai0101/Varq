# Isolate EPUB web content

**Status:** Accepted

## Decision

Treat an EPUB as offline, untrusted publication data, not a web application. `EpubWebIsolationService` requires a nonpersistent `WKWebsiteDataStore` and installs a compiled content-rule list before any book document is loaded. The list blocks resource schemes by default and exempts only local `file:` resources. WebKit handles embedded `data:` resources separately; they do not contact a server. Failure to prepare the policy fails the open operation, rather than loading unfiltered content.

The renderer sets `WKWebpagePreferences.allowsContentJavaScript = false` for navigation. Inline scripts, referenced scripts, event handlers, and `javascript:` book URLs must not execute. Varq's native pagination, selection, highlights, note markers, and chapter-text calls use `WKContentWorld.defaultClient`, rather than sharing page-world globals with author code. Content worlds share the DOM; they are not separate documents or a replacement for disabling author scripts.

Navigation is limited to main-frame spine files whose resolved paths remain inside the extracted publication root. Remote URLs, other file destinations, new windows, and subframes are cancelled. Blank navigation is allowed only to clear a closed reader. Note activation accepts only a known stored note ID in the main frame. Native navigation completions are matched to their `WKNavigation` object so a cancelled foreign navigation or close cannot satisfy a different pending chapter load.

Local CSS, images, and embedded data resources remain readable through `loadFileURL(...allowingReadAccessTo: publication.rootDirectory)`. Script-dependent interactive books and online assets are intentionally not supported by this offline reader. There is no implicit opening of external links in a browser or automatic online fallback. No sandbox/network entitlements are broadened.

## Verification and limits

Real WebKit tests verify book-authored inline/referenced/event/URL scripts and a nonlocal stylesheet are blocked, while local CSS/images, pagination reflow, native text extraction, highlighting, and note activation work. An unhardened positive control executes an inline author script and loads the probe stylesheet, confirming the test can observe both behaviors without isolation. A controlled custom-scheme handler observes actual resource requests, not just preference values. Additional checks cancel external links, outside-root files, new-window links, subframes, and unknown note IDs. Separate isolation-service tests reject persistent storage and prepare multiple ephemeral views.

These checks cover book-driven loads in the configured WebKit reader. They do not promise prevention of macOS/WebKit background traffic, engine vulnerabilities, every speculative connection behavior, secure erasure, or arbitrary injected native code. Archive entry/path/size validation is a separate boundary, not provided by a content rule list.

**Signed HTTP/HTTPS verification:** Completed with the production renderer in an independently signed sandboxed native app; see `docs/verification/epub-network-isolation.md` and `scripts/verify-epub-network-isolation.sh`. Real loopback HTTP/HTTPS servers observe 19 resource/action classes per transport in an unhardened control, including direct external font/background/import loads from a local stylesheet. Public and decrypted-private fixture paths generate zero observed requests while local assets, annotations, reflow, chapter turns, and close/reopen work. Verification-only certificate pinning and permissive ATS prevent transport errors from masking missing isolation. A deliberately unhardened public/private fixture run makes the same observer fail. Neither this harness nor the unit custom-scheme tests claim coverage of all speculative/background traffic.

**Manual before release:** Test representative legitimate EPUBs in the normal signed app for layout regressions and real mouse/keyboard/context-menu interactions. Exercise private books with genuine Touch ID/password prompts and cancellation. Remote-only/interactive content should not trigger an online fallback. The automated signed harness uses renderer APIs and an in-memory fixture-key adapter; it does not claim the full SwiftUI/authentication workflow.

## API references

- [Apple: allowsContentJavaScript](https://developer.apple.com/documentation/webkit/wkwebpagepreferences/allowscontentjavascript)
- [Apple: WKUserContentController](https://developer.apple.com/documentation/webkit/wkusercontentcontroller)
- [Apple: WKContentWorld](https://developer.apple.com/documentation/webkit/wkcontentworld)
- [Apple: WKContentRuleList](https://developer.apple.com/documentation/webkit/wkcontentrulelist)
