import Foundation

public struct AssistUndoTool: AssistTool {
    public let id = "safe_undo"
    public let name = "Undo Last Action"
    public let description = "Reverts the last modification made by the agent."

    public init() {}

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Reverts the last modification made by Assist.",
            properties: [
                "steps": JSONSchema(type: "integer", description: "Number of actions to undo (defaults to 1).")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        do {
            let snapshots = try AssistSnapshotFunctions.listSnapshots()
            guard snapshots.count >= 2 else {
                return .failure("At least two snapshots are required to undo (current baseline + previous state).")
            }
            let previous = snapshots[1]
            try AssistSnapshotFunctions.restoreSnapshot(id: previous.id, to: context.workspaceRoot)
            return .success("Last action undone by restoring snapshot \(previous.id)", data: ["restored_snapshot": previous.id])
        } catch {
            return .failure("Undo failed: \(error.localizedDescription)")
        }
    }
}
