import Foundation
import os

private let logger = Logger(subsystem: "com.swiftcode.app", category: "LLMService")

public enum LLMProvider: String, CaseIterable, Codable {
    case openRouter = "OpenRouter"
    case anthropic = "Anthropic"
    case openai = "OpenAI"
    case google = "Gemini"
    case mistral = "Mistral"
    case qwen = "Qwen"
    case offline = "Offline"
    case codex = "Codex"

    public static func from(rawValue: String?) -> LLMProvider {
        guard let rawValue = rawValue else { return .openRouter }
        return LLMProvider(rawValue: rawValue) ?? .openRouter
    }

    public var keychainKey: String {
        switch self {
        case .openRouter: return KeychainService.openRouterAPIKey
        case .anthropic: return "anthropic_api_key"
        case .openai: return "openai_api_key"
        case .google: return "gemini_api_key"
        case .mistral: return "mistral_api_key"
        case .qwen: return "qwen_api_key"
        case .offline: return "offline_model_selected"
        case .codex: return KeychainService.codexUserAPIKey
        }
    }

    public var baseURL: URL {
        switch self {
        case .openRouter: return URL(string: "https://openrouter.ai/api/v1")!
        case .anthropic: return URL(string: "https://api.anthropic.com/v1")!
        case .openai: return URL(string: "https://api.openai.com/v1")!
        case .google: return URL(string: "https://generativelanguage.googleapis.com/v1beta/openai")!
        case .mistral: return URL(string: "https://api.mistral.ai/v1")!
        case .qwen: return URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1")!
        case .offline: return URL(string: "http://localhost")!
        case .codex: return URL(string: "http://localhost:3003/v1")!
        }
    }
}

public enum AIRoutingMode: String, CaseIterable {
    case alwaysLocal = "Always Local"
    case alwaysServer = "Always Server"
    case dynamic = "Dynamic"

    public static func from(rawValue: String?) -> AIRoutingMode {
        guard let rawValue else { return .dynamic }
        return AIRoutingMode(rawValue: rawValue) ?? .dynamic
    }
}

public enum LLMError: LocalizedError {
    case invalidKey
    case rateLimited
    case networkError(String)
    case modelNotFound
    case unknown(String)
    case missingOfflineDefaultModel
    case offlineFallbackUnavailable
    case swiftCloudLimitReached(String)

    public var errorDescription: String? {
        switch self {
        case .invalidKey: return "invalid_key"
        case .rateLimited: return "rate_limited"
        case .networkError(let desc): return "network_error: \(desc)"
        case .modelNotFound: return "model_not_found"
        case .unknown(let desc): return desc
        case .missingOfflineDefaultModel: return "No default offline model selected. Download and set a default offline model in Settings."
        case .offlineFallbackUnavailable: return "Server unavailable and no default offline model configured. Add an API key or download an offline model."
        case .swiftCloudLimitReached(let desc): return desc
        }
    }
}

public struct LLMResponse: Sendable {
    public let modelName: String
    public let completionText: String
    public let tokenUsage: TokenUsage?
    public let latency: TimeInterval

    public struct TokenUsage: Sendable, Codable {
        public let promptTokens: Int
        public let completionTokens: Int
        public let totalTokens: Int

        public init(promptTokens: Int, completionTokens: Int, totalTokens: Int) {
            self.promptTokens = promptTokens
            self.completionTokens = completionTokens
            self.totalTokens = totalTokens
        }
    }

    public init(modelName: String, completionText: String, tokenUsage: TokenUsage?, latency: TimeInterval) {
        self.modelName = modelName
        self.completionText = completionText
        self.tokenUsage = tokenUsage
        self.latency = latency
    }
}
