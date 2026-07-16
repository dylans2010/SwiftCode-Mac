import Foundation

public struct AssistChangeLogTool: AssistTool {
    public let id = "project_changelog"
    public let name = "View Changelog"
    public let description = "Displays the history of project snapshots and changes."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        do {
            let snapshots = try AssistSnapshotFunctions.listSnapshots()
            let log = snapshots.map { "[\($0.timestamp)] \($0.message) (ID: \($0.id))" }.joined(separator: "\n")
            return .success("Changelog retrieved successfully.", data: ["log": log.isEmpty ? "No snapshot history found." : log])
        } catch {
            return .failure("Failed to retrieve changelog: \(error.localizedDescription)")
        }
    }
}
