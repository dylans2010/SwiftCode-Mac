import Foundation

public enum ProviderKind: String, Codable, Sendable, CaseIterable, Hashable {
    case ollama, llamaCpp, openAI, claudeCode, codex, antigravity
    case acpAgent
    case openRouter
    case openCode
    case hermes
    case anthropic
    case foundationModels
    case scCloud
    case metaAssist

    public var displayName: String {
        switch self {
        case .ollama: "Ollama"
        case .llamaCpp: "llama.cpp"
        case .openAI: "OpenAI"
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .antigravity: "Antigravity"
        case .acpAgent: "ACP Agent"
        case .openRouter: "OpenRouter"
        case .openCode: "OpenCode"
        case .hermes: "Hermes"
        case .foundationModels: "Foundation Models"
        case .scCloud: "SwiftCode Cloud"
        case .metaAssist: "Assist with Meta"
        case .anthropic: "Anthropic"
        }
    }

    public var isLocalServer: Bool { self == .ollama || self == .llamaCpp || self == .openCode }
    public var cliAgent: CLIAgentKind? {
        switch self {
        case .claudeCode: .claudeCode
        case .codex: .codex
        case .antigravity: .antigravity
        default: nil
        }
    }
}

public enum ChatRole: String, Codable, Sendable, Equatable {
    case system, user, assistant
}

public struct ChatMessage: Codable, Sendable, Equatable {
    public var role: ChatRole
    public var content: String
    public init(_ role: ChatRole, _ content: String) {
        self.role = role
        self.content = content
    }
}

public struct ModelInfo: Codable, Sendable, Equatable, Hashable {
    public var id: String
    public var displayName: String
    public var contextWindow: Int?
    public var description: String?
    public var pricing: ModelPricing?

    public struct ModelPricing: Codable, Sendable, Equatable, Hashable {
        public var prompt: String?
        public var completion: String?
        public init(prompt: String? = nil, completion: String? = nil) {
            self.prompt = prompt
            self.completion = completion
        }
    }

    public init(id: String, displayName: String? = nil, contextWindow: Int? = nil,
                description: String? = nil, pricing: ModelPricing? = nil) {
        self.id = id
        self.displayName = displayName ?? id
        self.contextWindow = contextWindow
        self.description = description
        self.pricing = pricing
    }
}

public struct GenerationOptions: Codable, Sendable, Equatable {
    public var maxOutputTokens: Int?
    public var temperature: Double?
    public var topP: Double?
    public var topK: Int?
    public var repeatPenalty: Double?

    public init(maxOutputTokens: Int? = nil, temperature: Double? = nil, topP: Double? = nil, topK: Int? = nil, repeatPenalty: Double? = nil) {
        self.maxOutputTokens = maxOutputTokens
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.repeatPenalty = repeatPenalty
    }

    public static let assistantDefault = GenerationOptions(maxOutputTokens: 4096)
}

public struct ChatRequest: Sendable, Equatable {
    public var model: String?
    public var instructions: String
    public var messages: [ChatMessage]
    public var contextTokens: Int?
    public var workingDirectory: URL?
    public var generation: GenerationOptions
    public init(model: String?, instructions: String, messages: [ChatMessage], contextTokens: Int? = nil, workingDirectory: URL? = nil,
                generation: GenerationOptions = GenerationOptions()) {
        self.generation = generation
        self.model = model
        self.instructions = instructions
        self.messages = messages
        self.contextTokens = contextTokens
        self.workingDirectory = workingDirectory
    }

    public var flattenedPrompt: String {
        var s = instructions
        let earlier = messages.dropLast()
        if !earlier.isEmpty {
            s += "\n\n<conversation>\n"
            for m in earlier { s += "<\(m.role.rawValue)>\n\(m.content)\n</\(m.role.rawValue)>\n" }
            s += "</conversation>"
        }
        if let last = messages.last { s += "\n\n" + last.content }
        return s
    }
}

public struct TokenUsage: Sendable, Equatable, Codable {
    public var inputTokens: Int?
    public var outputTokens: Int?
    public init(inputTokens: Int? = nil, outputTokens: Int? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }
}

public enum ChatEvent: Sendable, Equatable {
    case text(String)
    case activity(String)
    case truncated
    case finished(TokenUsage?)
}

public enum ProviderAvailability: Sendable, Equatable {
    case ready([ModelInfo])
    case notRunning(hint: String)
    case noModels(hint: String)
    case notInstalled(hint: String)
    case signedOut(hint: String)
    case failed(String)

    public var isReady: Bool { if case .ready = self { true } else { false } }
    public var models: [ModelInfo] { if case .ready(let m) = self { m } else { [] } }
    public var hint: String? {
        switch self {
        case .ready: nil
        case .notRunning(let h), .noModels(let h), .notInstalled(let h), .signedOut(let h): h
        case .failed(let m): m
        }
    }
}

public enum AssistantError: Error, Sendable, Equatable, LocalizedError {
    case unreachable(service: String, url: String, hint: String)
    case http(status: Int, message: String)
    case modelNotFound(model: String, hint: String)
    case notSignedIn(hint: String)
    case planUsageNotEnabled
    case usageLimit(String)
    case temporarilyUnavailable(String)
    case unsupported(String)
    case incomplete(String)
    case failed(String)
    case tool(name: String, message: String)
    case malformed(String)
    case signIn(String)

    public var errorDescription: String? {
        switch self {
        case .unreachable(let service, let url, _): "\(service) is not running at \(url)."
        case .http(let status, let message): message.isEmpty ? "The server answered with HTTP \(status)." : "HTTP \(status): \(message)"
        case .modelNotFound(let model, _): "The model “\(model)” is not available."
        case .notSignedIn: "You are not signed in."
        case .planUsageNotEnabled: "ChatGPT plan usage isn't enabled for this app."
        case .usageLimit(let m), .temporarilyUnavailable(let m), .unsupported(let m), .failed(let m), .malformed(let m), .signIn(let m): m
        case .incomplete(let reason): "The response stopped early (\(reason))."
        case .tool(let name, let message): "\(name) stopped: \(message)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .unreachable(_, _, let hint), .modelNotFound(_, let hint), .notSignedIn(let hint): hint
        case .planUsageNotEnabled: "Sign in again and allow plan usage, or choose API key in Settings ▸ Coding Assistant."
        case .usageLimit: "Check your usage in ChatGPT settings."
        case .temporarilyUnavailable: "Try again shortly."
        default: nil
        }
    }
}

public protocol AssistantProvider: Sendable {
    var kind: ProviderKind { get }
    func availability() async -> ProviderAvailability
    func contextWindow(model: String) async -> Int?
    func send(_ request: ChatRequest) -> AsyncThrowingStream<ChatEvent, Error>
}

extension AssistantProvider {
    public func contextWindow(model: String) async -> Int? { nil }
}

func eventStream(_ body: @escaping @Sendable (AsyncThrowingStream<ChatEvent, Error>.Continuation) async throws -> Void)
    -> AsyncThrowingStream<ChatEvent, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
            do {
                try await body(continuation)
                continuation.finish()
            } catch is CancellationError {
                continuation.finish(throwing: CancellationError())
            } catch {
                continuation.finish(throwing: error)
            }
        }
        continuation.onTermination = { _ in task.cancel() }
    }
}
