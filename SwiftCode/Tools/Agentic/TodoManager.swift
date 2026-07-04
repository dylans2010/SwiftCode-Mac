import Foundation

public struct TodoManagerTool: AgentTool {
    public static let identifier = "todo_manager"
    public let name = "todo_manager"
    public let description = "Manages a todo list."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "action": ["type": "string"] as [String: any Sendable],
            "todo": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["action"]
    ]

    public func run(action: String, todo: String?) async throws -> [String] {
        return ["Todo list updated"]
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let action = arguments["action"] as? String else {
            throw AgentError.toolError("Missing action")
        }
        let todo = arguments["todo"] as? String
        let result = try await run(action: action, todo: todo)
        return result.joined(separator: "\n")
    }
}
