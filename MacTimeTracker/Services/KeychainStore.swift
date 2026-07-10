import Foundation
import Security

/// Minimal wrapper over the macOS Keychain for the Harvest personal access
/// token. The token is *only* ever stored here — never in UserDefaults, never
/// logged.
enum KeychainStore {
    /// Service identifier used to namespace our keychain items.
    private static let service = "com.forecastlogger.harvest"
    private static let account = "personal-access-token"

    /// Accessibility for the token: readable after the first unlock, but bound
    /// to *this device only* — it is never migrated to another Mac via a backup
    /// or restore, which limits where the credential can end up.
    private static let accessible = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    /// Store (or overwrite) the token. Passing an empty string deletes it.
    @discardableResult
    static func saveToken(_ token: String) -> Bool {
        guard !token.isEmpty else { return deleteToken() }
        guard let data = token.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        // Try to update an existing item first; if none, add a new one. The
        // accessibility is set on both paths so an item created by an older
        // build is migrated to ThisDeviceOnly on the next save.
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessible,
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = accessible
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        }
        return false
    }

    /// Load the token, or nil if none is stored.
    static func loadToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token
    }

    /// Remove the stored token.
    @discardableResult
    static func deleteToken() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
