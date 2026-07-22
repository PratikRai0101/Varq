# Store normalized PDF selection geometry

**Status:** Accepted

## Context

ADR 0005 stored only a PDF page and a normalized vertical position. That made PDF highlights useful for export, but restoration drew a page-wide approximation rather than the selected words. Varq now needs the same multi-line, text-following visual result for PDFs that EPUB receives from its DOM range.

PDFKit does not expose a stable character range, but it does expose stable page-space bounds for each selected line. Those bounds do not depend on the current zoom level.

## Decision

Use `TextHighlightAnchor` schema version 3 for newly created PDF highlights. A PDF anchor uses the `pdfSelectionGeometry` precision mode and contains:

- the existing `BookLocator` for the PDF page;
- the selected quote; and
- one or more rectangles normalized to that page's media box.

`PDFBookRenderer` obtains a rectangle for each `PDFSelection.selectionsByLine()` entry, normalizes it before persistence, and restores it as PDF highlight quadrilaterals. This preserves the selected line fragments across reader sessions and view-scale changes.

Schema-2 `coarsePagePosition` anchors remain decodable and render through the old approximate fallback. New highlights never create that fallback form.

## Consequences

- New PDF highlights visually follow selected text instead of appearing as a page-wide stripe.
- Geometry is precise for rendering but remains a visual anchor, not a stable PDF character range; quote text remains available for export and future re-anchoring.
- Existing schema-2 highlights remain readable without a data migration.
