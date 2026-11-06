import Foundation
import Security

// MARK: - SDKKeychain
//
// Purpose-built Keychain wrapper for the SwiftCode SDK host (ADR §11).
//
// WHY THIS EXISTS — audit finding (do not "simplify" this back):
// The app's general-purpose `KeychainService` DUPLICATES every secret it
// stores — base64-encoded — into UserDefaults under
// `com.swiftcode.fallback.key.<key>`, and keeps secrets in an in-memory
// cache. UserDefaults plist data is world-readable to anything with the
// user's file access and is backed up/synced in ways the Keychain is not.
// A UserDefaults "fallback" for secrets is not a fallback, it is a leak.
//
// This wrapper therefore upholds three hard rules:
//   1. Secrets live ONLY in the Keychain (`kSecClassGenericPassword`,
//      service `com.swiftcode.sdk`). There is NO UserDefaults fallback,
//      under any circumstance, including Keychain errors.
//   2. There is NO in-memory cache of secret values. Every `get` hits the
//      Keychain. (Callers that need a value briefly must zero it when done.)
//   3. Keychain failures surface as `SDKError(code: .serviceUnavailable)` —
//      never silently, never by degrading to a weaker store.
//
// Storage parameters:
// - Accessibility `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`: secrets are
//   unavailable while the device is locked and never migrate to another
//   device via iCloud Keychain sync. Appropriate for Studio-managed
//   developer credentials on a workstation; background access while locked
//   is intentionally unsupported.
// - No `kSecAttrSynchronizable`: nothing here syncs.
// - Values are UTF-8 strings (JSON metadata, base64 device key).
//
// Thread-safety: static functions only, no stored mutable state. All
// Security.framework calls are synchronous and thread-safe.

public enum SDKKeychain {

    /// Keychain service partition for all SDK host secrets.
    public static let service = "com.swiftcode.sdk"

    private static nonisolated(unsafe) let accessibility: CFString = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

    // MARK: - Write

    /// Stores `value` under `key`, creating or replacing the item.
    /// Throws `.serviceUnavailable` on any Keychain failure.
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
            // Already exists: replace the value in place (keeps the original
            // accessibility and creation attributes).
            let updateQuery = baseQuery(forKey: key)
            let updates: [String: Any] = [kSecValueData as String: data]
            status = SecItemUpdate(updateQuery as CFDictionary, updates as CFDictionary)
        }
        guard status == errSecSuccess else {
            throw keychainError(operation: "store", message: "Could not store the SDK credential.", status: status, reason: nil)
        }
    }

    // MARK: - Read

    /// Returns the value stored under `key`, or `nil` when no item exists.
    /// Throws `.serviceUnavailable` on Keychain failure or corrupt data.
    /// Every call reads from the Keychain — values are never cached.
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

    // MARK: - Delete

    /// Deletes the item under `key`. Idempotent: deleting a key that does
    /// not exist succeeds. Throws `.serviceUnavailable` on Keychain failure.
    public static func delete(forKey key: String) throws {
        try validateKey(key)

        let status = SecItemDelete(baseQuery(forKey: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw keychainError(operation: "delete", message: "Could not delete the SDK credential.", status: status, reason: nil)
        }
    }

    // MARK: - Enumeration (internal)

    /// Returns the account names of all items in the SDK service partition
    /// whose account starts with `prefix`. Used to list stored API key
    /// metadata without knowing the IDs up front.
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

    // MARK: - Private helpers

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

    /// Builds the Keychain-failure error. `diagnostics` carry only the
    /// operation name, the numeric OSStatus, and a machine reason — never
    /// secret values, never the stored data.
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
