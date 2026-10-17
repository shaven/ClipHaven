import ClipHavenCore
import Foundation
import LocalAuthentication
import Security

struct KeychainError: Error, CustomStringConvertible {
    let status: OSStatus
    var description: String {
        "Keychain error \(status): \(SecCopyErrorMessageString(status, nil) as String? ?? "unknown")"
    }
}

/// Generic-password items in the login keychain, one per `SecretRef`.
///
/// A new item first tries the data-protection keychain with a `.userPresence` access control, so
/// the Keychain itself demands Touch ID. A Developer ID build without a provisioning profile may
/// be refused that (`errSecMissingEntitlement`, -34018; unverified); the item is then stored in the
/// file keychain and only the app-level check guards it.
final class KeychainProvider: SecretProvider {
    private let authenticator: TouchIDAuthenticator
    /// Whether the last `store` got the Keychain-enforced access control.
    private(set) var lastStoreWasEnforced = false

    init(authenticator: TouchIDAuthenticator) {
        self.authenticator = authenticator
    }

    func read(_ ref: SecretRef) throws -> String? {
        var query = base(ref)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if let context = authenticator.lastContext { query[kSecUseAuthenticationContext as String] = context }

        for protectedKeychain in [true, false] {
            query[kSecUseDataProtectionKeychain as String] = protectedKeychain
            var result: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &result)
            switch status {
            case errSecSuccess:
                return (result as? Data).map { String(decoding: $0, as: UTF8.self) }
            case errSecItemNotFound, errSecMissingEntitlement:
                continue
            default:
                throw KeychainError(status: status)
            }
        }
        return nil
    }

    func store(_ value: String, as ref: SecretRef) throws {
        try remove(ref)
        var attributes = base(ref)
        attributes[kSecValueData as String] = Data(value.utf8)

        var enforced = attributes
        enforced[kSecUseDataProtectionKeychain as String] = true
        if let control = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, nil) {
            enforced[kSecAttrAccessControl as String] = control
            let status = SecItemAdd(enforced as CFDictionary, nil)
            if status == errSecSuccess {
                lastStoreWasEnforced = true
                return
            }
            NSLog("ClipHaven: Keychain-enforced item refused (\(status)); using the file keychain")
        }

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        lastStoreWasEnforced = false
    }

    func remove(_ ref: SecretRef) throws {
        for protectedKeychain in [true, false] {
            var query = base(ref)
            query[kSecUseDataProtectionKeychain as String] = protectedKeychain
            let status = SecItemDelete(query as CFDictionary)
            guard [errSecSuccess, errSecItemNotFound, errSecMissingEntitlement].contains(status) else {
                throw KeychainError(status: status)
            }
        }
    }

    private func base(_ ref: SecretRef) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: ref.service,
         kSecAttrAccount as String: ref.account]
    }
}
