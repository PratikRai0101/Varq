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

    @Test func refusesDiscardingAManagedCopyWhoseContentChanged() async throws {
        let library = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: library) }
        let service = ImportService(libraryDirectory: library)
        let imported = try await service.importEpub(at: fixtureURL)
        let managed = library.appendingPathComponent(imported.libraryRelativePath)
        let changed = Data("unrecognized replacement".utf8)
        try changed.write(to: managed)

        do {
            try await service.discardImportedBook(at: imported.libraryRelativePath)
            Issue.record("An unrecognized managed copy must not be deleted")
        } catch {
            #expect(try Data(contentsOf: managed) == changed)
        }
    }

    @Test func hashesAndParsesTheManagedPdfSnapshotNotAChangingOriginal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let pdfFixture = fixtureURL.deletingLastPathComponent().appendingPathComponent("minimal.pdf")
        let source = root.appendingPathComponent("Original.pdf")
        try FileManager.default.copyItem(at: pdfFixture, to: source)
        let library = root.appendingPathComponent("Library")
        let manager = ImportRecoveryTestFileManager()
        manager.mutateOriginalAfterCopy = true
        let imported = try await ImportService(libraryDirectory: library, fileManager: manager).importPDF(at: source)
        let managed = library.appendingPathComponent(imported.libraryRelativePath)

        #expect(imported.title == "Original")
        #expect(try await ContentHashService().hash(of: managed) == imported.contentHash)
        #expect(try Data(contentsOf: source) == Data("changed original".utf8))
        let expected = try Data(contentsOf: pdfFixture)
        #expect(try Data(contentsOf: managed) == expected)
    }

    private var fixtureURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/minimal.epub")
    }
}
