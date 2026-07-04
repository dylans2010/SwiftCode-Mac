import Foundation

public struct TaskPlannerTool {
    public static let identifier = "task_planner"

    public func run(goal: String) async throws -> [String] {
        return ["Step 1 for \(goal)"]
    }
}
