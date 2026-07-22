import AppKit
import Foundation
import PDFKit
import Testing
@testable import Varq

@MainActor
struct PDFBookRendererTests {
    @Test func opensAndNavigatesThePdfFixtureUsingBookLocators() async throws {
        let renderer = PDFBookRenderer(navigationView: FakePDFNavigationView())

        try await renderer.open(bookURL: pdfFixtureURL, at: nil)
        #expect(renderer.currentLocator?.spineIndex == 0)
        #expect(try await renderer.goBackward() == false)
        #expect(try await renderer.goForward() == false)

        let firstPageLocator = try BookLocator(format: .pdf, spineIndex: 0, progression: 0)
        try await renderer.go(to: firstPageLocator)
        #expect(renderer.currentLocator == firstPageLocator)
    }

    @Test func createsAGeometricHighlightAnchorFromSelectedPdfText() async throws {
        let navigationView = FakePDFNavigationView()
        let renderer = PDFBookRenderer(navigationView: navigationView)
        try await renderer.open(bookURL: pdfFixtureURL, at: nil)
        let page = try #require(navigationView.document?.page(at: 0))
        let pageBounds = page.bounds(for: .mediaBox)
        let selectionBounds = CGRect(
            x: pageBounds.minX + pageBounds.width * 0.2,
            y: pageBounds.minY + pageBounds.height * 0.7,
            width: pageBounds.width * 0.5,
            height: pageBounds.height * 0.05
        )
        navigationView.textSelection = PDFTextSelection(
            text: "Selected PDF passage",
            bounds: selectionBounds,
            lineBounds: [selectionBounds]
        )

        let anchor = try #require(try await renderer.selectedTextHighlightAnchor())

        #expect(anchor.precision == .pdfSelectionGeometry)
        #expect(anchor.quote.exact == "Selected PDF passage")
        let restoredBounds = try #require(anchor.pdfSelectionRects?.first).rect(within: pageBounds)
        #expect(abs(restoredBounds.minX - selectionBounds.minX) < 0.001)
        #expect(abs(restoredBounds.minY - selectionBounds.minY) < 0.001)
        #expect(abs(restoredBounds.width - selectionBounds.width) < 0.001)
        #expect(abs(restoredBounds.height - selectionBounds.height) < 0.001)
    }

    @Test func preservesGeometryForEachSelectedPdfLine() async throws {
        let navigationView = FakePDFNavigationView()
        let renderer = PDFBookRenderer(navigationView: navigationView)
        try await renderer.open(bookURL: pdfFixtureURL, at: nil)
        let page = try #require(navigationView.document?.page(at: 0))
        let pageBounds = page.bounds(for: .mediaBox)
        let firstLine = CGRect(
            x: pageBounds.minX + pageBounds.width * 0.2,
            y: pageBounds.minY + pageBounds.height * 0.25,
            width: pageBounds.width * 0.5,
            height: pageBounds.height * 0.05
        )
        let secondLine = CGRect(
            x: pageBounds.minX + pageBounds.width * 0.2,
            y: pageBounds.minY + pageBounds.height * 0.35,
            width: pageBounds.width * 0.4,
            height: pageBounds.height * 0.05
        )
        navigationView.textSelection = PDFTextSelection(
            text: "A multi-line PDF passage",
            bounds: firstLine.union(secondLine),
            lineBounds: [firstLine, secondLine]
        )

        let anchor = try #require(try await renderer.selectedTextHighlightAnchor())

        #expect(anchor.pdfSelectionRects?.count == 2)
    }

    @Test func restoresPdfHighlightsUsingTheirSavedSelectionGeometry() async throws {
        let navigationView = FakePDFNavigationView()
        let renderer = PDFBookRenderer(navigationView: navigationView)
        try await renderer.open(bookURL: pdfFixtureURL, at: nil)
        let page = try #require(navigationView.document?.page(at: 0))
        let pageBounds = page.bounds(for: .mediaBox)
        let selectionBounds = CGRect(
            x: pageBounds.minX + pageBounds.width * 0.2,
            y: pageBounds.minY + pageBounds.height * 0.25,
            width: pageBounds.width * 0.5,
            height: pageBounds.height * 0.1
        )
        let anchor = try TextHighlightAnchor(
            pdfLocator: BookLocator(format: .pdf, spineIndex: 0, progression: 0),
            selectionRects: [try NormalizedPDFRect(rect: selectionBounds, within: pageBounds)],
            quote: TextQuoteSelector(exact: "Saved PDF passage")
        )
        let highlight = Highlight(
            locatorData: try JSONEncoder().encode(anchor),
            selectedText: anchor.quote.exact,
            colorTag: HighlightColorTag.saffron.rawValue
        )

        await renderer.renderHighlights([highlight])

        let annotation = try #require(page.annotations.first { $0.contents == "varq-highlight" })
        #expect(abs(annotation.bounds.minX - selectionBounds.minX) < 0.001)
        #expect(abs(annotation.bounds.minY - selectionBounds.minY) < 0.001)
        #expect(abs(annotation.bounds.width - selectionBounds.width) < 0.001)
        #expect(abs(annotation.bounds.height - selectionBounds.height) < 0.001)
        #expect(annotation.quadrilateralPoints?.count == 4)
    }

    @Test func rendersClickablePdfNoteMarkers() async throws {
        let navigationView = FakePDFNavigationView()
        let renderer = PDFBookRenderer(navigationView: navigationView)
        try await renderer.open(bookURL: pdfFixtureURL, at: nil)
        let page = try #require(navigationView.document?.page(at: 0))
        let locator = try BookLocator(format: .pdf, spineIndex: 0, progression: 0)
        let note = ReadingNote(
            anchorData: try JSONEncoder().encode(ReadingNoteAnchor(pageLocator: locator)),
            body: "A personal PDF note",
            colorTag: HighlightColorTag.highlightPink.rawValue
        )

        await renderer.renderNotes([note])

        let annotation = try #require(page.annotations.first {
            $0.userName == "varq-note:\(note.id.uuidString)"
        })
        #expect(annotation.contents == "A personal PDF note")
        #expect(annotation.iconType == .comment)
    }

    @Test func appliesTheSelectedPageToneToThePdfView() async throws {
        let navigationView = FakePDFNavigationView()
        let renderer = PDFBookRenderer(navigationView: navigationView)

        try await renderer.updateReadingAppearance(ReadingAppearance(pageTone: .dark))

        #expect(navigationView.pageTone == .dark)
    }

    @Test func rejectsAnEpubLocator() async throws {
        let renderer = PDFBookRenderer(navigationView: FakePDFNavigationView())
        try await renderer.open(bookURL: pdfFixtureURL, at: nil)
        let epubLocator = try BookLocator(
            format: .epub,
            spineIndex: 0,
            resourceHref: "chapter.xhtml",
            progression: 0
        )

        await #expect(throws: BookRendererError.incompatibleLocatorFormat(.epub)) {
            try await renderer.go(to: epubLocator)
        }
    }

    private var pdfFixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/minimal.pdf")
    }
}

@MainActor
private final class FakePDFNavigationView: NSView, PDFNavigationView {
    var document: PDFDocument?
    var textSelection: PDFTextSelection?
    private(set) var displayedPage: PDFPage?
    private(set) var pageTone: ReaderPageTone?

    var renderedView: NSView { self }

    func selectedTextSelection(on page: PDFPage) -> PDFTextSelection? {
        textSelection
    }

    func go(to page: PDFPage) {
        displayedPage = page
    }

    func setPageTone(_ pageTone: ReaderPageTone) {
        self.pageTone = pageTone
    }
}
