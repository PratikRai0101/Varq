import Foundation
import Testing
@testable import Varq

struct ObsidianVaultExportServiceTests {
    @Test func writesStableManagedBookAndArtifactFiles() throws {
        let vault = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: vault) }
        let collection = BookCollection(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "Essays")
        let book = Book(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, title: "A Book", author: "An Author", libraryRelativePath: "book.epub", contentHash: "hash", format: .epub)
        book.collections = [collection]

        let report = try ObsidianVaultExportService().export(books: [book], to: vault)
        let bookFile = vault.appendingPathComponent("Varq/Books/\(book.id.uuidString).md")
        let artifactFile = vault.appendingPathComponent("Varq/Reading Artifacts/\(book.id.uuidString).md")

        #expect(report == ObsidianVaultExportReport(exportedBookCount: 1, skippedPrivateBookCount: 0))
        #expect(try String(contentsOf: bookFile, encoding: .utf8).contains("varq_id: \"\(book.id.uuidString)\""))
        #expect(try String(contentsOf: bookFile, encoding: .utf8).contains("[[Collections/\(collection.id.uuidString)|Essays]]"))
        #expect(FileManager.default.fileExists(atPath: artifactFile.path))
        #expect(try ObsidianVaultExportService().export(books: [book], to: vault) == report)
    }

    @Test func skipsPrivateBooks() throws {
        let vault = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: vault) }
        let book = Book(title: "Private", author: "Author", libraryRelativePath: "book.epub", contentHash: "hash", format: .epub, isPrivate: true)

        let report = try ObsidianVaultExportService().export(books: [book], to: vault)

        #expect(report == ObsidianVaultExportReport(exportedBookCount: 0, skippedPrivateBookCount: 1))
        #expect(!FileManager.default.fileExists(atPath: vault.appendingPathComponent("Varq/Books").path))
    }

    @Test func neverOverwritesAnUnmanagedFile() throws {
        let vault = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: vault) }
        let book = Book(title: "Book", author: "Author", libraryRelativePath: "book.epub", contentHash: "hash", format: .epub)
        let conflict = vault.appendingPathComponent("Varq/Books/\(book.id.uuidString).md")
        try FileManager.default.createDirectory(at: conflict.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "My vault note".write(to: conflict, atomically: true, encoding: .utf8)

        #expect(throws: ObsidianVaultExportError.unmanagedFileConflict("Books/\(book.id.uuidString).md")) {
            try ObsidianVaultExportService().export(books: [book], to: vault)
        }
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
