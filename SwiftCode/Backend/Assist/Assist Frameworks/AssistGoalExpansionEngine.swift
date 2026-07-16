import Foundation

/// Automatically generates follow-up goals and expands task scope beyond the original request.
/// Enables true autonomous operation by continuously generating new work.
public final class AssistGoalExpansionEngine {
    private let context: AssistContext

    public init(context: AssistContext) {
        self.context = context
    }

    /// Generates expanded goals based on the completed task
    public func expandGoals(originalGoal: String, completedPlan: AssistExecutionPlan) async -> [String] {
        await context.logger.info("Expanding goals from completed task: \(originalGoal)", toolId: "GoalExpansion")

        let providerRawValue = UserDefaults.standard.string(forKey: "assist.selectedProvider") ?? AssistModelProvider.openAI.rawValue
        let provider = AssistModelProvider(rawValue: providerRawValue) ?? .openAI
        let apiKey = APIKeyManager.shared.retrieveKey(service: provider.apiKeyProvider)

        let prompt = """
        \(AssistAgenticPrompt.systemPrompt)

        # GOAL EXPANSION TASK
        Original goal: "\(originalGoal)"

        The task has been completed. Generate 3-5 logical follow-up tasks that would improve or extend this work.

        Examples of expansion:
        - If a view was created, add authentication, validation, or persistence
        - If a service was created, add error handling, logging, or tests
        - If a feature was implemented, add UI improvements, optimization, or documentation

        Return JSON array ONLY:
        ["follow-up task 1", "follow-up task 2", "follow-up task 3"]
        """

        let response = await AssistLLMService.generateResponse(prompt: prompt, provider: provider, apiKey: apiKey)

        if response.success {
            return parseGoals(from: response.content)
        } else {
            await context.logger.warning("Goal expansion failed, no follow-ups generated", toolId: "GoalExpansion")
            return []
        }
    }

    private func parseGoals(from content: String) -> [String] {
        var jsonStr = content
        if let range = content.range(of: "\\[.*\\]", options: .regularExpression) {
            jsonStr = String(content[range])
        }

        guard let data = jsonStr.data(using: .utf8),
              let goals = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return goals
    }
}
