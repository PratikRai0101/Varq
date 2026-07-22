import CoreGraphics
import Testing
import WebKit
@testable import Varq

@MainActor
struct ReaderWebViewContextMenuTests {
    @Test func forwardsDomContextMenuEventsToTheNativeMenuHandler() async throws {
        let webView = ReaderWebView(frame: .zero)
        let loader = WebViewLoadDelegate()
        try await loader.load("<p>Selected text</p>", into: webView)

        var receivedPoint: CGPoint?
        webView.varqContextMenuRequestHandler = { receivedPoint = $0 }
        let result = try await webView.evaluateJavaScript("""
        (() => {
            const selection = window.getSelection();
            const range = document.createRange();
            range.selectNodeContents(document.querySelector('p'));
            selection.removeAllRanges();
            selection.addRange(range);
            return document.dispatchEvent(new MouseEvent('contextmenu', {
                bubbles: true,
                cancelable: true,
                clientX: 17,
                clientY: 23
            }));
        })();
        """)
        let wasNotCancelled = try #require(result as? Bool)
        #expect(!wasNotCancelled)
        for _ in 0..<10 where receivedPoint == nil {
            await Task.yield()
        }

        #expect(receivedPoint?.x == 17)
        #expect(receivedPoint?.y == 23)
    }
}

@MainActor
private final class WebViewLoadDelegate: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func load(_ html: String, into webView: WKWebView) async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.navigationDelegate = self
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(
        _ webView: WKWebView,
        didFail navigation: WKNavigation!,
        withError error: Error
    ) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}
