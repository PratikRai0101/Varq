import CryptoKit
import Foundation
import SwiftData
import Testing
@testable import Varq

@MainActor
struct PrivateBookViewModelTests {
    @Test func marksTheBookPrivateAfterProtectionSucceeds() throws {
        let fixture = try PrivateBookFixture()
        defer { fixture.cleanup() }
        let viewModel = PrivateBookViewModel(protectionService: fixture.protector)

        viewModel.markPrivate(book: fixture.book, managedFileURL: fixture.fileURL, using: fixture.context)

        #expect(fixture.book.isPrivate)
        #expect(viewModel.errorMessage == nil)
        try fixture.expectEncryptedContents()
    }

    @Test func failedMarkSaveRestoresThePublicFlagAndPlaintext() throws {
        let fixture = try PrivateBookFixture()
        defer { fixture.cleanup() }
        let viewModel = PrivateBookViewModel(protectionService: fixture.protector, saveChanges: { _ in
            throw ViewModelTestError.saveFailed
        })

        viewModel.markPrivate(book: fixture.book, managedFileURL: fixture.fileURL, using: fixture.context)

        #expect(!fixture.book.isPrivate)
        #expect(try Data(contentsOf: fixture.fileURL) == fixture.plaintext)
        #expect(fixture.keyStore.keys[fixture.book.id] == nil)
        #expect(viewModel.errorMessage == ViewModelTestError.saveFailed.localizedDescription)
    }

    @Test func failedUnmarkSaveRestoresThePrivateFlagAndEncryption() throws {
        let fixture = try PrivateBookFixture(isPrivate: true)
        defer { fixture.cleanup() }
        let viewModel = PrivateBookViewModel(protectionService: fixture.protector, saveChanges: { _ in
            throw ViewModelTestError.saveFailed
        })

        viewModel.unmarkPrivate(book: fixture.book, managedFileURL: fixture.fileURL, using: fixture.context)

        #expect(fixture.book.isPrivate)
        #expect(viewModel.errorMessage == ViewModelTestError.saveFailed.localizedDescription)
        try fixture.expectEncryptedContents()
    }

    @Test func successfulMarkSaveIsNotRolledBackWhenJournalCleanupFails() throws {
        let fixture = try PrivateBookFixture()
        defer { fixture.cleanup() }
        let protector = PrivateBookProtectionService(
            keyStore: fixture.keyStore,
            journal: PrivateBookRecoveryJournalService(fileManager: RollbackCleanupFailingFileManager())
        )
        let viewModel = PrivateBookViewModel(protectionService: protector)

        viewModel.markPrivate(book: fixture.book, managedFileURL: fixture.fileURL, using: fixture.context)

        #expect(fixture.book.isPrivate)
        #expect(!viewModel.isRecoveryComplete)
        #expect(viewModel.errorMessage != nil)
        try fixture.expectEncryptedContents()
        let retry = PrivateBookViewModel(protectionService: fixture.protector)
        retry.recoverInterruptedChanges(using: fixture.context, managedLibraryDirectory: fixture.directory)
        #expect(retry.isRecoveryComplete)
        #expect(fixture.book.isPrivate)
        try fixture.expectEncryptedContents()
    }

    @Test func failedRollbackJournalCleanupDoesNotMarkRestoredPlaintextPrivate() throws {
        let fixture = try PrivateBookFixture()
        defer { fixture.cleanup() }
        let protector = PrivateBookProtectionService(
            keyStore: fixture.keyStore,
            journal: PrivateBookRecoveryJournalService(fileManager: RollbackCleanupFailingFileManager())
        )
        let viewModel = PrivateBookViewModel(protectionService: protector, saveChanges: { _ in
            throw ViewModelTestError.saveFailed
        })

        viewModel.markPrivate(book: fixture.book, managedFileURL: fixture.fileURL, using: fixture.context)

        #expect(!fixture.book.isPrivate)
        #expect(try Data(contentsOf: fixture.fileURL) == fixture.plaintext)
        #expect(fixture.keyStore.keys[fixture.book.id] == nil)
        let message = try #require(viewModel.errorMessage)
        #expect(message.contains(ViewModelTestError.saveFailed.localizedDescription))
        #expect(message.contains(ViewModelTestError.journalCleanupFailed.localizedDescription))
        let retry = PrivateBookViewModel(protectionService: fixture.protector)
        retry.recoverInterruptedChanges(using: fixture.context, managedLibraryDirectory: fixture.directory)
        #expect(retry.isRecoveryComplete)
        #expect(!fixture.book.isPrivate)
    }

    @Test func reportsMarkSaveAndKeyCleanupFailuresWithoutClaimingTheFileIsPrivate() throws {
        let fixture = try PrivateBookFixture()
        defer { fixture.cleanup() }
        fixture.keyStore.removalError = ViewModelTestError.keyCleanupFailed
        let viewModel = PrivateBookViewModel(protectionService: fixture.protector, saveChanges: { _ in
            throw ViewModelTestError.saveFailed
        })

        viewModel.markPrivate(book: fixture.book, managedFileURL: fixture.fileURL, using: fixture.context)

        #expect(!fixture.book.isPrivate)
        #expect(try Data(contentsOf: fixture.fileURL) == fixture.plaintext)
        let message = try #require(viewModel.errorMessage)
        #expect(message.contains(ViewModelTestError.saveFailed.localizedDescription))
        #expect(message.contains(ViewModelTestError.keyCleanupFailed.localizedDescription))
    }

