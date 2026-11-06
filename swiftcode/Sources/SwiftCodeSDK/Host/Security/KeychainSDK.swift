import Foundation

// MARK: - KeychainSDK
//
// Ported from Legacy `SwiftCode/SDK/Host/Security/KeychainSDK.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// The host Keychain vault for extension secrets. Values live under the
// namespace `com.swiftcode.sdk.security.<securityID>.<valueID>`, one
// account per value, stored as a JSON envelope
// `{data base64, label, created, modified}`. The extension never sees
// plaintext: `readValue` is INTERNAL — only host code in this module
// (notably `SDKSecurityService.useValue`) may read a value, and only to
// inject it into an approved host operation.
//
// Storage seam: `SDKSecretStoring` (macOS Keychain via `SDKKeychain`,
// file store on Linux). Legacy used the Security framework directly
// with service prefix `com.swiftcode.sdk.security`; here the full
// namespaced string is the account inside the SDK secret store
// (service `com.swiftcode.sdk`), which preserves the namespace and
// keeps enumeration working on both platforms. Accessibility
// WhenUnlockedThisDeviceOnly, no sync, no UserDefaults, no cache —
// those properties hold on the macOS backend.

public enum KeychainSDK {
    /// Namespace prefix for every vault account.
    public static let servicePrefix = "com.swiftcode.sdk.security"

    /// Metadata for one stored value. The secret bytes live in the
    /// envelope's `data` field and are never exposed by the metadata
    /// APIs (`listValueIDs` returns these, never values).
    public struct ValueMetadata: Sendable, Codable, Equatable {
        public let valueID: String
        public let label: String?
        public let created: Date
        public let modified: Date

        public init(valueID: String, label: String? = nil, created: Date = Date(), modified: Date = Date()) {
            self.valueID = valueID
            self.label = label
            self.created = created
            self.modified = modified
        }
    }

    private struct Envelope: Codable {
        var data: Data
        var label: String?
        var created: Date
        var modified: Date
        /// Namespaced Security ID (`<extensionID>.<appSecurityID>`) this
        /// value belongs to. Written by `addValue` so `listAllApps` can
        /// recover the app grouping exactly; older envelopes without it
        /// fall back to a last-dot split of the account name.
        var securityID: String?

        init(data: Data, label: String?, created: Date, modified: Date, securityID: String? = nil) {
            self.data = data
            self.label = label
            self.created = created
            self.modified = modified
            self.securityID = securityID
        }

        private enum CodingKeys: String, CodingKey {
            case data, label, created, modified, securityID
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            data = try container.decode(Data.self, forKey: .data)
            label = try container.decodeIfPresent(String.self, forKey: .label)
            created = try container.decode(Date.self, forKey: .created)
            modified = try container.decode(Date.self, forKey: .modified)
            securityID = try container.decodeIfPresent(String.self, forKey: .securityID)
        }
    }

    private static let store: any SDKSecretStoring = SDKSecretStoreFactory.defaultStore()

    static func account(for securityID: String, valueID: String) -> String {
        "\(servicePrefix).\(securityID).\(valueID)"
    }

    static func accountPrefix(for securityID: String) -> String {
        "\(servicePrefix).\(securityID)."
    }

    /// Stores (or replaces) a value. Returns whether a value already
    /// existed. The label is optional metadata, never secret material.
    public static func addValue(
        securityID: String,
        valueID: String,
        value: Data,
        label: String?
    ) throws -> Bool {
        try validateSecurityID(securityID)
        try validateValueID(valueID)
        if let label { try validateLabel(label) }
        let account = account(for: securityID, valueID: valueID)
        let existed = (try? store.read(account: account)) != nil
        let now = Date()
        let created: Date
        if let existing = try? store.read(account: account),
           let envelope = try? Self.decodeEnvelope(existing) {
            created = envelope.created
        } else {
            created = now
        }
        let envelope = Envelope(data: value, label: label, created: created, modified: now, securityID: securityID)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(envelope)
        try store.write(data, account: account)
        return existed
    }

    /// Host-only read. INTERNAL by design: only host code in this
    /// module may call it, and only to inject the value into an
    /// approved host operation. Never expose to extensions.
    static func readValue(securityID: String, valueID: String) throws -> Data? {
        try validateSecurityID(securityID)
        try validateValueID(valueID)
        guard let data = try store.read(account: account(for: securityID, valueID: valueID)) else {
            return nil
        }
        return try decodeEnvelope(data).data
    }

