import Foundation

public struct AskUserTool: AgentTool {
    public static let identifier = "ask_user"
    public let name = "ask_user"
    public let description = "Asks the user a clarifying question."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "question": ["type": "string"] as [String: any Sendable],
            "input_type": ["type": "string", "enum": ["text", "selection"]] as [String: any Sendable],
            "options": ["type": "array", "items": ["type": "string"] as [String: any Sendable]] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["question", "input_type"]
    ]

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        return "Awaiting user response..."
    }
}
