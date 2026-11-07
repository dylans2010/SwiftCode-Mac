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

    @MainActor
    public func storedAPIKey() async -> String? {
        guard let keyProvider = apiKeyProvider else { return nil }
        return await APIKeyManager.shared.retrieveKey(service: keyProvider)
    }

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
        case .meta: return URL(string: "https://api.meta.ai/v1/chat/completions")
        case .kimi: return URL(string: "https://api.moonshot.cn/v1/chat/completions")
        case .openRouter: return URL(string: "https://openrouter.ai/api/v1/chat/completions")
        case .openCode: return OpenCodeConfiguration.load().serverURL
        case .hermes: return nil
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
