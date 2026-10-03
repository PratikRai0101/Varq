import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import Varq

@MainActor
struct PrivateBookRecoveryTests {
    @Test func restartBeforeEncryptionLeavesTheBookPublicAndRemovesAnUnusedKey() throws {
        let fixture = try RecoveryFixture()
        defer { fixture.cleanup() }
        let key = SymmetricKey(size: .bits256)
        let ciphertext = try PrivateBookCryptoService().encrypt(fixture.plaintext, using: key)
        _ = try PrivateBookRecoveryJournalService().begin(
            bookID: fixture.bookID, managedFileURL: fixture.fileURL,
            originalIsPrivate: false, originalData: fixture.plaintext, changedData: ciphertext
        )
        try fixture.keyStore.store(key, for: fixture.bookID)
        let (context, book) = try fixture.openBook()
        let service = PrivateBookProtectionService(keyStore: fixture.keyStore)
        let recovery = PrivateBookViewModel(protectionService: service)

        recovery.recoverInterruptedChanges(using: context, managedLibraryDirectory: fixture.libraryDirectory)

        #expect(recovery.isRecoveryComplete)
        #expect(!book.isPrivate)
        #expect(try Data(contentsOf: fixture.fileURL) == fixture.plaintext)
        #expect(fixture.keyStore.keys[fixture.bookID] == nil)
        #expect(try service.recoverableChanges(in: fixture.libraryDirectory).isEmpty)
    }

    @Test func restartAfterDecryptionSavesThePublicFlagBeforeRemovingTheKey() throws {
        let fixture = try RecoveryFixture()
        defer { fixture.cleanup() }
        try fixture.makePrivate()
        let record = try fixture.prepareUnprotect()
        try PrivateBookRecoveryJournalService().replaceManagedFile(record, in: fixture.libraryDirectory, with: fixture.plaintext)
        let (context, book) = try fixture.openBook()
        #expect(book.isPrivate)
        let previousAuthenticationCount = fixture.keyStore.authenticationRequests
        let service = PrivateBookProtectionService(keyStore: fixture.keyStore)
        let recovery = PrivateBookViewModel(protectionService: service, saveChanges: { context in
            #expect(fixture.keyStore.keys[fixture.bookID] != nil)
            try context.save()
        })

        recovery.recoverInterruptedChanges(using: context, managedLibraryDirectory: fixture.libraryDirectory)

        #expect(recovery.isRecoveryComplete)
        #expect(!book.isPrivate)
        let (_, reopenedBook) = try fixture.openBook()
        #expect(!reopenedBook.isPrivate)
        #expect(fixture.keyStore.keys[fixture.bookID] == nil)
        #expect(fixture.keyStore.authenticationRequests == previousAuthenticationCount)
        #expect(try service.recoverableChanges(in: fixture.libraryDirectory).isEmpty)
    }

    @Test func restartBeforeDecryptionKeepsEncryptionAndTheKey() throws {
        let fixture = try RecoveryFixture()
        defer { fixture.cleanup() }
        try fixture.makePrivate()
        _ = try fixture.prepareUnprotect()
        let originalCiphertext = try Data(contentsOf: fixture.fileURL)
        let (context, book) = try fixture.openBook()
        let service = PrivateBookProtectionService(keyStore: fixture.keyStore)
        let recovery = PrivateBookViewModel(protectionService: service)

        recovery.recoverInterruptedChanges(using: context, managedLibraryDirectory: fixture.libraryDirectory)

        #expect(recovery.isRecoveryComplete)
        #expect(book.isPrivate)
        #expect(try Data(contentsOf: fixture.fileURL) == originalCiphertext)
        #expect(fixture.keyStore.keys[fixture.bookID] != nil)
        #expect(try service.recoverableChanges(in: fixture.libraryDirectory).isEmpty)
    }

    @Test func restartRemovesStagedPlaintextWithoutDecryptingTheManagedBook() throws {
        let fixture = try RecoveryFixture()
        defer { fixture.cleanup() }
        try fixture.makePrivate()
        _ = try fixture.prepareUnprotect()
        let stagingURL = fixture.recordURL.deletingLastPathComponent().appendingPathComponent("replacement")
        try fixture.plaintext.write(to: stagingURL)
        let ciphertext = try Data(contentsOf: fixture.fileURL)
        let authenticationCount = fixture.keyStore.authenticationRequests
        let (context, book) = try fixture.openBook()
        let recovery = PrivateBookViewModel(protectionService: PrivateBookProtectionService(keyStore: fixture.keyStore))

        recovery.recoverInterruptedChanges(using: context, managedLibraryDirectory: fixture.libraryDirectory)

        #expect(recovery.isRecoveryComplete)
        #expect(book.isPrivate)
        #expect(try Data(contentsOf: fixture.fileURL) == ciphertext)
        #expect(!FileManager.default.fileExists(atPath: stagingURL.path))
        #expect(fixture.keyStore.authenticationRequests == authenticationCount)
        #expect(fixture.keyStore.keys[fixture.bookID] != nil)
    }

