import Foundation

public struct ProgressTrackerTool: AgentTool {
    public static let identifier = "progress_tracker"
    public let name = "progress_tracker"
    public let description = "Tracks the progress of a task."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "taskID": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["taskID"]
    ]

    public func run(taskID: String) async throws -> Double {
        return 0.75
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let taskID = arguments["taskID"] as? String else {
            throw AgentError.toolError("Missing taskID")
        }
        let progress = try await run(taskID: taskID)
        return "Progress for \(taskID): \(progress * 100)%"
    }
}
