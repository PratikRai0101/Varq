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

    @Test func createsStructuredJsonExport() throws {
        let book = Book(title: "Fixture Book", author: "Varq Tests", libraryRelativePath: "fixture.epub", contentHash: "hash", format: .epub)
        let locator = try BookLocator(format: .epub, spineIndex: 0, resourceHref: "chapter.xhtml", progression: 0)
        let highlight = Highlight(locatorData: try JSONEncoder().encode(locator), selectedText: "A selected passage", note: nil, colorTag: "terracotta", book: book)

        let data = try ExportService().jsonData(for: book, highlights: [highlight])
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let exportedHighlights = try #require(object["highlights"] as? [[String: Any]])

        #expect(object["title"] as? String == "Fixture Book")
        #expect(exportedHighlights.first?["text"] as? String == "A selected passage")
        #expect(exportedHighlights.first?["color"] as? String == "terracotta")
    }

    @Test func escapesQuotesInYamlFrontmatter() throws {
        let book = Book(title: "The \"Secret\" History", author: "O'Brien, Jack", libraryRelativePath: "fixture.epub", contentHash: "hash", format: .epub)
        let markdown = ExportService().markdown(for: book, highlights: [])

        #expect(markdown.contains("title: \"The \\\"Secret\\\" History\""))
        #expect(markdown.contains("author: \"O'Brien, Jack\""))
    }

    @Test func handlesMultilineHighlightWithBlockquotePrefix() throws {
        let book = Book(title: "Book", author: "Author", libraryRelativePath: "fixture.epub", contentHash: "hash", format: .epub)
        let locator = try BookLocator(format: .epub, spineIndex: 0, resourceHref: "chapter.xhtml", progression: 0)
        let highlight = Highlight(locatorData: try JSONEncoder().encode(locator), selectedText: "Line one\nLine two\nLine three", note: nil, colorTag: "maroon", book: book)

        let markdown = ExportService().markdown(for: book, highlights: [highlight])

        #expect(markdown.contains("> Line one\n> Line two\n> Line three"))
    }

    @Test func omitsNoteLineWhenNoteIsEmpty() throws {
        let book = Book(title: "Book", author: "Author", libraryRelativePath: "fixture.epub", contentHash: "hash", format: .epub)
        let locator = try BookLocator(format: .epub, spineIndex: 0, resourceHref: "chapter.xhtml", progression: 0)
        let highlight = Highlight(locatorData: try JSONEncoder().encode(locator), selectedText: "Text", note: nil, colorTag: "saffron", book: book)

        let markdown = ExportService().markdown(for: book, highlights: [highlight])

        #expect(!markdown.contains("Note:"))
    }

    @Test func jsonExportOmitsNullNotes() throws {
        let book = Book(title: "Book", author: "Author", libraryRelativePath: "fixture.epub", contentHash: "hash", format: .epub)
        let locator = try BookLocator(format: .epub, spineIndex: 0, resourceHref: "chapter.xhtml", progression: 0)
        let highlight = Highlight(locatorData: try JSONEncoder().encode(locator), selectedText: "Text", note: nil, colorTag: "saffron", book: book)

        let data = try ExportService().jsonData(for: book, highlights: [highlight])
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let exportedHighlights = try #require(object["highlights"] as? [[String: Any]])

        // Swift JSONEncoder omits nil values by default; the key should be absent.
        #expect(!exportedHighlights.first!.keys.contains("note"))
    }

    @Test func jsonExportIncludesNoteWhenPresent() throws {
        let book = Book(title: "Book", author: "Author", libraryRelativePath: "fixture.epub", contentHash: "hash", format: .epub)
        let locator = try BookLocator(format: .epub, spineIndex: 0, resourceHref: "chapter.xhtml", progression: 0)
        let highlight = Highlight(locatorData: try JSONEncoder().encode(locator), selectedText: "Text", note: "My note", colorTag: "saffron", book: book)

        let data = try ExportService().jsonData(for: book, highlights: [highlight])
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let exportedHighlights = try #require(object["highlights"] as? [[String: Any]])

        #expect(exportedHighlights.first?["note"] as? String == "My note")
    }

    @Test func markdownContainsExportedAtTimestamp() throws {
        let book = Book(title: "Book", author: "Author", libraryRelativePath: "fixture.epub", contentHash: "hash", format: .epub)
        let markdown = ExportService().markdown(for: book, highlights: [])

        #expect(markdown.contains("exported_at:"))
    }

    @Test func jsonUsesIso8601DateEncoding() throws {
        let book = Book(title: "Book", author: "Author", libraryRelativePath: "fixture.epub", contentHash: "hash", format: .epub)
        let locator = try BookLocator(format: .epub, spineIndex: 0, resourceHref: "chapter.xhtml", progression: 0)
        let pastDate = Date(timeIntervalSince1970: 1_700_000_000)
        let highlight = Highlight(locatorData: try JSONEncoder().encode(locator), selectedText: "Text", note: nil, colorTag: "saffron", dateCreated: pastDate, book: book)

        let data = try ExportService().jsonData(for: book, highlights: [highlight])
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let exportedHighlights = try #require(object["highlights"] as? [[String: Any]])

        #expect(exportedHighlights.first?["createdAt"] as? String == "2023-11-14T22:13:20Z")
    }
}
