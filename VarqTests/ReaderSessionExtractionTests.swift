import AppKit
import Foundation
import Testing
import WebKit
@testable import Varq

@MainActor
struct ReaderSessionExtractionTests {
    @Test func restartRemovesAbandonedEpubAndComicExtractionTrees() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        var owner: ReaderSessionStorageService? = ReaderSessionStorageService(rootDirectory: directory)
        let epubDirectory = try #require(owner).makeDirectory()
        let comicDirectory = try #require(owner).makeDirectory()
        let epub = try await EpubPublicationService().extract(at: fixture("minimal.epub"), into: epubDirectory)
        let comic = try await CbzPublicationService().extract(at: fixture("minimal.cbz"), into: comicDirectory)
        let chapter = try #require(epub.spine.first).fileURL
        let page = try #require(comic.pages.first).fileURL
        #expect(FileManager.default.fileExists(atPath: chapter.path))
        #expect(FileManager.default.fileExists(atPath: page.path))
        owner = nil

        try ReaderSessionStorageService(rootDirectory: directory).cleanupStaleSessions()

        #expect(!FileManager.default.fileExists(atPath: chapter.path))
        #expect(!FileManager.default.fileExists(atPath: page.path))
    }

    @Test func epubRendererUsesALeasedExtractionAndReleasesItOnClose() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .init(x: 0, y: 0, width: 900, height: 700), configuration: configuration)
        let renderer = EpubWebRenderer(webView: webView, publicationService: EpubPublicationService(), sessionRootDirectory: directory)
        try await renderer.open(bookURL: fixture("minimal.epub"))
        let chapter = try #require(webView.url)
        let cleanup = ReaderSessionStorageService(rootDirectory: directory.appendingPathComponent("ReaderSessions"))
        try cleanup.cleanupStaleSessions()
        #expect(FileManager.default.fileExists(atPath: chapter.path))

        await renderer.close()

        #expect(!FileManager.default.fileExists(atPath: chapter.path))
    }

    @Test func defaultEpubViewDoesNotPersistWebsiteData() throws {
        _ = NSApplication.shared
        let renderer = EpubWebRenderer()
        let webView = try #require(renderer.view as? WKWebView)
        #expect(!webView.configuration.websiteDataStore.isPersistent)
    }

    private func fixture(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures").appendingPathComponent(name)
    }
}
