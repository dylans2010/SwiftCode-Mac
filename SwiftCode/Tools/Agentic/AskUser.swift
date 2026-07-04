import Foundation

public struct AskUserTool: AgentTool {
    public static let identifier = "ask_user"
    public let name = "ask_user"
    public let description = "Asks the user a clarifying question."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "question": ["type": "string"],
            "input_type": ["type": "string", "enum": ["text", "selection"]],
            "options": ["type": "array", "items": ["type": "string"]]
        ],
        "required": ["question", "input_type"]
    ]

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        return "Awaiting user response..."
    }
}
