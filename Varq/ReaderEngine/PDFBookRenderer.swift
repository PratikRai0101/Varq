import AppKit
import PDFKit
import SwiftUI

struct PDFTextSelection {
    let text: String
    let bounds: CGRect
}

@MainActor
protocol PDFNavigationView: AnyObject {
    var renderedView: NSView { get }
    var document: PDFDocument? { get set }

    func selectedTextSelection(on page: PDFPage) -> PDFTextSelection?
    func go(to page: PDFPage)
    func setPageTone(_ pageTone: ReaderPageTone)
}

extension PDFView: PDFNavigationView {
    var renderedView: NSView { self }

    func selectedTextSelection(on page: PDFPage) -> PDFTextSelection? {
        guard let selection = currentSelection,
              selection.pages.count == 1,
              selection.pages.first === page,
              let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            return nil
        }

        let bounds = selection.bounds(for: page)
        guard !bounds.isNull, !bounds.isEmpty else {
            return nil
        }
        return PDFTextSelection(text: text, bounds: bounds)
    }

    func setPageTone(_ pageTone: ReaderPageTone) {
        switch pageTone {
        case .light:
            backgroundColor = NSColor(Color.varqParchment)
        case .dark:
            backgroundColor = NSColor(Color.varqIndigo)
        case .sepia:
            backgroundColor = NSColor(Color.varqSepia)
        }
    }
}

@MainActor
final class PDFBookRenderer: BookRenderer, TextSelectionProviding {
    private let navigationView: any PDFNavigationView
    private(set) var currentLocator: BookLocator?

    var view: NSView { navigationView.renderedView }
    let supportedFormat: BookFormat = .pdf
    var readingProgressFraction: Double {
        guard let document = navigationView.document,
              let currentLocator,
              document.pageCount > 1 else {
            return 0
        }
        return min(max(Double(currentLocator.spineIndex) / Double(document.pageCount - 1), 0), 1)
    }

    init() {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .horizontal
        navigationView = pdfView
    }

    init(navigationView: any PDFNavigationView) {
        self.navigationView = navigationView
    }

    func open(bookURL: URL, at locator: BookLocator? = nil) async throws {
        guard let document = PDFDocument(url: bookURL), document.pageCount > 0 else {
            throw BookRendererError.cannotOpenDocument
        }

        navigationView.document = document
        let initialLocator = try locator ?? BookLocator(
            format: .pdf,
            spineIndex: 0,
            progression: 0
        )
        try await go(to: initialLocator)
    }

    func selectedTextHighlightAnchor() async throws -> TextHighlightAnchor? {
        guard let currentLocator,
              let document = navigationView.document,
              let page = document.page(at: currentLocator.spineIndex),
              let selection = navigationView.selectedTextSelection(on: page),
              let approximatePosition = normalizedVerticalPosition(of: selection.bounds, on: page) else {
            return nil
        }
        return try TextHighlightAnchor(
            coarsePDFLocator: currentLocator,
            approximatePosition: approximatePosition,
            quote: TextQuoteSelector(exact: selection.text)
        )
    }

    func updateReadingAppearance(_ appearance: ReadingAppearance) async throws {
        // PDFKit renders embedded PDF typography, so only the native view's surrounding page tone changes.
        navigationView.setPageTone(appearance.pageTone)
    }

    func close() async {
        navigationView.document = nil
        currentLocator = nil
    }

    func renderHighlights(_ highlights: [Highlight]) async {
        guard let document = navigationView.document else { return }

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else { continue }
            for annotation in page.annotations where annotation.contents == "varq-highlight" {
                page.removeAnnotation(annotation)
            }
        }

        for highlight in highlights {
            guard let anchor = try? JSONDecoder().decode(TextHighlightAnchor.self, from: highlight.locatorData),
                  anchor.precision == .coarsePagePosition,
                  let page = document.page(at: anchor.locator.spineIndex) else {
                continue
            }

            guard let approximatePosition = anchor.approximatePosition else {
                continue
            }

            let pageBounds = page.bounds(for: .mediaBox)
            guard pageBounds.width > 0, pageBounds.height > 0 else {
                continue
            }
            let horizontalInset = min(VarqSpacing.regular, pageBounds.width / 4)
            let highlightHeight = min(VarqSpacing.regular, pageBounds.height * 0.04)
            let midpoint = pageBounds.minY + pageBounds.height * approximatePosition
            let y = min(
                max(midpoint - highlightHeight / 2, pageBounds.minY),
                pageBounds.maxY - highlightHeight
            )
            let rect = CGRect(
                x: pageBounds.minX + horizontalInset,
                y: y,
                width: pageBounds.width - horizontalInset * 2,
                height: highlightHeight
            )

            let annotation = PDFAnnotation(bounds: rect, forType: .highlight, withProperties: nil)
            annotation.color = nsColor(for: highlight.colorTag)
            annotation.contents = "varq-highlight"
            page.addAnnotation(annotation)
        }
    }

    private func normalizedVerticalPosition(of selectionBounds: CGRect, on page: PDFPage) -> Double? {
        let pageBounds = page.bounds(for: .mediaBox)
        guard pageBounds.height > 0 else {
            return nil
        }
        let position = (selectionBounds.midY - pageBounds.minY) / pageBounds.height
        guard position.isFinite else {
            return nil
        }
        return min(max(position, 0), 1)
    }

    private func nsColor(for colorTag: String) -> NSColor {
        switch HighlightColorTag(rawValue: colorTag) {
        case .saffron: NSColor(Color.varqSaffron)
        case .terracotta: NSColor(Color.varqTerracotta)
        case .maroon: NSColor(Color.varqMaroon)
        case nil: NSColor(Color.varqSaffron)
        }
    }

    func goForward() async throws -> Bool {
        guard let currentLocator,
              let document = navigationView.document,
              currentLocator.spineIndex + 1 < document.pageCount else {
            return false
        }

        try await go(to: BookLocator(
            format: .pdf,
            spineIndex: currentLocator.spineIndex + 1,
            progression: 0
        ))
        return true
    }

    func goBackward() async throws -> Bool {
        guard let currentLocator, currentLocator.spineIndex > 0 else {
            return false
        }

        try await go(to: BookLocator(
            format: .pdf,
            spineIndex: currentLocator.spineIndex - 1,
            progression: 0
        ))
        return true
    }

    func go(to locator: BookLocator) async throws {
        guard locator.format == supportedFormat else {
            throw BookRendererError.incompatibleLocatorFormat(locator.format)
        }
        guard locator.resourceHref == nil,
              let document = navigationView.document,
              let page = document.page(at: locator.spineIndex) else {
            throw BookRendererError.invalidLocator
        }

        navigationView.go(to: page)
        currentLocator = locator
    }
}
