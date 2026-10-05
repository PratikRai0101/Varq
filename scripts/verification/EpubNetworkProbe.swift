import AppKit
import CryptoKit
import Foundation
import Security
import WebKit

/// Runs real production EPUB rendering inside an independently signed sandbox.
/// A verification-only delegate pins the ephemeral loopback TLS cert and
/// forwards all renderer navigation decisions/completions unchanged.
@main
struct EpubNetworkProbe {
    @MainActor
    static func main() async {
        do {
            let args = CommandLine.arguments
            guard args.count == 2 || (args.count == 3 && args[2] == "--leak-control") else { throw Failure.failed("Expected outside-container canary path and optional --leak-control") }
            try assertSandbox(URL(fileURLWithPath: CommandLine.arguments[1]))
            _ = NSApplication.shared
            NSApp.setActivationPolicy(.accessory)
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("EpubNetworkVerification-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            if args.count == 3 {
                for mode in ["public", "private"] { try await positiveControl(in: root, fixtureMode: mode) }
                print("PASS: deliberate unhardened public/private leak control exercised")
                return
            }
            try await positiveControl(in: root)
            for mode in ["public", "private"] {
                try await isolatedReader(mode: mode, in: root)
            }
            print("PASS: signed sandbox production EPUB renderer, local assets, annotations, chapter turns, and close/reopen")
        } catch {
            FileHandle.standardError.write(Data("Verification failed: \(error)\n".utf8))
            exit(1)
        }
    }

