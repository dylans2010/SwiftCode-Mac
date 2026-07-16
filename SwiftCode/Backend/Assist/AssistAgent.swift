import Foundation

@MainActor
public final class AssistAgent: ObservableObject {
    private let context: AssistContext
    private let api = AssistAPI.shared

    @Published public var isRunning = false

    public init(context: AssistContext, registry: AssistToolRegistry) {
        self.context = context
        self.api.configure(context: context)
    }

    public func processIntent(_ intent: String) async -> AssistAIResponse {
        isRunning = true
        defer { isRunning = false }

        do {
            // Claude Code-level execution flow via AssistAPI

            // 1. Enhance Prompt (Internal step if not already specific)
            let enhanceResponse = await api.enhancePrompt(userInput: intent)
            let finalIntent = enhanceResponse.success ? (enhanceResponse.data?["enhancedPrompt"] ?? intent) : intent

            // 2. Analyze
            let analyzeResponse = await api.analyze()
            await context.logger.info("Codebase analysis complete: \(analyzeResponse.markdown ?? "")")

            // 3. Plan
            let planResponse = await api.plan(intent: finalIntent)
            guard planResponse.success, let planStr = planResponse.data?["plan"], let planData = planStr.data(using: .utf8) else {
                return AssistAIResponse(content: "", success: false, error: "Failed to generate plan: \(planResponse.error ?? "Unknown error")")
            }

            let plan = try JSONDecoder().decode(AssistExecutionPlan.self, from: planData)

            // 4. Execute (Autonomous engine integration)
            let takeoverEnabled = UserDefaults.standard.bool(forKey: "assist.takeoverEnabled")

            if takeoverEnabled {
                let autonomousEngine = _AssistCriticalAutonomousEngine(context: context)
                try await autonomousEngine.run(intent: finalIntent)
                return await generateFinalReport(for: finalIntent)
            } else {
                let executeResponse = await api.execute(plan: plan)
                if executeResponse.success {
                    return await generateFinalReport(for: finalIntent, plan: plan)
                } else {
                    return AssistAIResponse(content: "", success: false, error: "Execution failed: \(executeResponse.error ?? "Unknown error")")
                }
            }
        } catch {
            await context.logger.error("Agent execution failed: \(error.localizedDescription)")
            return AssistAIResponse(content: "I couldn't complete that request safely.", success: false, error: "Assist execution failed: \(error.localizedDescription)")
        }
    }

    private func generateFinalReport(for intent: String, plan: AssistExecutionPlan? = nil) async -> AssistAIResponse {
        await context.logger.info("Generating final report for: \(intent)")

        let modelID = await AssistModelManager.shared.selectedModelID
        let providerRawValue = UserDefaults.standard.string(forKey: "assist.selectedProvider") ?? AssistModelProvider.openAI.rawValue
        let provider = AssistModelProvider(rawValue: providerRawValue) ?? .openAI
        let apiKey = APIKeyManager.shared.retrieveKey(service: provider.apiKeyProvider)

        var prompt = "\(AssistAgenticPrompt.systemPrompt)\n\n# TASK COMPLETED\nTask: \(intent)\nStatus: Completed.\n"

        if let plan = plan {
            prompt += "\n## EXECUTION DATA\n"
            prompt += plan.steps.map { "- \($0.description) (\($0.status.rawValue))" }.joined(separator: "\n")
        }

        prompt += "\n\nProvide the final report in the strict markdown format specified in the system prompt."

        let finalResponse = await AssistLLMService.generateResponse(
            prompt: prompt,
            provider: provider,
            apiKey: apiKey,
            modelOverride: modelID
        )

        return finalResponse
    }
}
