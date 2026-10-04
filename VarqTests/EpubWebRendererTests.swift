import AppKit
import Foundation
import Testing
import WebKit
@testable import Varq

@MainActor
struct EpubWebRendererTests {
    @Test func reflowsPaginationWhenViewportChanges() async throws {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 900, height: 700), configuration: config)
        webView.autoresizingMask = [.width, .height]
        let window = NSWindow(
            contentRect: .init(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = webView
        window.orderFrontRegardless()
        defer { window.close() }

        let renderer = EpubWebRenderer(
            webView: webView,
            publicationService: EpubPublicationService(),
            sessionRootDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("VarqEpubWebRendererTests", isDirectory: true)
        )
        defer { Task { await renderer.close() } }

        try await renderer.open(bookURL: epubFixtureURL)
        window.setContentSize(.init(width: 520, height: 700))
        window.contentView?.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))

        try await renderer.updateViewport()

        let viewportWidth = try await browserNumber("window.innerWidth", in: webView)
        let paginationWidth = try await browserNumber(
            "Number.parseFloat(getComputedStyle(document.documentElement).width)",
            in: webView
        )
        let viewportHeight = try await browserNumber("window.innerHeight", in: webView)
        let paginationHeight = try await browserNumber(
            "Number.parseFloat(getComputedStyle(document.body).height)",
            in: webView
        )

        #expect(abs(paginationWidth - viewportWidth) < 1)
        #expect(abs(paginationHeight - viewportHeight) < 1)
    }

    @Test func bookAuthoredScriptsDoNotExecuteButReaderScriptsStillWork() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let book = try makeIsolationEpub(in: root, chapter: """
        <html xmlns="http://www.w3.org/1999/xhtml"><head><script>document.documentElement.setAttribute('data-book-script', 'ran');</script>
        <script src="evil.js"></script></head>
        <body onload="document.documentElement.setAttribute('data-book-event', 'ran')">
        <p>Safe readable chapter.</p>
        <a id="script-link" href="javascript:document.documentElement.setAttribute('data-book-url', 'ran')">Unsafe action</a>
        </body></html>
        """, resources: ["OEBPS/evil.js": Data("document.documentElement.setAttribute('data-book-external', 'ran');".utf8)])
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 900, height: 700), configuration: config)
        let renderer = EpubWebRenderer(webView: webView, publicationService: EpubPublicationService(), sessionRootDirectory: root)
        try await renderer.open(bookURL: book)
        _ = try await browserNumber("document.getElementById('script-link').click(); 0", in: webView)

        let count = try await browserNumber("document.documentElement.getAttributeNames().filter(n => n.startsWith('data-book-')).length", in: webView)
        #expect(count == 0)
        #expect(try await renderer.currentChapterText()?.contains("Safe readable chapter.") == true)
        #expect(try await browserNumber("document.querySelectorAll('#varq-pagination-style').length", in: webView) == 1)
        let locator = try #require(renderer.currentLocator)
        let offset = Int(try await browserNumber("document.body.textContent.indexOf('Safe readable')", in: webView))
        let anchor = try TextHighlightAnchor(locator: locator, startOffset: offset, endOffset: offset + 4, quote: TextQuoteSelector(exact: "Safe"))
        await renderer.renderHighlights([Highlight(locatorData: try JSONEncoder().encode(anchor), selectedText: "Safe", colorTag: "saffron")])
        #expect(try await browserNumber("document.querySelectorAll('mark.varq-highlight').length", in: webView) == 1)
        let note = ReadingNote(anchorData: try JSONEncoder().encode(ReadingNoteAnchor(pageLocator: locator)), body: "Local note", colorTag: "saffron")
        var activatedNote: UUID?
        renderer.setNoteActivationHandler { activatedNote = $0 }
        await renderer.renderNotes([note])
        _ = try await browserNumber("document.querySelector('a.varq-page-note-marker').click(); 0", in: webView)
        try await Task.sleep(for: .milliseconds(50))
        #expect(activatedNote == note.id)
        await renderer.close()
    }

    @Test func unhardenedWebViewExecutesAuthorScriptsAndLoadsProbeResources() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let chapter = root.appendingPathComponent("control.html")
        try Data("""
        <html><head><link rel="stylesheet" href="remoteprobe://assets/control.css"/>
        <script>document.documentElement.setAttribute('data-book-script', 'ran');</script>
        </head><body>Positive control.</body></html>
        """.utf8).write(to: chapter)
        let probe = EpubProbeSchemeHandler()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(probe, forURLScheme: "remoteprobe")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.loadFileURL(chapter, allowingReadAccessTo: root)
        defer { webView.stopLoading() }
        for _ in 0..<100 {
            if !probe.requests.isEmpty && !webView.isLoading { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(probe.requests.count == 1)
        #expect(try await browserNumber("document.documentElement.hasAttribute('data-book-script') ? 1 : 0", in: webView) == 1)
    }

    @Test func blocksNonlocalResourcesWhileKeepingLocalStylesAndImages() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let png = try #require(Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLbtAAAAABJRU5ErkJggg=="))
        let book = try makeIsolationEpub(in: root, chapter: """
        <html xmlns="http://www.w3.org/1999/xhtml"><head>
        <link rel="stylesheet" href="local.css"/><link rel="stylesheet" href="remoteprobe://assets/remote.css"/>
        </head><body><p id="local-content">Offline chapter.</p><img id="local-image" src="local.png"/>
        <iframe src="remoteprobe://assets/frame.html"></iframe>
        <a id="remote-link" href="https://example.invalid/private-content">Remote link</a>
        <a id="outside-link" href="file:///etc/hosts">Outside file</a>
        <a id="window-link" href="chapter.xhtml" target="_blank">New window</a>
        <a id="unknown-note" href="varq-note://00000000-0000-0000-0000-000000000000">Unknown note</a>
        </body></html>
        """, resources: ["OEBPS/local.css": Data("#local-content {padding-left:17px;}".utf8), "OEBPS/local.png": png])
        let probe = EpubProbeSchemeHandler()
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        config.setURLSchemeHandler(probe, forURLScheme: "remoteprobe")
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 900, height: 700), configuration: config)
        let renderer = EpubWebRenderer(webView: webView, publicationService: EpubPublicationService(), sessionRootDirectory: root)
        try await renderer.open(bookURL: book)

        #expect(probe.requests.isEmpty)
        #expect(try await browserNumber("parseFloat(getComputedStyle(document.getElementById('local-content')).paddingLeft)", in: webView) == 17)
        #expect(try await browserNumber("document.getElementById('local-image').naturalWidth", in: webView) == 1)
        let originalURL = webView.url
        var activatedNote: UUID?
        renderer.setNoteActivationHandler { activatedNote = $0 }
        for id in ["remote-link", "outside-link", "window-link", "unknown-note"] {
            _ = try await browserNumber("document.getElementById('\(id)').click(); 0", in: webView)
            try await Task.sleep(for: .milliseconds(100))
            #expect(webView.url == originalURL)
        }
        #expect(activatedNote == nil)
        #expect(probe.requests.isEmpty)
        await renderer.close()
    }

    private var epubFixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/minimal.epub")
    }

    private func browserNumber(_ expression: String, in webView: WKWebView) async throws -> Double {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(expression) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let number = result as? NSNumber {
                    continuation.resume(returning: number.doubleValue)
                } else {
                    continuation.resume(throwing: EpubWebRendererTestError.expectedNumber)
                }
            }
        }
    }
}

private enum EpubWebRendererTestError: Error {
    case expectedNumber
}
