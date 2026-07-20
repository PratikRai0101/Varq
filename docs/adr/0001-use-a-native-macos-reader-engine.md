# Use a native macOS reader engine

**Status:** Accepted

Varq will remain a native macOS app rather than become a Mac Catalyst app to use Readium. Readium Swift Toolkit supports iOS/UIKit, not the native macOS target; Varq will instead use format-specific native components behind a reader-engine boundary (PDFKit for PDF, WebKit plus EPUB parsing for EPUB, and archive image decoding for comics). This preserves the product's native-macOS goal, but requires validating the CBR decoder before implementation.

## Considered options

- Mac Catalyst with Readium: rejected because it conflicts with the native macOS product direction.
- Porting Readium: rejected for MVP because maintaining an unmerged UIKit-to-AppKit port would materially expand scope.
