import Foundation

public struct CodexModelRouter: Sendable {
    public init() {}

    @MainActor
    public func useCodex() -> Bool {
        (UserDefaults.standard.object(forKey: "useCodexAsAgent") as? Bool)
            ?? (UserDefaults.standard.object(forKey: "useCodexAsDefaultAgent") as? Bool)
            ?? false
    }

    @MainActor
    public func routePrompt(_ prompt: String, useContext: Bool) async throws -> String {
        if useCodex() {
            return try await CodexManager.shared.sendPrompt(useContext ? "[Context Aware]\n\n\(prompt)" : prompt)
        }
        let settings = AssistantSettings()
        let backends = AssistantBackends(settings: settings, store: defaultSecretStore(), account: nil)
        let provider = backends.provider(settings.provider)
        var output = ""
        let stream = provider.send(ChatRequest(model: nil, instructions: "", messages: [ChatMessage(.user, prompt)]))
        for try await event in stream {
            if case .text(let text) = event { output += text }
        }
        return output
    }
}
