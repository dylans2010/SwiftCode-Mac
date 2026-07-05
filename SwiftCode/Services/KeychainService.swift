import Foundation
import Security

/// Secure storage for API keys and tokens using the iOS Keychain.
final class KeychainService {
    static let shared = KeychainService()
    private init() {}

    private let service = "com.swiftcode.app"

    // MARK: - Public API

    /// Store or update a string value for the given key.
    @discardableResult
    func set(_ value: String, forKey key: String) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }

        // Delete any existing item first.
        delete(forKey: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        return status == errSecSuccess
    }

    /// Retrieve the string value for the given key, or nil if not found.
    func get(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        return value
    }

    /// Delete the value stored under the given key.
    @discardableResult
    func delete(forKey key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    /// Returns true if a value exists for the given key.
    func contains(key: String) -> Bool {
        get(forKey: key) != nil
    }
}

// MARK: - Convenience key constants
extension KeychainService {
    static let openRouterAPIKey = "openrouter_api_key"
    static let githubToken = "github_personal_access_token"
    static let codexUserAPIKey = "codex_user_api_key"
    static let codexAppAPIKey = "codex_app_api_key"
}
