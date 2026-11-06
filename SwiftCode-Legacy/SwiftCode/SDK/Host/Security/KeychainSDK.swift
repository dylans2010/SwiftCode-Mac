import Foundation
import Security

// MARK: - KeychainSDK
//
// Real macOS Keychain wrapper backing the SDK's `use.Security` capability —
// the per-app secret vault (API keys, OAuth client secrets, tokens) that
// lets an app ask the HOST to hold credentials the app itself may never see.
//
// WHY THIS EXISTS — per-app isolation (do not "simplify" this back):
//   1. Every app gets its OWN Keychain service partition:
//      `com.swiftcode.sdk.security.<securityID>`, where `securityID` is the
//      app's Security ID tied to its verified extension identity (manifest
//      + registry, assigned by the host — NEVER taken from an
//      extension-supplied IPC payload). Cross-app access is impossible BY
//      CONSTRUCTION: every query exact-matches `kSecAttrService` against
//      the namespaced service string, and `validateSecurityID` rejects any
//      input that could alias or escape the partition (`/`, whitespace or
//      control characters, empty segments, leading/trailing dots, any `..`,
//      oversize strings). The namespaced service is built in exactly one
//      place (`namespacedService(for:)`); no method accepts a raw service
//      string.
//   2. Secrets live ONLY in the Keychain (`kSecClassGenericPassword`).
//      There is NO UserDefaults fallback and NO in-memory cache of secret
//      values — every read hits the Keychain. (Same hard rules as
//      `SDKKeychain` in `Host/APIKeys/SDKKeychain.swift`; see its header
//      for the audit history.)
//   3. Secret BYTES never cross the IPC boundary. `readValue` is
//      module-`internal` (not `public`) and documented HOST-ONLY: the host
//      uses it to inject credentials into outbound requests it builds
//      itself (e.g. completing an OAuth exchange on the app's behalf),
//      then lets the bytes deallocate. Apps and extensions see metadata
//      only (`ValueMetadata`) — never data.
//
// Storage parameters:
// - Accessibility `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — verified
//   against `SDKKeychain`, which uses the same constant: items are
//   unavailable while the device is locked and never migrate to another
//   device via iCloud Keychain sync. Background access while locked is
//   intentionally unsupported.
// - No `kSecAttrSynchronizable`: nothing here syncs.
// - The account field carries the Security Value ID (`openai-key`,
//   `google-client-secret`, …); the label field carries the human label.
//
// There is no "default" or ambient identity: every public method takes an
// explicit `securityID` (and, where relevant, an explicit `valueID`).
//
// Thread-safety: static functions only, no stored mutable state. All
// Security.framework calls are synchronous and thread-safe.

public enum KeychainSDK {

    // MARK: - Metadata

    /// Metadata for one stored value. Carries NO secret material — safe to
    /// hand to the host's management UI or (via a host adapter) to the app
    /// as an inventory listing. The secret bytes are never exposed here.
    public struct ValueMetadata: Sendable, Codable, Hashable {
        /// The Security Value ID (`kSecAttrAccount`).
        public let valueID: String
        /// The human-readable label, if one was stored.
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

    // MARK: - Namespace

    /// Keychain service prefix for ALL Security vault partitions. The full
    /// service is `prefix + "." + <validated securityID>`. Nothing in this
    /// file ever queries a service string that did not go through
    /// `namespacedService(for:)` first.
    public static let servicePrefix = "com.swiftcode.sdk.security"

    private static nonisolated(unsafe) let accessibility: CFString = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

    private static let maxIDLength = 128
    private static let maxLabelLength = 256

    // MARK: - Write

    /// Stores `data` under (`securityID`, `valueID`), creating the item or
    /// replacing it in place (preserving the original accessibility and
    /// creation attributes). `label` is optional metadata shown in
    /// listings; a `nil` label on update preserves the existing label.
    ///
    /// Throws `.invalidArgument` for a bad securityID/valueID, empty data,
    /// or an oversize label; `.serviceUnavailable` on Keychain failure.
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
            // Already exists: replace the value (and label, when given) in
            // place, keeping the original accessibility and creation date.
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

    // MARK: - Read (host-only)

    /// Returns the secret bytes for (`securityID`, `valueID`), or `nil`
    /// when no item exists. Every call reads from the Keychain — values are
    /// never cached.
    ///
    /// Throws `.invalidArgument` on bad IDs, `.serviceUnavailable` on
    /// Keychain failure or corrupt data.
    ///
    /// HOST-ONLY — `internal` on purpose. The secret bytes MUST NEVER
    /// cross the IPC boundary to an extension or app, be written to a log,
    /// be cached in memory, or be returned from any `public` API. Callers
    /// use the bytes briefly (e.g. injecting a credential into a
    /// host-built outbound request) and must not retain copies.
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

    // MARK: - Existence

