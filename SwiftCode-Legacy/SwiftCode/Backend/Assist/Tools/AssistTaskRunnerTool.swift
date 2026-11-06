import Foundation

public struct AssistTaskRunnerTool: AssistTool {
    public let id = "task_runner"
    public let name = "Run Task"
    public let description = "Executes a registered internal Swift task within the sandbox."

    public init() {}

    public var capability: ToolCapability { .systemExecution }
    public var riskLevel: ToolRiskLevel { .execution }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Executes a registered internal Swift task within the sandbox.",
            properties: [
                "task_id": JSONSchema(type: "string", description: "Identifier of the registered task to execute.")
            ],
            required: ["task_id"]
        )
    }

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
