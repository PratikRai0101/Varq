import Foundation

// Stateless except for test-controlled failure settings; used only from MainActor tests.
final class FailingSessionCleanupFileManager: FileManager, @unchecked Sendable {
    var failingPath: String?
    var failDiscarded = false

    override func removeItem(at URL: URL) throws {
        if URL.path == failingPath || (failDiscarded && URL.lastPathComponent.hasPrefix(".discarded-")) {
            throw SessionCleanupTestError.denied
        }
        try super.removeItem(at: URL)
    }
}

enum SessionCleanupTestError: LocalizedError {
    case denied

    var errorDescription: String? { "Test reader-session cleanup denied." }
}
