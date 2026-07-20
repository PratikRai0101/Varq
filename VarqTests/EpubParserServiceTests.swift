import Foundation
import Testing
@testable import Varq

struct EpubParserServiceTests {
    @Test func parsesMetadataAndCoverFromAnEpub() async throws {
        let service = EpubParserService()

        let metadata = try await service.parse(at: fixtureURL)

        #expect(metadata.title == "Varq Fixture")
        #expect(metadata.author == "Varq Tests")
        #expect(metadata.coverImageData?.isEmpty == false)
    }

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/minimal.epub")
    }
}
