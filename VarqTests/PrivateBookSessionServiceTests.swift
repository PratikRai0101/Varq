import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import Varq

@MainActor
struct PrivateBookSessionServiceTests {
    @Test func startupRemovesAnAbandonedPrivateCopyWithoutTouchingCiphertextOrKeys() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = directory.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        let managed = library.appendingPathComponent("book.pdf")
        let key = SymmetricKey(size: .bits256)
        let ciphertext = try PrivateBookCryptoService().encrypt(Data("private PDF text".utf8), using: key)
        try ciphertext.write(to: managed)
        let book = Book(title: "Private", author: "Varq", libraryRelativePath: "book.pdf", contentHash: "hash", format: .pdf, isPrivate: true)
        let keyStore = FakeSessionKeyStore(key: key, bookID: book.id)
        let root = directory.appendingPathComponent("ReaderSessions")
        var storage: ReaderSessionStorageService? = ReaderSessionStorageService(rootDirectory: root)
        var session: PrivateBookSessionService? = PrivateBookSessionService(keyStore: keyStore, storage: storage)
        let plaintextURL = try #require(session).readerURL(for: book, managedFileURL: managed)
        session = nil
        storage = nil
        let container = try ModelContainer(for: Book.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        context.insert(book)
        try context.save()
        let recovery = PrivateBookViewModel(readerSessionStorage: ReaderSessionStorageService(rootDirectory: root))

        recovery.recoverInterruptedChanges(using: context, managedLibraryDirectory: library)

        #expect(recovery.isRecoveryComplete)
        #expect(!FileManager.default.fileExists(atPath: plaintextURL.path))
        #expect(try Data(contentsOf: managed) == ciphertext)
        #expect(keyStore.retrievalCount == 1)
        #expect(book.isPrivate)
    }

    @Test func cleanupFailureBlocksStartupUntilRetrySucceeds() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let root = directory.appendingPathComponent("ReaderSessions")
        var old: ReaderSessionStorageService? = ReaderSessionStorageService(rootDirectory: root)
        let payload = try #require(old).makeDirectory()
        try Data("stale private text".utf8).write(to: payload.appendingPathComponent("book.epub"))
        old = nil
        let manager = FailingSessionCleanupFileManager()
        manager.failDiscarded = true
        let storage = ReaderSessionStorageService(rootDirectory: root, fileManager: manager)
        let container = try ModelContainer(for: Book.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let recovery = PrivateBookViewModel(readerSessionStorage: storage)
        recovery.recoverInterruptedChanges(using: context, managedLibraryDirectory: directory.appendingPathComponent("Library"))
        #expect(!recovery.isRecoveryComplete)
        #expect(try #require(recovery.errorMessage).contains(SessionCleanupTestError.denied.localizedDescription))
        manager.failDiscarded = false
        recovery.recoverInterruptedChanges(using: context, managedLibraryDirectory: directory.appendingPathComponent("Library"))
        #expect(recovery.isRecoveryComplete)
        #expect(recovery.errorMessage == nil)
    }

    @Test func failedCloseRemainsRetriableAfterStorageFinishesCleanup() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let managed = directory.appendingPathComponent("book.epub")
        let key = SymmetricKey(size: .bits256)
        let ciphertext = try PrivateBookCryptoService().encrypt(Data("private text".utf8), using: key)
        try ciphertext.write(to: managed)
        let book = Book(title: "Private", author: "Varq", libraryRelativePath: "book.epub", contentHash: "hash", format: .epub, isPrivate: true)
        let manager = FailingSessionCleanupFileManager()
        let storage = ReaderSessionStorageService(rootDirectory: directory.appendingPathComponent("ReaderSessions"), fileManager: manager)
        let session = PrivateBookSessionService(keyStore: FakeSessionKeyStore(key: key, bookID: book.id), storage: storage)
        let url = try session.readerURL(for: book, managedFileURL: managed)
        manager.failingPath = url.deletingLastPathComponent().path
        #expect(throws: SessionCleanupTestError.denied) { try session.closeSession() }
        #expect(FileManager.default.fileExists(atPath: url.path))
        manager.failingPath = nil
        try storage.cleanupStaleSessions()
        try session.closeSession()
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try Data(contentsOf: managed) == ciphertext)
    }

    @Test func decryptsPrivateBooksOnlyIntoASessionDirectory() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let managedURL = directory.appendingPathComponent("book.epub")
        let plaintext = Data("private book".utf8)
        try plaintext.write(to: managedURL)
        let book = Book(title: "Private", author: "Varq", libraryRelativePath: "book.epub", contentHash: "hash", format: .epub, isPrivate: true)
        let key = SymmetricKey(size: .bits256)
        let crypto = PrivateBookCryptoService()
        try crypto.encryptManagedFile(at: managedURL, using: key)
        let keyStore = FakeSessionKeyStore(key: key, bookID: book.id)
        let storage = ReaderSessionStorageService(rootDirectory: directory.appendingPathComponent("ReaderSessions"))
        let session = PrivateBookSessionService(keyStore: keyStore, storage: storage)

        let readerURL = try session.readerURL(for: book, managedFileURL: managedURL)

        #expect(readerURL != managedURL)
        #expect(try Data(contentsOf: readerURL) == plaintext)
        let mode = try FileManager.default.attributesOfItem(atPath: readerURL.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
        try session.closeSession()
        #expect(!FileManager.default.fileExists(atPath: readerURL.path))
        _ = try session.readerURL(for: book, managedFileURL: managedURL)
        #expect(keyStore.retrievalCount == 1)
        try session.endApplicationSession()
    }
}

final class FakeSessionKeyStore: PrivateBookKeyStoring {
    let key: SymmetricKey
    let bookID: UUID
    private(set) var retrievalCount = 0
    init(key: SymmetricKey, bookID: UUID) { self.key = key; self.bookID = bookID }
    func store(_ key: SymmetricKey, for bookID: UUID) throws { }
    func key(for bookID: UUID, authenticationPrompt: String) throws -> SymmetricKey {
        retrievalCount += 1
        return key
    }
    func removeKey(for bookID: UUID) throws { }
}
