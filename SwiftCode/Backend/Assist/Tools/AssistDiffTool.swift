import Foundation

public struct AssistDiffTool: AssistTool {
    public let id = "project_diff"
    public let name = "Diff Project"
    public let description = "Compares the current project state with the latest snapshot."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        do {
            let snapshots = try AssistSnapshotFunctions.listSnapshots()
            guard let latest = snapshots.first else {
                return .success("No snapshots found to compare.")
            }

            let diffs = try AssistSnapshotFunctions.compare(project: context.workspaceRoot, withSnapshot: latest.id)
            let formattedDiff = diffs.map { "\($0.status.rawValue.uppercased()): \($0.path)" }.joined(separator: "\n")

            return .success("Diff completed with snapshot '\(latest.message)'.", data: ["diff": formattedDiff.isEmpty ? "No differences found." : formattedDiff])
        } catch {
            return .failure("Diff failed: \(error.localizedDescription)")
        }
    }
}