    @Test func recoveryKeyCleanupFailureKeepsTheJournalForAnIdempotentRetry() throws {
        let fixture = try RecoveryFixture()
        defer { fixture.cleanup() }
        try fixture.makePrivate()
        let record = try fixture.prepareUnprotect()
        try PrivateBookRecoveryJournalService().replaceManagedFile(record, in: fixture.libraryDirectory, with: fixture.plaintext)
        fixture.keyStore.removalError = RecoveryTestError.keyCleanupFailed
        let (context, book) = try fixture.openBook()
        let service = PrivateBookProtectionService(keyStore: fixture.keyStore)
        let recovery = PrivateBookViewModel(protectionService: service)

        recovery.recoverInterruptedChanges(using: context, managedLibraryDirectory: fixture.libraryDirectory)

        #expect(!recovery.isRecoveryComplete)
        #expect(!book.isPrivate)
        #expect(try service.recoverableChanges(in: fixture.libraryDirectory).count == 1)
        #expect(fixture.keyStore.keys[fixture.bookID] != nil)
        fixture.keyStore.removalError = nil
        recovery.recoverInterruptedChanges(using: context, managedLibraryDirectory: fixture.libraryDirectory)
        recovery.recoverInterruptedChanges(using: context, managedLibraryDirectory: fixture.libraryDirectory)
        #expect(recovery.isRecoveryComplete)
        #expect(recovery.errorMessage == nil)
        #expect(fixture.keyStore.keys[fixture.bookID] == nil)
        #expect(try service.recoverableChanges(in: fixture.libraryDirectory).isEmpty)
    }

    @Test func unknownManagedContentBlocksRecoveryWithoutChangingTheFlagOrRemovingTheKey() throws {
        let fixture = try RecoveryFixture()
        defer { fixture.cleanup() }
        _ = try PrivateBookProtectionService(keyStore: fixture.keyStore).protect(bookID: fixture.bookID, managedFileURL: fixture.fileURL)
        let unexpectedData = Data("unrecognized content, preserve me".utf8)
        try unexpectedData.write(to: fixture.fileURL)
        let (context, book) = try fixture.openBook()
        let recovery = PrivateBookViewModel(protectionService: PrivateBookProtectionService(keyStore: fixture.keyStore))

        recovery.recoverInterruptedChanges(using: context, managedLibraryDirectory: fixture.libraryDirectory)

        #expect(!recovery.isRecoveryComplete)
        #expect(!book.isPrivate)
        #expect(try Data(contentsOf: fixture.fileURL) == unexpectedData)
        #expect(fixture.keyStore.keys[fixture.bookID] != nil)
        #expect(FileManager.default.fileExists(atPath: fixture.recordURL.path))
        let message = try #require(recovery.errorMessage)
        #expect(message.contains("will not guess"))
        recovery.clearError()
        #expect(recovery.errorMessage == message)
    }

    @Test func missingLibraryEntryKeepsEncryptedContentAndRecoveryState() throws {
        let fixture = try RecoveryFixture()
        defer { fixture.cleanup() }
        _ = try PrivateBookProtectionService(keyStore: fixture.keyStore).protect(bookID: fixture.bookID, managedFileURL: fixture.fileURL)
        let ciphertext = try Data(contentsOf: fixture.fileURL)
        let (context, book) = try fixture.openBook()
        context.delete(book)
        try context.save()
        let recovery = PrivateBookViewModel(protectionService: PrivateBookProtectionService(keyStore: fixture.keyStore))

        recovery.recoverInterruptedChanges(using: context, managedLibraryDirectory: fixture.libraryDirectory)

        #expect(!recovery.isRecoveryComplete)
        #expect(try Data(contentsOf: fixture.fileURL) == ciphertext)
        #expect(fixture.keyStore.keys[fixture.bookID] != nil)
        #expect(FileManager.default.fileExists(atPath: fixture.recordURL.path))
    }

    @Test func recoverySaveFailureRetainsTheJournalAndKeyForRetry() throws {
        let fixture = try RecoveryFixture()
        defer { fixture.cleanup() }
        _ = try PrivateBookProtectionService(keyStore: fixture.keyStore).protect(bookID: fixture.bookID, managedFileURL: fixture.fileURL)
        let (context, book) = try fixture.openBook()
        let service = PrivateBookProtectionService(keyStore: fixture.keyStore)
        let recovery = PrivateBookViewModel(protectionService: service, saveChanges: { _ in
            throw RecoveryTestError.saveFailed
        })

        recovery.recoverInterruptedChanges(using: context, managedLibraryDirectory: fixture.libraryDirectory)

        #expect(!recovery.isRecoveryComplete)
        #expect(!book.isPrivate)
        #expect(fixture.keyStore.keys[fixture.bookID] != nil)
        #expect(try service.recoverableChanges(in: fixture.libraryDirectory).count == 1)
        let retry = PrivateBookViewModel(protectionService: PrivateBookProtectionService(keyStore: fixture.keyStore))
        retry.recoverInterruptedChanges(using: context, managedLibraryDirectory: fixture.libraryDirectory)
        #expect(retry.isRecoveryComplete)
        #expect(book.isPrivate)
        #expect(try service.recoverableChanges(in: fixture.libraryDirectory).isEmpty)
    }

