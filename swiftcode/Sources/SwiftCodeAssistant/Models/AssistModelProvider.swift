// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Backend/Assist/AssistModels.swift (lines 63–167 only)
//   (Legacy main ab03f681) — `AssistModelProvider` + `AssistAIResponse`.
//   The rest of that 1,122-line file is already on main in the destination
//   `SwiftCodeAssistant/Models/AssistModels.swift` (752 lines) and is NOT
//   redeclared here; `AssistModelFilter` (same Legacy file, lines 838–870)
//   is staged separately as `AssistModelFilter.swift`; `AssistLLMService`
//   (same Legacy file, lines 168–214) is NOT staged — it needs `LLMService`
//   (1,413-line file, unowned) — see staging-wire/unowned/DISPOSITIONS.md.
//
// Destination: SwiftCodeAssistant/Models/AssistModelProvider.swift.
//
// No adaptations except `public` access on the members Legacy left
// internal (`apiKeyProvider`, `llmProvider`). Dependencies, all present:
// `LLMProvider` (staged in this same batch, `LLMProviderModels.swift`),
// `APIKeyManager` (staged in this same batch, `APIKeyManager.swift`),
// `OpenCodeConfiguration.load()` (staged in this same batch,
// `OpenCodeConfiguration+Load.swift`).
// NOTE: `AssistModelProvider` is also referenced by
// `AssistProviderConfiguration.AssistProviderSelection` in Legacy, which is
// NOT staged (blocked: `AgentModelAdapter`, unowned).

import Foundation

public enum AssistModelProvider: String, Codable, CaseIterable, Sendable {
    case openAI = "ChatGPT"
    case anthropic = "Claude"
    case gemini = "Gemini"
    case mistral = "Mistral"
    case meta = "Meta AI"
    case kimi = "Kimi"
    case openRouter = "OpenRouter"
    case openCode = "OpenCode"
    case hermes = "Hermes"
    case codex = "Codex"

    public static func from(llmProvider: LLMProvider) -> AssistModelProvider {
        switch llmProvider {
        case .openai: return .openAI
        case .anthropic: return .anthropic
        case .google: return .gemini
        case .mistral: return .mistral
        case .openRouter, .qwen, .offline: return .openRouter
        case .codex: return .codex
        }
    }

    /// The stored-key provider for this Assist provider, or nil when the
    /// provider holds no SwiftCode-managed API key. OpenCode is nil: its
    /// model credentials live in OpenCode's own configuration and the
    /// server is local, so there is no key for SwiftCode to retrieve —
    /// returning another provider's key here would mix credentials.
    public var apiKeyProvider: APIKeyProvider? {
        switch self {
        case .openAI: return .openai
        case .anthropic: return .anthropic
        case .gemini: return .google
        case .mistral: return .mistral
        case .meta, .kimi: return .openRouter
        case .openRouter: return .openRouter
        case .openCode: return nil
        case .hermes: return nil
        case .codex: return .openai
        }
    }

    /// Stored key for this provider, or nil for OpenCode (no
    /// SwiftCode-managed key exists for it) and for Hermes (its
    /// credentials live in Hermes' own ~/.hermes/.env, never in
    /// SwiftCode's Keychain). Single call site for the legacy
    /// final-report paths so they cannot accidentally pick up
    /// another provider's credential.
    @MainActor
    public func storedAPIKey() async -> String? {
        guard let keyProvider = apiKeyProvider else { return nil }
        return await APIKeyManager.shared.retrieveKey(service: keyProvider)
    }

    /// LLMService routing for providers that go through LLMService.
    /// OpenCode does NOT go through LLMService (AgentModelAdapter routes
    /// `opencode:` models to OpenCodeClient before LLMService is reached),
    /// so this mapping is never consulted for it — and
    /// AssistLLMService.generateResponse fails closed for .openCode
    /// rather than silently sending an OpenCode model to OpenRouter.
    /// Hermes likewise never goes through LLMService (it runs through
    /// HermesProvider's CLI process); the mapping value below is
    /// unreachable for it because generateResponse fails closed for
    /// .hermes first.
    public var llmProvider: LLMProvider {
        switch self {
        case .openAI: return .openai
        case .anthropic: return .anthropic
        case .gemini: return .google
        case .mistral: return .mistral
        case .meta, .kimi, .openRouter: return .openRouter
        case .openCode: return .openRouter
        case .hermes: return .openRouter
        case .codex: return .codex
        }
    }

    public var endpoint: URL? {
        switch self {
        case .openAI: return URL(string: "https://api.openai.com/v1/chat/completions")
        case .anthropic: return URL(string: "https://api.anthropic.com/v1/messages")
        case .gemini: return URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent")
        case .mistral: return URL(string: "https://api.mistral.ai/v1/chat/completions")
        case .meta: return URL(string: "https://api.meta.ai/v1/chat/completions") // Example
        case .kimi: return URL(string: "https://api.moonshot.cn/v1/chat/completions")
        case .openRouter: return URL(string: "https://openrouter.ai/api/v1/chat/completions")
        case .openCode: return OpenCodeConfiguration.load().serverURL
        case .hermes: return nil // No SwiftCode HTTP endpoint: Hermes runs through its CLI process (HermesProvider).
        case .codex: return URL(string: "http://localhost:3003/v1/chat/completions")
        }
    }
}

public struct AssistAIResponse: Sendable {
    public let content: String
    public let success: Bool
    public let error: String?

    public init(content: String, success: Bool, error: String? = nil) {
        self.content = content
        self.success = success
        self.error = error
    }
}
