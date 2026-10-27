import Foundation
import Security

/// Synchronizable generic-password items. iCloud Keychain carries them to the user's
/// other devices end-to-end encrypted, so Apple never sees the values.
enum Keychain {
    private static var service: String { Bundle.main.bundleIdentifier ?? "chatbot" }

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: kCFBooleanTrue as Any,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    static func read(_ account: String) -> Data? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    /// Adds an item only if none exists. Returns `errSecDuplicateItem` if one does.
    static func add(_ data: Data, account: String) -> OSStatus {
        var q = query(account)
        q[kSecValueData as String] = data
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(q as CFDictionary, nil)
    }

    /// Adds or replaces an item.
    @discardableResult
    static func write(_ data: Data, account: String) -> Bool {
        let status = SecItemUpdate(query(account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            return add(data, account: account) == errSecSuccess
        }
        return status == errSecSuccess
    }

    static func delete(_ account: String) {
        SecItemDelete(query(account) as CFDictionary)
    }
}
