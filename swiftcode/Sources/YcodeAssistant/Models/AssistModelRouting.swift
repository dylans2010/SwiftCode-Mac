import Foundation

public struct ModelCapabilities: OptionSet, Sendable, Codable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let toolCalling = ModelCapabilities(rawValue: 1 << 0)
    public static let streaming = ModelCapabilities(rawValue: 1 << 1)
    public static let structuredOutput = ModelCapabilities(rawValue: 1 << 2)
    public static let reasoning = ModelCapabilities(rawValue: 1 << 3)
    public static let vision = ModelCapabilities(rawValue: 1 << 4)
    public static let largeContext = ModelCapabilities(rawValue: 1 << 5)
    public static let parallelToolCalls = ModelCapabilities(rawValue: 1 << 6)
    public static let codeGeneration = ModelCapabilities(rawValue: 1 << 7)
    public static let systemInstructions = ModelCapabilities(rawValue: 1 << 8)
    public static let subagents = ModelCapabilities(rawValue: 1 << 9)
    public static let backgroundExecution = ModelCapabilities(rawValue: 1 << 10)

    public static let longContext: ModelCapabilities = .largeContext

    public static let standardCloud: ModelCapabilities = [
        .toolCalling, .streaming, .structuredOutput, .largeContext, .codeGeneration, .systemInstructions, .subagents
    ]

    public static let advancedReasoning: ModelCapabilities = [
        .toolCalling, .streaming, .structuredOutput, .reasoning, .largeContext, .parallelToolCalls, .codeGeneration, .systemInstructions, .subagents
    ]

    public static let localFoundation: ModelCapabilities = [
        .codeGeneration, .structuredOutput
    ]
}

public struct ModelSpecification: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public let displayName: String
    public let provider: ProviderKind
    public let contextWindowTokens: Int
    public let capabilities: ModelCapabilities
    public let defaultTemperature: Double

    public init(
        id: String,
        displayName: String,
        provider: ProviderKind,
        contextWindowTokens: Int = 128_000,
        capabilities: ModelCapabilities = .standardCloud,
        defaultTemperature: Double = 0.2
    ) {
        self.id = id
        self.displayName = displayName
        self.provider = provider
        self.contextWindowTokens = contextWindowTokens
        self.capabilities = capabilities
        self.defaultTemperature = defaultTemperature
    }
}

