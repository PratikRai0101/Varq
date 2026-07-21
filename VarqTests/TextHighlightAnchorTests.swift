import Foundation
import Testing
@testable import Varq

struct TextHighlightAnchorTests {
    @Test func roundTripsAnEpubTextRange() throws {
        let locator = try BookLocator(
            format: .epub,
            spineIndex: 2,
            resourceHref: "text/chapter-3.xhtml",
            progression: 0.375
        )
        let anchor = try TextHighlightAnchor(
            locator: locator,
            startOffset: 42,
            endOffset: 53,
            quote: TextQuoteSelector(exact: "selected text", prefix: "The ", suffix: " continues")
        )

        let decoded = try JSONDecoder().decode(TextHighlightAnchor.self, from: JSONEncoder().encode(anchor))

        #expect(decoded == anchor)
    }

    @Test func supportsACoarsePdfPageAnchor() throws {
        let locator = try BookLocator(format: .pdf, spineIndex: 4, progression: 0)

        let anchor = try TextHighlightAnchor(
            coarsePDFLocator: locator,
            approximatePosition: 0.4,
            quote: TextQuoteSelector(exact: "PDF text")
        )

        #expect(anchor.precision == .coarsePagePosition)
        #expect(anchor.approximatePosition == 0.4)
        #expect(try JSONDecoder().decode(TextHighlightAnchor.self, from: JSONEncoder().encode(anchor)) == anchor)
    }

    @Test func rejectsComicAndInvalidTextRanges() throws {
        let cbzLocator = try BookLocator(format: .cbz, spineIndex: 0, progression: 0)
        #expect(throws: TextHighlightAnchorError.unsupportedFormat(.cbz)) {
            try TextHighlightAnchor(
                locator: cbzLocator,
                startOffset: 0,
                endOffset: 1,
                quote: TextQuoteSelector(exact: "Image")
            )
        }

        let epubLocator = try BookLocator(format: .epub, spineIndex: 0, resourceHref: "chapter.xhtml", progression: 0)
        #expect(throws: TextHighlightAnchorError.invalidTextRange(start: 4, end: 4)) {
            try TextHighlightAnchor(
                locator: epubLocator,
                startOffset: 4,
                endOffset: 4,
                quote: TextQuoteSelector(exact: "text")
            )
        }
    }
}
