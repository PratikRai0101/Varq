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

    @Test func createsACoarseHighlightAnchorFromSelectedPdfText() async throws {
        let navigationView = FakePDFNavigationView()
        navigationView.selectedText = "Selected PDF passage"
        let renderer = PDFBookRenderer(navigationView: navigationView)
        try await renderer.open(bookURL: pdfFixtureURL, at: nil)

        let anchor = try #require(try await renderer.selectedTextHighlightAnchor())

        #expect(anchor.precision == .coarsePagePosition)
        #expect(anchor.quote.exact == "Selected PDF passage")
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
    var selectedText: String?
    private(set) var displayedPage: PDFPage?
    private(set) var pageTone: ReaderPageTone?

    var renderedView: NSView { self }

    func go(to page: PDFPage) {
        displayedPage = page
    }

    func setPageTone(_ pageTone: ReaderPageTone) {
        self.pageTone = pageTone
    }
}
