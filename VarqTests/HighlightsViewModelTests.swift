import Foundation
import Testing
@testable import Varq

@MainActor
struct HighlightsViewModelTests {
    @Test func sortsHighlightsWithNewestFirst() throws {
        let book = Book(title: "Fixture", author: "Author", libraryRelativePath: "book.epub", contentHash: "hash", format: .epub)
        let locator = try BookLocator(format: .epub, spineIndex: 0, resourceHref: "chapter.xhtml", progression: 0)
        let older = Highlight(locatorData: try JSONEncoder().encode(locator), selectedText: "Older", colorTag: "saffron", dateCreated: .distantPast, book: book)
        let newer = Highlight(locatorData: try JSONEncoder().encode(locator), selectedText: "Newer", colorTag: "maroon", dateCreated: .now, book: book)
        let viewModel = HighlightsViewModel()

        viewModel.load(for: book)

        #expect(viewModel.highlights.map(\.selectedText) == [newer.selectedText, older.selectedText])
    }
}
