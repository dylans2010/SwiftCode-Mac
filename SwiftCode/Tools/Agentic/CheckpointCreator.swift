import Foundation

public struct CheckpointCreatorTool: AgentTool {
    public static let identifier = "checkpoint_creator"
    public let name = "checkpoint_creator"
    public let description = "Creates a checkpoint of the current state."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "description": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["description"]
    ]

    public func run(description: String) async throws -> String {
        return "Checkpoint '\(description)' created"
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let description = arguments["description"] as? String else {
            throw AgentError.toolError("Missing description")
        }
        return try await run(description: description)
    }
}
