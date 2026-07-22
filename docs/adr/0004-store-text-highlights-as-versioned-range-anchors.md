# Store text highlights as versioned range anchors

**Status:** Accepted

## Context

`BookLocator` identifies a reader position, but not a selected text range. A highlight must restore its selected quote after an EPUB reflow and must work with PDFKit's page text. Persisting an engine-specific `Range`, DOM node, or `PDFSelection` would couple SwiftData to WebKit or PDFKit and would not survive a new reader session.

## Decision

Store `TextHighlightAnchor` as the Codable value in `Highlight.locatorData`. It is independent of the existing `BookLocator` schema used by `ReadingProgress` and contains:

- a `BookLocator` identifying the EPUB spine resource or PDF page;
- UTF-16 `startOffset` and exclusive `endOffset` within that content unit;
- a `TextQuoteSelector` with the exact selected quote and optional surrounding prefix/suffix; and
- its own schema version.

The quote selector permits an adapter to verify offsets and, in a future content-migration feature, re-anchor a range when offsets no longer match. The initial schema supports EPUB and PDF only. CBZ has image pages rather than selectable text and is explicitly rejected.

The WebKit EPUB adapter derives offsets from the resource's `textContent`. PDFKit geometry is persisted separately in the schema-3 `pdfSelectionGeometry` form defined by ADR 0007. Renderer-specific selection APIs remain behind the reader-engine boundary; Views and SwiftData never receive WebKit or PDFKit selection types.

## Consequences

- `ReadingProgress.locatorData` remains a `BookLocator`; existing reading-position data requires no migration.
- `Highlight.locatorData` has a distinct, explicit schema and can evolve separately from reader navigation.
- MVP highlights are limited to one EPUB spine resource or one PDF page. Cross-resource/page selections require a future anchor schema version.
