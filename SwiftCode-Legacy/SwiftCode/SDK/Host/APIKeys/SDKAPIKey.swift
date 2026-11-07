import CryptoKit
import Foundation

public struct SDKAPIKeyScope: Sendable, Hashable, RawRepresentable, Codable {
    public let rawValue: String

    public init?(rawValue: String) {
        guard !rawValue.isEmpty else { return nil }
        self.rawValue = rawValue
    }

    private init(unchecked rawValue: String) {
        self.rawValue = rawValue
    }

    public static let appsCreate = SDKAPIKeyScope(unchecked: "apps:create")
    public static let appsPublish = SDKAPIKeyScope(unchecked: "apps:publish")
    public static let capabilitiesRequest = SDKAPIKeyScope(unchecked: "capabilities:request")

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

public struct SDKAPIKey: Sendable, Codable {
    public let id: UUID
    public let keyPrefix: String
    public let label: String
    public let scopes: Set<SDKAPIKeyScope>
    public var entitlements: Set<SDKEntitlement>
    public let createdAt: Date
    public var lastUsedAt: Date?
    public var revokedAt: Date?
    public let expiresAt: Date?

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

    public var isRevoked: Bool { revokedAt != nil }

    public var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }
}

public enum SDKAPIKeyCodec {

    public static let livePrefix = "sc_dev_live"
    public static let testPrefix = "sc_dev_test"

    private static let maxSecretLength = 4096

    private struct Payload: Codable {
        let id: UUID
        let prefix: String
        let iat: Int
    }

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
        guard payload.prefix == prefix else { throw invalidSecretError() }

        return (payload.id, prefix)
    }

    public static func extractPresentedKeyID(from secret: String) -> UUID? {
        guard secret.count <= maxSecretLength else { return nil }

        let rest: Substring
        if secret.hasPrefix(livePrefix + "_") {
            rest = secret.dropFirst(livePrefix.count + 1)
        } else if secret.hasPrefix(testPrefix + "_") {
            rest = secret.dropFirst(testPrefix.count + 1)
        } else {
            return nil
        }

        let parts = rest.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return nil }
        guard let payloadJSON = base64URLDecode(String(parts[0])) else { return nil }

        struct IDOnly: Decodable { let id: UUID }
        return try? JSONDecoder().decode(IDOnly.self, from: payloadJSON).id
    }

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

    private static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var diff: UInt8 = 0
        for (x, y) in zip(a, b) {
            diff |= x ^ y
        }
        return diff == 0
    }
}

extension SDKAPIKey {
    private enum CodingKeys: String, CodingKey {
        case id
        case keyPrefix
        case label
        case scopes
        case entitlements
        case createdAt
        case lastUsedAt
        case revokedAt
        case expiresAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        keyPrefix = try container.decode(String.self, forKey: .keyPrefix)
        label = try container.decode(String.self, forKey: .label)
        scopes = try container.decode(Set<SDKAPIKeyScope>.self, forKey: .scopes)
        entitlements = try container.decodeIfPresent(Set<SDKEntitlement>.self, forKey: .entitlements) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        lastUsedAt = try container.decodeIfPresent(Date.self, forKey: .lastUsedAt)
        revokedAt = try container.decodeIfPresent(Date.self, forKey: .revokedAt)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(keyPrefix, forKey: .keyPrefix)
        try container.encode(label, forKey: .label)
        try container.encode(scopes, forKey: .scopes)
        try container.encode(entitlements, forKey: .entitlements)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(lastUsedAt, forKey: .lastUsedAt)
        try container.encodeIfPresent(revokedAt, forKey: .revokedAt)
        try container.encodeIfPresent(expiresAt, forKey: .expiresAt)
    }
}
