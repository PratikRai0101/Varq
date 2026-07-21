import Foundation
import Testing
@testable import Varq

struct EpubPublicationServiceTests {
    @Test func extractsTheFixtureSpineIntoAnEphemeralDirectory() async throws {
        let extractionDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: extractionDirectory) }
        let service = EpubPublicationService()

        let publication = try await service.extract(at: fixtureURL, into: extractionDirectory)

        #expect(publication.spine.count == 1)
        #expect(publication.spine.first?.href == "chapter-1.xhtml")
        #expect(FileManager.default.fileExists(atPath: publication.spine[0].fileURL.path))

        try await service.remove(publication)
        #expect(!FileManager.default.fileExists(atPath: extractionDirectory.path))
    }

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/minimal.epub")
    }
}
