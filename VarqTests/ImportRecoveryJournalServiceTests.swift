import Foundation
import Testing
@testable import Varq

@MainActor
struct ImportRecoveryJournalServiceTests {
    private let fixtureHash = "92d762053739df652863577f28ec06178241e34a8b8b38f889783dd8a38671de"

    @Test func restartBeforeCopyRemovesOnlyTheRecordedEmptyImport() throws {
        let library = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: library) }
        let journal = ImportRecoveryJournalService()
        _ = try journal.begin(format: .epub, contentHash: fixtureHash, in: library)
        let legacy = library.appendingPathComponent("unmarked.epub")
        try Data("unknown legacy book".utf8).write(to: legacy)

        try ImportRecoveryJournalService().recover(in: library, committedBooks: [])

        #expect(try !journal.hasPendingImports(in: library))
        #expect(try Data(contentsOf: legacy) == Data("unknown legacy book".utf8))
    }

    @Test func restartKeepsACommittedCopyButRemovesAnUncommittedCopy() async throws {
        for committed in [false, true] {
            let library = temporaryLibrary()
            defer { try? FileManager.default.removeItem(at: library) }
            let imported = try await ImportService(libraryDirectory: library).importEpub(at: fixtureURL)
            let books = committed ? [CommittedImportBook(id: imported.id, fileName: imported.libraryRelativePath,
                                                        contentHash: imported.contentHash, isPrivate: false)] : []

            try ImportRecoveryJournalService().recover(in: library, committedBooks: books)

            #expect(FileManager.default.fileExists(atPath: library.appendingPathComponent(imported.libraryRelativePath).path) == committed)
            #expect(try !ImportRecoveryJournalService().hasPendingImports(in: library))
            if committed {
                let expected = try Data(contentsOf: fixtureURL)
                #expect(try Data(contentsOf: library.appendingPathComponent(imported.libraryRelativePath)) == expected)
            }
        }
    }

    @Test func conflictingOwnershipAndChangedContentArePreserved() async throws {
        let library = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: library) }
        let imported = try await ImportService(libraryDirectory: library).importEpub(at: fixtureURL)
        let otherOwner = CommittedImportBook(id: UUID(), fileName: imported.libraryRelativePath, contentHash: imported.contentHash, isPrivate: false)
        #expect(throws: ImportRecoveryError.self) {
            try ImportRecoveryJournalService().recover(in: library, committedBooks: [otherOwner])
        }
        let managed = library.appendingPathComponent(imported.libraryRelativePath)
        let unknown = Data("unknown replacement".utf8)
        try unknown.write(to: managed)
        #expect(throws: ImportRecoveryError.self) {
            try ImportRecoveryJournalService().recover(in: library, committedBooks: [])
        }
        #expect(try Data(contentsOf: managed) == unknown)
        #expect(try ImportRecoveryJournalService().hasPendingImports(in: library))
    }

    @Test func corruptedMetadataAndUnknownEntriesAreNotRemoved() async throws {
        for damage in ["json", "checksum", "unknown-entry"] {
            let library = temporaryLibrary()
            defer { try? FileManager.default.removeItem(at: library) }
            let imported = try await ImportService(libraryDirectory: library).importEpub(at: fixtureURL)
            let directory = library.appendingPathComponent(".book-imports/" + imported.id.uuidString)
            let recordURL = directory.appendingPathComponent("record.json")
            if damage == "json" {
                try Data("damaged record".utf8).write(to: recordURL)
            } else if damage == "checksum" {
                var record = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: recordURL)) as? [String: Any])
                record["checksum"] = "invalid checksum"
                try JSONSerialization.data(withJSONObject: record).write(to: recordURL)
            } else {
                try Data("unknown artifact".utf8).write(to: directory.appendingPathComponent("unknown"))
            }
            do {
                try ImportRecoveryJournalService().recover(in: library, committedBooks: [])
                Issue.record("Unknown recovery state must not be removed")
            } catch {
                #expect(FileManager.default.fileExists(atPath: directory.path))
                #expect(FileManager.default.fileExists(atPath: library.appendingPathComponent(imported.libraryRelativePath).path))
            }
        }
    }

    @Test func retriesInterruptedCompletedCleanupEvenWithoutItsRecord() async throws {
        let library = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: library) }
        let manager = ImportRecoveryTestFileManager()
        let service = ImportService(libraryDirectory: library, fileManager: manager)
        let imported = try await service.importEpub(at: fixtureURL)
        manager.failCompletedRemoval = true
        do { try await service.discardImportedBook(at: imported.libraryRelativePath); Issue.record("Expected cleanup failure") }
        catch { }
        let completed = library.appendingPathComponent(".book-imports/.completed-" + imported.id.uuidString)
        try FileManager.default.removeItem(at: completed.appendingPathComponent("record.json"))
        manager.failCompletedRemoval = false

        try ImportRecoveryJournalService(fileManager: manager).recover(in: library, committedBooks: [])

        #expect(try !ImportRecoveryJournalService().hasPendingImports(in: library))
        #expect(!FileManager.default.fileExists(atPath: completed.path))
    }

    @Test func rejectsSymlinkedJournalAndLeavesTheTargetIntact() throws {
        let library = temporaryLibrary()
        let outside = temporaryLibrary()
        defer { try? FileManager.default.removeItem(at: library); try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let original = outside.appendingPathComponent("keep")
        try Data("external".utf8).write(to: original)
        try FileManager.default.createSymbolicLink(at: library.appendingPathComponent(".book-imports"), withDestinationURL: outside)
        #expect(throws: ImportRecoveryError.self) { try ImportRecoveryJournalService().recover(in: library, committedBooks: []) }
        #expect(try Data(contentsOf: original) == Data("external".utf8))
    }

    private func temporaryLibrary() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }
    private var fixtureURL: URL { URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/minimal.epub") }
}
