import CryptoKit
import Foundation

protocol PrivateBookProtecting: AnyObject {
    func protect(bookID: UUID, managedFileURL: URL) throws -> PrivateBookProtectionHandle
    func rollbackProtection(_ handle: PrivateBookProtectionHandle, bookID: UUID, managedFileURL: URL) throws
    func unprotect(bookID: UUID, managedFileURL: URL) throws
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
            try? keyStore.removeKey(for: bookID)
            throw error
        }
    }

    func rollbackProtection(_ handle: PrivateBookProtectionHandle, bookID: UUID, managedFileURL: URL) throws {
        try cryptoService.decryptReplacingManagedFile(at: managedFileURL, using: handle.key)
        try keyStore.removeKey(for: bookID)
    }

    func unprotect(bookID: UUID, managedFileURL: URL) throws {
        let key = try keyStore.key(for: bookID, authenticationPrompt: "Unlock private book to remove protection")
        try cryptoService.decryptReplacingManagedFile(at: managedFileURL, using: key)
        try keyStore.removeKey(for: bookID)
    }
}

struct PrivateBookProtectionHandle {
    fileprivate let key: SymmetricKey

    init(key: SymmetricKey) {
        self.key = key
    }
}
