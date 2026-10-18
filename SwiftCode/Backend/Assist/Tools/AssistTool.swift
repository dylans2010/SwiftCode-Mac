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

public indirect enum JSONSchemaItems: Codable, Sendable, Hashable {
    case single(JSONSchema)
    case dictionary([String: JSONSchema])

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .single(let schema):
            try container.encode(schema)
        case .dictionary(let dict):
            if dict.count == 1, let schema = dict["type"] {
                try container.encode(schema)
            } else {
                try container.encode(dict)
            }
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let schema = try? container.decode(JSONSchema.self) {
            self = .single(schema)
        } else if let dict = try? container.decode([String: JSONSchema].self) {
            if dict.count == 1, let schema = dict["type"] {
                self = .single(schema)
            } else {
                self = .dictionary(dict)
            }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid JSONSchema items")
        }
    }
}

public struct JSONSchema: Codable, Sendable, Hashable {
    public let type: String
    public let description: String?
    public let properties: [String: JSONSchema]?
    public let required: [String]?
    public let items: JSONSchemaItems?

    public init(
        type: String,
        description: String? = nil,
        properties: [String: JSONSchema]? = nil,
        required: [String]? = nil,
        items: JSONSchema? = nil
    ) {
        self.type = type
        self.description = description
        self.properties = properties
        self.required = required
        self.items = items.map { .single($0) }
    }

    public init(
        type: String,
        description: String? = nil,
        properties: [String: JSONSchema]? = nil,
        required: [String]? = nil,
        items: [String: JSONSchema]?
    ) {
        self.type = type
        self.description = description
        self.properties = properties
        self.required = required
        if let items = items {
            if items.count == 1, let schema = items["type"] {
                self.items = .single(schema)
            } else {
                self.items = .dictionary(items)
            }
        } else {
            self.items = nil
        }
    }
}

@MainActor
public protocol AssistTool: Sendable {
    var id: String { get }
    var name: String { get }
    var description: String { get }
    var parametersSchema: JSONSchema { get }
    var capability: ToolCapability { get }
    var riskLevel: ToolRiskLevel { get }
    var isReadOnly: Bool { get }
    var isMutating: Bool { get }
    var prerequisites: [String] { get }
    var estimatedCost: Double { get }

    // Unified capability extensions:
    var outputFormat: ToolOutputFormat { get }
    var requiredPermission: ToolPermissionRequirement { get }
    var supportedOperations: [String] { get }
    var knownLimitations: [String] { get }
    var canChainResult: Bool { get }
    var isDestructive: Bool { get }
    var resourceScope: String { get }

    func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult
}

public extension AssistTool {
    var parametersSchema: JSONSchema {
        JSONSchema(type: "object", description: description, properties: [:], required: [])
    }

    var capability: ToolCapability {
        .general
    }

    var riskLevel: ToolRiskLevel {
        .safeRead
    }

    var isReadOnly: Bool {
        riskLevel == .safeRead
    }

    var isMutating: Bool {
        riskLevel == .safeMutation || riskLevel == .potentiallyDestructive
    }

    var isDestructive: Bool {
        riskLevel == .potentiallyDestructive
    }

    var prerequisites: [String] {
        []
    }

    var estimatedCost: Double {
        0.01
    }

    var outputFormat: ToolOutputFormat {
        if id == "take_screenshot" { return .image }
        if id == "take_screenrecord" { return .video }
        if isMutating { return .file }
        return .text
    }

    var requiredPermission: ToolPermissionRequirement {
        if id == "take_screenshot" || id == "take_screenrecord" { return .screenRecording }
        if id == "use_app" { return .accessibility }
        if id == "use_terminal" { return .terminalExecution }
        if isMutating { return .fileSystem }
        return .none
    }

    var supportedOperations: [String] {
        if id == "use_app" {
            return ["launch", "activate", "list_applications", "inspect_application", "list_windows", "select_window", "close_application", "inspect_ui", "get_accessibility_tree", "get_focused_element", "take_screenshot", "inspect_window", "click", "double_click", "right_click", "move_pointer", "drag", "scroll", "type_text", "press_key", "press_shortcut", "select_all", "copy", "paste", "activate_element", "set_element_value", "select_menu", "wait_for_element", "wait_for_window", "verify"]
        }
        if id == "take_screenshot" {
            return ["fullscreen", "region"]
        }
        if id == "take_screenrecord" {
            return ["window", "application_display"]
        }
        return []
    }

    var knownLimitations: [String] {
        if id == "take_screenrecord" {
            return ["Audio capture is not supported; captures video stream of target application only.", "Maximum duration is 60 seconds."]
        }
        if id == "take_screenshot" {
            return ["Requires Screen Recording authorization in macOS System Settings."]
        }
        if id == "use_app" {
            return ["Requires Accessibility authorization in macOS System Settings.", "Target app must expose standard macOS Accessibility elements."]
        }
        return []
    }

    var canChainResult: Bool {
        return true
    }

    var resourceScope: String {
        if id == "take_screenshot" || id == "take_screenrecord" || id == "use_app" {
            return "macOS Desktop & Window System"
        }
        return "Workspace Project"
    }
}

