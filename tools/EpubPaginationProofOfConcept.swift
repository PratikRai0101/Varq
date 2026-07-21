// PROTOTYPE — validates the EPUB/WebKit CSS-columns decision; not production code.
import AppKit
import Foundation
import WebKit

@main
final class EpubPaginationProofOfConcept: NSObject, NSApplicationDelegate, WKNavigationDelegate {
    private let epubURL: URL
    private let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 640, height: 480))
    private var window: NSWindow?

    init(epubURL: URL) {
        self.epubURL = epubURL
    }

    static func main() {
        guard CommandLine.arguments.count == 2 else {
            fputs("Usage: EpubPaginationProofOfConcept <fixture.epub>\n", stderr)
            exit(EXIT_FAILURE)
        }

        let app = NSApplication.shared
        let delegate = EpubPaginationProofOfConcept(
            epubURL: URL(fileURLWithPath: CommandLine.arguments[1])
        )
        app.delegate = delegate
        app.setActivationPolicy(.regular)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let chapterHTML = try extractChapterHTML()
            let window = NSWindow(
                contentRect: webView.frame,
                styleMask: [.titled],
                backing: .buffered,
                defer: false
            )
            window.contentView = webView
            window.makeKeyAndOrderFront(nil)
            self.window = window

            webView.navigationDelegate = self
            webView.loadHTMLString(paginatedHTML(chapterHTML), baseURL: nil)
        } catch {
            finish(with: "EPUB pagination proof failed: \(error)", exitCode: EXIT_FAILURE)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        webView.evaluateJavaScript("""
        (() => {
            const root = document.body;
            const maximumOffset = root.scrollWidth - root.clientWidth;
            root.scrollLeft = maximumOffset * 0.5;
            return JSON.stringify({
                clientWidth: root.clientWidth,
                maximumOffset,
                restoredProgression: maximumOffset === 0 ? 0 : root.scrollLeft / maximumOffset
            });
        })();
        """) { [weak self] result, error in
            guard let self else { return }
            if let error {
                self.finish(with: "EPUB pagination proof failed: \(error)", exitCode: EXIT_FAILURE)
                return
            }
            guard let result = result as? String,
                  let data = result.data(using: .utf8),
                  let metrics = try? JSONDecoder().decode(PaginationMetrics.self, from: data) else {
                self.finish(with: "EPUB pagination proof failed: CSS columns did not return pagination metrics.", exitCode: EXIT_FAILURE)
                return
            }
            guard metrics.maximumOffset > 0,
                  abs(metrics.restoredProgression - 0.5) < 0.01 else {
                self.finish(with: "EPUB pagination proof failed: CSS columns did not produce a restorable offset. \(metrics)", exitCode: EXIT_FAILURE)
                return
            }

            print("EPUB pagination proof passed: clientWidth=\(metrics.clientWidth), maximumOffset=\(metrics.maximumOffset), restoredProgression=\(metrics.restoredProgression)")
            self.finish(with: "", exitCode: EXIT_SUCCESS)
        }
    }

    func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        finish(with: "EPUB pagination proof failed: \(error)", exitCode: EXIT_FAILURE)
    }

    private func extractChapterHTML() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", epubURL.path, "OEBPS/chapter-1.xhtml"]
        let output = Pipe()
        process.standardOutput = output
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == EXIT_SUCCESS,
              let html = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) else {
            throw ProofError.couldNotExtractFixtureChapter
        }
        return html
    }

    private func paginatedHTML(_ chapterHTML: String) -> String {
        let paginationStyle = """
        <style>
        html { width: 640px; height: 480px; margin: 0; overflow: hidden; }
        body { width: 640px; height: 480px; margin: 0; overflow: hidden; column-width: 640px; column-gap: 0; column-fill: auto; }
        p { margin: 0 0 1em; }
        </style>
        """
        return chapterHTML.replacingOccurrences(of: "</head>", with: "\(paginationStyle)</head>")
    }

    private func finish(with message: String, exitCode: Int32) {
        if !message.isEmpty {
            fputs("\(message)\n", stderr)
        }
        window?.close()
        NSApp.terminate(nil)
        exit(exitCode)
    }
}

private struct PaginationMetrics: Decodable {
    let clientWidth: Double
    let maximumOffset: Double
    let restoredProgression: Double
}

private enum ProofError: Error {
    case couldNotExtractFixtureChapter
}
