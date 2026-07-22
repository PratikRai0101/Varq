import AppKit
import PDFKit
import WebKit

@MainActor
final class ReaderWebView: WKWebView {
    var varqContextMenuItemsProvider: (() -> [NSMenuItem])?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)

        let items = varqContextMenuItemsProvider?() ?? []
        guard !items.isEmpty else {
            return
        }
        if !menu.items.isEmpty {
            menu.insertItem(.separator(), at: 0)
        }
        for item in items.reversed() {
            menu.insertItem(item, at: 0)
        }
    }
}

@MainActor
final class ReaderPDFView: PDFView {
    var varqContextMenuItemsProvider: (() -> [NSMenuItem])?
    var noteMarkerHandler: ((UUID) -> Void)?
    private var annotationHitObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        observeAnnotationHits()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        observeAnnotationHits()
    }

    deinit {
        if let annotationHitObserver {
            NotificationCenter.default.removeObserver(annotationHitObserver)
        }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let items = varqContextMenuItemsProvider?() ?? []
        guard !items.isEmpty else {
            return super.menu(for: event)
        }

        let menu = super.menu(for: event) ?? NSMenu()
        if !menu.items.isEmpty {
            menu.insertItem(.separator(), at: 0)
        }
        for item in items.reversed() {
            menu.insertItem(item, at: 0)
        }
        return menu
    }

    private func observeAnnotationHits() {
        annotationHitObserver = NotificationCenter.default.addObserver(
            forName: .PDFViewAnnotationHit,
            object: self,
            queue: .main
        ) { [weak self] notification in
            guard let annotation = notification.userInfo?["PDFAnnotationHit"] as? PDFAnnotation,
                  let identifier = annotation.userName,
                  identifier.hasPrefix("varq-note:"),
                  let noteID = UUID(uuidString: String(identifier.dropFirst("varq-note:".count))) else {
                return
            }
            Task { @MainActor [weak self] in
                self?.noteMarkerHandler?(noteID)
            }
        }
    }
}
