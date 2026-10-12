import CryptoKit
import Foundation

// MARK: - SDKAPIKeyScope
//
// A scope entitlement carried by a developer API key (spec §8.2.1, ADR §11).
// The three v1 scopes are fixed; the type is intentionally open —
// `init?(rawValue:)` accepts any non-empty string so that future scopes
// (ADR minor-bump additions) decode from stored metadata without breaking
// older hosts. Encoding is the bare scope string, e.g. `"apps:create"`.

public struct SDKAPIKeyScope: Sendable, Hashable, RawRepresentable, Codable {
    public let rawValue: String

    /// Accepts any non-empty scope string. Empty strings are never valid.
    public init?(rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.rawValue = rawValue
    }

    /// Internal non-failable initializer for the known v1 constants.
    private init(unchecked rawValue: String) {
        self.rawValue = rawValue
    }

    /// Required to create/publish apps targeting the SwiftCode platform.
    public static let appsCreate = SDKAPIKeyScope(unchecked: "apps:create")
    /// Required to publish/release apps targeting the SwiftCode platform.
    public static let appsPublish = SDKAPIKeyScope(unchecked: "apps:publish")
    /// Required to request privileged capabilities (network, custom builds,
    /// credential usage, platform publishing).
    public static let capabilitiesRequest = SDKAPIKeyScope(unchecked: "capabilities:request")

    // MARK: Codable (single-value: the bare scope string)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let scope = SDKAPIKeyScope(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Developer API key scope must be a non-empty string."
            )
        }
        self = scope
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - SDKAPIKey
//
// Stored metadata for one developer API key. This is metadata ONLY — the
// secret itself is never persisted. Secrets are verified by HMAC-SHA256
// against the device key (`SDKAPIKeyStore`), so there is no secret hash in
// storage to steal. `revokedAt != nil` means revoked; verification checks it
// on every call, so revocation takes effect immediately (spec §8.2.1,
// ADR §11).

public struct SDKAPIKey: Sendable, Codable {
    public let id: UUID
    /// `"sc_dev_live"` or `"sc_dev_test"` — also the secret's literal prefix.
    public let keyPrefix: String
    /// Human-readable label from Studio → Settings → Developer API Keys.
    public let label: String
    public let scopes: Set<SDKAPIKeyScope>
    public let createdAt: Date
    public var lastUsedAt: Date?
    public var revokedAt: Date?

    public init(
        id: UUID = UUID(),
        keyPrefix: String,
        label: String,
        scopes: Set<SDKAPIKeyScope>,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil,
        revokedAt: Date? = nil
    ) {
        self.id = id
        self.keyPrefix = keyPrefix
        self.label = label
        self.scopes = scopes
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.revokedAt = revokedAt
    }

    /// True when the key has been revoked. Convenience only — the
    /// authorization boundary must go through `SDKAPIKeyStore.verify(secret:)`,
    /// which enforces this on every call.
    public var isRevoked: Bool { revokedAt != nil }
}

// MARK: - SDKAPIKeyCodec
//
// Signed secret format: `<prefix>_<base64url(payloadJSON)>.<base64url(signature)>`
// where `payloadJSON = {"id": uuid, "prefix": prefix, "iat": unixTime}`
// (canonical JSON, sorted keys) and
// `signature = HMAC-SHA256(payloadB64_UTF8, deviceKey)`.
///
/// base64url = RFC 4648 §5 (no padding).
///
/// SECURITY CONTRACT:
/// - The secret is generated once and returned once; it is never logged,
///   never persisted, and never appears in any `SDKError` message or
///   diagnostics. Treat every `String` carrying a secret as toxic: do not
///   print it, do not interpolate it into errors, do not write it to disk.
/// - Verification uses a constant-time signature comparison. Malformed
///   secrets, bad signatures, and unknown key IDs all map to the same
///   `.apiKeyInvalid` error so callers cannot distinguish the failure mode.

public enum SDKAPIKeyCodec {

    // MARK: - Constants

    /// Live-key prefix: `sc_dev_live_…`
    public static let livePrefix = "sc_dev_live"
    /// Test-key prefix: `sc_dev_test_…`
    public static let testPrefix = "sc_dev_test"

    /// Rejects absurdly long inputs before any parsing (DoS bound).
    private static let maxSecretLength = 4096

