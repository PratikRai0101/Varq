import CryptoKit
import Foundation

struct PrivateBookCryptoService {
    func encryptManagedFile(at fileURL: URL, using key: SymmetricKey) throws {
        let plaintext = try Data(contentsOf: fileURL)
        try replaceFile(at: fileURL, with: encrypt(plaintext, using: key))
    }

    func decryptReplacingManagedFile(at encryptedFileURL: URL, using key: SymmetricKey) throws {
        let ciphertext = try Data(contentsOf: encryptedFileURL)
        try replaceFile(at: encryptedFileURL, with: decrypt(ciphertext, using: key))
    }

    func decryptManagedFile(at encryptedFileURL: URL, to destinationURL: URL, using key: SymmetricKey) throws {
        let ciphertext = try Data(contentsOf: encryptedFileURL)
        let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
        let plaintext = try AES.GCM.open(sealedBox, using: key)
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try plaintext.write(to: destinationURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destinationURL.path)
    }

    func encrypt(_ plaintext: Data, using key: SymmetricKey) throws -> Data {
        let sealedBox = try AES.GCM.seal(plaintext, using: key)
        guard let ciphertext = sealedBox.combined else {
            throw PrivateBookCryptoError.missingCombinedRepresentation
        }
        return ciphertext
    }

    func decrypt(_ ciphertext: Data, using key: SymmetricKey) throws -> Data {
        try AES.GCM.open(AES.GCM.SealedBox(combined: ciphertext), using: key)
    }

    private func replaceFile(at fileURL: URL, with data: Data) throws {
        let temporaryURL = fileURL.deletingLastPathComponent()
            .appendingPathComponent(UUID().uuidString)
        try data.write(to: temporaryURL, options: .atomic)
        do {
            _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporaryURL)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }
}

enum PrivateBookCryptoError: Error, Equatable {
    case missingCombinedRepresentation
}
