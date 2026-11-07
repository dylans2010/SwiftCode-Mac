import Foundation
import Security

public enum SDKKeychain {

    public static let service = "com.swiftcode.sdk"

    private static nonisolated(unsafe) let accessibility: CFString = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

    public static func set(_ value: String, forKey key: String) throws {
        try validateKey(key)
        guard let data = value.data(using: .utf8) else {
            throw keychainError(
                operation: "store",
                message: "Could not store the SDK credential.",
                status: nil,
                reason: "utf8-encode-failed"
            )
        }

        var addQuery = baseQuery(forKey: key)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = accessibility

        var status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let updateQuery = baseQuery(forKey: key)
            let updates: [String: Any] = [kSecValueData as String: data]
            status = SecItemUpdate(updateQuery as CFDictionary, updates as CFDictionary)
        }
        guard status == errSecSuccess else {
            throw keychainError(operation: "store", message: "Could not store the SDK credential.", status: status, reason: nil)
        }
    }

    public static func get(forKey key: String) throws -> String? {
        try validateKey(key)

        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw keychainError(operation: "read", message: "Could not read the SDK credential.", status: status, reason: nil)
        }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw keychainError(
                operation: "read",
                message: "The stored SDK credential is corrupt and cannot be used.",
                status: status,
                reason: "utf8-decode-failed"
            )
        }
        return value
    }

    public static func delete(forKey key: String) throws {
        try validateKey(key)

        let status = SecItemDelete(baseQuery(forKey: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw keychainError(operation: "delete", message: "Could not delete the SDK credential.", status: status, reason: nil)
        }
    }

    static func accountNames(withPrefix prefix: String) throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return []
        }
        guard status == errSecSuccess else {
            throw keychainError(operation: "list", message: "Could not list SDK credentials.", status: status, reason: nil)
        }
        guard let items = result as? [[String: Any]] else {
            throw keychainError(
                operation: "list",
                message: "Could not list SDK credentials.",
                status: status,
                reason: "unexpected-result-shape"
            )
        }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
            .filter { $0.hasPrefix(prefix) }
    }

    private static func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
    }

    private static func validateKey(_ key: String) throws {
        guard !key.isEmpty, key.count <= 256 else {
            throw SDKError(
                code: .invalidArgument,
                message: "Invalid SDK credential key.",
                diagnostics: ["reason": "bad-key-length"]
            )
        }
    }

    private static func keychainError(
        operation: String,
        message: String,
        status: OSStatus?,
        reason: String?
    ) -> SDKError {
        var diagnostics: [String: String] = ["operation": operation]
        if let status {
            diagnostics["osstatus"] = String(status)
        }
        if let reason {
            diagnostics["reason"] = reason
        }
        return SDKError(
            code: .serviceUnavailable,
            message: message,
            suggestion: "The macOS Keychain could not be reached. Check that the Keychain is unlocked and try again.",
            diagnostics: diagnostics
        )
    }
}
