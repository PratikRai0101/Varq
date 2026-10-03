import CryptoKit
import Foundation

@MainActor
final class PrivateBookSessionService {
    private let cryptoService: PrivateBookCryptoService
    private let keyStore: any PrivateBookKeyStoring
    private let storage: ReaderSessionStorageService
    private var sessionDirectories: Set<URL> = []
    private var unlockedKeys: [UUID: SymmetricKey] = [:]

    init(
        cryptoService: PrivateBookCryptoService? = nil,
        keyStore: (any PrivateBookKeyStoring)? = nil,
        storage: ReaderSessionStorageService? = nil
    ) {
        self.cryptoService = cryptoService ?? PrivateBookCryptoService()
        self.keyStore = keyStore ?? PrivateBookKeyStore()
        self.storage = storage ?? .shared
    }

    func readerURL(for book: Book, managedFileURL: URL) throws -> URL {
        guard book.isPrivate else { return managedFileURL }
        // Storage cleanup must succeed before authentication or plaintext writes.
        let directory = try storage.makeDirectory()
        sessionDirectories.insert(directory)
        let decryptedURL = directory.appendingPathComponent(managedFileURL.lastPathComponent)
        do {
            let key: SymmetricKey
            if let unlockedKey = unlockedKeys[book.id] {
                key = unlockedKey
            } else {
                key = try keyStore.key(for: book.id, authenticationPrompt: "Unlock private book")
                unlockedKeys[book.id] = key
            }
            try cryptoService.decryptManagedFile(at: managedFileURL, to: decryptedURL, using: key)
            return decryptedURL
        } catch {
            let readingError = error
            do {
                try storage.removeDirectory(directory)
                sessionDirectories.remove(directory)
            } catch {
                throw PrivateBookSessionError.cleanupFailed(operationError: readingError, cleanupError: error)
            }
            throw readingError
        }
    }

    func closeSession() throws {
        var firstError: (any Error)?
        for directory in sessionDirectories.sorted(by: { $0.path < $1.path }) {
            do {
                try storage.removeDirectory(directory)
                sessionDirectories.remove(directory)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
    }

    func endApplicationSession() throws {
        defer { unlockedKeys.removeAll() }
        try closeSession()
    }
}

enum PrivateBookSessionError: LocalizedError {
    case cleanupFailed(operationError: any Error, cleanupError: any Error)

    var errorDescription: String? {
        switch self {
        case let .cleanupFailed(operationError, cleanupError):
            "Varq could not open the private book: \(operationError.localizedDescription) " +
                "Temporary-file cleanup also failed: \(cleanupError.localizedDescription)"
        }
    }
}
