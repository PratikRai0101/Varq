import CryptoKit
import Foundation

@MainActor
protocol PrivateBookProtecting: AnyObject {
    func protect(bookID: UUID, managedFileURL: URL) throws -> PrivateBookProtectionHandle
    func completeProtection(bookID: UUID, managedFileURL: URL) throws
    func rollbackProtection(_ handle: PrivateBookProtectionHandle, bookID: UUID, managedFileURL: URL) throws
    /// The callback must either save the public state or throw without committing it.
    /// A key-cleanup error can occur after a successful save; it does not undo that save.
    func unprotect(bookID: UUID, managedFileURL: URL, persistUnprotectedState: () throws -> Void) throws
    func recoverableChanges(in managedLibraryDirectory: URL) throws -> [PrivateBookRecoveryState]
    /// Call only after saving the flag that matches the recovered file state.
    func completeRecovery(_ state: PrivateBookRecoveryState, in managedLibraryDirectory: URL) throws
}

@MainActor
final class PrivateBookProtectionService: PrivateBookProtecting {
    private let cryptoService: PrivateBookCryptoService
    private let keyStore: any PrivateBookKeyStoring
    private let journal: PrivateBookRecoveryJournalService

    init(
        cryptoService: PrivateBookCryptoService? = nil,
        keyStore: (any PrivateBookKeyStoring)? = nil,
        journal: PrivateBookRecoveryJournalService? = nil
    ) {
        self.cryptoService = cryptoService ?? PrivateBookCryptoService()
        self.keyStore = keyStore ?? PrivateBookKeyStore()
        self.journal = journal ?? PrivateBookRecoveryJournalService()
    }

    func protect(bookID: UUID, managedFileURL: URL) throws -> PrivateBookProtectionHandle {
        let key = SymmetricKey(size: .bits256)
        let original = try Data(contentsOf: managedFileURL)
        let ciphertext = try cryptoService.encrypt(original, using: key)
        let library = managedFileURL.deletingLastPathComponent().resolvingSymlinksInPath()
        let record = try journal.begin(
            bookID: bookID, managedFileURL: managedFileURL,
            originalIsPrivate: false, originalData: original, changedData: ciphertext
        )
        do {
            try keyStore.store(key, for: bookID)
            try journal.replaceManagedFile(record, in: library, with: ciphertext)
            return PrivateBookProtectionHandle(key: key, record: record)
        } catch {
            let encryptionError = error
            do {
                let state = try journal.state(for: record, in: library)
                // Never remove the key if replacement committed, or if the file
                // cannot be verified. Startup recovery will reconcile that state.
                guard !state.isPrivate else { throw PrivateBookRecoveryError.pendingChange }
                try keyStore.removeKey(for: bookID)
                try journal.finish(state, in: library)
            } catch {
                throw PrivateBookProtectionError.rollbackFailed(operationError: encryptionError, rollbackError: error)
            }
            throw encryptionError
        }
    }

    func completeProtection(bookID: UUID, managedFileURL: URL) throws {
        let library = managedFileURL.deletingLastPathComponent().resolvingSymlinksInPath()
        let state = try journal.pendingStates(in: library).first { $0.record.bookID == bookID }
        guard let state, state.isPrivate, state.record.fileName == managedFileURL.lastPathComponent else {
            throw PrivateBookRecoveryError.invalidJournal
        }
        try journal.finish(state, in: library)
    }

    func rollbackProtection(_ handle: PrivateBookProtectionHandle, bookID: UUID, managedFileURL: URL) throws {
        guard handle.record.bookID == bookID, handle.record.fileName == managedFileURL.lastPathComponent else {
            throw PrivateBookRecoveryError.invalidJournal
        }
        let library = managedFileURL.deletingLastPathComponent().resolvingSymlinksInPath()
        let plaintext = try cryptoService.decrypt(Data(contentsOf: managedFileURL), using: handle.key)
        try journal.replaceManagedFile(handle.record, in: library, with: plaintext)
        try removeKeyAfterDecryption(for: bookID)
        do {
            try journal.finish(journal.state(for: handle.record, in: library), in: library)
        } catch {
            throw PrivateBookProtectionError.rollbackCleanupFailed(error)
        }
    }

    func unprotect(bookID: UUID, managedFileURL: URL, persistUnprotectedState: () throws -> Void) throws {
        let key = try keyStore.key(for: bookID, authenticationPrompt: "Unlock private book to remove protection")
        let original = try Data(contentsOf: managedFileURL)
        let plaintext = try cryptoService.decrypt(original, using: key)
        let library = managedFileURL.deletingLastPathComponent().resolvingSymlinksInPath()
        let record = try journal.begin(
            bookID: bookID, managedFileURL: managedFileURL,
            originalIsPrivate: true, originalData: original, changedData: plaintext
        )
        try journal.replaceManagedFile(record, in: library, with: plaintext)
        do {
            try persistUnprotectedState()
        } catch {
            let persistenceError = error
            do {
                // Restore the exact original bytes so the journal remains valid
                // even if the app terminates during this rollback.
                try journal.replaceManagedFile(record, in: library, with: original)
                try journal.finish(journal.state(for: record, in: library), in: library)
            } catch {
                throw PrivateBookProtectionError.rollbackFailed(operationError: persistenceError, rollbackError: error)
            }
            throw persistenceError
        }
        try removeKeyAfterDecryption(for: bookID)
        try journal.finish(journal.state(for: record, in: library), in: library)
    }

    func recoverableChanges(in managedLibraryDirectory: URL) throws -> [PrivateBookRecoveryState] {
        try journal.pendingStates(in: managedLibraryDirectory)
    }

    func completeRecovery(_ state: PrivateBookRecoveryState, in managedLibraryDirectory: URL) throws {
        let current = try journal.state(for: state.record, in: managedLibraryDirectory)
        guard current.contentHash == state.contentHash else { throw PrivateBookRecoveryError.unrecognizedContent }
        if !current.isPrivate {
            try removeKeyAfterDecryption(for: current.record.bookID)
        }
        try journal.finish(current, in: managedLibraryDirectory)
    }

    private func removeKeyAfterDecryption(for bookID: UUID) throws {
        do {
            try keyStore.removeKey(for: bookID)
        } catch {
            throw PrivateBookProtectionError.keyCleanupFailed(error)
        }
    }
}

enum PrivateBookProtectionError: LocalizedError {
    case rollbackFailed(operationError: any Error, rollbackError: any Error)
    /// Decryption succeeded, but the no-longer-needed key could not be removed.
    case keyCleanupFailed(any Error)
    /// The original public file was restored and its key removed.
    case rollbackCleanupFailed(any Error)

    var errorDescription: String? {
        switch self {
        case let .rollbackFailed(operationError, rollbackError):
            "The protection change failed: \(operationError.localizedDescription) " +
                "Rollback also failed: \(rollbackError.localizedDescription) " +
                "The book needs recovery before its protection can be trusted."
        case let .keyCleanupFailed(error):
            "The managed file is no longer encrypted, but Varq could not remove its encryption key: " +
                error.localizedDescription
        case let .rollbackCleanupFailed(error):
            "The managed file was restored, but Varq could not finish recovery cleanup: " + error.localizedDescription
        }
    }
}

struct PrivateBookProtectionHandle {
    fileprivate let key: SymmetricKey
    fileprivate let record: PrivateBookRecoveryRecord
}
