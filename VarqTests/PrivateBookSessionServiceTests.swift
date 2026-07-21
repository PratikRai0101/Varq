import CryptoKit
import Foundation
import Testing
@testable import Varq

struct PrivateBookSessionServiceTests {
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
        let session = PrivateBookSessionService(keyStore: keyStore)

        let readerURL = try session.readerURL(for: book, managedFileURL: managedURL)

        #expect(readerURL != managedURL)
        #expect(try Data(contentsOf: readerURL) == plaintext)
        session.closeSession()
        #expect(!FileManager.default.fileExists(atPath: readerURL.path))
        _ = try session.readerURL(for: book, managedFileURL: managedURL)
        #expect(keyStore.retrievalCount == 1)
    }
}

private final class FakeSessionKeyStore: PrivateBookKeyStoring {
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