public enum AssistModelSpecification {
    public static func specification(for modelId: String) -> ModelSpecification {
        if let openCode = OpenCodeModelID.parse(modelId) {
            return ModelSpecification(
                id: modelId,
                displayName: openCode.displayName,
                provider: .openCode,
                contextWindowTokens: 128_000,
                capabilities: .standardCloud
            )
        }
        if let hermes = HermesModelID.parse(modelId) {
            return ModelSpecification(
                id: modelId,
                displayName: hermes.spec,
                provider: .hermes,
                contextWindowTokens: 128_000,
                capabilities: .standardCloud
            )
        }
        if SCCloudProvider.isCloudModelID(modelId) {
            let endpointName = SCCloudProvider.endpointName(forInternalID: modelId)
            return ModelSpecification(
                id: modelId,
                displayName: endpointName ?? SCCloudProvider.displayNameFallback,
                provider: .scCloud,
                contextWindowTokens: 128_000,
                capabilities: [.structuredOutput, .systemInstructions, .codeGeneration, .largeContext]
            )
        }

        let lower = modelId.lowercased()

        if lower.contains("claude") || lower.contains("anthropic") {
            let displayName: String
            if lower.contains("3-7") || lower.contains("3.7") {
                displayName = "Claude 3.7 Sonnet"
            } else if lower.contains("haiku") {
                displayName = "Claude 3.5 Haiku"
            } else if lower.contains("opus") {
                displayName = "Claude 3 Opus"
            } else {
                displayName = "Claude 3.5 Sonnet"
            }
            return ModelSpecification(
                id: modelId,
                displayName: displayName,
                provider: modelId.contains("/") ? .openRouter : .anthropic,
                contextWindowTokens: 200_000,
                capabilities: [.toolCalling, .streaming, .structuredOutput, .vision, .largeContext, .codeGeneration, .systemInstructions, .subagents]
            )
        } else if lower.contains("gpt") || lower.contains("o1") || lower.contains("o3") || lower.contains("chatgpt") || lower.contains("openai") {
            let displayName: String
            if lower.contains("o3-mini") {
                displayName = "o3-mini"
            } else if lower.contains("o1") {
                displayName = "o1"
            } else if lower.contains("gpt-4o-mini") {
                displayName = "GPT-4o Mini"
            } else {
                displayName = "GPT-4o"
            }
            return ModelSpecification(
                id: modelId,
                displayName: displayName,
                provider: .openAI,
                contextWindowTokens: 128_000,
                capabilities: [.toolCalling, .streaming, .structuredOutput, .vision, .largeContext, .parallelToolCalls, .codeGeneration, .systemInstructions, .subagents]
            )
        } else if lower.contains("gemini") {
            let displayName = lower.contains("flash") ? "Gemini 3.8 Flash" : "Gemini 3.8 Pro"
            return ModelSpecification(
                id: modelId,
                displayName: displayName,
                provider: .openRouter,
                contextWindowTokens: 1_000_000,
                capabilities: [.toolCalling, .streaming, .structuredOutput, .largeContext, .codeGeneration, .systemInstructions, .subagents]
            )
        } else if lower.contains("mistral") || lower.contains("codestral") || lower.contains("pixtral") {
            let displayName = lower.contains("codestral") ? "Codestral" : "Mistral Large"
            return ModelSpecification(
                id: modelId,
                displayName: displayName,
                provider: .openRouter,
                contextWindowTokens: 128_000,
                capabilities: [.toolCalling, .streaming, .structuredOutput, .largeContext, .codeGeneration, .systemInstructions, .subagents]
            )
        } else if lower.contains("deepseek") {
            return ModelSpecification(
                id: modelId,
                displayName: "DeepSeek V3",
                provider: .openRouter,
                contextWindowTokens: 64_000,
                capabilities: [.toolCalling, .streaming, .structuredOutput, .largeContext, .codeGeneration, .systemInstructions, .subagents]
            )
        } else if lower.contains("codex") {
            return ModelSpecification(
                id: modelId,
                displayName: "Codex Local Bridge",
                provider: .codex,
                contextWindowTokens: 32_000,
                capabilities: [.codeGeneration, .structuredOutput]
            )
        } else if lower.contains("ollama") || lower.contains("lmstudio") {
            return ModelSpecification(
                id: modelId,
                displayName: modelId,
                provider: .ollama,
                contextWindowTokens: 32_000,
                capabilities: [.toolCalling, .streaming, .codeGeneration, .systemInstructions]
            )
        } else if lower.contains("afm 3 core") || lower.contains("afm-3-core") || lower.contains("apple") || lower.contains("foundation") {
            return ModelSpecification(
                id: modelId,
                displayName: "Apple Foundation Models",
                provider: .foundationModels,
                contextWindowTokens: 8_192,
                capabilities: .localFoundation
            )
        }

        return ModelSpecification(
            id: modelId,
            displayName: modelId,
            provider: .openRouter,
            contextWindowTokens: 128_000,
            capabilities: .standardCloud
        )
    }

    public static func contextBudget(for modelId: String) -> AgentModelContextBudget {
        let spec = specification(for: modelId)
        return AgentModelContextBudget(
            modelId: modelId,
            contextWindowTokens: spec.contextWindowTokens
        )
    }

    public static func normalizePrompt(systemPrompt: String, userInstructions: String, for modelId: String) -> String {
        let spec = specification(for: modelId)
        if spec.capabilities.contains(.systemInstructions) {
            return "\(systemPrompt)\n\n# TASK EXECUTION INSTRUCTIONS\n\(userInstructions)"
        } else {
            return "SYSTEM DIRECTIVES:\n\(systemPrompt)\n\nUSER REQUEST:\n\(userInstructions)"
        }
    }
}

public struct AgentModelContextBudget: Sendable, Equatable {
    public let modelId: String
    public let contextWindowTokens: Int
    public let reservedOutputTokens: Int
    public let maxInputTokens: Int
    public let utilizationRatio: Double

    public init(modelId: String, contextWindowTokens: Int, reservedOutputTokens: Int = 4096) {
        self.modelId = modelId
        self.contextWindowTokens = contextWindowTokens
        self.reservedOutputTokens = reservedOutputTokens
        self.maxInputTokens = max(1024, contextWindowTokens - reservedOutputTokens)
        self.utilizationRatio = Double(reservedOutputTokens) / Double(contextWindowTokens)
    }

