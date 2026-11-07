import Foundation

public enum AgentError: Error, Codable, Sendable {
    case modelError(String)
    case toolError(String)
    case contextError(String)
    case unknown(String)

    public var localizedDescription: String {
        switch self {
        case .modelError(let msg): return "Model error: \(msg)"
        case .toolError(let msg): return "Tool error: \(msg)"
        case .contextError(let msg): return "Context error: \(msg)"
        case .unknown(let msg): return "Unknown error: \(msg)"
        }
    }
}

public struct AgentToolCall: Codable, Sendable {
    public let id: String
    public let name: String
    public let arguments: String

    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }
}

public struct AgentToolResult: Codable, Sendable {
    public let toolCallId: String
    public let content: String
    public let isError: Bool

    public init(toolCallId: String, content: String, isError: Bool = false) {
        self.toolCallId = toolCallId
        self.content = content
        self.isError = isError
    }
}
