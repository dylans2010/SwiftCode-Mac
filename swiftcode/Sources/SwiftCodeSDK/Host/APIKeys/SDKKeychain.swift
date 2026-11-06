import Foundation
#if canImport(Security)
import Security
#endif

// MARK: - SDKSecretStoring
//
// Ported from Legacy `SwiftCode/SDK/Host/APIKeys/SDKKeychain.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// The SDK host needs a secret store with ENUMERATION — the API key store
// lists key metadata (`sdk.apikey.*`) and the Assist application store
// lists applications (`sdk.assistapp.*`). SwiftCodeAssistant's `SecretStore`
// protocol has no enumeration, so it cannot serve here; this protocol is
// the SDK host's own seam. The macOS backend uses the same Security
// framework primitives as SwiftCodeAssistant's `KeychainSecretStore`; the
// Linux backend mirrors its `FileSecretStore` discipline (0700 directory,
// 0600 files, atomic writes) under a separate SDK directory so SDK
// secrets never share a store with assistant secrets.

/// A secret store with enumeration, for SDK host secrets (device key,
/// API key metadata, Assist applications, KeychainSDK vault envelopes).
/// Values are opaque bytes; callers own the encoding. Never store a
/// presented API key secret here — only metadata and host-held keys.
public protocol SDKSecretStoring: Sendable {
    /// Returns the stored value, or `nil` when the account does not exist.
    func read(account: String) throws -> Data?
    /// Creates or replaces the stored value.
    func write(_ data: Data, account: String) throws
    /// Deletes the stored value. No-op when absent.
    func delete(account: String) throws
    /// All account names starting with `prefix`, sorted.
    func accountNames(withPrefix prefix: String) throws -> [String]
}

public enum SDKSecretStoreFactory {
    /// The default store for this platform: macOS Keychain, or the file
    /// store on Linux.
    public static func defaultStore() -> any SDKSecretStoring {
        #if canImport(Security)
        return SDKKeychain.shared
        #else
        return SDKFileSecretStore()
        #endif
    }
}

// MARK: - SDKKeychain (macOS)

#if canImport(Security)

/// macOS Keychain-backed secret store for SDK host secrets.
///
/// Service `com.swiftcode.sdk`, accessibility
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. No UserDefaults
/// fallback, no in-memory cache. Failures surface as
/// `.serviceUnavailable` — the host fails closed, never silently
/// regenerating key material.
public final class SDKKeychain: SDKSecretStoring, @unchecked Sendable {
    public static let shared = SDKKeychain()

    /// The Keychain service for all SDK host secrets.
    public static let service = "com.swiftcode.sdk"

    private init() {}

    public func read(account: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "The secret store is unavailable.",
                suggestion: "Check that the Keychain is unlocked and try again.",
                diagnostics: ["keychainStatus": String(status)]
            )
        }
        return data
    }

    public func write(_ data: Data, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "The secret store is unavailable.",
                suggestion: "Check that the Keychain is unlocked and try again.",
                diagnostics: ["keychainStatus": String(status)]
            )
        }
    }

    public func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "The secret store is unavailable.",
                suggestion: "Check that the Keychain is unlocked and try again.",
                diagnostics: ["keychainStatus": String(status)]
            )
        }
    }

    public func accountNames(withPrefix prefix: String) throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var items: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &items)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let attributes = items as? [[String: Any]] else {
            throw SDKError(
                code: .serviceUnavailable,
                message: "The secret store is unavailable.",
                suggestion: "Check that the Keychain is unlocked and try again.",
                diagnostics: ["keychainStatus": String(status)]
            )
        }
        return attributes
            .compactMap { $0[kSecAttrAccount as String] as? String }
            .filter { $0.hasPrefix(prefix) }
            .sorted()
    }
}

#else

// MARK: - SDKFileSecretStore (Linux)

/// File-backed secret store for Linux, mirroring the discipline of
/// SwiftCodeAssistant's `FileSecretStore`: a 0700 directory, 0600 files,
/// atomic writes. Directory: `~/.config/swiftcode/sdk-secrets` (or
/// `$XDG_CONFIG_HOME/swiftcode/sdk-secrets`). Separate from the assistant
/// secret store — SDK secrets never share a store with assistant secrets.
public final class SDKFileSecretStore: SDKSecretStoring, @unchecked Sendable {
    private let directory: URL

    public init(directory: URL? = nil) {
        if let directory {
            self.directory = directory
        } else if let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"], !xdg.isEmpty {
            self.directory = URL(fileURLWithPath: xdg).appendingPathComponent("swiftcode/sdk-secrets", isDirectory: true)
        } else {
            self.directory = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".config/swiftcode/sdk-secrets", isDirectory: true)
        }
    }

    private func fileURL(for account: String) -> URL {
        // Accounts are host-controlled identifiers; encode them so they
        // can never escape the directory.
        let encoded = Data(account.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return directory.appendingPathComponent(encoded, isDirectory: false)
    }

    private func ensureDirectory() throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            throw SDKError(code: .serviceUnavailable, message: "The secret store is unavailable.",
                           suggestion: "Check the secret store directory permissions and try again.",
                           diagnostics: ["ioError": error.localizedDescription])
        }
    }

    public func read(account: String) throws -> Data? {
        let url = fileURL(for: account)
        do {
            return try Data(contentsOf: url)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return nil
        } catch {
            throw SDKError(code: .serviceUnavailable, message: "The secret store is unavailable.",
                           diagnostics: ["ioError": error.localizedDescription])
        }
    }

    public func write(_ data: Data, account: String) throws {
        try ensureDirectory()
        let url = fileURL(for: account)
        do {
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            throw SDKError(code: .serviceUnavailable, message: "The secret store is unavailable.",
                           diagnostics: ["ioError": error.localizedDescription])
        }
    }

    public func delete(account: String) throws {
        let url = fileURL(for: account)
        do {
            try FileManager.default.removeItem(at: url)
        } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileNoSuchFileError {
            return
        } catch {
            throw SDKError(code: .serviceUnavailable, message: "The secret store is unavailable.",
                           diagnostics: ["ioError": error.localizedDescription])
        }
    }

    public func accountNames(withPrefix prefix: String) throws -> [String] {
        // File names are base64-encoded accounts, so enumeration reads
        // each file name back through the decoder. The store is small
        // (one file per key/application), so this is a bounded scan.
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return []
        }
        return names.compactMap { name -> String? in
            var base64 = name.replacingOccurrences(of: "_", with: "/").replacingOccurrences(of: "-", with: "+")
            let remainder = base64.count % 4
            if remainder > 0 { base64 += String(repeating: "=", count: 4 - remainder) }
            guard let data = Data(base64Encoded: base64),
                  let account = String(data: data, encoding: .utf8),
                  account.hasPrefix(prefix) else { return nil }
            return account
        }.sorted()
    }
}

#endif
