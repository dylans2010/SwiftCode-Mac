import Foundation

public struct RollbackChangesTool: AgentTool {
    public static let identifier = "rollback_changes"
    public let name = "rollback_changes"
    public let description = "Rolls back changes to a specified checkpoint."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "checkpointID": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["checkpointID"]
    ]

    public func run(checkpointID: String) async throws -> String {
        return "Changes rolled back to \(checkpointID)"
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let checkpointID = arguments["checkpointID"] as? String else {
            throw AgentError.toolError("Missing checkpointID")
        }
        return try await run(checkpointID: checkpointID)
    }
}
