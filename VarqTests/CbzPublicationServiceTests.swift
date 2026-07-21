import Foundation
import Testing
@testable import Varq

struct CbzPublicationServiceTests {
    @Test func extractsImagePagesIntoTheRequestedDirectory() async throws {
        let rootDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: rootDirectory) }
        let service = CbzPublicationService()

        let publication = try await service.extract(at: fixtureURL, into: rootDirectory)

        #expect(publication.pages.map(\.archivePath) == ["001.png", "002.png"])
        #expect(publication.pages.allSatisfy { FileManager.default.fileExists(atPath: $0.fileURL.path) })

        try await service.remove(publication)
        #expect(!FileManager.default.fileExists(atPath: rootDirectory.path))
    }

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/minimal.cbz")
    }
}
