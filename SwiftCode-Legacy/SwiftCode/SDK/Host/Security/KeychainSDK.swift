import Foundation
import Security

public enum KeychainSDK {

    public struct ValueMetadata: Sendable, Codable, Hashable {
        public let valueID: String
        public let label: String?
        public let created: Date
        public let modified: Date

        public init(valueID: String, label: String?, created: Date, modified: Date) {
            self.valueID = valueID
            self.label = label
            self.created = created
            self.modified = modified
        }
    }

    public static let servicePrefix = "com.swiftcode.sdk.security"

    private static nonisolated(unsafe) let accessibility: CFString = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

    private static let maxIDLength = 128
    private static let maxLabelLength = 256

    public static func addValue(
        securityID: String,
        valueID: String,
        data: Data,
        label: String?
    ) throws {
        let service = try namespacedService(for: securityID)
        try validateValueID(valueID)
        guard !data.isEmpty else {
            throw invalidInput(operation: "store", reason: "empty-data")
        }
        if let label, label.count > maxLabelLength {
            throw invalidInput(operation: "store", reason: "label-too-long")
        }

        var addQuery = baseQuery(service: service, valueID: valueID)
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = accessibility
        if let label {
            addQuery[kSecAttrLabel as String] = label
        }

        var status = SecItemAdd(addQuery as CFDictionary, nil)
        if status == errSecDuplicateItem {
            let matchQuery = baseQuery(service: service, valueID: valueID)
            var updates: [String: Any] = [kSecValueData as String: data]
            if let label {
                updates[kSecAttrLabel as String] = label
            }
            status = SecItemUpdate(matchQuery as CFDictionary, updates as CFDictionary)
        }
        guard status == errSecSuccess else {
            throw keychainError(
                operation: "store",
                message: "Could not store the security value.",
                status: status,
                reason: nil
            )
        }
    }

    static func readValue(securityID: String, valueID: String) throws -> Data? {
        let service = try namespacedService(for: securityID)
        try validateValueID(valueID)

        var query = baseQuery(service: service, valueID: valueID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw keychainError(
                operation: "read",
                message: "Could not read the security value.",
                status: status,
                reason: nil
            )
        }
        guard let data = item as? Data else {
            throw keychainError(
                operation: "read",
                message: "The stored security value is corrupt and cannot be used.",
                status: status,
                reason: "unexpected-result-shape"
            )
        }
        return data
    }

    public static func hasValue(securityID: String, valueID: String) throws -> Bool {
        let service = try namespacedService(for: securityID)
        try validateValueID(valueID)

        var query = baseQuery(service: service, valueID: valueID)
        query[kSecReturnAttributes as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        if status == errSecItemNotFound {
            return false
        }
        guard status == errSecSuccess else {
            throw keychainError(
                operation: "exists",
                message: "Could not check the security value.",
                status: status,
                reason: nil
            )
        }
        return true
    }

    public static func listValueIDs(securityID: String) throws -> [ValueMetadata] {
        let service = try namespacedService(for: securityID)

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
            throw keychainError(
                operation: "list",
                message: "Could not list security values.",
                status: status,
                reason: nil
            )
        }
        guard let items = result as? [[String: Any]] else {
            throw keychainError(
                operation: "list",
                message: "Could not list security values.",
                status: status,
                reason: "unexpected-result-shape"
            )
        }

        return items.compactMap { attributes -> ValueMetadata? in
            guard let valueID = attributes[kSecAttrAccount as String] as? String,
                  let created = attributes[kSecAttrCreationDate as String] as? Date,
                  let modified = attributes[kSecAttrModificationDate as String] as? Date
            else { return nil }
            let label = attributes[kSecAttrLabel as String] as? String
            return ValueMetadata(valueID: valueID, label: label, created: created, modified: modified)
        }
        .sorted { $0.valueID < $1.valueID }
    }

    public static func deleteValue(securityID: String, valueID: String) throws {
        let service = try namespacedService(for: securityID)
        try validateValueID(valueID)

        let status = SecItemDelete(baseQuery(service: service, valueID: valueID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw keychainError(
                operation: "delete",
                message: "Could not delete the security value.",
                status: status,
                reason: nil
            )
        }
    }

    public static func deleteAllValues(securityID: String) throws {
        let service = try namespacedService(for: securityID)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw keychainError(
                operation: "delete-all",
                message: "Could not delete the app's security values.",
                status: status,
                reason: nil
            )
        }
    }

