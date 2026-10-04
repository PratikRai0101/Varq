import Foundation
import Testing
import WebKit
@testable import Varq

@MainActor
struct EpubWebIsolationServiceTests {
    @Test func rejectsPersistentStorageBeforeAnyBookCanLoad() async throws {
        let view = WKWebView(frame: .zero)
        do {
            try await EpubWebIsolationService().prepare(view)
            Issue.record("Persistent website storage must be rejected")
        } catch {
            #expect(error is EpubWebIsolationError)
            #expect(view.url == nil)
        }
    }

    @Test func preparesMultipleEphemeralViewsWithContentScriptsDisabled() async throws {
        let service = EpubWebIsolationService()
        for _ in 0..<2 {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            let view = WKWebView(frame: .zero, configuration: configuration)
            try await service.prepare(view)
            #expect(!view.configuration.websiteDataStore.isPersistent)
            #expect(!view.configuration.defaultWebpagePreferences.allowsContentJavaScript)
        }
    }
}
