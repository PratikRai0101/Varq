import AppKit
import Foundation
import WebKit

@MainActor
final class EpubWebRenderer: NSObject, BookRenderer, TextSelectionProviding, WKNavigationDelegate {
    private let webView: WKWebView
    private let publicationService: EpubPublicationService
    private let sessionRootDirectory: URL
    private var publication: EpubPublication?
    private var appearance = ReadingAppearance()
    private var navigationContinuation: CheckedContinuation<Void, Error>?

    private(set) var currentLocator: BookLocator?
    var view: NSView { webView }
    let supportedFormat: BookFormat = .epub

    override init() {
        webView = WKWebView()
        publicationService = EpubPublicationService()
        sessionRootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Varq", isDirectory: true)
            .appendingPathComponent("EPUBReader", isDirectory: true)
        super.init()
        webView.navigationDelegate = self
    }

    init(
        webView: WKWebView,
        publicationService: EpubPublicationService,
        sessionRootDirectory: URL
    ) {
        self.webView = webView
        self.publicationService = publicationService
        self.sessionRootDirectory = sessionRootDirectory
        super.init()
        webView.navigationDelegate = self
    }

    func open(bookURL: URL, at locator: BookLocator? = nil) async throws {
        await close()

        let extractionDirectory = sessionRootDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let publication = try await publicationService.extract(
            at: bookURL,
            into: extractionDirectory
        )
        self.publication = publication

        do {
            let initialLocator = try locator ?? BookLocator(
                format: .epub,
                spineIndex: 0,
                resourceHref: publication.spine[0].href,
                progression: 0
            )
            try await go(to: initialLocator)
        } catch {
            await close()
            throw error
        }
    }

    func updateReadingAppearance(_ appearance: ReadingAppearance) async throws {
        self.appearance = appearance
        guard let currentLocator else {
            return
        }

        try await applyPaginationStyle()
        let progression = try await setProgression(currentLocator.progression)
        try updateCurrentLocator(progression: progression)
    }

    func selectedTextHighlightAnchor() async throws -> TextHighlightAnchor? {
        guard let currentLocator else {
            return nil
        }
        let result = try await evaluate(script: """
        (() => {
            const selection = window.getSelection();
            if (!selection || selection.rangeCount === 0 || selection.isCollapsed) return null;
            const range = selection.getRangeAt(0);
            const rootRange = document.createRange();
            rootRange.selectNodeContents(document.body);
            rootRange.setEnd(range.startContainer, range.startOffset);
            const startOffset = rootRange.toString().length;
            rootRange.selectNodeContents(document.body);
            rootRange.setEnd(range.endContainer, range.endOffset);
            const endOffset = rootRange.toString().length;
            const content = document.body.textContent || '';
            return JSON.stringify({
                startOffset,
                endOffset,
                exact: selection.toString(),
                prefix: content.slice(Math.max(0, startOffset - 32), startOffset),
                suffix: content.slice(endOffset, endOffset + 32)
            });
        })();
        """)
        guard let json = result as? String,
              let data = json.data(using: .utf8) else {
            return nil
        }
        let selection = try JSONDecoder().decode(WebTextSelection.self, from: data)
        return try TextHighlightAnchor(
            locator: currentLocator,
            startOffset: selection.startOffset,
            endOffset: selection.endOffset,
            quote: TextQuoteSelector(exact: selection.exact, prefix: selection.prefix, suffix: selection.suffix)
        )
    }

    func close() async {
        if let publication {
            try? await publicationService.remove(publication)
        }
        publication = nil
        currentLocator = nil
        webView.loadHTMLString("", baseURL: nil)
    }

    func goForward() async throws -> Bool {
        guard let currentLocator, let publication else {
            return false
        }

        let metrics = try await paginationMetrics()
        let nextOffset = min(metrics.offset + metrics.clientWidth, metrics.maximumOffset)
        if nextOffset > metrics.offset {
            let progression = try await setProgression(nextOffset / metrics.maximumOffset)
            try updateCurrentLocator(progression: progression)
            return true
        }

        let nextSpineIndex = currentLocator.spineIndex + 1
        guard publication.spine.indices.contains(nextSpineIndex) else {
            return false
        }
        try await loadSpineResource(at: nextSpineIndex, progression: 0)
        return true
    }

    func goBackward() async throws -> Bool {
        guard let currentLocator, let publication else {
            return false
        }

        let metrics = try await paginationMetrics()
        let previousOffset = max(metrics.offset - metrics.clientWidth, 0)
        if previousOffset < metrics.offset {
            let progression = try await setProgression(previousOffset / metrics.maximumOffset)
            try updateCurrentLocator(progression: progression)
            return true
        }

        let previousSpineIndex = currentLocator.spineIndex - 1
        guard publication.spine.indices.contains(previousSpineIndex) else {
            return false
        }
        try await loadSpineResource(at: previousSpineIndex, progression: 1)
        return true
    }

    func go(to locator: BookLocator) async throws {
        guard locator.format == supportedFormat else {
            throw BookRendererError.incompatibleLocatorFormat(locator.format)
        }
        guard let publication,
              publication.spine.indices.contains(locator.spineIndex),
              publication.spine[locator.spineIndex].href == locator.resourceHref else {
            throw BookRendererError.invalidLocator
        }

        try await loadSpineResource(at: locator.spineIndex, progression: locator.progression)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationContinuation?.resume()
        navigationContinuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        resumeNavigation(throwing: error)
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        resumeNavigation(throwing: error)
    }

