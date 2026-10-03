import CryptoKit
import Foundation
@testable import Varq

final class DeletionTestKeyStore: PrivateBookKeyStoring {
    var keys: [UUID: SymmetricKey] = [:]
    var removalError: (any Error)?

    func store(_ key: SymmetricKey, for bookID: UUID) throws { keys[bookID] = key }
    func key(for bookID: UUID, authenticationPrompt: String) throws -> SymmetricKey {
        guard let key = keys[bookID] else { throw CocoaError(.fileNoSuchFile) }
        return key
    }
    func removeKey(for bookID: UUID) throws {
        if let removalError { throw removalError }
        keys.removeValue(forKey: bookID)
    }
}

final class DeletionTestFileManager: FileManager, @unchecked Sendable {
    var failMovesToManagedFile = false
    var failStaging = false
    var failCompletedRemoval = false

    override func moveItem(at source: URL, to destination: URL) throws {
        if (failStaging && destination.lastPathComponent == "payload") ||
            (failMovesToManagedFile && source.lastPathComponent == "payload") {
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.moveItem(at: source, to: destination)
    }

    override func removeItem(at url: URL) throws {
        if failCompletedRemoval && url.lastPathComponent.hasPrefix(".completed-") {
            throw CocoaError(.fileWriteNoPermission)
        }
        try super.removeItem(at: url)
    }
}
