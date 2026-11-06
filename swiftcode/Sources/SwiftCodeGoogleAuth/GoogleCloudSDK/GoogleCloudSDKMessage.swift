//
//  GoogleCloudSDKMessage.swift
//  SwiftCode
//
//  Message and attachment domain models for Antigravity sessions.
//
//  Ported from Legacy (Dylan's own code; direct port authorised
//  under MIT):
//    SwiftCode/Backend/Assist/Assist Frameworks/Google Cloud SDK/GoogleCloudSDKMessage.swift
//
//  Adaptations for the destination:
//  - Legacy's `GoogleCloudSDKResponse` stored `[String: JSONValue]`,
//    where `JSONValue` was Legacy's app-wide JSON type. The
//    destination has a `JSONValue` in SwiftCodeExtensions
//    (null/bool/int/double/string/array/object), but
//    SwiftCodeGoogleAuth does not depend on SwiftCodeExtensions, so
//    that type is not visible here — and redeclaring a bare
//    `JSONValue` in this target would collide for any module that
//    imports both. The response value type is therefore the local
//    `GoogleCloudSDKJSONValue` below, with the same case shape
//    (int and double kept distinct, as in SwiftCodeExtensions).
//    `GoogleCloudSDKTransport.toJSONValue` builds it from bridge
//    JSON. If SwiftCodeGoogleAuth ever gains a dependency on
//    SwiftCodeExtensions, this type should be deleted and the
//    response switched back to that module's `JSONValue`.

import Foundation

/// An arbitrary JSON value carried in a bridge RPC result.
///
/// Same case shape as SwiftCodeExtensions' `JSONValue` (which this
/// target cannot import): `int` and `double` are distinct cases so
/// a value decoded from JSON keeps its integer form when it has no
/// fraction.
public enum GoogleCloudSDKJSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([GoogleCloudSDKJSONValue])
    case object([String: GoogleCloudSDKJSONValue])

    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var intValue: Int? {
        switch self {
        case .int(let value): return value
        case .double(let value) where value.truncatingRemainder(dividingBy: 1) == 0: return Int(value)
        default: return nil
        }
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var arrayValue: [GoogleCloudSDKJSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: GoogleCloudSDKJSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([GoogleCloudSDKJSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: GoogleCloudSDKJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not a valid JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

public enum GoogleCloudSDKRole: String, Codable, Sendable {
    case user = "user"
    case assistant = "assistant"
    case system = "system"
}

public struct GoogleCloudSDKAttachment: Identifiable, Sendable, Codable {
    public var id: String { path }
    public let name: String
    public let path: String
    public let mimeType: String?
    public let content: String?

    public init(name: String, path: String, mimeType: String? = nil, content: String? = nil) {
        self.name = name
        self.path = path
        self.mimeType = mimeType
        self.content = content
    }

    public func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "name": name,
            "path": path,
        ]
        if let mimeType = mimeType { dict["mimeType"] = mimeType }
        if let content = content { dict["content"] = content }
        return dict
    }
}

public struct GoogleCloudSDKMessage: Identifiable, Sendable, Codable {
    public let id: UUID
    public let role: GoogleCloudSDKRole
    public let content: String
    public let attachments: [GoogleCloudSDKAttachment]
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        role: GoogleCloudSDKRole,
        content: String,
        attachments: [GoogleCloudSDKAttachment] = [],
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.attachments = attachments
        self.timestamp = timestamp
    }
}

public struct GoogleCloudSDKResponse: Sendable {
    public let data: [String: GoogleCloudSDKJSONValue]

    public init(_ data: [String: GoogleCloudSDKJSONValue] = [:]) {
        self.data = data
    }

    public subscript(key: String) -> GoogleCloudSDKJSONValue? {
        data[key]
    }

    public var status: String? {
        if case .string(let str) = data["status"] { return str }
        return nil
    }

    public var conversationId: String? {
        if case .string(let str) = data["conversationId"] { return str }
        return nil
    }

    public var sdkVersion: String? {
        if case .string(let str) = data["sdkVersion"] { return str }
        return nil
    }
}
