import AppKit
import Foundation
import WebKit

@MainActor
final class EpubWebRenderer: NSObject, BookRenderer, TextSelectionProviding, ReaderAnnotationInteractionProviding, WKNavigationDelegate {
    private let webView: WKWebView
    private let publicationService: EpubPublicationService
    private let sessionRootDirectory: URL
    private var publication: EpubPublication?
    private var appearance = ReadingAppearance()
    private var navigationContinuation: CheckedContinuation<Void, Error>?
    private var storedHighlights: [Highlight] = []
    private var storedNotes: [ReadingNote] = []
    private var annotationActionHandler: ((ReaderAnnotationAction) -> Void)?
    private var noteActivationHandler: ((UUID) -> Void)?

    private(set) var currentLocator: BookLocator?
    var view: NSView { webView }
    let supportedFormat: BookFormat = .epub
    var readingProgressFraction: Double {
        guard let publication, let currentLocator, !publication.spine.isEmpty else {
            return 0
        }
        return min(max((Double(currentLocator.spineIndex) + currentLocator.progression) / Double(publication.spine.count), 0), 1)
    }

    override init() {
        webView = ReaderWebView()
        publicationService = EpubPublicationService()
        sessionRootDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Varq", isDirectory: true)
            .appendingPathComponent("EPUBReader", isDirectory: true)
        super.init()
        webView.navigationDelegate = self
        configureContextMenu()
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
        configureContextMenu()
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

    func setAnnotationActionHandler(_ handler: @escaping (ReaderAnnotationAction) -> Void) {
        annotationActionHandler = handler
    }

    func setNoteActivationHandler(_ handler: @escaping (UUID) -> Void) {
        noteActivationHandler = handler
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

    private func configureContextMenu() {
        guard let webView = webView as? ReaderWebView else {
            return
        }
        webView.varqContextMenuItemsProvider = { [weak self] in
            self?.annotationContextMenuItems() ?? []
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

    func renderHighlights(_ highlights: [Highlight]) async {
        storedHighlights = highlights
        let anchors: [[String: Any]] = highlights.compactMap { highlight in
            guard let anchor = try? JSONDecoder().decode(TextHighlightAnchor.self, from: highlight.locatorData),
                  anchor.precision == .exactTextRange,
                  let start = anchor.startOffset,
                  let end = anchor.endOffset,
                  anchor.locator.spineIndex == currentLocator?.spineIndex else {
                return nil
            }
            return [
                "start": start,
                "end": end,
                "color": highlight.colorTag
            ]
        }
        let colorMap = HighlightColorTag.allCases.map {
            "\($0.rawValue): '\($0.webHighlightColor)66'"
        }.joined(separator: ",\n                ")

        let js = """
        (() => {
            document.querySelectorAll('mark.varq-highlight').forEach(el => {
                const parent = el.parentNode;
                while (el.firstChild) parent.insertBefore(el.firstChild, el);
                parent.removeChild(el);
                parent.normalize();
            });

            const colorMap = {
                \(colorMap)
            };
            const highlights = \(serializeAnchors(anchors));

            function createTextWalker() {
                const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
                let offset = 0;
                const nodes = [];
                let node;
                while (node = walker.nextNode()) {
                    nodes.push({ node, start: offset, end: offset + node.textContent.length });
                    offset += node.textContent.length;
                }
                return nodes;
            }

            for (const highlight of highlights) {
                const nodes = createTextWalker();
                for (const info of nodes.reverse()) {
                    const start = Math.max(highlight.start, info.start);
                    const end = Math.min(highlight.end, info.end);
                    if (start >= end) continue;
                    try {
                        const range = document.createRange();
                        range.setStart(info.node, start - info.start);
                        range.setEnd(info.node, end - info.start);
                        const mark = document.createElement('mark');
                        mark.className = 'varq-highlight';
                        mark.style.background = colorMap[highlight.color] || colorMap.saffron;
                        mark.style.color = 'inherit';
                        range.surroundContents(mark);
                    } catch (error) {}
                }
            }
        })();
        """
        _ = try? await evaluate(script: js)
    }

    func renderNotes(_ notes: [ReadingNote]) async {
        storedNotes = notes
        guard let currentLocator else {
            return
        }

        let markers = notes.compactMap { note -> WebNoteMarker? in
            guard let anchor = try? JSONDecoder().decode(ReadingNoteAnchor.self, from: note.anchorData),
                  anchor.locator.format == currentLocator.format,
                  anchor.locator.spineIndex == currentLocator.spineIndex,
                  anchor.locator.resourceHref == currentLocator.resourceHref else {
                return nil
            }

            let summary = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !summary.isEmpty else {
                return nil
            }
            switch anchor.kind {
            case .textSelection:
                guard let textAnchor = anchor.textSelection,
                      textAnchor.precision == .exactTextRange,
                      let endOffset = textAnchor.endOffset else {
                    return nil
                }
                return WebNoteMarker(
                    id: note.id.uuidString,
                    kind: .textSelection,
                    endOffset: endOffset,
                    summary: String(summary.prefix(140)),
                    color: note.colorTag
                )
            case .pageLocation:
                guard abs(anchor.locator.progression - currentLocator.progression) < 0.03 else {
                    return nil
                }
                return WebNoteMarker(
                    id: note.id.uuidString,
                    kind: .pageLocation,
                    endOffset: nil,
                    summary: String(summary.prefix(140)),
                    color: note.colorTag
                )
            }
        }
        guard let markerData = try? JSONEncoder().encode(markers),
              let markerJSON = String(data: markerData, encoding: .utf8) else {
            return
        }
        let colorMap = HighlightColorTag.allCases.map {
            "\($0.rawValue): '\($0.webHighlightColor)'"
        }.joined(separator: ",\n                ")

        let js = """
        (() => {
            document.querySelectorAll('a.varq-note-marker, a.varq-page-note-marker').forEach(el => el.remove());

            const styleID = 'varq-note-marker-style';
            let style = document.getElementById(styleID);
            if (!style) {
                style = document.createElement('style');
                style.id = styleID;
                document.head.appendChild(style);
            }
            style.textContent = `
                .varq-note-marker, .varq-page-note-marker {
                    display: inline-block;
                    box-sizing: border-box;
                    width: 0.72em;
                    height: 0.72em;
                    margin-left: 0.18em;
                    vertical-align: super;
                    border-radius: 50%;
                    background: var(--varq-note-color);
                    border: 1px solid currentColor;
                    cursor: pointer;
                    text-decoration: none !important;
                }
                .varq-page-note-marker {
                    position: fixed;
                    z-index: 10;
                    top: calc(1rem + var(--varq-note-index) * 1.5rem);
                    right: 1rem;
                    margin: 0;
                    vertical-align: baseline;
                }
            `;

            const colorMap = {
                \(colorMap)
            };
            const notes = \(markerJSON);

            function createTextWalker() {
                const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
                let offset = 0;
                const nodes = [];
                let node;
                while (node = walker.nextNode()) {
                    nodes.push({ node, start: offset, end: offset + node.textContent.length });
                    offset += node.textContent.length;
                }
                return nodes;
            }

            function markerFor(note, pageIndex) {
                const marker = document.createElement('a');
                marker.href = 'varq-note://' + note.id;
                marker.className = note.kind === 'pageLocation' ? 'varq-page-note-marker' : 'varq-note-marker';
                marker.title = note.summary;
                marker.setAttribute('aria-label', 'Open note: ' + note.summary);
                marker.style.setProperty('--varq-note-color', colorMap[note.color] || colorMap.saffron);
                marker.style.setProperty('--varq-note-index', pageIndex);
                return marker;
            }

            let pageMarkerIndex = 0;
            for (const note of notes) {
                if (note.kind === 'pageLocation') {
                    document.body.appendChild(markerFor(note, pageMarkerIndex));
                    pageMarkerIndex += 1;
                    continue;
                }
                const nodes = createTextWalker();
                const info = nodes.find(node => note.endOffset >= node.start && note.endOffset <= node.end);
                if (!info) continue;
                try {
                    const range = document.createRange();
                    range.setStart(info.node, note.endOffset - info.start);
                    range.collapse(true);
                    range.insertNode(markerFor(note, 0));
                } catch (error) {}
            }
        })();
        """
        _ = try? await evaluate(script: js)
    }

    func navigate(to highlightAnchor: TextHighlightAnchor) async throws {
        try await go(to: highlightAnchor.locator)
        await scrollToHighlight(highlightAnchor)
    }

    private func scrollToHighlight(_ highlightAnchor: TextHighlightAnchor) async {
        guard highlightAnchor.precision == .exactTextRange,
              let start = highlightAnchor.startOffset else {
            return
        }
        let js = """
        (() => {
            function createTextWalker() {
                const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
                let offset = 0;
                const nodes = [];
                let node;
                while (node = walker.nextNode()) {
                    nodes.push({ node, start: offset, end: offset + node.textContent.length });
                    offset += node.textContent.length;
                }
                return nodes;
            }
            function findOffset(nodes, target) {
                for (const n of nodes) {
                    if (target >= n.start && target <= n.end) {
                        return { node: n.node, offset: target - n.start };
                    }
                }
                return null;
            }
            const nodes = createTextWalker();
            const info = findOffset(nodes, \(start));
            if (info) {
                const range = document.createRange();
                range.setStart(info.node, info.offset);
                range.collapse(true);
                const rect = range.getBoundingClientRect();
                if (rect.top < 0 || rect.bottom > window.innerHeight) {
                    info.node.parentElement.scrollIntoView({ block: 'center', behavior: 'smooth' });
                }
            }
        })();
        """
        _ = try? await evaluate(script: js)
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
            await renderNotes(storedNotes)
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
            await renderNotes(storedNotes)
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
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
    ) {
        guard navigationAction.request.url?.scheme == "varq-note",
              let host = navigationAction.request.url?.host,
              let noteID = UUID(uuidString: host) else {
            decisionHandler(.allow)
            return
        }
        noteActivationHandler?(noteID)
        decisionHandler(.cancel)
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
        await renderHighlights(storedHighlights)
        await renderNotes(storedNotes)
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
                    min-height: ${height}px !important;
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
                    text-align: justify !important;
                    -webkit-hyphens: auto !important;
                    orphans: 2 !important;
                    widows: 2 !important;
                }
                /* Only reset elements that commonly break columns; keep relative positioning intact */
                body > *, body section > *, body article > *, body div > * {
                    max-width: 100% !important;
                    white-space: normal !important;
                }
                p, li, blockquote, dd, td, th, figcaption {
                    overflow-wrap: break-word !important;
                    text-align: justify !important;
                }
                img, svg, video, canvas, figure {
                    max-width: 100% !important;
                    max-height: 80vh !important;
                    height: auto !important;
                    display: block !important;
                    margin: 0.5em auto !important;
                    float: none !important;
                    clear: both !important;
                }
                h1, h2, h3, h4, h5, h6 {
                    break-inside: avoid !important;
                    page-break-inside: avoid !important;
                    -webkit-column-break-inside: avoid !important;
                    text-align: left !important;
                }
                a, a:link, a:visited, a:hover, a:active {
                    color: inherit !important;
                    text-decoration: none !important;
                    border-bottom: none !important;
                }
                ::-webkit-scrollbar,
                *::-webkit-scrollbar,
                * *::-webkit-scrollbar {
                    display: none !important;
                    width: 0 !important;
                    height: 0 !important;
                }
                * {
                    scrollbar-width: none !important;
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

    private func serializeAnchors(_ anchors: [[String: Any]]) -> String {
        let items = anchors.compactMap { anchor -> WebHighlight? in
            guard let start = anchor["start"] as? Int,
                  let end = anchor["end"] as? Int,
                  let color = anchor["color"] as? String else {
                return nil
            }
            return WebHighlight(start: start, end: end, color: color)
        }
        guard let data = try? JSONEncoder().encode(items),
              let json = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return json
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

private struct WebHighlight: Encodable {
    let start: Int
    let end: Int
    let color: String
}

private struct WebNoteMarker: Encodable {
    let id: String
    let kind: ReadingNoteAnchorKind
    let endOffset: Int?
    let summary: String
    let color: String
}

private struct PaginationMetrics: Decodable {
    let clientWidth: Double
    let maximumOffset: Double
    let offset: Double
}