    /// Returns `true` when an item exists for (`securityID`, `valueID`).
    /// Existence only — the secret bytes are never returned or logged.
    ///
    /// Throws `.invalidArgument` on bad IDs, `.serviceUnavailable` on
    /// Keychain failure.
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

    // MARK: - List (metadata only)

    /// Lists every value stored for `securityID`, metadata only: value ID,
    /// label, and creation/modification dates. Secret bytes are NEVER
    /// returned by this function. Returns `[]` when the partition is empty.
    ///
    /// Throws `.invalidArgument` on a bad securityID,
    /// `.serviceUnavailable` on Keychain failure.
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

    // MARK: - Delete

    /// Deletes the item for (`securityID`, `valueID`). Idempotent: deleting
    /// a value that does not exist succeeds.
    ///
    /// Throws `.invalidArgument` on bad IDs, `.serviceUnavailable` on
    /// Keychain failure.
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

    /// Deletes EVERY value in the `securityID` partition — the uninstall
    /// path. Scoped to this app's namespaced service only; other apps'
    /// partitions are untouched by construction. Idempotent.
    ///
    /// Throws `.invalidArgument` on a bad securityID,
    /// `.serviceUnavailable` on Keychain failure.
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

    // MARK: - Namespace validation

    /// Builds the Keychain service for `securityID` AFTER validation.
    /// `com.swiftcode.sdk.security.<securityID>` — the single choke point
    /// through which every operation derives its service string, which is
    /// what makes cross-app access impossible by construction: there is no
    /// other path from an identifier to a service string in this file.
    private static func namespacedService(for securityID: String) throws -> String {
        try validateSecurityID(securityID)
        return "\(servicePrefix).\(securityID)"
    }

    /// Validates an app Security ID: reverse-DNS-ish, bounded, and unable
    /// to escape or alias the `com.swiftcode.sdk.security.` partition.
    ///
    /// Rules: 1…128 chars total; at least two dot-separated segments (a
    /// bare word like `keychain` is rejected — Security IDs are namespaced
    /// like bundle IDs); every segment 1…63 chars, ASCII letters/digits
    /// with interior `-` only (never leading/trailing). Rejected outright:
    /// empty, `/`, whitespace, control characters, leading/trailing dots,
    /// empty segments, and any `..` (path-traversal shape).
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

    /// Validates a Security Value ID (`openai-key`, `google-client-secret`,
    /// …): a single kebab-ish label, 1…128 chars, ASCII letters/digits with
    /// interior `.`/`-`/`_` (never leading/trailing). Same traversal
    /// rejections as `validateSecurityID`: no `/`, no whitespace or
    /// control characters, no `..`.
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

    /// Reverse-DNS segment: starts and ends ASCII alphanumeric, interior may
    /// contain `-`. Pure-ASCII by construction (rejects whitespace, control
    /// characters, and every other Unicode shape).
    private static func isDNSSegment(_ segment: String) -> Bool {
        guard (1...63).contains(segment.count) else { return false }
        let chars = Array(segment)
        guard let first = chars.first, let last = chars.last,
              first.isASCIILetterOrDigit, last.isASCIILetterOrDigit
        else { return false }
        return chars.allSatisfy { $0.isASCIILetterOrDigit || $0 == "-" }
    }

    /// Value-ID label: starts and ends ASCII alphanumeric, interior may
    /// also contain `.`, `-`, `_`.
    private static func isValueSegment(_ value: String) -> Bool {
        let chars = Array(value)
        guard let first = chars.first, let last = chars.last,
              first.isASCIILetterOrDigit, last.isASCIILetterOrDigit
        else { return false }
        return chars.allSatisfy { $0.isASCIILetterOrDigit || $0 == "." || $0 == "-" || $0 == "_" }
    }

    // MARK: - Query + errors

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

    /// Builds the Keychain-failure error. `diagnostics` carry only the
    /// operation name, the numeric OSStatus, and a machine reason — never
    /// secret values, never the stored data, never a label (labels are
    /// free text and could themselves contain pasted secrets). An
    /// `errSecAuthFailed` status surfaces as an actionable auth failure,
    /// not a generic outage.
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

    /// Diagnostics for the SDK developer log: operation name + machine
    /// reason only, passed through the shared redaction helpers
    /// (`SDKLogRedaction`) so that even a future caller passing free text
    /// here cannot leak secret material into
    /// `~/.swiftcode/logs/developer-sdk.log`.
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

// MARK: - Character helpers

private extension Character {
    /// ASCII letter or digit only — by explicit Unicode-scalar ranges, so
    /// no locale or Unicode-shape surprise can widen the accepted set.
    var isASCIILetterOrDigit: Bool {
        unicodeScalars.allSatisfy { scalar in
            let v = scalar.value
            return (v >= 0x30 && v <= 0x39)   // 0-9
                || (v >= 0x41 && v <= 0x5A)   // A-Z
                || (v >= 0x61 && v <= 0x7A)   // a-z
        }
    }
}
