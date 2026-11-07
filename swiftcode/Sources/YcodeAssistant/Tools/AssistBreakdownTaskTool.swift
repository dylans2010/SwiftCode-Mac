import Foundation

public struct AssistBreakdownTaskTool: AssistTool {
    public let id = "intel_breakdown_task"
    public let name = "Breakdown Task"
    public let description = "Breaks down a plan into granular, actionable steps."

    public init() {}

    public var capability: ToolCapability { .planning }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Breaks a stored plan into granular actionable steps.",
            properties: [
                "planId": JSONSchema(type: "string", description: "Plan identifier previously returned by intel_plan_task.")
            ],
            required: ["planId"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let planId = input["planId"] as? String else {
            return .failure("Missing required parameter: planId")
        }

        guard let plan = context.memory.retrieve(key: "plan:\(planId)") else {
            return .failure("No stored plan found for planId: \(planId)")
        }

        let granular = plan
            .components(separatedBy: .newlines)
            .flatMap { line -> [String] in
                ["\(line)", "- Define acceptance criteria for: \(line)", "- Implement and self-review: \(line)"]
            }
            .joined(separator: "\n")

        context.memory.store(key: "plan_breakdown:\(planId)", value: granular)
        return .success("Task breakdown completed for plan \(planId)", data: ["breakdown": granular])
    }
}
