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

**Manual before release:** Open public and private adversarial fixture books in the signed app with local CSS/fonts/images, scripts, external styles/images/fonts, iframes, forms, redirects, and external links. Confirm readable local content and annotations still work and book-driven remote loads/navigation do not. Use a controlled HTTP endpoint with an unhardened positive control to distinguish blocked loads from missing network access. Check close/reopen and chapter turns. Test representative legitimate EPUBs for layout regressions; remote-only/interactive content should not trigger an online fallback. The unit custom-scheme probe is not a substitute for this HTTP/HTTPS inspection.

## API references

- [Apple: allowsContentJavaScript](https://developer.apple.com/documentation/webkit/wkwebpagepreferences/allowscontentjavascript)
- [Apple: WKUserContentController](https://developer.apple.com/documentation/webkit/wkusercontentcontroller)
- [Apple: WKContentWorld](https://developer.apple.com/documentation/webkit/wkcontentworld)
- [Apple: WKContentRuleList](https://developer.apple.com/documentation/webkit/wkcontentrulelist)
