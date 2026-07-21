import CryptoKit
import Foundation

final class PrivateBookSessionService {
    private let cryptoService: PrivateBookCryptoService
    private let keyStore: any PrivateBookKeyStoring
    private let fileManager: FileManager
    private var sessionDirectories: Set<URL> = []
    private var unlockedKeys: [UUID: SymmetricKey] = [:]

    init(
        cryptoService: PrivateBookCryptoService = PrivateBookCryptoService(),
        keyStore: any PrivateBookKeyStoring = PrivateBookKeyStore(),
        fileManager: FileManager = .default
    ) {
        self.cryptoService = cryptoService
        self.keyStore = keyStore
        self.fileManager = fileManager
    }

    func readerURL(for book: Book, managedFileURL: URL) throws -> URL {
        guard book.isPrivate else { return managedFileURL }
        let key: SymmetricKey
        if let unlockedKey = unlockedKeys[book.id] {
            key = unlockedKey
        } else {
            key = try keyStore.key(for: book.id, authenticationPrompt: "Unlock private book")
            unlockedKeys[book.id] = key
        }
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("Varq-Private-Session", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let decryptedURL = directory.appendingPathComponent(managedFileURL.lastPathComponent)
        do {
            try cryptoService.decryptManagedFile(at: managedFileURL, to: decryptedURL, using: key)
            sessionDirectories.insert(directory)
            return decryptedURL
        } catch {
            try? fileManager.removeItem(at: directory)
            throw error
        }
    }

    func closeSession() {
        for directory in sessionDirectories {
            try? fileManager.removeItem(at: directory)
        }
        sessionDirectories.removeAll()
    }

    func endApplicationSession() {
        closeSession()
        unlockedKeys.removeAll()
    }
}
