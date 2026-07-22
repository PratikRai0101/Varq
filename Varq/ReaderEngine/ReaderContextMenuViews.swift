import AppKit
import PDFKit
import WebKit

@MainActor
final class ReaderWebView: WKWebView {
    private static let contextMenuMessageName = "varqReaderContextMenu"

    var varqContextMenuItemsProvider: (() -> [NSMenuItem])?
    var varqContextMenuRequestHandler: ((CGPoint) -> Void)?
    private var contextMenuMessageHandler: WebContextMenuMessageHandler?

    convenience init(frame frameRect: NSRect) {
        self.init(frame: frameRect, configuration: WKWebViewConfiguration())
    }

    override init(frame frameRect: NSRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frameRect, configuration: configuration)
        installContextMenuBridge()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        installContextMenuBridge()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        addVarqItems(to: super.menu(for: event))
    }

    private func installContextMenuBridge() {
        let script = WKUserScript(
            source: """
            (() => {
                document.addEventListener('contextmenu', event => {
                    const selection = window.getSelection();
                    if (!selection || selection.isCollapsed) return;
                    event.preventDefault();
                    window.webkit.messageHandlers.varqReaderContextMenu.postMessage({
                        x: event.clientX,
                        y: event.clientY
                    });
                });
            })();
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
        let messageHandler = WebContextMenuMessageHandler()
        messageHandler.webView = self
        contextMenuMessageHandler = messageHandler
        configuration.userContentController.addUserScript(script)
        configuration.userContentController.add(messageHandler, name: Self.contextMenuMessageName)
    }

    fileprivate func deliverContextMenuRequest(at point: CGPoint) {
        varqContextMenuRequestHandler?(point)
    }

    private func addVarqItems(to defaultMenu: NSMenu?) -> NSMenu? {
        let items = varqContextMenuItemsProvider?() ?? []
        guard !items.isEmpty else {
            return defaultMenu
        }

        let menu = defaultMenu ?? NSMenu()
        if !menu.items.isEmpty {
            menu.insertItem(.separator(), at: 0)
        }
        for item in items.reversed() {
            menu.insertItem(item, at: 0)
        }
        return menu
    }
}

private final class WebContextMenuMessageHandler: NSObject, WKScriptMessageHandler {
    weak var webView: ReaderWebView?

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let x = body["x"] as? Double,
              let y = body["y"] as? Double else {
            return
        }
        Task { @MainActor [weak webView] in
            webView?.deliverContextMenuRequest(at: CGPoint(x: x, y: y))
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