    /// The signed payload. `iat` is informational (key age / debugging);
    /// API keys do not expire — revocation is the lifecycle control
    /// (spec §8.2.1: "revocation must be immediate at the authorization
    /// boundary").
    private struct Payload: Codable {
        let id: UUID
        let prefix: String
        let iat: Int
    }

    // MARK: - Generation

    /// Builds a signed secret for `key` using `deviceKey`.
    /// The secret is returned to the caller ONCE — see `SDKAPIKeyStore.createKey`.
    public static func generateSecret(for key: SDKAPIKey, deviceKey: SymmetricKey) throws -> String {
        guard key.keyPrefix == livePrefix || key.keyPrefix == testPrefix else {
            throw SDKError(
                code: .invalidArgument,
                message: "Cannot generate a developer API key secret: unknown key prefix.",
                suggestion: "Use \"\(livePrefix)\" or \"\(testPrefix)\"."
            )
        }
        let payload = Payload(
            id: key.id,
            prefix: key.keyPrefix,
            iat: Int(Date().timeIntervalSince1970)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let payloadJSON: Data
        do {
            payloadJSON = try encoder.encode(payload)
        } catch {
            throw SDKError(
                code: .serviceUnavailable,
                message: "Could not generate the developer API key secret.",
                diagnostics: ["reason": "payload-encode-failed"]
            )
        }
        let payloadB64 = base64URLEncode(payloadJSON)
        let mac = HMAC<SHA256>.authenticationCode(for: Data(payloadB64.utf8), using: deviceKey)
        let signatureB64 = base64URLEncode(Data(mac))
        return "\(key.keyPrefix)_\(payloadB64).\(signatureB64)"
    }

    // MARK: - Verification

    /// Parses `secret`, verifies its HMAC against `deviceKey`, and returns
    /// the key ID and prefix bound into the signature. Any malformed input,
    /// signature mismatch, or payload inconsistency → `.apiKeyInvalid`.
    /// Never includes the secret (or any part of it) in the thrown error.
    public static func parseAndVerify(_ secret: String, deviceKey: SymmetricKey) throws -> (id: UUID, prefix: String) {
        guard secret.count <= maxSecretLength else { throw invalidSecretError() }

        let prefix: String
        let rest: Substring
        if secret.hasPrefix(livePrefix + "_") {
            prefix = livePrefix
            rest = secret.dropFirst(livePrefix.count + 1)
        } else if secret.hasPrefix(testPrefix + "_") {
            prefix = testPrefix
            rest = secret.dropFirst(testPrefix.count + 1)
        } else {
            throw invalidSecretError()
        }

        let parts = rest.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2 else { throw invalidSecretError() }
        let payloadB64 = String(parts[0])
        let signatureB64 = String(parts[1])
        guard !payloadB64.isEmpty, !signatureB64.isEmpty else { throw invalidSecretError() }

        guard
            let payloadJSON = base64URLDecode(payloadB64),
            let signatureBytes = base64URLDecode(signatureB64),
            signatureBytes.count == SHA256.byteCount
        else {
            throw invalidSecretError()
        }

        let expectedMAC = HMAC<SHA256>.authenticationCode(for: Data(payloadB64.utf8), using: deviceKey)
        guard constantTimeEqual(Data(expectedMAC), signatureBytes) else {
            throw invalidSecretError()
        }

        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: payloadJSON)
        } catch {
            throw invalidSecretError()
        }
        // The signature binds the payload prefix; it must match the secret's
        // outer prefix or the secret was spliced together from two keys.
        guard payload.prefix == prefix else { throw invalidSecretError() }

        return (payload.id, prefix)
    }

    // MARK: - Private helpers

    private static func invalidSecretError() -> SDKError {
        SDKError(
            code: .apiKeyInvalid,
            message: "The developer API key is invalid or could not be verified.",
            suggestion: "Check the key for typos, or generate a new key in Studio → Settings → Developer API Keys."
        )
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64URLDecode(_ string: String) -> Data? {
        var s = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = s.count % 4
        if remainder != 0 {
            s += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: s)
    }

    /// Constant-time byte comparison. Lengths are checked first (a length
    /// mismatch rejects immediately); equal-length inputs are compared
    /// without early exit.
    private static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for (x, y) in zip(a, b) {
            diff |= x ^ y
        }
        return diff == 0
    }
}
