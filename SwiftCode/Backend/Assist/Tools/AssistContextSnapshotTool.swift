import Foundation

public struct AssistContextSnapshotTool: AssistTool {
    public let id = "mem_context_snapshot"
    public let name = "Context Snapshot"
    public let description = "Captures a snapshot of the current environment and open files for future reference."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        do {
            let snapshots = try AssistSnapshotFunctions.listSnapshots()
            let latestSnapshot = snapshots.first?.id ?? "none"
            let memoryMarker = UUID().uuidString
            let payload = "session=\(context.sessionId.uuidString)\nworkspace=\(context.workspaceRoot.path)\nlatest_snapshot=\(latestSnapshot)"
            context.memory.store(key: "context_snapshot:\(memoryMarker)", value: payload)
            return .success("Context snapshot captured", data: ["snapshot_key": "context_snapshot:\(memoryMarker)", "latest_snapshot": latestSnapshot])
        } catch {
            return .failure("Failed capturing context snapshot: \(error.localizedDescription)")
        }
    }
}
