import Foundation
import Testing
@testable import Varq

struct ContentHashServiceTests {
    @Test func hashesFileContentWithSHA256() async throws {
        let hash = try await ContentHashService().hash(of: fixtureURL)
        #expect(hash == "92d762053739df652863577f28ec06178241e34a8b8b38f889783dd8a38671de")
    }

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/minimal.epub")
    }
}