    @Test func failedMarkRollbackKeepsThePrivateFlagAndReportsRecoveryIsNeeded() throws {
        let fixture = try PrivateBookFixture()
        defer { fixture.cleanup() }
        let recoveryURL = fixture.directory.appendingPathComponent("recovery.epub")
        let viewModel = PrivateBookViewModel(protectionService: fixture.protector, saveChanges: { _ in
            try FileManager.default.moveItem(at: fixture.fileURL, to: recoveryURL)
            throw ViewModelTestError.saveFailed
        })

        viewModel.markPrivate(book: fixture.book, managedFileURL: fixture.fileURL, using: fixture.context)

        #expect(fixture.book.isPrivate)
        let message = try #require(viewModel.errorMessage)
        #expect(message.contains(ViewModelTestError.saveFailed.localizedDescription))
        #expect(message.contains("Rollback also failed"))
        #expect(message.contains("needs recovery"))
        try fixture.expectEncryptedContents(at: recoveryURL)
    }

    @Test func successfulUnmarkSaveRemovesProtectionAndTheKey() throws {
        let fixture = try PrivateBookFixture(isPrivate: true)
        defer { fixture.cleanup() }
        let viewModel = PrivateBookViewModel(protectionService: fixture.protector)

        viewModel.unmarkPrivate(book: fixture.book, managedFileURL: fixture.fileURL, using: fixture.context)

        #expect(!fixture.book.isPrivate)
        #expect(try Data(contentsOf: fixture.fileURL) == fixture.plaintext)
        #expect(fixture.keyStore.keys[fixture.book.id] == nil)
        #expect(viewModel.errorMessage == nil)
    }

    @Test func unmarkKeyCleanupFailureLeavesTheSuccessfullySavedBookPublic() throws {
        let fixture = try PrivateBookFixture(isPrivate: true)
        defer { fixture.cleanup() }
        fixture.keyStore.removalError = ViewModelTestError.keyCleanupFailed
        let viewModel = PrivateBookViewModel(protectionService: fixture.protector)

        viewModel.unmarkPrivate(book: fixture.book, managedFileURL: fixture.fileURL, using: fixture.context)

        #expect(!fixture.book.isPrivate)
        #expect(try Data(contentsOf: fixture.fileURL) == fixture.plaintext)
        #expect(fixture.keyStore.keys[fixture.book.id] != nil)
        let message = try #require(viewModel.errorMessage)
        #expect(message.contains("no longer encrypted"))
        #expect(message.contains(ViewModelTestError.keyCleanupFailed.localizedDescription))
    }
}

@MainActor
private struct PrivateBookFixture {
    let directory: URL
    let fileURL: URL
    let plaintext = Data("private book content".utf8)
    let book: Book
    let context: ModelContext
    let keyStore: ViewModelTestKeyStore
    let protector: PrivateBookProtectionService

    init(isPrivate: Bool = false) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        fileURL = directory.appendingPathComponent("book.epub")
        let container = try ModelContainer(for: Book.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
        book = Book(title: "Private", author: "Varq", libraryRelativePath: "book.epub", contentHash: "hash", format: .epub)
        keyStore = ViewModelTestKeyStore()
        protector = PrivateBookProtectionService(keyStore: keyStore)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try plaintext.write(to: fileURL)
            context.insert(book)
            if isPrivate {
                _ = try protector.protect(bookID: book.id, managedFileURL: fileURL)
                book.isPrivate = true
            }
            try context.save()
            if isPrivate {
                try protector.completeProtection(bookID: book.id, managedFileURL: fileURL)
            }
        } catch {
            cleanup()
            throw error
        }
    }

    func expectEncryptedContents(at url: URL? = nil) throws {
        let ciphertext = try Data(contentsOf: url ?? fileURL)
        let key = try keyStore.key(for: book.id, authenticationPrompt: "Test")
        #expect(ciphertext != plaintext)
        #expect(try AES.GCM.open(AES.GCM.SealedBox(combined: ciphertext), using: key) == plaintext)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private enum ViewModelTestError: LocalizedError {
    case saveFailed
    case keyCleanupFailed
    case journalCleanupFailed

    var errorDescription: String? {
        switch self {
        case .saveFailed: "Test database save failed."
        case .keyCleanupFailed: "Test key cleanup failed."
        case .journalCleanupFailed: "Test recovery cleanup failed."
        }
    }
}

// Stateless fault injection at the filesystem boundary.
private final class RollbackCleanupFailingFileManager: FileManager, @unchecked Sendable {
    override func removeItem(at URL: URL) throws {
        if URL.lastPathComponent.hasPrefix(".completed-") {
            throw ViewModelTestError.journalCleanupFailed
        }
        try super.removeItem(at: URL)
    }
}

private final class ViewModelTestKeyStore: PrivateBookKeyStoring {
    var keys: [UUID: SymmetricKey] = [:]
    var removalError: (any Error)?
    func store(_ key: SymmetricKey, for bookID: UUID) throws { keys[bookID] = key }
    func key(for bookID: UUID, authenticationPrompt: String) throws -> SymmetricKey {
        guard let key = keys[bookID] else { throw PrivateBookKeyStoreError.keychainStatus(-1) }
        return key
    }
    func removeKey(for bookID: UUID) throws {
        if let removalError { throw removalError }
        keys[bookID] = nil
    }
}
