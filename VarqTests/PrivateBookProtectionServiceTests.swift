import CryptoKit
import Foundation
import Testing
@testable import Varq

struct PrivateBookProtectionServiceTests {
    @Test func encryptsTheManagedFileAndRollsBackWithTheSameKey() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("book.epub")
        let plaintext = Data("private book content".utf8)
        try plaintext.write(to: fileURL)
        let bookID = UUID()
        let keyStore = FakePrivateBookKeyStore()
        let service = PrivateBookProtectionService(keyStore: keyStore)

        let handle = try service.protect(bookID: bookID, managedFileURL: fileURL)
        #expect(try Data(contentsOf: fileURL) != plaintext)
        #expect(keyStore.keys[bookID] != nil)

        try service.rollbackProtection(handle, bookID: bookID, managedFileURL: fileURL)
        #expect(try Data(contentsOf: fileURL) == plaintext)
        #expect(keyStore.keys[bookID] == nil)
    }
}

private final class FakePrivateBookKeyStore: PrivateBookKeyStoring {
    var keys: [UUID: SymmetricKey] = [:]
    func store(_ key: SymmetricKey, for bookID: UUID) throws { keys[bookID] = key }
    func key(for bookID: UUID, authenticationPrompt: String) throws -> SymmetricKey {
        guard let key = keys[bookID] else { throw PrivateBookKeyStoreError.keychainStatus(-1) }
        return key
    }
    func removeKey(for bookID: UUID) throws { keys[bookID] = nil }
}
