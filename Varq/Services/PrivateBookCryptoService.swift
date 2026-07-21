import CryptoKit
import Foundation

struct PrivateBookCryptoService {
    func encryptManagedFile(at fileURL: URL, using key: SymmetricKey) throws {
        let plaintext = try Data(contentsOf: fileURL)
        let sealedBox = try AES.GCM.seal(plaintext, using: key)
        guard let ciphertext = sealedBox.combined else {
            throw PrivateBookCryptoError.missingCombinedRepresentation
        }
        try replaceFile(at: fileURL, with: ciphertext)
    }

    func decryptManagedFile(at encryptedFileURL: URL, to destinationURL: URL, using key: SymmetricKey) throws {
        let ciphertext = try Data(contentsOf: encryptedFileURL)
        let sealedBox = try AES.GCM.SealedBox(combined: ciphertext)
        let plaintext = try AES.GCM.open(sealedBox, using: key)
        try FileManager.default.createDirectory(
            at: destinationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try plaintext.write(to: destinationURL, options: .atomic)
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
