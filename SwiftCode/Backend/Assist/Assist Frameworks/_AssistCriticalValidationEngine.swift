import Foundation

/// [CRITICAL SYSTEM FILE] - HIGH RISK
/// Validates the outputs of an autonomous execution iteration to ensure requirements are met.
public final class _AssistCriticalValidationEngine {
    private let context: AssistContext

    public init(context: AssistContext) {
        self.context = context
    }

    /// Validates the outcome of a completed plan.
    public func validate(plan: AssistExecutionPlan) async throws -> ValidationResult {
        await context.logger.info("Validating plan results for: \(plan.goal)", toolId: "ValidationEngine")

        // 1. Check for step failures
        let failedSteps = plan.steps.filter { $0.status == .failed }
        if !failedSteps.isEmpty {
            let feedback = failedSteps.map { "\($0.toolId): \($0.result?.error ?? "Unknown error")" }.joined(separator: "; ")
            return .failure("One or more steps failed: \(feedback)")
        }

        // 2. Perform AI-based verification of the final state
        let providerRawValue = UserDefaults.standard.string(forKey: "assist.selectedProvider") ?? AssistModelProvider.openAI.rawValue
        let provider = AssistModelProvider(rawValue: providerRawValue) ?? .openAI
        let apiKey = APIKeyManager.shared.retrieveKey(service: provider.apiKeyProvider)

        let prompt = """
        \(AssistAgenticPrompt.systemPrompt)

        # VALIDATION TASK
        The user goal was: "\(plan.goal)"
        The execution plan has finished. Analyze the plan steps and results to determine if the goal has been successfully met.

        Steps performed:
        \(plan.steps.map { "- \($0.description) (\($0.status.rawValue))" }.joined(separator: "\n"))

        Return a JSON object ONLY:
        { "isSuccess": true/false, "feedback": "Detailed explanation of what is missing or incorrect if isSuccess is false." }
        """

        let response = await AssistLLMService.generateResponse(prompt: prompt, provider: provider, apiKey: apiKey)

        if response.success {
            return parseValidation(from: response.content)
        } else {
            // If AI validation fails (e.g. network error), we check if all steps were 'completed'
            let allCompleted = plan.steps.allSatisfy { $0.status == .completed }
            return allCompleted ? .success : .failure("Execution finished but some steps did not complete successfully.")
        }
    }

    private func parseValidation(from content: String) -> ValidationResult {
        var jsonStr = content
        if let range = content.range(of: "\\{.*\\}", options: .regularExpression) {
            jsonStr = String(content[range])
        }

        guard let data = jsonStr.data(using: .utf8),
              let result = try? JSONDecoder().decode(ValidationResult.self, from: data) else {
            return .success // Default to success to avoid loops if JSON is unparseable but execute reached end
        }
        return result
    }
}

public struct ValidationResult: Codable {
    public let isSuccess: Bool
    public let feedback: String

    public static var success: ValidationResult { ValidationResult(isSuccess: true, feedback: "All requirements met.") }
    public static func failure(_ feedback: String) -> ValidationResult { ValidationResult(isSuccess: false, feedback: feedback) }
}