    public func fitsContext(estimatedTokens: Int) -> Bool {
        estimatedTokens <= maxInputTokens
    }

    public func estimatedTokenCount(for text: String) -> Int {
        text.count / 4
    }
}

public enum AssistModelEligibilityError: LocalizedError, Equatable {
    case ineligibleModel(modelID: String, provider: String?)
    case noEligibleFreeModelAvailable(provider: String?)

    public var errorDescription: String? {
        switch self {
        case .ineligibleModel(let modelID, let provider):
            let provStr = provider.map { " on provider '\($0)'" } ?? ""
            return "Model '\(modelID)'\(provStr) is ineligible under the 'Only Use Free Models' policy. The model ID must contain 'free' (case-insensitive)."
        case .noEligibleFreeModelAvailable(let provider):
            let provStr = provider.map { " for provider '\($0)'" } ?? ""
            return "No eligible free model is available\(provStr). Please disable 'Only Use Free Models' or select a provider that offers free models."
        }
    }
}

public struct AssistModelEligibilityPolicy {
    public static func isEligible(modelID: String, onlyUseFreeModels: Bool) -> Bool {
        guard onlyUseFreeModels else { return true }
        let trimmed = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed.localizedCaseInsensitiveContains("free")
    }

    public static func validateExecutionEligibility(modelID: String, provider: String? = nil, onlyUseFreeModels: Bool) throws {
        guard onlyUseFreeModels else { return }
        if !isEligible(modelID: modelID, onlyUseFreeModels: true) {
            throw AssistModelEligibilityError.ineligibleModel(modelID: modelID, provider: provider)
        }
    }

    public static func filterEligibleModelIDs(_ modelIDs: [String], onlyUseFreeModels: Bool) -> [String] {
        guard onlyUseFreeModels else { return modelIDs }
        return modelIDs.filter { isEligible(modelID: $0, onlyUseFreeModels: true) }
    }

    public static func filterEligible<T>(_ models: [T], onlyUseFreeModels: Bool, idKeyPath: KeyPath<T, String>) -> [T] {
        guard onlyUseFreeModels else { return models }
        return models.filter { isEligible(modelID: $0[keyPath: idKeyPath], onlyUseFreeModels: true) }
    }

    public static func filterEligible<T>(_ models: [T], onlyUseFreeModels: Bool, idExtractor: (T) -> String) -> [T] {
        guard onlyUseFreeModels else { return models }
        return models.filter { isEligible(modelID: idExtractor($0), onlyUseFreeModels: true) }
    }
}

public struct HermesModelID: Equatable, Sendable {
    public let spec: String

    public var storedID: String { "hermes:\(spec)" }

    public var provider: String? {
        guard let colon = spec.firstIndex(of: ":") else { return nil }
        let value = String(spec[..<colon])
        return value.isEmpty ? nil : value
    }

    public var model: String {
        guard let colon = spec.firstIndex(of: ":") else { return spec }
        return String(spec[spec.index(after: colon)...])
    }

    public init(spec: String) {
        self.spec = spec
    }

    public static func parse(_ storedID: String) -> HermesModelID? {
        guard storedID.hasPrefix("hermes:") else { return nil }
        let spec = String(storedID.dropFirst("hermes:".count))
        guard !spec.isEmpty else { return nil }
        let parsed = HermesModelID(spec: spec)
        guard !parsed.model.isEmpty else { return nil }
        return parsed
    }

    public static func isHermesModelID(_ storedID: String) -> Bool {
        parse(storedID) != nil
    }
}

extension OpenCodeConfiguration {
    public init(settings: AssistantSettings) {
        let url = URL(string: settings.openCodeURL)
        self.init(
            serverURL: url ?? Self.defaultServerURL,
            agentName: settings.openCodeAgentName,
            managedServerEnabled: false
        )
    }

    public func apply(to settings: inout AssistantSettings) {
        settings.openCodeURL = serverURL.absoluteString
        settings.openCodeAgentName = agentName
    }
}

public enum AssistRoutingStrategy: String, Codable, Sendable, CaseIterable {
    case providerDefault = "default"
    case appModels = "app_models"

    public var displayName: String {
        switch self {
        case .providerDefault: "Provider default"
        case .appModels: "App model catalog"
        }
    }

