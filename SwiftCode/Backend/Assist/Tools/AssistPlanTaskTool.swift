import Foundation

public struct AssistPlanTaskTool: AssistTool {
    public let id = "intel_plan_task"
    public let name = "Plan Task"
    public let description = "Generates a high-level execution plan for a complex task."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let task = input["task"] as? String else {
            return .failure("Missing required parameter: task")
        }

        let planId = UUID().uuidString
        let verbs = task
            .components(separatedBy: CharacterSet(charactersIn: ",.;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let steps: [String]
        if verbs.isEmpty {
            steps = ["Analyze requirements", "Implement changes", "Validate with tests", "Summarize outputs"]
        } else {
            steps = verbs.enumerated().map { "\($0.offset + 1). \($0.element)" }
        }

        context.memory.store(key: "plan:\(planId)", value: steps.joined(separator: "\n"))
        return .success("Plan generated for task: \(task)", data: ["planId": planId, "steps": steps.joined(separator: "\n")])
    }
}
