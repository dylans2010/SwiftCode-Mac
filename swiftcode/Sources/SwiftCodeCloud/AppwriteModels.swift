import Foundation

/// One JSON value, for Appwrite user preferences (`prefs`), whose
/// values are arbitrary JSON. Legacy only ever stored strings there
/// (`swiftcode_id`), but the wire type is unrestricted, so decoding
/// keeps every value instead of dropping non-strings.
public enum AppwriteJSONValue: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case null
    case array([AppwriteJSONValue])
    case object([String: AppwriteJSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([AppwriteJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: AppwriteJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unsupported JSON value in Appwrite prefs")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        case .null: try container.encodeNil()
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// The value as a string, when it is one. Legacy reads
    /// `prefs["swiftcode_id"]` as a string; anything else is not a
    /// SwiftCode id.
    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}

/// An Appwrite account user, as returned by `GET /account` and
/// `POST /account`. Only the fields the IDE uses are modelled; the
/// server returns more (phone, labels, targets, `accessedAt`), which
/// decoding ignores.
///
/// Appwrite dates arrive as ISO 8601 strings with fractional seconds
/// (`2026-01-15T10:30:00.000+00:00`), which `JSONDecoder`'s
/// `.iso8601` strategy does not accept on every platform, so decoding
/// goes through `AppwriteDecoder`.
public struct AppwriteUser: Codable, Sendable, Equatable {
    public var id: String
    public var createdAt: Date
    public var updatedAt: Date
    public var name: String
    public var email: String
    public var emailVerification: Bool
    public var phoneVerification: Bool
    public var status: Bool
    /// Arbitrary per-user preferences. Legacy stores the stable
    /// SwiftCode id here under the key `swiftcode_id`.
    public var prefs: [String: AppwriteJSONValue]

    public init(
        id: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        name: String = "",
        email: String,
        emailVerification: Bool = false,
        phoneVerification: Bool = false,
        status: Bool = true,
        prefs: [String: AppwriteJSONValue] = [:]
    ) {
        self.id = id
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.name = name
        self.email = email
        self.emailVerification = emailVerification
        self.phoneVerification = phoneVerification
        self.status = status
        self.prefs = prefs
    }

    enum CodingKeys: String, CodingKey {
        case id = "$id"
        case createdAt = "$createdAt"
        case updatedAt = "$updatedAt"
        case name
        case email
        case emailVerification
        case phoneVerification
        case status
        case prefs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        email = try container.decode(String.self, forKey: .email)
        emailVerification = try container.decodeIfPresent(Bool.self, forKey: .emailVerification) ?? false
        phoneVerification = try container.decodeIfPresent(Bool.self, forKey: .phoneVerification) ?? false
        status = try container.decodeIfPresent(Bool.self, forKey: .status) ?? true
        prefs = try container.decodeIfPresent([String: AppwriteJSONValue].self, forKey: .prefs) ?? [:]
    }
}

/// An Appwrite session, as returned by
/// `POST /account/sessions/email`. The session *secret* is not in
/// this body — Appwrite delivers it as the `Set-Cookie` header
/// (`a_session_<project>`); the client captures that header and
/// persists the secret in the secret store.
public struct AppwriteSession: Codable, Sendable, Equatable {
    public var id: String
    public var userID: String
    public var expire: Date
    public var provider: String
    public var current: Bool

    public init(
        id: String,
        userID: String,
        expire: Date,
        provider: String = "email",
        current: Bool = true
    ) {
        self.id = id
        self.userID = userID
        self.expire = expire
        self.provider = provider
        self.current = current
    }

    enum CodingKeys: String, CodingKey {
        case id = "$id"
        case userID = "userId"
        case expire
        case provider
        case current
    }
}

/// One file in an Appwrite Storage bucket, as returned by
/// `GET /storage/buckets/{bucketId}/files`.
public struct AppwriteFile: Codable, Sendable, Equatable {
    public var id: String
    public var bucketID: String
    public var name: String
    public var mimeType: String
    public var sizeOriginal: Int

    public init(id: String, bucketID: String, name: String, mimeType: String = "", sizeOriginal: Int = 0) {
        self.id = id
        self.bucketID = bucketID
        self.name = name
        self.mimeType = mimeType
        self.sizeOriginal = sizeOriginal
    }

    enum CodingKeys: String, CodingKey {
        case id = "$id"
        case bucketID = "bucketId"
        case name
        case mimeType
        case sizeOriginal
    }
}

/// The JSON envelope Appwrite returns for a failed request:
/// `{"message": ..., "code": ..., "type": ..., "version": ...}`.
public struct AppwriteErrorBody: Codable, Sendable, Equatable {
    public var message: String
    public var code: Int?
    public var type: String?
}

/// A `JSONDecoder` that understands Appwrite's date strings, with and
/// without fractional seconds.
public enum AppwriteDecoder {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = date(from: text) { return date }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Invalid Appwrite date: \(text)")
        }
        return decoder
    }

    /// Parses an Appwrite ISO 8601 date, accepting fractional seconds
    /// (`2026-01-15T10:30:00.000+00:00`) and plain seconds
    /// (`2026-01-15T10:30:00Z`).
    public static func date(from text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: text)
    }
}
