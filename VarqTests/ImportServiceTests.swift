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
