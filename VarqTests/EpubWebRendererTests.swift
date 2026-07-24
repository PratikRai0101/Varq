import AppKit
import Foundation
import Testing
import WebKit
@testable import Varq

@MainActor
struct EpubWebRendererTests {
    @Test func reflowsPaginationWhenViewportChanges() async throws {
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 900, height: 700))
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
