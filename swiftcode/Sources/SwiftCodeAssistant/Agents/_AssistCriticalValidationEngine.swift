import Foundation

@MainActor
public final class _AssistCriticalValidationEngine: Sendable {
    private let context: AssistContext

    public init(context: AssistContext) {
        self.context = context
    }

    public func validate(plan: AssistExecutionPlan) async throws -> ValidationResult {
        await context.logger.info("Validating plan results for: \(plan.goal)", toolId: "ValidationEngine")

        let failedSteps = plan.steps.filter { $0.status == .failed }
        if !failedSteps.isEmpty {
            let feedback = failedSteps.map { "\($0.toolId): \($0.result?.error ?? "Unknown error")" }.joined(separator: "; ")
            return .failure("One or more steps failed: \(feedback)")
        }

        let providerRawValue = UserDefaults.standard.string(forKey: "assist.selectedProvider") ?? AssistModelProvider.openAI.rawValue
        let provider = AssistModelProvider(rawValue: providerRawValue) ?? .openAI
        let apiKey = await provider.storedAPIKey()

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
            let allCompleted = plan.steps.allSatisfy { $0.status == .completed }
            return allCompleted ? .success : .failure("Execution finished but some steps did not complete successfully.")
        }
    }

    private func parseValidation(from content: String) -> ValidationResult {
        var cleaned = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("```json") {
            cleaned = String(cleaned.dropFirst(7))
        } else if cleaned.hasPrefix("```") {
            cleaned = String(cleaned.dropFirst(3))
        }
        if cleaned.hasSuffix("```") {
            cleaned = String(cleaned.dropLast(3))
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        if let firstBrace = cleaned.firstIndex(of: "{"),
           let lastBrace = cleaned.lastIndex(of: "}") {
            let candidate = String(cleaned[firstBrace...lastBrace])
            if let data = candidate.data(using: .utf8),
               let result = try? JSONDecoder().decode(ValidationResult.self, from: data) {
                return result
            }
        }

        if let data = cleaned.data(using: .utf8),
           let result = try? JSONDecoder().decode(ValidationResult.self, from: data) {
            return result
        }

        return .success
    }
}

public struct ValidationResult: Codable {
    public let isSuccess: Bool
    public let feedback: String

    public static var success: ValidationResult { ValidationResult(isSuccess: true, feedback: "All requirements met.") }
    public static func failure(_ feedback: String) -> ValidationResult { ValidationResult(isSuccess: false, feedback: feedback) }
}
