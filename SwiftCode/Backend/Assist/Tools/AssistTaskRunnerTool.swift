import Foundation

public struct AssistTaskRunnerTool: AssistTool {
    public let id = "task_runner"
    public let name = "Run Task"
    public let description = "Executes a registered internal Swift task within the sandbox."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let taskId = input["task_id"] as? String else {
            return .failure("Missing required parameter: task_id")
        }

        do {
            let output = try await AssistExecutionFunctions.executeTask(id: taskId, context: context)
            return .success("Task '\(taskId)' executed successfully.", data: ["output": output])
        } catch {
            return .failure("Task '\(taskId)' failed: \(error.localizedDescription)")
        }
    }
}
