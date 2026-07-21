import CryptoKit
import Foundation
import Testing
@testable import Varq

struct PrivateBookKeyStoreTests {
    @Test func storesRetrievesAndRemovesAPerBookKey() throws {
        let keychain = FakeKeychainItemAccess()
        let store = PrivateBookKeyStore(keychain: keychain)
        let bookID = UUID()
        let key = SymmetricKey(size: .bits256)

        try store.store(key, for: bookID)
        let retrievedKey = try store.key(for: bookID, authenticationPrompt: "Unlock private shelf")
        try store.removeKey(for: bookID)

        #expect(retrievedKey.withUnsafeBytes { Data($0) } == key.withUnsafeBytes { Data($0) })
        #expect(keychain.lastPrompt == "Unlock private shelf")
        #expect(keychain.dataByAccount[bookID.uuidString] == nil)
    }

    @Test func storesAKeyInTheSystemKeychain() throws {
        let store = PrivateBookKeyStore()
        let bookID = UUID()
        defer { try? store.removeKey(for: bookID) }

        try store.store(SymmetricKey(size: .bits256), for: bookID)
    }
}

private final class FakeKeychainItemAccess: KeychainItemAccessing {
    var dataByAccount: [String: Data] = [:]
    var lastPrompt: String?

    func storeKeyData(_ data: Data, account: String) throws { dataByAccount[account] = data }
    func keyData(account: String, authenticationPrompt: String) throws -> Data {
        lastPrompt = authenticationPrompt
        guard let data = dataByAccount[account] else { throw PrivateBookKeyStoreError.keychainStatus(-1) }
        return data
    }
    func removeKeyData(account: String) throws { dataByAccount[account] = nil }
}
