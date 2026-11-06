import Foundation
import Crypto

// MARK: - SDKAPIKey
//
// Ported from Legacy `SwiftCode/SDK/Host/APIKeys/SDKAPIKey.swift`
// (Dylan's own code; direct port authorised under MIT).
//
// Developer API keys authenticate the *developer* of an extension, not
// the extension itself. The secret is shown exactly once at creation and
// never persisted; only metadata is stored. Verification is HMAC-SHA256
// over the payload with a host-held device key.

/// A developer API key scope. Open `RawRepresentable`: the three known
/// values below are the current set, but any non-empty string is accepted
/// so future scopes do not break decoding of stored key records.
public struct SDKAPIKeyScope: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public static let appsCreate = SDKAPIKeyScope("apps:create")
    public static let appsPublish = SDKAPIKeyScope("apps:publish")
    public static let capabilitiesRequest = SDKAPIKeyScope("capabilities:request")

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        guard !value.isEmpty else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "API key scope must not be empty.")
        }
        self.rawValue = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Metadata for one developer API key. The secret itself is NEVER stored
/// here — only the key ID, prefix, label, scopes, entitlements, and
/// lifecycle timestamps.
public struct SDKAPIKey: Codable, Sendable, Equatable {
    public let id: UUID
    /// `sc_dev_live` or `sc_dev_test` — also the first segment of the secret.
    public let keyPrefix: String
    public let label: String
    public let scopes: Set<SDKAPIKeyScope>
    public var entitlements: Set<SDKEntitlement>
    public let createdAt: Date
    public var lastUsedAt: Date?
    public var revokedAt: Date?
    public var expiresAt: Date?

    public var isRevoked: Bool { revokedAt != nil }
    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }

    public init(
        id: UUID = UUID(),
        keyPrefix: String,
        label: String,
        scopes: Set<SDKAPIKeyScope>,
        entitlements: Set<SDKEntitlement> = [],
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil,
        revokedAt: Date? = nil,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.keyPrefix = keyPrefix
        self.label = label
        self.scopes = scopes
        self.entitlements = entitlements
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.revokedAt = revokedAt
        self.expiresAt = expiresAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, keyPrefix, label, scopes, entitlements, createdAt, lastUsedAt, revokedAt, expiresAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        keyPrefix = try container.decode(String.self, forKey: .keyPrefix)
        label = try container.decode(String.self, forKey: .label)
        scopes = try container.decode(Set<SDKAPIKeyScope>.self, forKey: .scopes)
        // Back-compat: key records written before entitlements existed
        // decode with an empty entitlement set.
        entitlements = try container.decodeIfPresent(Set<SDKEntitlement>.self, forKey: .entitlements) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        revokedAt = try container.decodeIfPresent(Date.self, forKey: .revokedAt)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
    }
}

// MARK: - SDKAPIKeyCodec

/// Encodes and verifies developer API key secrets.
///
/// Secret format: `<prefix>_<base64url(payloadJSON)>.<base64url(sig)>`,
/// where the payload is `{"id": "<uuid>", "prefix": "<prefix>", "iat": <unix>}`
/// and `sig` is HMAC-SHA256 over the payload's base64url bytes with the
/// host device key. Base64url is RFC 4648 §5 without padding. Signature
/// comparison is constant-time. Every verification failure maps to
/// `.apiKeyInvalid` and the secret is never included in an error.
public enum SDKAPIKeyCodec {
    public static let livePrefix = "sc_dev_live"
    public static let testPrefix = "sc_dev_test"
    public static let maxSecretLength = 4096

    /// Generates a new secret for `key` with `deviceKey`. The secret is
    /// returned once; the caller must not persist it.
    public static func generateSecret(for key: SDKAPIKey, deviceKey: Data) -> String {
        let payload: [String: Any] = [
            "id": key.id.uuidString,
            "prefix": key.keyPrefix,
            "iat": Int(Date().timeIntervalSince1970),
        ]
        let payloadData = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
        let payloadB64 = base64URLEncode(payloadData)
        let signature = hmacSHA256(key: deviceKey, message: Data(payloadB64.utf8))
        return "\(key.keyPrefix)_\(payloadB64).\(base64URLEncode(signature))"
    }

    /// Parses and verifies `secret` against `deviceKey`. Returns the key
    /// ID and prefix carried by the payload on success; throws
    /// `.apiKeyInvalid` for every failure mode (malformed, bad prefix,
    /// bad signature, oversize). The caller re-reads key metadata from
    /// the store — the payload is never trusted for lifecycle state.
    public static func parseAndVerify(secret: String, deviceKey: Data) throws -> (keyID: UUID, prefix: String) {
        guard secret.count <= maxSecretLength else {
            throw SDKError(code: .apiKeyInvalid, message: "The developer API key is invalid.")
        }
        let parts = secret.split(separator: "_", maxSplits: 1)
        guard parts.count == 2 else {
            throw SDKError(code: .apiKeyInvalid, message: "The developer API key is invalid.")
        }
        let prefix = String(parts[0])
        guard prefix == livePrefix || prefix == testPrefix else {
            throw SDKError(code: .apiKeyInvalid, message: "The developer API key is invalid.")
        }
        let rest = String(parts[1])
        let segments = rest.split(separator: ".")
        guard segments.count == 2,
              let payloadData = base64URLDecode(String(segments[0])),
              let presentedSignature = base64URLDecode(String(segments[1])) else {
            throw SDKError(code: .apiKeyInvalid, message: "The developer API key is invalid.")
        }
        // Constant-time comparison only — never compare signatures with `==`.
        let expectedSignature = hmacSHA256(key: deviceKey, message: Data(segments[0].utf8))
        guard constantTimeEqual(presentedSignature, expectedSignature) else {
            throw SDKError(code: .apiKeyInvalid, message: "The developer API key is invalid.")
        }
        guard let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let idString = payload["id"] as? String,
              let id = UUID(uuidString: idString),
              let payloadPrefix = payload["prefix"] as? String,
              payloadPrefix == prefix else {
            throw SDKError(code: .apiKeyInvalid, message: "The developer API key is invalid.")
        }
        return (id, prefix)
    }

    /// Extracts the key ID from a presented secret WITHOUT verifying it.
    /// UNTRUSTED — usable only as a rate-limit bucket key, never for
    /// authorization. Returns `nil` when the secret is unparseable.
    public static func extractPresentedKeyID(from secret: String) -> String? {
        let parts = secret.split(separator: "_", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        let segments = parts[1].split(separator: ".")
        guard segments.count == 2,
              let payloadData = base64URLDecode(String(segments[0])),
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any],
              let id = payload["id"] as? String else { return nil }
        return id
    }

    // MARK: - Helpers

    static func hmacSHA256(key: Data, message: Data) -> Data {
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: SymmetricKey(data: key))
        return Data(mac)
    }

    /// Constant-time byte comparison. Length mismatch is a failure, and
    /// the loop always runs over the full length — never `==`.
    static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var diff: UInt8 = 0
        for (a, b) in zip(lhs, rhs) { diff |= a ^ b }
        return diff == 0
    }

    static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    static func base64URLDecode(_ string: String) -> Data? {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}
