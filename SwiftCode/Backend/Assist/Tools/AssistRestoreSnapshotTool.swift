import Foundation

public struct AssistRestoreSnapshotTool: AssistTool {
    public let id = "project_restore"
    public let name = "Restore Snapshot"
    public let description = "Restores the project to a previously saved state."

    public init() {}

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Restores project to a previously saved snapshot.",
            properties: [
                "snapshot_id": JSONSchema(type: "string", description: "The unique identifier of the snapshot to restore.")
            ],
            required: ["snapshot_id"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let snapshotId = input["snapshot_id"] as? String else {
            return .failure("Missing required parameter: snapshot_id")
        }

        do {
            try AssistSnapshotFunctions.restoreSnapshot(id: snapshotId, to: context.workspaceRoot)
            return .success("Successfully restored project to snapshot: \(snapshotId)")
        } catch {
            return .failure("Failed to restore snapshot: \(error.localizedDescription)")
        }
    }
}
