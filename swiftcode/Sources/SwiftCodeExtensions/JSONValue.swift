import Foundation

/// An arbitrary JSON value, used for RPC params/results, manifest
/// configuration defaults, and extension command arguments.
///
/// `int` and `double` are distinct cases: a value decoded from JSON
/// keeps its integer form when it has no fraction, so `1` round-trips
/// as `.int(1)` rather than `.double(1)`.
public enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

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

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public static func stringDictionary(_ dict: [String: String]) -> JSONValue {
        .object(Dictionary(uniqueKeysWithValues: dict.map { ($0.key, .string($0.value)) }))
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
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
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

/// The single error type that escapes this target (spec §10).
public enum SwiftCodeExtensionError: Error, LocalizedError, Sendable {
    case notInstalled(String)
    case disabled(String)
    case incompatible(String)
    case missingDependencies([String])
    case permissionDenied(ExtensionCapability)
    case registry(String)
    case network(String)
    case package(String)
    case manifest(String)
    case host(String)
    case timeout(String)
    case invalidRequest(String)
    case cancelled
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled(let id): return "Extension '\(id)' is not installed."
        case .disabled(let id): return "Extension '\(id)' is disabled."
        case .incompatible(let reason): return reason
        case .missingDependencies(let ids): return "Missing dependencies: \(ids.joined(separator: ", "))."
        case .permissionDenied(let capability):
            return "Permission denied: \(capability.displayName). Grant it in Extensions > Permissions."
        case .registry(let message): return message
        case .network(let message): return message
        case .package(let message): return message
        case .manifest(let message): return message
        case .host(let message): return message
        case .timeout(let message): return message
        case .invalidRequest(let message): return message
        case .cancelled: return "Operation cancelled."
        case .unknown(let message): return message
        }
    }
}
