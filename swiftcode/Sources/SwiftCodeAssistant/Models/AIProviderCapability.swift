import Foundation

/// Per-provider capability flags (Legacy
/// `SwiftCode/Core/AI/Agent/AIProvider.swift`, Dylan's own code, ported
/// under MIT). The destination's `AssistantProvider` had no capability
/// set; per-model capabilities already exist as `ModelCapabilities`
/// (`AssistModelRouting.swift`) and stay the source of truth for
/// model-level facts (vision is model-level, not provider-level).
public enum AIProviderCapability: String, Codable, Sendable, CaseIterable {
    case toolCalling = "tool_calling"
    case vision = "vision"
    case streaming = "streaming"
}

public extension ProviderKind {
    /// The capabilities this provider kind offers. Every provider
    /// streams by contract (`AssistantProvider.send` returns a
    /// stream). Tool calling is listed for the kinds whose providers
    /// implement tool use; vision is deliberately not listed here —
    /// it depends on the model (`ModelCapabilities.vision` /
    /// `ModelSpecification`), not the provider. A provider that knows
    /// more overrides `AssistantProvider.capabilities`.
    var aiCapabilities: Set<AIProviderCapability> {
        switch self {
        case .openAI, .openRouter, .codex, .claudeCode, .openCode, .hermes, .acpAgent, .antigravity:
            return [.streaming, .toolCalling]
        case .ollama, .llamaCpp, .foundationModels, .scCloud, .metaAssist:
            return [.streaming]
        }
    }
}

public extension AssistantProvider {
    /// This provider's capabilities (Legacy `AIProviderCapability`).
    /// Defaults to the kind-level set; providers override when they
    /// know more (e.g. a vision-capable model list).
    var capabilities: Set<AIProviderCapability> { kind.aiCapabilities }
}
