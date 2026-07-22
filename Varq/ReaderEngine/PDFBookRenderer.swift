import AppKit
import PDFKit
import SwiftUI

struct PDFTextSelection {
    let text: String
    let bounds: CGRect
    let lineBounds: [CGRect]
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
        let lineBounds = selection.selectionsByLine().compactMap { lineSelection -> CGRect? in
            let lineBounds = lineSelection.bounds(for: page)
            return lineBounds.isNull || lineBounds.isEmpty ? nil : lineBounds
        }
        return PDFTextSelection(
            text: text,
            bounds: bounds,
            lineBounds: lineBounds.isEmpty ? [bounds] : lineBounds
        )
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
final class PDFBookRenderer: BookRenderer, TextSelectionProviding, ReaderAnnotationInteractionProviding {
    private let navigationView: any PDFNavigationView
    private var annotationActionHandler: ((ReaderAnnotationAction) -> Void)?
    private var noteActivationHandler: ((UUID) -> Void)?
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
        let pdfView = ReaderPDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .horizontal
        navigationView = pdfView
        configureContextMenu()
    }

    init(navigationView: any PDFNavigationView) {
        self.navigationView = navigationView
        configureContextMenu()
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

    func setAnnotationActionHandler(_ handler: @escaping (ReaderAnnotationAction) -> Void) {
        annotationActionHandler = handler
    }

    func setNoteActivationHandler(_ handler: @escaping (UUID) -> Void) {
        noteActivationHandler = handler
    }

    private func configureContextMenu() {
        guard let pdfView = navigationView.renderedView as? ReaderPDFView else {
            return
        }
        pdfView.varqContextMenuItemsProvider = { [weak self] in
            self?.annotationContextMenuItems() ?? []
        }
        pdfView.noteMarkerHandler = { [weak self] noteID in
            self?.noteActivationHandler?(noteID)
        }
    }

    private func annotationContextMenuItems() -> [NSMenuItem] {
        ReaderAnnotationContextMenu.items(
            target: self,
            highlightAction: #selector(createHighlightFromContextMenu(_:)),
            removeHighlightAction: #selector(removeHighlightFromContextMenu(_:)),
            noteAction: #selector(createNoteFromContextMenu(_:)),
            removeNoteAction: #selector(removeNoteFromContextMenu(_:)),
            pageNoteAction: #selector(createPageNoteFromContextMenu(_:)),
            removePageNoteAction: #selector(removePageNoteFromContextMenu(_:))
        )
    }

    @objc private func createHighlightFromContextMenu(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let color = HighlightColorTag(rawValue: rawValue) else {
            return
        }
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                guard let anchor = try await self.selectedTextHighlightAnchor() else {
                    return
                }
                self.annotationActionHandler?(.createHighlight(anchor: anchor, color: color))
            } catch {
                return
            }
        }
    }

    @objc private func removeHighlightFromContextMenu(_ sender: NSMenuItem) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                guard let anchor = try await self.selectedTextHighlightAnchor() else {
                    return
                }
                self.annotationActionHandler?(.removeHighlight(anchor: anchor))
            } catch {
                return
            }
        }
    }

    @objc private func createNoteFromContextMenu(_ sender: NSMenuItem) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                guard let anchor = try await self.selectedTextHighlightAnchor() else {
                    return
                }
                self.annotationActionHandler?(.createNote(anchor: anchor))
            } catch {
                return
            }
        }
    }

    @objc private func removeNoteFromContextMenu(_ sender: NSMenuItem) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }
            do {
                guard let anchor = try await self.selectedTextHighlightAnchor() else {
                    return
                }
                self.annotationActionHandler?(.removeNote(anchor: anchor))
            } catch {
                return
            }
        }
    }

    @objc private func createPageNoteFromContextMenu(_ sender: NSMenuItem) {
        guard let currentLocator else {
            return
        }
        annotationActionHandler?(.createPageNote(locator: currentLocator))
    }

    @objc private func removePageNoteFromContextMenu(_ sender: NSMenuItem) {
        guard let currentLocator else {
            return
        }
        annotationActionHandler?(.removePageNote(locator: currentLocator))
    }

    func selectedTextHighlightAnchor() async throws -> TextHighlightAnchor? {
        guard let currentLocator,
              let document = navigationView.document,
              let page = document.page(at: currentLocator.spineIndex),
              let selection = navigationView.selectedTextSelection(on: page) else {
            return nil
        }
        let pageBounds = page.bounds(for: .mediaBox)
        let selectionRects = try selection.lineBounds.map {
            try NormalizedPDFRect(rect: $0, within: pageBounds)
        }
        return try TextHighlightAnchor(
            pdfLocator: currentLocator,
            selectionRects: selectionRects,
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
                  let page = document.page(at: anchor.locator.spineIndex) else {
                continue
            }

            switch anchor.precision {
            case .pdfSelectionGeometry:
                guard let normalizedRects = anchor.pdfSelectionRects else {
                    continue
                }
                let pageBounds = page.bounds(for: .mediaBox)
                addHighlightAnnotation(
                    for: normalizedRects.map { $0.rect(within: pageBounds) },
                    to: page,
                    colorTag: highlight.colorTag
                )
            case .coarsePagePosition:
                guard let approximatePosition = anchor.approximatePosition else {
                    continue
                }
                addLegacyCoarseHighlight(
                    at: approximatePosition,
                    to: page,
                    colorTag: highlight.colorTag
                )
            case .exactTextRange:
                continue
            }
        }
    }

    func renderNotes(_ notes: [ReadingNote]) async {
        guard let document = navigationView.document else {
            return
        }

        for pageIndex in 0..<document.pageCount {
            guard let page = document.page(at: pageIndex) else {
                continue
            }
            for annotation in page.annotations where annotation.userName?.hasPrefix("varq-note:") == true {
                page.removeAnnotation(annotation)
            }
        }

        for note in notes {
            guard let anchor = try? JSONDecoder().decode(ReadingNoteAnchor.self, from: note.anchorData),
                  let page = document.page(at: anchor.locator.spineIndex),
                  let markerBounds = noteMarkerBounds(for: anchor, on: page) else {
                continue
            }

            let annotation = PDFAnnotation(bounds: markerBounds, forType: .text, withProperties: nil)
            annotation.iconType = .comment
            annotation.color = noteColor(for: note.colorTag)
            annotation.contents = String(note.body.prefix(240))
            annotation.userName = "varq-note:\(note.id.uuidString)"
            page.addAnnotation(annotation)
        }
    }

    private func noteMarkerBounds(for anchor: ReadingNoteAnchor, on page: PDFPage) -> CGRect? {
        let pageBounds = page.bounds(for: .mediaBox)
        guard pageBounds.width > 0, pageBounds.height > 0 else {
            return nil
        }
        let size = min(VarqSpacing.regular, min(pageBounds.width, pageBounds.height) * 0.05)
        guard size > 0 else {
            return nil
        }

        switch anchor.kind {
        case .textSelection:
            guard let textAnchor = anchor.textSelection else {
                return nil
            }
            let selectedRect: CGRect?
            switch textAnchor.precision {
            case .pdfSelectionGeometry:
                selectedRect = textAnchor.pdfSelectionRects?.last?.rect(within: pageBounds)
            case .coarsePagePosition:
                guard let position = textAnchor.approximatePosition else {
                    return nil
                }
                selectedRect = CGRect(
                    x: pageBounds.midX,
                    y: pageBounds.minY + pageBounds.height * position,
                    width: 0,
                    height: 0
                )
            case .exactTextRange:
                selectedRect = nil
            }
            guard let selectedRect else {
                return nil
            }
            return CGRect(
                x: min(max(selectedRect.maxX, pageBounds.minX), pageBounds.maxX - size),
                y: min(max(selectedRect.maxY - size, pageBounds.minY), pageBounds.maxY - size),
                width: size,
                height: size
            )
        case .pageLocation:
            return CGRect(
                x: pageBounds.maxX - size * 1.5,
                y: pageBounds.maxY - size * 1.5,
                width: size,
                height: size
            )
        }
    }

    private func noteColor(for colorTag: String) -> NSColor {
        let color = HighlightColorTag(rawValue: colorTag)?.varqColor ?? Color.varqSaffron
        return NSColor(color).withAlphaComponent(0.9)
    }

    private func addHighlightAnnotation(for rects: [CGRect], to page: PDFPage, colorTag: String) {
        let nonEmptyRects = rects.filter { !$0.isNull && !$0.isEmpty }
        guard let bounds = nonEmptyRects.reduce(nil as CGRect?, { partialResult, rect in
            partialResult?.union(rect) ?? rect
        }) else {
            return
        }

        let annotation = PDFAnnotation(bounds: bounds, forType: .highlight, withProperties: nil)
        annotation.quadrilateralPoints = nonEmptyRects.flatMap { rect in
            let localRect = rect.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
            return [
                NSValue(point: CGPoint(x: localRect.minX, y: localRect.maxY)),
                NSValue(point: CGPoint(x: localRect.maxX, y: localRect.maxY)),
                NSValue(point: CGPoint(x: localRect.minX, y: localRect.minY)),
                NSValue(point: CGPoint(x: localRect.maxX, y: localRect.minY))
            ]
        }
        annotation.color = nsColor(for: colorTag)
        annotation.contents = "varq-highlight"
        page.addAnnotation(annotation)
    }

    private func addLegacyCoarseHighlight(
        at approximatePosition: Double,
        to page: PDFPage,
        colorTag: String
    ) {
        let pageBounds = page.bounds(for: .mediaBox)
        guard pageBounds.width > 0, pageBounds.height > 0 else {
            return
        }
        let horizontalInset = min(VarqSpacing.regular, pageBounds.width / 4)
        let highlightHeight = min(VarqSpacing.regular, pageBounds.height * 0.04)
        let midpoint = pageBounds.minY + pageBounds.height * approximatePosition
        let y = min(
            max(midpoint - highlightHeight / 2, pageBounds.minY),
            pageBounds.maxY - highlightHeight
        )
        addHighlightAnnotation(
            for: [
                CGRect(
                    x: pageBounds.minX + horizontalInset,
                    y: y,
                    width: pageBounds.width - horizontalInset * 2,
                    height: highlightHeight
                )
            ],
            to: page,
            colorTag: colorTag
        )
    }

    private func nsColor(for colorTag: String) -> NSColor {
        let color = HighlightColorTag(rawValue: colorTag)?.varqColor ?? Color.varqSaffron
        return NSColor(color).withAlphaComponent(0.45)
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
