import CryptoKit
import Foundation

protocol PrivateBookProtecting: AnyObject {
    func protect(bookID: UUID, managedFileURL: URL) throws -> PrivateBookProtectionHandle
    func rollbackProtection(_ handle: PrivateBookProtectionHandle, bookID: UUID, managedFileURL: URL) throws
    /// The callback must either save the public state or throw without committing it.
    /// A key-cleanup error can occur after a successful save; it does not undo that save.
    func unprotect(bookID: UUID, managedFileURL: URL, persistUnprotectedState: () throws -> Void) throws
}

final class PrivateBookProtectionService: PrivateBookProtecting {
    private let cryptoService: PrivateBookCryptoService
    private let keyStore: any PrivateBookKeyStoring

    init(
        cryptoService: PrivateBookCryptoService = PrivateBookCryptoService(),
        keyStore: any PrivateBookKeyStoring = PrivateBookKeyStore()
    ) {
        self.cryptoService = cryptoService
        self.keyStore = keyStore
    }

    func protect(bookID: UUID, managedFileURL: URL) throws -> PrivateBookProtectionHandle {
        let key = SymmetricKey(size: .bits256)
        try keyStore.store(key, for: bookID)
        do {
            try cryptoService.encryptManagedFile(at: managedFileURL, using: key)
            return PrivateBookProtectionHandle(key: key)
        } catch {
            let encryptionError = error
            do {
                try keyStore.removeKey(for: bookID)
            } catch {
                throw PrivateBookProtectionError.rollbackFailed(
                    operationError: encryptionError,
                    rollbackError: error
                )
            }
            throw encryptionError
        }
    }

    func rollbackProtection(_ handle: PrivateBookProtectionHandle, bookID: UUID, managedFileURL: URL) throws {
        try cryptoService.decryptReplacingManagedFile(at: managedFileURL, using: handle.key)
        try removeKeyAfterDecryption(for: bookID)
    }

    func unprotect(bookID: UUID, managedFileURL: URL, persistUnprotectedState: () throws -> Void) throws {
        let key = try keyStore.key(for: bookID, authenticationPrompt: "Unlock private book to remove protection")
        try cryptoService.decryptReplacingManagedFile(at: managedFileURL, using: key)
        do {
            try persistUnprotectedState()
        } catch {
            let persistenceError = error
            do {
                try cryptoService.encryptManagedFile(at: managedFileURL, using: key)
            } catch {
                throw PrivateBookProtectionError.rollbackFailed(
                    operationError: persistenceError,
                    rollbackError: error
                )
            }
            throw persistenceError
        }
        try removeKeyAfterDecryption(for: bookID)
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

    var errorDescription: String? {
        switch self {
        case let .rollbackFailed(operationError, rollbackError):
            "The protection change failed: \(operationError.localizedDescription) " +
                "Rollback also failed: \(rollbackError.localizedDescription) " +
                "The book needs recovery before its protection can be trusted."
        case let .keyCleanupFailed(error):
            "The managed file is no longer encrypted, but Varq could not remove its encryption key: " +
                error.localizedDescription
        }
    }
}

struct PrivateBookProtectionHandle {
    fileprivate let key: SymmetricKey

    init(key: SymmetricKey) {
        self.key = key
    }
}
