import Foundation
import Testing
@testable import Varq

struct ExportServiceTests {
    @Test func createsObsidianCompatibleMarkdown() throws {
        let book = Book(title: "Fixture Book", author: "Varq Tests", libraryRelativePath: "fixture.epub", contentHash: "hash", format: .epub)
        let locator = try BookLocator(format: .epub, spineIndex: 0, resourceHref: "chapter.xhtml", progression: 0)
        let highlight = Highlight(locatorData: try JSONEncoder().encode(locator), selectedText: "A selected passage", note: "A useful note", colorTag: "saffron", book: book)

        let markdown = ExportService().markdown(for: book, highlights: [highlight])

        #expect(markdown.contains("title: \"Fixture Book\""))
        #expect(markdown.contains("author: \"Varq Tests\""))
        #expect(markdown.contains("> A selected passage"))
        #expect(markdown.contains("Note: A useful note"))
    }
}
