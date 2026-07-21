import CryptoKit
import Foundation
import LocalAuthentication
import Security

protocol PrivateBookKeyStoring: AnyObject {
    func store(_ key: SymmetricKey, for bookID: UUID) throws
    func key(for bookID: UUID, authenticationPrompt: String) throws -> SymmetricKey
    func removeKey(for bookID: UUID) throws
}

protocol KeychainItemAccessing: AnyObject {
    func storeKeyData(_ data: Data, account: String) throws
    func keyData(account: String, authenticationPrompt: String) throws -> Data
    func removeKeyData(account: String) throws
}

final class PrivateBookKeyStore: PrivateBookKeyStoring {
    private let keychain: any KeychainItemAccessing

    init(keychain: any KeychainItemAccessing = SystemKeychainItemAccess()) {
        self.keychain = keychain
    }

    func store(_ key: SymmetricKey, for bookID: UUID) throws {
        try keychain.storeKeyData(key.withUnsafeBytes { Data($0) }, account: bookID.uuidString)
    }

    func key(for bookID: UUID, authenticationPrompt: String) throws -> SymmetricKey {
        SymmetricKey(data: try keychain.keyData(account: bookID.uuidString, authenticationPrompt: authenticationPrompt))
    }

    func removeKey(for bookID: UUID) throws {
        try keychain.removeKeyData(account: bookID.uuidString)
    }
}

final class SystemKeychainItemAccess: KeychainItemAccessing {
    private let serviceIdentifier = "dev.pratikrai.Varq.private-book-key"

    func storeKeyData(_ data: Data, account: String) throws {
        try removeKeyData(account: account)
        let accessControl = try createAccessControl()
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceIdentifier,
            kSecAttrAccount: account,
            kSecAttrAccessControl: accessControl,
            kSecValueData: data
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw PrivateBookKeyStoreError.keychainStatus(status) }
    }

    private func createAccessControl() throws -> SecAccessControl {
        var accessControlError: Unmanaged<CFError>?
        let context = LAContext()
        var error: NSError?
        let biometricsAvailable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        let flags: SecAccessControlCreateFlags = biometricsAvailable ? .biometryCurrentSet : .userPresence
        guard let accessControl = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, flags, &accessControlError) else {
            throw accessControlError?.takeRetainedValue() ?? PrivateBookKeyStoreError.accessControlCreationFailed
        }
        return accessControl
    }

    func keyData(account: String, authenticationPrompt: String) throws -> Data {
        let context = LAContext()
        context.localizedReason = authenticationPrompt
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: serviceIdentifier,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecUseAuthenticationContext: context
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            throw PrivateBookKeyStoreError.keychainStatus(status)
        }
        return data
    }

    func removeKeyData(account: String) throws {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: serviceIdentifier, kSecAttrAccount: account]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw PrivateBookKeyStoreError.keychainStatus(status) }
    }
}

enum PrivateBookKeyStoreError: Error, Equatable {
    case accessControlCreationFailed
    case keychainStatus(OSStatus)
}
