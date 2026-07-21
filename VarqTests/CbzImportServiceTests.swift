import Foundation
import Testing
@testable import Varq

struct CbzImportServiceTests {
    @Test func importsCbzIntoTheManagedLibrary() async throws {
        let libraryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: libraryDirectory) }
        let service = ImportService(libraryDirectory: libraryDirectory)

        let importedBook = try await service.importCBZ(at: fixtureURL)

        #expect(importedBook.title == "minimal")
        #expect(importedBook.author == "Unknown Author")
        #expect(importedBook.coverImageData?.isEmpty == false)
        #expect(importedBook.format == .cbz)
        #expect(FileManager.default.fileExists(atPath: libraryDirectory.appendingPathComponent(importedBook.libraryRelativePath).path))
    }

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/minimal.cbz")
    }
}
