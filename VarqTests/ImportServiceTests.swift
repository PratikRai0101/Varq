import Foundation
import Testing
@testable import Varq

struct ImportServiceTests {
    @Test func importsEpubIntoTheManagedLibrary() async throws {
        let libraryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: libraryDirectory)
        }
        let service = ImportService(libraryDirectory: libraryDirectory)

        let importedBook = try await service.importEpub(at: fixtureURL)

        #expect(importedBook.title == "Varq Fixture")
        #expect(importedBook.author == "Varq Tests")
        #expect(importedBook.coverImageData?.isEmpty == false)
        #expect(importedBook.format == .epub)
        #expect(importedBook.contentHash == "92d762053739df652863577f28ec06178241e34a8b8b38f889783dd8a38671de")
        #expect(
            FileManager.default.fileExists(
                atPath: libraryDirectory
                    .appendingPathComponent(importedBook.libraryRelativePath)
                    .path
            )
        )
    }

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/minimal.epub")
    }
}
