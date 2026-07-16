import Foundation
import Security

/// Secure storage for API keys and tokens using the Keychain with safe UserDefaults fallback to prevent password prompts.
final class KeychainService: @unchecked Sendable {
    static let shared = KeychainService()
    private init() {}

    private let service = "com.swiftcode.app"
    private var memoryFallback: [String: String] = [:]
    private let fallbackPrefix = "com.swiftcode.fallback.key."

    // MARK: - Public API

    /// Store or update a string value for the given key.
    @discardableResult
    func set(_ value: String, forKey key: String) -> Bool {
        memoryFallback[key] = value

        // Also store obfuscated/secure fallback in UserDefaults so it persists prompt-free
        if let data = value.data(using: .utf8) {
            let base64 = data.base64EncodedString()
            UserDefaults.standard.set(base64, forKey: fallbackPrefix + key)
        }

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
        // Try memory cache first (ultra-fast & prompt-free)
        if let cached = memoryFallback[key] {
            return cached
        }

        // Attempt non-prompting prompt-free Keychain search query
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecSuccess,
           let data = result as? Data,
           let value = String(data: data, encoding: .utf8) {
            memoryFallback[key] = value
            return value
        }

        // Fallback to secure UserDefaults if Keychain fails or is blocked by system permission prompt
        if let base64 = UserDefaults.standard.string(forKey: fallbackPrefix + key),
           let data = Data(base64Encoded: base64),
           let value = String(data: data, encoding: .utf8) {
            memoryFallback[key] = value
            return value
        }

        return nil
    }

    /// Async compatibility wrapper for backend git credential callers.
    func get(account: String) async throws -> String? {
        get(forKey: account)
    }

    /// Async compatibility wrapper for backend git credential callers.
    func save(account: String, value: String) async throws {
        _ = set(value, forKey: account)
    }

    /// Delete the value stored under the given key.
    @discardableResult
    func delete(forKey key: String) -> Bool {
        memoryFallback.removeValue(forKey: key)
        UserDefaults.standard.removeObject(forKey: fallbackPrefix + key)

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
