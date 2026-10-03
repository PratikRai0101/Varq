import CryptoKit
import Foundation
import Testing
@testable import Varq

struct PrivateBookProtectionServiceTests {
    @Test func failedUnprotectSaveKeepsTheBookEncryptedAndItsKeyUsable() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("book.epub")
        let plaintext = Data("private book content".utf8)
        try plaintext.write(to: fileURL)
        let bookID = UUID()
        let keyStore = FakePrivateBookKeyStore()
        let service = PrivateBookProtectionService(keyStore: keyStore)
        _ = try service.protect(bookID: bookID, managedFileURL: fileURL)

        #expect(throws: TestPersistenceError.saveFailed) {
            try service.unprotect(bookID: bookID, managedFileURL: fileURL) {
                throw TestPersistenceError.saveFailed
            }
        }

        let ciphertext = try Data(contentsOf: fileURL)
        #expect(ciphertext != plaintext)
        let key = try keyStore.key(for: bookID, authenticationPrompt: "Test")
        #expect(try AES.GCM.open(AES.GCM.SealedBox(combined: ciphertext), using: key) == plaintext)
    }

    @Test func successfulUnprotectKeepsTheKeyUntilPersistenceFinishes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("book.epub")
        let plaintext = Data("private book content".utf8)
        try plaintext.write(to: fileURL)
        let bookID = UUID()
        let keyStore = FakePrivateBookKeyStore()
        let service = PrivateBookProtectionService(keyStore: keyStore)
        _ = try service.protect(bookID: bookID, managedFileURL: fileURL)

        try service.unprotect(bookID: bookID, managedFileURL: fileURL) {
            #expect(try Data(contentsOf: fileURL) == plaintext)
            _ = try keyStore.key(for: bookID, authenticationPrompt: "Test")
        }

        #expect(try Data(contentsOf: fileURL) == plaintext)
        #expect(keyStore.keys[bookID] == nil)
    }

    @Test func failedUnprotectRollbackReportsBothFailuresAndRetainsTheKey() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fileURL = directory.appendingPathComponent("book.epub")
        try Data("private book content".utf8).write(to: fileURL)
        let bookID = UUID()
        let keyStore = FakePrivateBookKeyStore()
        let service = PrivateBookProtectionService(keyStore: keyStore)
        _ = try service.protect(bookID: bookID, managedFileURL: fileURL)

        do {
            try service.unprotect(bookID: bookID, managedFileURL: fileURL) {
                // Simulate a filesystem failure at rollback by making the managed
                // path unavailable after decryption, without discarding its data.
                try FileManager.default.moveItem(at: fileURL, to: directory.appendingPathComponent("recovery.epub"))
                throw TestPersistenceError.saveFailed
            }
            Issue.record("Expected a failed rollback")
        } catch let PrivateBookProtectionError.rollbackFailed(operationError, rollbackError) {
            #expect(operationError as? TestPersistenceError == .saveFailed)
            #expect((rollbackError as NSError).domain == NSCocoaErrorDomain)
        }

        _ = try keyStore.key(for: bookID, authenticationPrompt: "Test")
    }

    @Test func encryptionFailureDoesNotSilentlyHideKeyCleanupFailure() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("missing.epub")
        let keyStore = FakePrivateBookKeyStore()
        keyStore.removalError = TestPersistenceError.keyCleanupFailed
        let service = PrivateBookProtectionService(keyStore: keyStore)

        do {
            _ = try service.protect(bookID: UUID(), managedFileURL: fileURL)
            Issue.record("Expected encryption and cleanup failures")
        } catch let PrivateBookProtectionError.rollbackFailed(operationError, rollbackError) {
            #expect((operationError as NSError).domain == NSCocoaErrorDomain)
            #expect(rollbackError as? TestPersistenceError == .keyCleanupFailed)
        }
    }

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

private enum TestPersistenceError: Error {
    case saveFailed
    case keyCleanupFailed
}

private final class FakePrivateBookKeyStore: PrivateBookKeyStoring {
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
