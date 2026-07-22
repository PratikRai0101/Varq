# Use coarse PDF highlight anchors

**Status:** Superseded by ADR 0007

## Context

Varq's EPUB adapter can calculate exact UTF-16 text offsets from a WebKit DOM selection. PDFKit's public `PDFSelection` API exposes the selected quote and its bounds on a page, but not a stable character range. Reconstructing an offset by searching a page string is ambiguous when the quote occurs more than once.

## Decision

`TextHighlightAnchor` schema version 2 has two explicit precision modes:

- `exactTextRange`: EPUB's resource-level UTF-16 start/end offsets and quote selector.
- `coarsePagePosition`: PDF's `BookLocator` page index, selected quote, and normalized vertical position derived from the selected bounds on that page.

PDF highlight creation must use `coarsePagePosition`; it must not claim exact text-range precision. The limitation is retained in the anchor itself so list, export, and future restoration code can present it accurately.

## Consequences

- EPUB highlights can be restored and rendered against their exact source range.
- PDF highlights remain useful for notes and export, but their visual restoration can only be approximate until a reliable PDFKit range strategy is available.
- Existing schema-1 anchors are rejected rather than interpreted incorrectly. No released Varq build persisted schema-1 highlight data.