    public static func hasValue(securityID: String, valueID: String) throws -> Bool {
        try validateSecurityID(securityID)
        try validateValueID(valueID)
        return try store.read(account: account(for: securityID, valueID: valueID)) != nil
    }

    /// Metadata only, sorted by value ID. Values are never returned.
    public static func listValueIDs(securityID: String) throws -> [ValueMetadata] {
        try validateSecurityID(securityID)
        let prefix = accountPrefix(for: securityID)
        let accounts = try store.accountNames(withPrefix: prefix)
        var result: [ValueMetadata] = []
        for account in accounts {
            guard let data = try? store.read(account: account),
                  let envelope = try? decodeEnvelope(data) else { continue }
            let valueID = String(account.dropFirst(prefix.count))
            result.append(ValueMetadata(valueID: valueID, label: envelope.label, created: envelope.created, modified: envelope.modified))
        }
        return result.sorted { $0.valueID < $1.valueID }
    }

    public static func deleteValue(securityID: String, valueID: String) throws {
        try validateSecurityID(securityID)
        try validateValueID(valueID)
        try store.delete(account: account(for: securityID, valueID: valueID))
    }

    /// Deletes every value under `securityID`. Returns the count.
    /// Used by the uninstall wipe (`deleteAllValues`).
    public static func deleteAllValues(securityID: String) throws -> Int {
        try validateSecurityID(securityID)
        let prefix = accountPrefix(for: securityID)
        let accounts = try store.accountNames(withPrefix: prefix)
        for account in accounts {
            try store.delete(account: account)
        }
        return accounts.count
    }

    // MARK: - Validation

    /// A Security ID is reverse-DNS-ish: 1–128 characters, at least two
    /// segments of 1–63 ASCII alphanumerics with interior `-`, no `/`,
    /// no `..`, no whitespace or control characters.
    public static func validateSecurityID(_ securityID: String) throws {
        guard (1...128).contains(securityID.count),
              !securityID.contains("/"),
              !securityID.contains(".."),
              securityID.unicodeScalars.allSatisfy({ !$0.properties.isWhitespace && !$0.isControlCharacter }),
              !securityID.contains(" ") else {
            throw SDKError(code: .invalidArgument, message: "The Security ID is invalid.")
        }
        let segments = securityID.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2,
              segments.allSatisfy({ segment in
                  (1...63).contains(segment.count)
                  && segment.unicodeScalars.allSatisfy({ $0.isASCIIAlphanumeric || $0 == "-" })
                  && segment.first.map({ $0.isLetter || $0.isNumber }) == true
                  && segment.last.map({ $0.isLetter || $0.isNumber }) == true
              }) else {
            throw SDKError(code: .invalidArgument, message: "The Security ID is invalid.")
        }
    }

    /// A value ID is 1–128 characters of ASCII alphanumerics with
    /// interior `.`, `/`, `-`, `_`.
    public static func validateValueID(_ valueID: String) throws {
        guard (1...128).contains(valueID.count),
              valueID.unicodeScalars.allSatisfy({ $0.isASCIIAlphanumeric || "./-_".contains(Character($0)) }),
              valueID.first.map({ $0.isLetter || $0.isNumber }) == true,
              valueID.last.map({ $0.isLetter || $0.isNumber }) == true else {
            throw SDKError(code: .invalidArgument, message: "The value ID is invalid.")
        }
    }

    /// A label is 1–256 characters, no NUL.
    public static func validateLabel(_ label: String) throws {
        guard (1...256).contains(label.count), !label.contains("\0") else {
            throw SDKError(code: .invalidArgument, message: "The label is invalid.")
        }
    }

    /// The namespaced Security ID recorded in a stored value's envelope,
    /// when the value was written with one. Host-only helper for
    /// `listAllApps`: the envelope is the exact grouping key. Returns nil
    /// for envelopes written before the field existed (or unreadable data).
    static func securityIDInEnvelope(_ data: Data) -> String? {
        (try? decodeEnvelope(data))?.securityID
    }

    // MARK: - Private

    private static func decodeEnvelope(_ data: Data) throws -> Envelope {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Envelope.self, from: data)
    }
}

private extension Unicode.Scalar {
    var isASCIIAlphanumeric: Bool {
        (value >= 48 && value <= 57) || (value >= 65 && value <= 90) || (value >= 97 && value <= 122)
    }

    var isControlCharacter: Bool {
        value < 32 || value == 127
    }
}
