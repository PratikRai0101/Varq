import CryptoKit
import Foundation
import Testing
@testable import Varq

@MainActor
struct BookDeletionServiceTests {
    @Test func refusesSymlinksAndPendingProtectionChangesWithoutMovingTheBook() throws {
        let library = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: library) }
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let original = library.appendingPathComponent("original.epub")
        let bytes = Data("original book".utf8)
        try bytes.write(to: original)
        let linked = library.appendingPathComponent("linked.epub")
        try FileManager.default.createSymbolicLink(at: linked, withDestinationURL: original)
        #expect(throws: BookDeletionError.self) {
            _ = try BookDeletionService().stage(bookID: UUID(), fileName: "linked.epub", isPrivate: false, in: library)
        }
        let id = UUID()
        try FileManager.default.createDirectory(at: library.appendingPathComponent(".private-book-recovery/" + id.uuidString), withIntermediateDirectories: true)
        #expect(throws: BookDeletionError.self) {
            _ = try BookDeletionService().stage(bookID: id, fileName: "original.epub", isPrivate: false, in: library)
        }
        #expect(try Data(contentsOf: original) == bytes)
    }

    @Test func committedPrivateDeletionRetriesKeyCleanupAfterRestart() throws {
        let library = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: library) }
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let bookID = UUID()
        let keys = DeletionTestKeyStore()
        let key = SymmetricKey(size: .bits256)
        try keys.store(key, for: bookID)
        let ciphertext = try PrivateBookCryptoService().encrypt(Data("private content".utf8), using: key)
        try ciphertext.write(to: library.appendingPathComponent("book.pdf"))
        let service = BookDeletionService(keyStore: keys)
        let record = try service.stage(bookID: bookID, fileName: "book.pdf", isPrivate: true, in: library)
        keys.removalError = CocoaError(.fileWriteNoPermission)
        #expect(throws: (any Error).self) { try service.complete(record, in: library) }
        #expect(keys.keys[bookID] != nil)
        #expect(try service.pendingRecords(in: library).count == 1)
        keys.removalError = nil

        try BookDeletionService(keyStore: keys).recover(in: library, survivingBooks: [])

        #expect(keys.keys[bookID] == nil)
        #expect(try service.pendingRecords(in: library).isEmpty)
    }

    @Test func failedStagingKeepsTheOriginalFileAndLeavesNoPendingDeletion() throws {
        let library = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: library) }
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let source = library.appendingPathComponent("book.epub")
        let data = Data("original".utf8)
        try data.write(to: source)
        let manager = DeletionTestFileManager()
        manager.failStaging = true
        let service = BookDeletionService(fileManager: manager)
        #expect(throws: (any Error).self) {
            _ = try service.stage(bookID: UUID(), fileName: "book.epub", isPrivate: false, in: library)
        }
        #expect(try Data(contentsOf: source) == data)
        #expect(try service.pendingRecords(in: library).isEmpty)
    }

    @Test func restartFinishesInterruptedRecursiveCleanupEvenWithoutTheRecord() throws {
        let library = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: library) }
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try Data("book".utf8).write(to: library.appendingPathComponent("book.epub"))
        let manager = DeletionTestFileManager()
        let service = BookDeletionService(fileManager: manager)
        let record = try service.stage(bookID: UUID(), fileName: "book.epub", isPrivate: false, in: library)
        manager.failCompletedRemoval = true
        #expect(throws: (any Error).self) { try service.complete(record, in: library) }
        let completed = library.appendingPathComponent(".book-deletions/.completed-" + record.bookID.uuidString)
        try FileManager.default.removeItem(at: completed.appendingPathComponent("record.json"))

        try BookDeletionService().recover(in: library, survivingBooks: [])

        #expect(!FileManager.default.fileExists(atPath: completed.path))
    }

    @Test(arguments: ["../original.epub", "/tmp/original.epub", ".book-deletions", "nested/book.epub"])
    func refusesUnsafeManagedNames(fileName: String) throws {
        let library = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: library) }
        #expect(throws: BookDeletionError.self) {
            _ = try BookDeletionService().stage(bookID: UUID(), fileName: fileName, isPrivate: false, in: library)
        }
    }

    @Test(arguments: [false, true])
    func damagedMetadataOrUnknownPayloadIsPreserved(corruptRecord: Bool) throws {
        let library = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: library) }
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: library.appendingPathComponent("book.epub"))
        let record = try BookDeletionService().stage(bookID: UUID(), fileName: "book.epub", isPrivate: false, in: library)
        let directory = library.appendingPathComponent(".book-deletions/" + record.bookID.uuidString)
        let altered = directory.appendingPathComponent(corruptRecord ? "record.json" : "payload")
        let unknown = Data("unrecognized bytes".utf8)
        try unknown.write(to: altered)
        #expect(throws: (any Error).self) {
            try BookDeletionService().recover(in: library, survivingBooks: [])
        }
        #expect(try Data(contentsOf: altered) == unknown)
    }

    @Test func restartRestoresAStagedFileWhenTheDatabaseBookSurvives() throws {
        let library = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: library) }
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let source = library.appendingPathComponent("book.epub")
        let original = Data("book before process termination".utf8)
        try original.write(to: source)
        let book = Book(title: "Surviving", author: "Varq", libraryRelativePath: "book.epub", contentHash: "hash", format: .epub)
        _ = try BookDeletionService().stage(bookID: book.id, fileName: "book.epub", isPrivate: false, in: library)

        try BookDeletionService().recover(in: library, survivingBooks: [book])

        #expect(try Data(contentsOf: source) == original)
        #expect(try BookDeletionService().pendingRecords(in: library).isEmpty)
    }

    @Test func privateKeyIsRetainedUntilCommittedDeletionCleanup() throws {
        let library = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: library) }
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let bookID = UUID()
        let key = SymmetricKey(size: .bits256)
        let keys = DeletionTestKeyStore()
        try keys.store(key, for: bookID)
        let source = library.appendingPathComponent("book.pdf")
        try PrivateBookCryptoService().encrypt(Data("private PDF".utf8), using: key).write(to: source)
        let service = BookDeletionService(keyStore: keys)
        let record = try service.stage(bookID: bookID, fileName: "book.pdf", isPrivate: true, in: library)
        #expect(keys.keys[bookID] != nil)

        try service.complete(record, in: library)

        #expect(keys.keys[bookID] == nil)
        #expect(try service.pendingRecords(in: library).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: source.path))
    }

    @Test func stagedDeletionCanRestoreTheExactManagedBook() throws {
        let library = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: library) }
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let source = library.appendingPathComponent("book.epub")
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/minimal.epub")
        let original = try Data(contentsOf: fixture)
        try original.write(to: source)
        let service = BookDeletionService()
        let bookID = UUID()

        let record = try service.stage(bookID: bookID, fileName: "book.epub", isPrivate: false, in: library)
        #expect(!FileManager.default.fileExists(atPath: source.path))
        try service.restore(record, in: library)

        #expect(try Data(contentsOf: source) == original)
        #expect(try service.pendingRecords(in: library).isEmpty)
    }
}