    private static func namespacedService(for securityID: String) throws -> String {
        try validateSecurityID(securityID)
        return "\(servicePrefix).\(securityID)"
    }

    private static func validateSecurityID(_ securityID: String) throws {
        guard !securityID.isEmpty, securityID.count <= maxIDLength else {
            throw invalidInput(operation: "validate-security-id", reason: "bad-length")
        }
        guard !securityID.contains("/") else {
            throw invalidInput(operation: "validate-security-id", reason: "path-separator")
        }
        guard !securityID.contains("..") else {
            throw invalidInput(operation: "validate-security-id", reason: "path-traversal")
        }
        let segments = securityID.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2,
              segments.allSatisfy({ isDNSSegment(String($0)) })
        else {
            throw invalidInput(operation: "validate-security-id", reason: "bad-reverse-dns")
        }
    }

    private static func validateValueID(_ valueID: String) throws {
        guard !valueID.isEmpty, valueID.count <= maxIDLength else {
            throw invalidInput(operation: "validate-value-id", reason: "bad-length")
        }
        guard !valueID.contains("/") else {
            throw invalidInput(operation: "validate-value-id", reason: "path-separator")
        }
        guard !valueID.contains("..") else {
            throw invalidInput(operation: "validate-value-id", reason: "path-traversal")
        }
        guard isValueSegment(valueID) else {
            throw invalidInput(operation: "validate-value-id", reason: "bad-characters")
        }
    }

    private static func isDNSSegment(_ segment: String) -> Bool {
        guard (1...63).contains(segment.count) else { return false }
        let chars = Array(segment)
        guard let first = chars.first, let last = chars.last,
              first.isASCIILetterOrDigit, last.isASCIILetterOrDigit
        else { return false }
        return chars.allSatisfy { $0.isASCIILetterOrDigit || $0 == "-" }
    }

    private static func isValueSegment(_ value: String) -> Bool {
        let chars = Array(value)
        guard let first = chars.first, let last = chars.last,
              first.isASCIILetterOrDigit, last.isASCIILetterOrDigit
        else { return false }
        return chars.allSatisfy { $0.isASCIILetterOrDigit || $0 == "." || $0 == "-" || $0 == "_" }
    }

    private static func baseQuery(service: String, valueID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: valueID,
        ]
    }

    private static func invalidInput(operation: String, reason: String) -> SDKError {
        SDKError(
            code: .invalidArgument,
            message: "Invalid security identifier.",
            suggestion: "Security IDs look like reverse-DNS names (for example, com.example.myapp) and value IDs look like openai-key.",
            diagnostics: sanitizedDiagnostics(operation: operation, reason: reason)
        )
    }

    private static func keychainError(
        operation: String,
        message: String,
        status: OSStatus?,
        reason: String?
    ) -> SDKError {
        var diagnostics = sanitizedDiagnostics(operation: operation, reason: reason)
        if let status {
            diagnostics["osstatus"] = String(status)
            if status == errSecAuthFailed {
                diagnostics["reason"] = "keychain-auth-failed"
            }
        }
        let suggestion: String
        if status == errSecAuthFailed {
            suggestion = "The macOS Keychain rejected the request (authentication failed). Unlock the Keychain and try again."
        } else {
            suggestion = "The macOS Keychain could not be reached. Check that the Keychain is unlocked and try again."
        }
        return SDKError(
            code: .serviceUnavailable,
            message: message,
            suggestion: suggestion,
            diagnostics: diagnostics
        )
    }

    private static func sanitizedDiagnostics(operation: String, reason: String?) -> [String: String] {
        var diagnostics: [String: String] = [
            "operation": SDKLogRedaction.redactSecrets(in: operation),
        ]
        if let reason {
            diagnostics["reason"] = SDKLogRedaction.redactDiagnosticValue(key: "reason", value: reason)
        }
        return diagnostics
    }
}

private extension Character {
    var isASCIILetterOrDigit: Bool {
        unicodeScalars.allSatisfy { scalar in
            let v = scalar.value
            return (v >= 0x30 && v <= 0x39)
                || (v >= 0x41 && v <= 0x5A)
                || (v >= 0x61 && v <= 0x7A)
        }
    }
}
