import Foundation
import Testing
@testable import Varq

struct PdfImportServiceTests {
    @Test func importsPdfIntoTheManagedLibrary() async throws {
        let libraryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: libraryDirectory)
        }
        let service = ImportService(libraryDirectory: libraryDirectory)

        let importedBook = try await service.importPDF(at: fixtureURL)

        #expect(importedBook.title == "minimal")
        #expect(importedBook.author == "Unknown Author")
        #expect(importedBook.coverImageData?.isEmpty == false)
        #expect(importedBook.format == .pdf)
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
            .appendingPathComponent("Fixtures/minimal.pdf")
    }
}
