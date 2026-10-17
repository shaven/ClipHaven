import ClipHavenCore
import Foundation
import Security

/// The shared snippet list as one iCloud-synchronizable Keychain item. It holds no password:
/// only snippet text and Keychain references (see `SnippetSync`).
final class SyncSnapshotStore: SnapshotStore {
    private var identity: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "ClipHaven.Sync",
         kSecAttrAccount as String: "snippets",
         kSecUseDataProtectionKeychain as String: true,
         kSecAttrSynchronizable as String: true]
    }

    func read() throws -> Data? {
        var query = identity
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw KeychainError(status: status)
        }
    }

    func write(_ data: Data) throws {
        var status = SecItemUpdate(identity as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var add = identity
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }
}
