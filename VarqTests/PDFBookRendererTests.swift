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

    @Test func createsACoarseHighlightAnchorAtTheSelectedPdfPosition() async throws {
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
            bounds: selectionBounds
        )

        let anchor = try #require(try await renderer.selectedTextHighlightAnchor())

        #expect(anchor.precision == .coarsePagePosition)
        #expect(anchor.quote.exact == "Selected PDF passage")
        let expectedPosition = (selectionBounds.midY - pageBounds.minY) / pageBounds.height
        #expect(abs((anchor.approximatePosition ?? -1) - expectedPosition) < 0.001)
    }

    @Test func restoresCoarsePdfHighlightsAtTheirSavedVerticalPosition() async throws {
        let navigationView = FakePDFNavigationView()
        let renderer = PDFBookRenderer(navigationView: navigationView)
        try await renderer.open(bookURL: pdfFixtureURL, at: nil)
        let page = try #require(navigationView.document?.page(at: 0))
        let anchor = try TextHighlightAnchor(
            coarsePDFLocator: BookLocator(format: .pdf, spineIndex: 0, progression: 0),
            approximatePosition: 0.25,
            quote: TextQuoteSelector(exact: "Saved PDF passage")
        )
        let highlight = Highlight(
            locatorData: try JSONEncoder().encode(anchor),
            selectedText: anchor.quote.exact,
            colorTag: HighlightColorTag.saffron.rawValue
        )

        await renderer.renderHighlights([highlight])

        let annotation = try #require(page.annotations.first { $0.contents == "varq-highlight" })
        let pageBounds = page.bounds(for: .mediaBox)
        let expectedMidpoint = pageBounds.minY + pageBounds.height * 0.25
        #expect(abs(annotation.bounds.midY - expectedMidpoint) < 0.001)
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
