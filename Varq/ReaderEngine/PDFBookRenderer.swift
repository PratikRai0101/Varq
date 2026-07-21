import AppKit
import PDFKit

@MainActor
protocol PDFNavigationView: AnyObject {
    var renderedView: NSView { get }
    var document: PDFDocument? { get set }

    func go(to page: PDFPage)
}

extension PDFView: PDFNavigationView {
    var renderedView: NSView { self }
}

@MainActor
final class PDFBookRenderer: BookRenderer {
    private let navigationView: any PDFNavigationView
    private(set) var currentLocator: BookLocator?

    var view: NSView { navigationView.renderedView }
    let supportedFormat: BookFormat = .pdf

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

    func updateReadingAppearance(_ appearance: ReadingAppearance) async throws {
        // PDFKit renders embedded PDF typography; it has no document-text typography controls.
    }

    func close() async {
        navigationView.document = nil
        currentLocator = nil
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
