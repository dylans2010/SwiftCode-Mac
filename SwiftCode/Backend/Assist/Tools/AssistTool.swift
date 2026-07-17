import Foundation

public enum JSONValue: Codable, Sendable, Hashable {
    case null
    case string(String)
    case number(Double)
    case boolean(Bool)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let str = try? container.decode(String.self) {
            self = .string(str)
        } else if let num = try? container.decode(Double.self) {
            self = .number(num)
        } else if let bool = try? container.decode(Bool.self) {
            self = .boolean(bool)
        } else if let arr = try? container.decode([JSONValue].self) {
            self = .array(arr)
        } else if let obj = try? container.decode([String: JSONValue].self) {
            self = .object(obj)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid JSONValue")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .string(let str):
            try container.encode(str)
        case .number(let num):
            try container.encode(num)
        case .boolean(let bool):
            try container.encode(bool)
        case .array(let arr):
            try container.encode(arr)
        case .object(let obj):
            try container.encode(obj)
        }
    }
}

public struct JSONSchema: Codable, Sendable, Hashable {
    public let type: String
    public let description: String?
    public let properties: [String: JSONSchema]?
    public let required: [String]?
    public let items: [String: JSONSchema]?

    public init(
        type: String,
        description: String? = nil,
        properties: [String: JSONSchema]? = nil,
        required: [String]? = nil,
        items: [String: JSONSchema]? = nil
    ) {
        self.type = type
        self.description = description
        self.properties = properties
        self.required = required
        self.items = items
    }
}

@MainActor
public protocol AssistTool: Sendable {
    var id: String { get }
    var name: String { get }
    var description: String { get }
    var parametersSchema: JSONSchema { get }

    func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult
}

public extension AssistTool {
    var parametersSchema: JSONSchema {
        JSONSchema(type: "object", description: description, properties: [:], required: [])
    }
}
