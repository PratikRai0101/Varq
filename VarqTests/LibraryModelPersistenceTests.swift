import Foundation
import SwiftData
import Testing
@testable import Varq

@MainActor
struct LibraryModelPersistenceTests {
    @Test func persistsBookWithReadingProgressAndHighlights() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: Book.self,
            ReadingProgress.self,
            Highlight.self,
            ReadingNote.self,
            configurations: configuration
        )
        let context = ModelContext(container)
        let libraryRelativePath = "Books/a-book.epub"
        let book = Book(
            title: "A Book",
            author: "An Author",
            libraryRelativePath: libraryRelativePath,
            contentHash: "fixture-hash",
            format: .epub
        )
        let progress = ReadingProgress(
            locatorData: Data("chapter-1".utf8),
            percentComplete: 0.25,
            book: book
        )
        let highlight = Highlight(
            locatorData: Data("chapter-1#p2".utf8),
            selectedText: "A selected passage",
            colorTag: "saffron",
            book: book
        )
        let note = ReadingNote(
            anchorData: Data("chapter-1#page".utf8),
            body: "A personal note",
            colorTag: "highlightGreen",
            book: book
        )

        context.insert(book)
        context.insert(progress)
        context.insert(highlight)
        context.insert(note)
        try context.save()

        let savedBooks = try context.fetch(FetchDescriptor<Book>())
        let savedBook = try #require(savedBooks.first(where: { $0.id == book.id }))

        #expect(savedBook.title == "A Book")
        #expect(savedBook.author == "An Author")
        #expect(savedBook.libraryRelativePath == libraryRelativePath)
        #expect(savedBook.contentHash == "fixture-hash")
        #expect(savedBook.format == .epub)
        #expect(savedBook.readingProgress?.percentComplete == 0.25)
        #expect(savedBook.highlights.count == 1)
        #expect(savedBook.highlights.first?.selectedText == "A selected passage")
        #expect(savedBook.notes.count == 1)
        #expect(savedBook.notes.first?.body == "A personal note")
    }
}
