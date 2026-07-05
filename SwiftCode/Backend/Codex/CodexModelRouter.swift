import Foundation

struct CodexModelRouter {
    @MainActor
    func useCodex() -> Bool {
        AppSettings.shared.useCodexAsDefaultAgent
    }

    @MainActor
    func routePrompt(_ prompt: String, useContext: Bool) async throws -> String {
        if useCodex() {
            return try await CodexManager.shared.sendPrompt(useContext ? "[Context Aware]\n\n\(prompt)" : prompt)
        }
        return try await LLMService.shared.generateExternalResponse(prompt: prompt, useContext: useContext)
    }
}
