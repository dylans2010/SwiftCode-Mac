import Foundation

public final class AssistPlanner {
    private let context: AssistContext

    public init(context: AssistContext) {
        self.context = context
    }

    public func plan(for intent: String) async throws -> AssistExecutionPlan {
        return try await TasksAIPlanner.shared.generatePlan(intent: intent, context: context)
    }

    private func parsePlan(from response: String) async throws -> AssistExecutionPlan {
        let pattern = "\\{(?:[^{}]|\\{(?:[^{}]|\\{[^{}]*\\})*\\})*\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
              let match = regex.firstMatch(in: response, options: [], range: NSRange(response.startIndex..., in: response)),
              let range = Range(match.range, in: response) else {
            await context.logger.error("No JSON found in planner response.")
            throw AssistPlannerError.invalidResponse
        }

        let jsonStr = String(response[range])
        guard let data = jsonStr.data(using: .utf8) else {
            throw AssistPlannerError.invalidResponse
        }

        struct RawPlan: Decodable {
            let goal: String?
            let steps: [RawStep]?
        }
        struct RawStep: Decodable {
            let toolId: String?
            let input: [String: String]?
            let description: String?
        }

        let raw = try JSONDecoder().decode(RawPlan.self, from: data)
        var plan = AssistExecutionPlan(goal: raw.goal ?? "Untitled Task")
        plan.steps = (raw.steps ?? []).compactMap { step in
            guard let toolId = step.toolId else { return nil }
            return AssistExecutionStep(
                toolId: toolId,
                input: step.input ?? [:],
                description: step.description ?? "Executing \(toolId)"
            )
        }

        if plan.steps.isEmpty {
            await context.logger.warning("Planner returned 0 steps for intent.")
        }

        return plan
    }
}

enum AssistPlannerError: Error {
    case invalidResponse
}
