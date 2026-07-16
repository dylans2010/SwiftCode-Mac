import Foundation

public struct AssistSnapshotProjectTool: AssistTool {
    public let id = "project_snapshot"
    public let name = "Snapshot Project"
    public let description = "Creates a full snapshot of the current project state."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let message = input["message"] as? String ?? "Manual Snapshot"
        do {
            let snapshotURL = try AssistSnapshotFunctions.createSnapshot(project: context.workspaceRoot, message: message)
            return .success("Successfully created project snapshot: \(message)", data: ["snapshot_id": snapshotURL.lastPathComponent])
        } catch {
            return .failure("Failed to create snapshot: \(error.localizedDescription)")
        }
    }
}
