# Use CSS columns for EPUB pagination

**Status:** Accepted

## Context

Varq needs a native macOS EPUB reader that can page forward and backward, re-open at a saved position after typography or window changes, and share one reader-engine seam with PDFKit. Readium is not available to the native macOS target (see `0001-use-a-native-macos-reader-engine.md`), so the EPUB adapter must use WebKit directly.

The difficult part is persistence. A WebKit CSS-column layout changes its physical column count and pixel offsets whenever the viewport, font, line height, or margins change. Persisting a physical `scrollLeft` or a column number would therefore reopen a book at the wrong location after a reflow.

## Decision

Use `WKWebView` to render one EPUB spine resource at a time. The EPUB adapter injects a constrained CSS-column layout into the resource: the reading viewport determines the column width and height, columns fill horizontally, and WebKit advances by one viewport-width column for page navigation.

The native reader-engine seam is the `BookRenderer` interface:

```swift
@MainActor
protocol BookRenderer: AnyObject {
    var view: NSView { get }
    var currentLocator: BookLocator? { get }
    var supportedFormat: BookFormat { get }

    func open(bookURL: URL, at locator: BookLocator?) async throws
    func goForward() async throws -> Bool
    func goBackward() async throws -> Bool
    func go(to locator: BookLocator) async throws
}
```

Each format adapter owns the rendering-specific mechanics behind this small interface. `ReaderViewModel` will depend on `BookRenderer`, not on WebKit or PDFKit types.

### `BookLocator` schema

`BookLocator` is the canonical Codable value serialized into `ReadingProgress.locatorData` and `Highlight.locatorData`.

| Field | Type | Meaning |
|---|---|---|
| `schemaVersion` | `Int` | Currently `1`. Decoding rejects unknown versions rather than silently misplacing a reader. |
| `format` | `BookFormat` | The adapter that may interpret the locator. |
| `spineIndex` | `Int` | Zero-based content-unit index. For EPUB, this is the spine index; for PDF, it is the zero-based page index. |
| `resourceHref` | `String?` | EPUB manifest href for the open spine resource; required for EPUB. It lets an adapter validate or recover from a changed spine order. PDF has no resource href. |
| `progression` | `Double` | Normalized offset in `[0, 1]` within the content unit. For EPUB it is `scrollLeft / (scrollWidth - clientWidth)`, not a pixel offset or column number. |

The locator initializer validates the schema version, nonnegative `spineIndex`, finite bounded `progression`, and EPUB href requirement. A future incompatible schema must increment `schemaVersion` and add an explicit migration path.

### EPUB navigation and restoration

1. Open the resource identified by `spineIndex` and verify its `resourceHref` when present.
2. After WebKit finishes layout, calculate the scrollable horizontal width.
3. Restore `scrollLeft` as `progression * (scrollWidth - clientWidth)`.
4. After any page turn or relevant reflow, calculate and publish a new normalized progression.
5. At a resource boundary, change the spine index and use progression `0` or `1` as appropriate.

The adapter must extract EPUB resources into an app-controlled temporary directory before using `WKWebView.loadFileURL`, then remove that directory when the reader session ends. It must never retain an external source URL or security-scoped bookmark; imports already live in Varq's managed library.

### PDFKit adapter mapping

`PDFBookRenderer` will satisfy the same interface with a native `PDFView`:

- `spineIndex` maps to the zero-based PDF page index.
- `resourceHref` is `nil`.
- `progression` is initially `0` at page granularity; it may later represent normalized in-page vertical position without changing the schema.
- PDF navigation returns `false` at the first or final page, matching the EPUB adapter's boundary behavior.

## Validation

A throwaway proof of concept loaded the self-authored `VarqTests/Fixtures/pagination.epub` chapter in a real `WKWebView`, applied a 640-point horizontal CSS-column viewport, set the normalized offset to `0.5`, and read it back. It produced:

```text
clientWidth=640.0, maximumOffset=12160.0, restoredProgression=0.5
```

This validates the central assumption: WebKit can render an EPUB resource into horizontal columns and restore a normalized position. The proof code was removed after the result was captured here; the permissively licensed fixture remains for adapter tests.

## Consequences

- The interface creates a real seam: EPUB and PDFKit adapters share lifecycle and navigation semantics while hiding their incompatible native rendering details.
- Typography and window reflow preserve an approximate normalized reading position, rather than a brittle physical page number.
- Versioned locators make incompatible future changes explicit.
- This MVP does not provide semantic EPUB CFI locations. A future semantic-location upgrade may add a new locator schema version for more exact restoration and text highlights.
- Complex EPUB JavaScript, DRM, and CBR remain outside this adapter's MVP responsibility.
