import Foundation

public struct QuestionHandlerTool: AgentTool {
    public static let identifier = "questions_handle"
    public let name = "questions_handle"
    public let description = "Asks multiple clarifying questions before starting work."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "questions": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "id": ["type": "string"],
                        "prompt": ["type": "string"],
                        "input_type": ["type": "string", "enum": ["text", "selection"]],
                        "options": ["type": "array", "items": ["type": "string"]]
                    ],
                    "required": ["id", "prompt", "input_type"]
                ]
            ]
        ],
        "required": ["questions"]
    ]

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        return "Awaiting user response to question set..."
    }
}
