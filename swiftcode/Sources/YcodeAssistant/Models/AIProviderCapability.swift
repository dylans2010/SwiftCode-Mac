import Foundation

public enum AIProviderCapability: String, Codable, Sendable, CaseIterable {
    case toolCalling = "tool_calling"
    case vision = "vision"
    case streaming = "streaming"
}

public extension ProviderKind {
    var aiCapabilities: Set<AIProviderCapability> {
        switch self {
        case .openAI, .openRouter, .codex, .claudeCode, .openCode, .hermes, .acpAgent, .antigravity, .anthropic, .gemini, .mistral:
            return [.streaming, .toolCalling]
        case .ollama, .llamaCpp, .foundationModels, .scCloud, .metaAssist:
            return [.streaming]
        }
    }
}

public extension AssistantProvider {
    var capabilities: Set<AIProviderCapability> { kind.aiCapabilities }
}