    @Test func restartAfterEncryptionSavesThePrivateFlagWithoutAuthentication() throws {
        let fixture = try RecoveryFixture()
        defer { fixture.cleanup() }
        let originalService = PrivateBookProtectionService(keyStore: fixture.keyStore)
        _ = try originalService.protect(bookID: fixture.bookID, managedFileURL: fixture.fileURL)

        // Open a fresh database context and service, as a relaunched app would.
        let (context, book) = try fixture.openBook()
        #expect(!book.isPrivate)
        let recovery = PrivateBookViewModel(protectionService: PrivateBookProtectionService(keyStore: fixture.keyStore))
        recovery.recoverInterruptedChanges(using: context, managedLibraryDirectory: fixture.libraryDirectory)

        #expect(recovery.isRecoveryComplete)
        #expect(recovery.errorMessage == nil)
        #expect(book.isPrivate)
        #expect(fixture.keyStore.authenticationRequests == 0)
        let (_, reopenedBook) = try fixture.openBook()
        #expect(reopenedBook.isPrivate)
    }
}

@MainActor
private struct RecoveryFixture {
    let directory: URL
    let libraryDirectory: URL
    let fileURL: URL
    let storeURL: URL
    let bookID: UUID
    let plaintext = Data("private recovery fixture".utf8)
    let keyStore = RecoveryKeyStore()

    init() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        libraryDirectory = directory.appendingPathComponent("Library", isDirectory: true)
        fileURL = libraryDirectory.appendingPathComponent("book.epub")
        storeURL = directory.appendingPathComponent("Library.store")
        bookID = UUID()
        do {
            try FileManager.default.createDirectory(at: libraryDirectory, withIntermediateDirectories: true)
            try plaintext.write(to: fileURL)
            let container = try ModelContainer(for: Book.self, configurations: ModelConfiguration(url: storeURL))
            let context = ModelContext(container)
            context.insert(Book(id: bookID, title: "Recovery", author: "Varq", libraryRelativePath: "book.epub", contentHash: "hash", format: .epub))
            try context.save()
        } catch {
            cleanup()
            throw error
        }
    }

    func openBook() throws -> (ModelContext, Book) {
        let container = try ModelContainer(for: Book.self, configurations: ModelConfiguration(url: storeURL))
        let context = ModelContext(container)
        let book = try #require(context.fetch(FetchDescriptor<Book>()).first)
        return (context, book)
    }

    var recordURL: URL {
        libraryDirectory.appendingPathComponent(".private-book-recovery")
            .appendingPathComponent(bookID.uuidString).appendingPathComponent("record.json")
    }

    func makePrivate() throws {
        let service = PrivateBookProtectionService(keyStore: keyStore)
        _ = try service.protect(bookID: bookID, managedFileURL: fileURL)
        let (context, book) = try openBook()
        book.isPrivate = true
        try context.save()
        try service.completeProtection(bookID: bookID, managedFileURL: fileURL)
    }

    func prepareUnprotect() throws -> PrivateBookRecoveryRecord {
        let original = try Data(contentsOf: fileURL)
        let key = try keyStore.key(for: bookID, authenticationPrompt: "Test")
        let decrypted = try PrivateBookCryptoService().decrypt(original, using: key)
        return try PrivateBookRecoveryJournalService().begin(
            bookID: bookID, managedFileURL: fileURL,
            originalIsPrivate: true, originalData: original, changedData: decrypted
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private enum RecoveryTestError: Error {
    case saveFailed
    case keyCleanupFailed
}

private final class RecoveryKeyStore: PrivateBookKeyStoring {
    var keys: [UUID: SymmetricKey] = [:]
    private(set) var authenticationRequests = 0
    var removalError: (any Error)?
    func store(_ key: SymmetricKey, for bookID: UUID) throws { keys[bookID] = key }
    func key(for bookID: UUID, authenticationPrompt: String) throws -> SymmetricKey {
        authenticationRequests += 1
        guard let key = keys[bookID] else { throw PrivateBookKeyStoreError.keychainStatus(-1) }
        return key
    }
    func removeKey(for bookID: UUID) throws {
        if let removalError { throw removalError }
        keys[bookID] = nil
    }
}
