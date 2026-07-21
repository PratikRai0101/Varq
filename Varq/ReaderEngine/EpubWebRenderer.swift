import AppKit
import Foundation
import WebKit

@MainActor
final class EpubWebRenderer: NSObject, BookRenderer, WKNavigationDelegate {
    private let webView: WKWebView
    private let publicationService: EpubPublicationService
    private let sessionRootDirectory: URL
    private var publication: EpubPublication?
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
        _ = try await evaluate(script: """
        (() => {
            const width = Math.max(window.innerWidth, 1);
            const height = Math.max(window.innerHeight, 1);
            const existingStyle = document.getElementById('varq-pagination-style');
            const style = existingStyle || document.createElement('style');
            if (!existingStyle) {
                style.id = 'varq-pagination-style';
                document.head.appendChild(style);
            }
            style.textContent = `
                html { width: ${width}px !important; height: ${height}px !important; margin: 0 !important; overflow: hidden !important; }
                body { width: ${width}px !important; height: ${height}px !important; margin: 0 !important; overflow: hidden !important; column-width: ${width}px !important; column-gap: 0 !important; column-fill: auto !important; }
            `;
            return true;
        })();
        """)
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

private struct PaginationMetrics: Decodable {
    let clientWidth: Double
    let maximumOffset: Double
    let offset: Double
}
