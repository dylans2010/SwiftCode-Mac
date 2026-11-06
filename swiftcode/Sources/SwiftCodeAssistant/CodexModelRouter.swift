import Foundation

/// Toggle-driven routing to Codex (Legacy
/// `SwiftCode/Backend/Codex/CodexModelRouter.swift`, Dylan's own code,
/// ported under MIT).
///
/// Adaptation: Legacy routed to `CodexManager.sendPrompt` when the
/// `useCodexAsAgent` / `useCodexAsDefaultAgent` UserDefaults toggles
/// were on, else to `LLMService.generateExternalResponse`. The
/// destination's `CodexManager.sendPrompt` still exists; the fallback
/// now runs one turn on the provider named by `AssistantSettings`
/// (the persisted provider picker) through `AssistantBackends`, and
/// collects the streamed text.
public struct CodexModelRouter: Sendable {
    public init() {}

    /// The two Legacy toggles, in Legacy's precedence: `useCodexAsAgent`
    /// wins, else `useCodexAsDefaultAgent`, else off.
    @MainActor
    public func useCodex() -> Bool {
        (UserDefaults.standard.object(forKey: "useCodexAsAgent") as? Bool)
            ?? (UserDefaults.standard.object(forKey: "useCodexAsDefaultAgent") as? Bool)
            ?? false
    }

    /// Routes one prompt: to Codex when the toggles say so (prefixing
    /// `"[Context Aware]\n\n"` when `useContext` is set), else to the
    /// configured assistant provider.
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