    @MainActor
    private static func makeView() -> (WKWebView, NSWindow) {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .init(x: 0, y: 0, width: 900, height: 700), configuration: config)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFrontRegardless()
        return (view, window)
    }

    @MainActor
    private static func positiveControl(in root: URL, fixtureMode: String = "control") async throws {
        let certURL = try required(Bundle.main.url(forResource: "server-cert", withExtension: "der"))
        let trust = VerificationNavigationDelegate(certificate: try Data(contentsOf: certURL))
        let (view, window) = makeView()
        defer { view.stopLoading(); window.close(); withExtendedLifetime(trust) {} }
        view.navigationDelegate = trust
        let extraction = root.appendingPathComponent("unhardened-" + fixtureMode)
        let publication = try await EpubPublicationService().extract(at: fixture(fixtureMode), into: extraction)
        try await load(publication.spine[0].fileURL, root: publication.rootDirectory, in: view)
        _ = try await number("document.fonts.load('17px RemoteProbehttp', 'A');document.fonts.load('17px RemoteProbehttps', 'A');document.fonts.load('17px DirectProbehttp','A');document.fonts.load('17px DirectProbehttps','A');0", in: view)
        try await Task.sleep(for: .seconds(1))
        try check(try await number("document.documentElement.getAttributeNames().filter(n=>n.startsWith('data-author-')).length", in: view) >= 4, "Unhardened author scripts/events did not run")
        for scheme in ["http", "https"] {
            _ = try await number("document.getElementById('link-\(scheme)').click();0", in: view)
            try await Task.sleep(for: .milliseconds(300))
            _ = try await number("document.getElementById('form-\(scheme)').submit();0", in: view)
            try await Task.sleep(for: .milliseconds(300))
        }
        for scheme in ["http", "https"] {
            try await load(publication.spine[0].fileURL, root: publication.rootDirectory, in: view)
            _ = try await number("document.getElementById('main-\(scheme)').click();0", in: view)
            try await Task.sleep(for: .milliseconds(500))
            try check(view.url?.scheme == scheme, "Unhardened main-frame navigation did not reach \(scheme)")
        }
        for index in [1, 2] {
            try await load(publication.spine[index].fileURL, root: publication.rootDirectory, in: view)
            try await Task.sleep(for: .milliseconds(500))
            try check(view.url?.scheme == (index == 1 ? "http" : "https"), "Unhardened meta redirect did not run")
        }
        print("PASS: unhardened real WebKit executes author code and permits loopback HTTP/HTTPS navigation")
    }

    @MainActor
    private static func isolatedReader(mode: String, in root: URL) async throws {
        let (view, window) = makeView()
        defer { window.close() }
        let renderer = EpubWebRenderer(webView: view, publicationService: EpubPublicationService(), sessionRootDirectory: root.appendingPathComponent(mode))
        let certURL = try required(Bundle.main.url(forResource: "server-cert", withExtension: "der"))
        let delegate = VerificationNavigationDelegate(certificate: try Data(contentsOf: certURL), renderer: renderer)
        view.navigationDelegate = delegate
        defer { withExtendedLifetime(delegate) {} }
        let source = try fixture(mode)
        var readingURL = source
        var session: PrivateBookSessionService?
        var ciphertext: Data?
        var encryptedURL: URL?
        if mode == "private" {
            let store = FixtureKeyStore()
            let book = Book(title: "Original network fixture", author: "Varq", libraryRelativePath: "private.epub", contentHash: "fixture", format: .epub, isPrivate: true)
            let key = SymmetricKey(size: .bits256)
            try store.store(key, for: book.id)
            let managed = root.appendingPathComponent("private.epub")
            let encrypted = try PrivateBookCryptoService().encrypt(Data(contentsOf: source), using: key)
            try encrypted.write(to: managed, options: .atomic)
            let storage = ReaderSessionStorageService(rootDirectory: root.appendingPathComponent("PrivateReaderSessions"))
            let privateSession = PrivateBookSessionService(keyStore: store, storage: storage)
            readingURL = try privateSession.readerURL(for: book, managedFileURL: managed)
            session = privateSession
            ciphertext = encrypted
            encryptedURL = managed
        }
        do {
            try await renderer.open(bookURL: readingURL)
            try await Task.sleep(for: .seconds(1))
            try await verifyLocalContent(view, renderer: renderer)
            let original = view.url
            for scheme in ["http", "https"] {
                for id in ["link-", "main-", "window-"] {
                    _ = try await number("document.getElementById('\(id)\(scheme)').click();0", in: view)
                    try await Task.sleep(for: .milliseconds(100))
                    try check(view.url == original, "\(mode) escaped to an external link")
                }
                _ = try await number("document.getElementById('form-\(scheme)').submit();0", in: view)
                try await Task.sleep(for: .milliseconds(100))
                try check(view.url == original, "\(mode) form escaped its spine document")
            }
            for id in ["javascript-link", "outside-link"] {
                _ = try await number("document.getElementById('\(id)').click();0", in: view)
                try await Task.sleep(for: .milliseconds(100))
                try check(view.url == original, "\(mode) escaped to author script or outside file")
            }
            try check(try await number("document.documentElement.getAttributeNames().filter(n=>n.startsWith('data-author-')).length", in: view) == 0, "Author script executed after interactions")
            try await verifyAnnotations(view, renderer: renderer)
            try check(try await renderer.goForward(), "Page turn did not advance")
            try check(try await renderer.goBackward(), "Page turn did not return")
            for (index, href) in [(1, "http-redirect.xhtml"), (2, "https-redirect.xhtml")] {
                try await renderer.go(to: BookLocator(format: .epub, spineIndex: index, resourceHref: href, progression: 0))
                try await Task.sleep(for: .milliseconds(500))
                try check(view.url?.isFileURL == true && renderer.currentLocator?.spineIndex == index, "\(mode) meta redirect escaped the local spine")
                try check(try await renderer.currentChapterText()?.contains("redirect chapter.") == true, "Local redirect chapter is unreadable")
            }
            await renderer.close()
            try await renderer.open(bookURL: readingURL)
            try await verifyLocalContent(view, renderer: renderer)
            window.setContentSize(.init(width: 520, height: 700))
            window.contentView?.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(100))
            try await renderer.updateViewport()
            try check(try await number("Math.abs(parseFloat(getComputedStyle(document.documentElement).width)-innerWidth)", in: view) < 1, "Pagination did not reflow")
            await renderer.close()
            if let encryptedURL, let ciphertext {
                try check(try Data(contentsOf: encryptedURL) == ciphertext, "Private managed ciphertext changed")
            }
            try session?.endApplicationSession()
            if mode == "private" { try check(!FileManager.default.fileExists(atPath: readingURL.path), "Private plaintext survived session close") }
            print("PASS: \(mode) offline assets, navigation, annotations, reflow, and session cleanup")
        } catch {
            await renderer.close()
            try? session?.endApplicationSession()
            throw error
        }
    }

    @MainActor
    private static func verifyLocalContent(_ view: WKWebView, renderer: EpubWebRenderer) async throws {
        _ = try await number("document.fonts.load('17px LocalProbe','A');0", in: view)
        for _ in 0..<100 {
            if try await number("Array.from(document.fonts).some(f=>f.family==='LocalProbe'&&f.status==='loaded')?1:0", in: view) == 1 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        try check(try await number("Array.from(document.fonts).some(f=>f.family==='LocalProbe'&&f.status==='loaded')?1:0", in: view) == 1, "Local original font failed to load")
        try check(try await number("parseFloat(getComputedStyle(document.getElementById('local-text')).paddingLeft)", in: view) == 17, "Local imported stylesheet failed")
        for id in ["local-image", "data-image"] {
            try check(try await number("document.getElementById('\(id)').naturalWidth", in: view) == 1, "Local/data image failed")
        }
        try check(try await number("document.documentElement.getAttributeNames().filter(n=>n.startsWith('data-author-')).length", in: view) == 0, "Author inline/local/remote/event scripts ran")
        try check(try await renderer.currentChapterText()?.contains("Safe local chapter.") == true, "Trusted chapter extraction failed")
        try check(try await number("document.querySelectorAll('#varq-pagination-style').length", in: view) == 1, "Trusted pagination style missing")
    }

    @MainActor
    private static func verifyAnnotations(_ view: WKWebView, renderer: EpubWebRenderer) async throws {
        let locator = try required(renderer.currentLocator)
        let offset = Int(try await number("document.body.textContent.indexOf('Safe local chapter.')", in: view))
        let anchor = try TextHighlightAnchor(locator: locator, startOffset: offset, endOffset: offset + 4, quote: TextQuoteSelector(exact: "Safe"))
        await renderer.renderHighlights([Highlight(locatorData: try JSONEncoder().encode(anchor), selectedText: "Safe", colorTag: "saffron")])
        try check(try await number("document.querySelectorAll('mark.varq-highlight').length", in: view) == 1, "Trusted highlight failed")
        let note = ReadingNote(anchorData: try JSONEncoder().encode(ReadingNoteAnchor(pageLocator: locator)), body: "Fixture note", colorTag: "saffron")
        var activated: UUID?
        renderer.setNoteActivationHandler { activated = $0 }
        await renderer.renderNotes([note])
        _ = try await number("document.querySelector('a.varq-page-note-marker').click();0", in: view)
        for _ in 0..<100 {
            if activated == note.id { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        try check(activated == note.id, "Trusted note marker did not activate")
    }

    @MainActor
    private static func load(_ url: URL, root: URL, in view: WKWebView) async throws {
        guard view.loadFileURL(url, allowingReadAccessTo: root) != nil else { throw Failure.failed("Control load failed") }
        try await Task.sleep(for: .milliseconds(100))
        for _ in 0..<300 {
            if !view.isLoading { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw Failure.failed("Control page load timed out")
    }

    @MainActor
    private static func number(_ script: String, in view: WKWebView) async throws -> Double {
        try await withCheckedThrowingContinuation { continuation in
            view.evaluateJavaScript(script, in: nil, in: .defaultClient) { result in
                switch result {
                case .success(let value):
                    guard let number = value as? NSNumber else { continuation.resume(throwing: Failure.failed("Expected JavaScript number")); return }
                    continuation.resume(returning: number.doubleValue)
                case .failure(let error): continuation.resume(throwing: error)
                }
            }
        }
    }
    private static func fixture(_ name: String) throws -> URL { try required(Bundle.main.url(forResource: name, withExtension: "epub", subdirectory: "Fixtures")) }
    private static func required<T>(_ value: T?) throws -> T { guard let value else { throw Failure.failed("Missing required value") }; return value }
    private static func check(_ value: Bool, _ message: String) throws { if !value { throw Failure.failed(message) } }
    private static func assertSandbox(_ url: URL) throws {
        do { _ = try Data(contentsOf: url) }
        catch {
            let e = error as NSError
            try check(e.domain == NSCocoaErrorDomain && e.code == NSFileReadNoPermissionError, "Canary failed for a reason other than sandbox denial")
            return
        }
        throw Failure.failed("Outside-container canary readable; sandbox is absent")
    }
    enum Failure: Error { case failed(String) }
}

@MainActor
private final class VerificationNavigationDelegate: NSObject, WKNavigationDelegate {
    let certificate: Data
    let renderer: EpubWebRenderer?
    init(certificate: Data, renderer: EpubWebRenderer? = nil) {
        self.certificate = certificate
        self.renderer = renderer
    }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, preferences: WKWebpagePreferences, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        if let renderer { renderer.webView(webView, decidePolicyFor: action, preferences: preferences, decisionHandler: decisionHandler) }
        else { decisionHandler(.allow, preferences) }
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        renderer?.webView(webView, didFinish: navigation)
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        renderer?.webView(webView, didFail: navigation, withError: error)
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        renderer?.webView(webView, didFailProvisionalNavigation: navigation, withError: error)
    }
    func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              challenge.protectionSpace.host == "127.0.0.1", let trust = challenge.protectionSpace.serverTrust,
              let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate], let leaf = chain.first,
              SecCertificateCopyData(leaf) as Data == certificate else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }
}

private final class FixtureKeyStore: PrivateBookKeyStoring {
    private var keys: [UUID: SymmetricKey] = [:]
    func store(_ key: SymmetricKey, for bookID: UUID) throws { keys[bookID] = key }
    func key(for bookID: UUID, authenticationPrompt: String) throws -> SymmetricKey {
        guard let key = keys[bookID] else { throw EpubNetworkProbe.Failure.failed("Missing fixture key") }
        return key
    }
    func removeKey(for bookID: UUID) throws { keys[bookID] = nil }
}
