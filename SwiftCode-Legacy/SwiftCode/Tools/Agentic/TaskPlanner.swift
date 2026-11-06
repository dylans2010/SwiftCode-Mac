import Foundation

public struct TaskPlannerTool: AgentTool {
    public static let identifier = "task_planner"
    public let name = "task_planner"
    public let description = "Plans tasks to achieve a goal."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "goal": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["goal"]
    ]

    public func run(goal: String) async throws -> [String] {
        return ["Step 1 for \(goal)"]
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let goal = arguments["goal"] as? String else {
            throw AgentError.toolError("Missing goal")
        }
        let plan = try await run(goal: goal)
        return plan.joined(separator: "\n")
    }
}
