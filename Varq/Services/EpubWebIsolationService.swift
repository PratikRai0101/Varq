import Foundation
import WebKit

/// An EPUB is offline data, not a trusted web application. Install the resource
/// policy before loading any book document; compilation failures fail closed.
@MainActor
final class EpubWebIsolationService {
    static let shared = EpubWebIsolationService()
    private var compilation: Task<WKContentRuleList, any Error>?

    func prepare(_ webView: WKWebView) async throws {
        guard !webView.configuration.websiteDataStore.isPersistent else {
            throw EpubWebIsolationError.persistentDataStore
        }
        webView.configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let rules = try await compiledRules()
        webView.configuration.userContentController.add(rules)
    }

    private func compiledRules() async throws -> WKContentRuleList {
        if let compilation { return try await compilation.value }
        let task = Task<WKContentRuleList, any Error> {
            try await withCheckedThrowingContinuation { continuation in
                // Block every resource scheme except local files. WebKit treats
                // data URLs separately; they cannot contact a server. Navigation
                // is additionally restricted by the renderer's delegate.
                let json = """
                [{"trigger":{"url-filter":".*"},"action":{"type":"block"}},
                 {"trigger":{"url-filter":"^file:"},"action":{"type":"ignore-previous-rules"}}]
                """
                WKContentRuleListStore.default().compileContentRuleList(
                    forIdentifier: "dev.varq.epub.offline.v1", encodedContentRuleList: json
                ) { rules, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let rules { continuation.resume(returning: rules) }
                    else { continuation.resume(throwing: EpubWebIsolationError.ruleCompilationFailed) }
                }
            }
        }
        compilation = task
        do { return try await task.value }
        catch { compilation = nil; throw error }
    }
}

enum EpubWebIsolationError: LocalizedError {
    case persistentDataStore
    case ruleCompilationFailed
    var errorDescription: String? {
        switch self {
        case .persistentDataStore: "The EPUB reader requires isolated, nonpersistent website storage."
        case .ruleCompilationFailed: "Varq could not install the EPUB reader's offline security policy. The book was not opened."
        }
    }
}
