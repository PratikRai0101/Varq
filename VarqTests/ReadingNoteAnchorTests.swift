import Foundation
import Testing
@testable import Varq

@MainActor
struct ReadingNoteAnchorTests {
    @Test func roundTripsATextSelectionNoteAnchor() throws {
        let locator = try BookLocator(
            format: .epub,
            spineIndex: 2,
            resourceHref: "text/chapter-3.xhtml",
            progression: 0.375
        )
        let textSelection = try TextHighlightAnchor(
            locator: locator,
            startOffset: 42,
            endOffset: 53,
            quote: TextQuoteSelector(exact: "selected text")
        )
        let anchor = ReadingNoteAnchor(textSelection: textSelection)

        let decoded = try JSONDecoder().decode(ReadingNoteAnchor.self, from: JSONEncoder().encode(anchor))

        #expect(decoded == anchor)
        #expect(decoded.kind == .textSelection)
        #expect(decoded.selectedText == "selected text")
    }

    @Test func roundTripsAPageLocationNoteAnchor() throws {
        let locator = try BookLocator(format: .pdf, spineIndex: 4, progression: 0)
        let anchor = ReadingNoteAnchor(pageLocator: locator)

        let decoded = try JSONDecoder().decode(ReadingNoteAnchor.self, from: JSONEncoder().encode(anchor))

        #expect(decoded == anchor)
        #expect(decoded.kind == .pageLocation)
        #expect(decoded.selectedText == nil)
    }
}