    public static func lenient(_ raw: String?) -> AssistRoutingStrategy {
        guard let raw else { return .providerDefault }
        return AssistRoutingStrategy(rawValue: raw) ?? .providerDefault
    }
}

public typealias AssistModelSource = ModelSource

public struct AssistCandidateModel: Sendable, Equatable {
    public var id: String
    public var modelIdentifier: String
    public var displayName: String
    public var provider: ProviderKind
    public var capabilities: ModelCapabilities
    public var contextWindow: Int
    public var supportsStreaming: Bool
    public var supportsToolCalling: Bool
    public var supportsAgenticUse: Bool
    public var supportsSubagents: Bool
    public var supportsVision: Bool
    public var supportsStructuredOutput: Bool
    public var priority: Int
    public var isConfigured: Bool
    public var hasCredentials: Bool
    public var source: AssistModelSource
    public var statusDescription: String
    public var endpointURL: String?
    public var isSynthetic: Bool

    public init(
        id: String,
        displayName: String? = nil,
        provider: ProviderKind,
        modelIdentifier: String? = nil,
        capabilities: ModelCapabilities = .standardCloud,
        contextWindow: Int = 128_000,
        supportsStreaming: Bool = true,
        supportsToolCalling: Bool = true,
        supportsAgenticUse: Bool = true,
        supportsSubagents: Bool = false,
        supportsVision: Bool = false,
        supportsStructuredOutput: Bool = true,
        priority: Int = 10,
        isConfigured: Bool = true,
        hasCredentials: Bool = true,
        source: AssistModelSource = .provider,
        statusDescription: String = "",
        endpointURL: String? = nil,
        isSynthetic: Bool = false
    ) {
        self.id = id
        self.modelIdentifier = modelIdentifier ?? id
        self.displayName = displayName ?? id
        self.provider = provider
        self.capabilities = capabilities
        self.contextWindow = contextWindow
        self.supportsStreaming = supportsStreaming
        self.supportsToolCalling = supportsToolCalling
        self.supportsAgenticUse = supportsAgenticUse
        self.supportsSubagents = supportsSubagents
        self.supportsVision = supportsVision
        self.supportsStructuredOutput = supportsStructuredOutput
        self.priority = priority
        self.isConfigured = isConfigured
        self.hasCredentials = hasCredentials
        self.source = source
        self.statusDescription = statusDescription
        self.endpointURL = endpointURL
        self.isSynthetic = isSynthetic
    }

    public init(availableModel m: AssistAvailableModel) {
        self.id = m.id
        self.modelIdentifier = m.modelIdentifier
        self.displayName = m.displayName
        self.provider = ProviderKind(rawValue: m.providerID) ?? .gemini
        self.capabilities = m.capabilities
        self.contextWindow = 128_000
        self.supportsStreaming = m.supportsStreaming
        self.supportsToolCalling = m.supportsToolCalling
        self.supportsAgenticUse = m.supportsAgenticUse
        self.supportsSubagents = m.supportsSubagents
        self.supportsVision = m.supportsVision
        self.supportsStructuredOutput = m.supportsStructuredOutput
        self.priority = m.priority
        self.isConfigured = m.isConfigured
        self.hasCredentials = m.isConfigured
        self.source = m.source
        self.statusDescription = m.statusDescription
        self.endpointURL = nil
        self.isSynthetic = false
    }

    public static func fromSpecification(id: String) -> AssistCandidateModel {
        let spec = AssistModelSpecification.specification(for: id)
        let endpointURL: String?
        switch spec.provider {
        case .openRouter where id.lowercased().contains("mistral"):
            endpointURL = "https://api.mistral.ai/v1"
        case .codex:
            endpointURL = "http://localhost:3003/v1"
        default:
            endpointURL = nil
        }
        return AssistCandidateModel(
            id: id,
            displayName: spec.displayName,
            provider: spec.provider,
            modelIdentifier: id,
            capabilities: spec.capabilities,
            contextWindow: spec.contextWindowTokens,
            supportsStreaming: spec.capabilities.contains(.streaming),
            supportsToolCalling: spec.capabilities.contains(.toolCalling),
            supportsAgenticUse: spec.capabilities.contains(.toolCalling),
            supportsSubagents: spec.capabilities.contains(.subagents),
            supportsVision: spec.capabilities.contains(.vision),
            supportsStructuredOutput: spec.capabilities.contains(.structuredOutput),
            priority: 10,
            endpointURL: endpointURL
        )
    }
}