    private func updateCurrentLocator(progression: Double) throws {
        guard let currentLocator else {
            throw BookRendererError.invalidLocator
        }
        self.currentLocator = try BookLocator(
            format: .epub,
            spineIndex: currentLocator.spineIndex,
            resourceHref: currentLocator.resourceHref,
            progression: progression
        )
    }

    private func loadSpineResource(at spineIndex: Int, progression: Double) async throws {
        guard let publication, publication.spine.indices.contains(spineIndex) else {
            throw BookRendererError.invalidLocator
        }

        let resource = publication.spine[spineIndex]
        try await load(resource, allowingReadAccessTo: publication.rootDirectory)
        try await applyPaginationStyle()
        let actualProgression = try await setProgression(progression)
        currentLocator = try BookLocator(
            format: .epub,
            spineIndex: spineIndex,
            resourceHref: resource.href,
            progression: actualProgression
        )
    }

    private func load(_ resource: EpubSpineResource, allowingReadAccessTo directory: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            navigationContinuation = continuation
            webView.loadFileURL(resource.fileURL, allowingReadAccessTo: directory)
        }
    }

    private func applyPaginationStyle() async throws {
        let margin = appearance.horizontalMargin
        let columns = appearance.epubPageLayout == .twoPageSpread ? 2 : 1
        let columnGap = columns > 1 ? 48.0 : 0.0
        let js = """
        (() => {
            const width = Math.max(window.innerWidth, 1);
            const height = Math.max(window.innerHeight, 1);
            const margin = \(margin);
            const columns = \(columns);
            const columnGap = \(columnGap);
            const availableWidth = Math.max(width - 2 * margin, 1);
            const columnWidth = Math.max((availableWidth - (columns - 1) * columnGap) / columns, 1);
            const existingStyle = document.getElementById('varq-pagination-style');
            const style = existingStyle || document.createElement('style');
            if (!existingStyle) {
                style.id = 'varq-pagination-style';
                document.head.appendChild(style);
            }
            style.textContent = `
                html {
                    width: ${width}px !important;
                    height: ${height}px !important;
                    margin: 0 !important;
                    padding: 0 !important;
                    overflow: hidden !important;
                    background: \(appearance.pageTone.cssBackgroundColor) !important;
                }
                body {
                    width: ${availableWidth}px !important;
                    height: ${height}px !important;
                    margin: 0 ${margin}px !important;
                    padding: 0 !important;
                    overflow: hidden !important;
                    column-width: ${columnWidth}px !important;
                    column-gap: ${columnGap}px !important;
                    column-fill: auto !important;
                    background: \(appearance.pageTone.cssBackgroundColor) !important;
                    color: \(appearance.pageTone.cssTextColor) !important;
                    font-family: \(appearance.fontFamily.cssFamily) !important;
                    font-size: \(appearance.fontSize)px !important;
                    line-height: \(appearance.lineHeight) !important;
                    -webkit-hyphens: auto !important;
                    orphans: 2 !important;
                    widows: 2 !important;
                }
                body *, body *::before, body *::after {
                    box-sizing: border-box !important;
                    max-width: 100% !important;
                    white-space: normal !important;
                    float: none !important;
                    position: static !important;
                    clear: both !important;
                }
                p, li, blockquote, dd, td, th {
                    overflow-wrap: break-word !important;
                }
                img, svg, video, canvas {
                    max-width: 100% !important;
                    max-height: 80% !important;
                    height: auto !important;
                    display: block !important;
                    margin: 0.5em auto !important;
                }
                h1, h2, h3, h4, h5, h6 {
                    break-inside: avoid !important;
                    page-break-inside: avoid !important;
                    -webkit-column-break-inside: avoid !important;
                }
            `;
            return true;
        })();
        """
        _ = try await evaluate(script: js)
    }

    private func paginationMetrics() async throws -> PaginationMetrics {
        let result = try await evaluate(script: """
        (() => {
            const root = document.body;
            return JSON.stringify({
                clientWidth: root.clientWidth,
                maximumOffset: Math.max(root.scrollWidth - root.clientWidth, 0),
                offset: root.scrollLeft
            });
        })();
        """)
        return try decodePaginationMetrics(from: result)
    }

    private func setProgression(_ progression: Double) async throws -> Double {
        let result = try await evaluate(script: """
        (() => {
            const root = document.body;
            const maximumOffset = Math.max(root.scrollWidth - root.clientWidth, 0);
            root.scrollLeft = maximumOffset * \(progression);
            return JSON.stringify({
                clientWidth: root.clientWidth,
                maximumOffset,
                offset: root.scrollLeft
            });
        })();
        """)
        let metrics = try decodePaginationMetrics(from: result)
        guard metrics.maximumOffset > 0 else {
            return 0
        }
        return metrics.offset / metrics.maximumOffset
    }

    private func decodePaginationMetrics(from result: Any) throws -> PaginationMetrics {
        guard let json = result as? String,
              let data = json.data(using: .utf8) else {
            throw BookRendererError.invalidLocator
        }
        return try JSONDecoder().decode(PaginationMetrics.self, from: data)
    }

    private func evaluate(script: String) async throws -> Any {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let result {
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(throwing: BookRendererError.invalidLocator)
                }
            }
        }
    }

    private func resumeNavigation(throwing error: Error) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }
}

private struct WebTextSelection: Decodable {
    let startOffset: Int
    let endOffset: Int
    let exact: String
    let prefix: String?
    let suffix: String?
}

private struct PaginationMetrics: Decodable {
    let clientWidth: Double
    let maximumOffset: Double
    let offset: Double
}
