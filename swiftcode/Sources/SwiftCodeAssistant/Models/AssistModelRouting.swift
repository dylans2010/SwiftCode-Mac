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

public enum AssistModelSource: String, Codable, Sendable {
    case provider
    case custom
    case cloud
    case foundation
}

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

public enum ModelRoutingFailureClass: String, Sendable {
    case rateLimited = "Rate Limited"
    case quotaExhausted = "Quota Exhausted"
    case authenticationFailed = "Authentication Failure"
    case modelUnavailable = "Model Unavailable"
    case providerUnavailable = "Provider Unavailable"
    case networkFailure = "Network Failure"
    case timeout = "Timeout"
    case unsupportedCapability = "Unsupported Capability"
    case malformedResponse = "Malformed Response"
    case internalAntigravityFailure = "Internal Antigravity Failure"
}

public struct ModelFailoverEvent: Identifiable, Sendable {
    public let id = UUID()
    public let timestamp = Date()
    public let failedModelID: String
    public let failedProviderID: String
    public let newModelID: String
    public let newProviderID: String
    public let failureClass: ModelRoutingFailureClass
    public let reason: String

    public init(
        failedModelID: String,
        failedProviderID: String,
        newModelID: String,
        newProviderID: String,
        failureClass: ModelRoutingFailureClass,
        reason: String
    ) {
        self.failedModelID = failedModelID
        self.failedProviderID = failedProviderID
        self.newModelID = newModelID
        self.newProviderID = newProviderID
        self.failureClass = failureClass
        self.reason = reason
    }
}

public actor AssistModelRouter {
    public static let shared = AssistModelRouter()
    public static let rateLimitQuarantine: TimeInterval = 60
    public static let authenticationQuarantine: TimeInterval = 600
    public static let unavailableQuarantine: TimeInterval = 120

    public init() {}

    public private(set) var quarantinedModels: [String: Date] = [:]
    public private(set) var failedAttemptsCount: [String: Int] = [:]
    public private(set) var lastFailoverEvent: ModelFailoverEvent?
    public private(set) var failoverHistory: [ModelFailoverEvent] = []

    public static func resolveDefaultModel(
        preferredID: String,
        discovered: [AssistCandidateModel],
        useCloudModel: Bool,
        cloudConfigured: Bool = false,
        cloudRemainingToday: Int = SCCloudProvider.dailyRequestLimit,
        cloudModels: [AssistCandidateModel] = []
    ) -> AssistCandidateModel {
        if useCloudModel, SCCloudProvider.isCloudModelID(preferredID) {
            return syntheticCloudModel(
                forCloudModelID: preferredID,
                remainingToday: cloudRemainingToday,
                isConfigured: cloudConfigured,
                firstDiscoveredEndpointName: cloudModels.first?.modelIdentifier
            )
        }
        if let match = discovered.first(where: { $0.id == preferredID || $0.modelIdentifier == preferredID }) {
            return match
        }
        if preferredID.lowercased().contains("afm") {
            return syntheticFoundationModel(id: preferredID)
        }
        return AssistCandidateModel.fromSpecification(id: preferredID)
    }

    public func resolveSavedModel(from eligible: [AssistCandidateModel]) -> AssistCandidateModel? {
        eligible.first
    }

    public static func selectNextModel(excluding: Set<String>, from candidates: [AssistCandidateModel]) -> AssistCandidateModel? {
        candidates.first { !excluding.contains($0.id) && !excluding.contains($0.modelIdentifier) }
    }

    public func eligibleCandidates(
        from allModels: [AssistCandidateModel],
        strategy: AssistRoutingStrategy,
        useProviderModelsOnly: Bool,
        useCloudModel: Bool,
        cloudModels: [AssistCandidateModel] = [],
        cloudConfigured: Bool = false,
        cloudRemainingToday: Int = SCCloudProvider.dailyRequestLimit
    ) -> [AssistCandidateModel] {
        _ = strategy
        let eligible = allModels.filter { model in
            guard model.supportsAgenticUse && model.supportsToolCalling else { return false }
            if useProviderModelsOnly, Self.isUserProvidedModel(model) { return false }
            guard model.isConfigured, model.hasCredentials else { return false }
            if let unquarantine = quarantinedModels[model.id], Date() < unquarantine { return false }
            if let unquarantine = quarantinedModels[model.modelIdentifier], Date() < unquarantine { return false }
            return true
        }

        var ranked = Self.rankModels(eligible)
        if useCloudModel {
            ranked.removeAll { SCCloudProvider.isCloudModelID($0.id) }
            if cloudModels.isEmpty {
                ranked.append(Self.syntheticCloudModel(
                    forCloudModelID: SCCloudProvider.internalIDPrefix,
                    remainingToday: cloudRemainingToday,
                    isConfigured: cloudConfigured
                ))
            } else {
                for info in cloudModels {
                    ranked.append(Self.syntheticCloudModel(
                        forCloudModelID: info.id,
                        remainingToday: cloudRemainingToday,
                        isConfigured: cloudConfigured,
                        firstDiscoveredEndpointName: info.modelIdentifier
                    ))
                }
            }
        }
        return ranked
    }

    public static func syntheticCloudModel(
        forCloudModelID cloudModelID: String,
        remainingToday: Int,
        isConfigured: Bool = false,
        firstDiscoveredEndpointName: String? = nil
    ) -> AssistCandidateModel {
        let endpointName = SCCloudProvider.endpointName(forInternalID: cloudModelID)
            ?? firstDiscoveredEndpointName
            ?? ""
        let displayName = endpointName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? SCCloudProvider.displayNameFallback
            : endpointName
        return AssistCandidateModel(
            id: cloudModelID,
            displayName: displayName,
            provider: .scCloud,
            modelIdentifier: endpointName,
            capabilities: [.structuredOutput, .systemInstructions, .codeGeneration, .largeContext],
            contextWindow: 128_000,
            supportsStreaming: false,
            supportsToolCalling: false,
            supportsAgenticUse: false,
            supportsSubagents: false,
            supportsVision: false,
            supportsStructuredOutput: true,
            priority: 1,
            isConfigured: isConfigured,
            hasCredentials: true,
            source: .cloud,
            statusDescription: "SwiftCode Cloud · \(remainingToday)/\(SCCloudProvider.dailyRequestLimit) left today"
        )
    }

    public static func syntheticFoundationModel(id: String) -> AssistCandidateModel {
        AssistCandidateModel(
            id: id,
            displayName: "Apple \(id) (On-Device)",
            provider: .foundationModels,
            modelIdentifier: id,
            capabilities: .localFoundation,
            contextWindow: 16_000,
            supportsStreaming: true,
            supportsToolCalling: false,
            supportsAgenticUse: false,
            supportsSubagents: false,
            supportsVision: id.contains("Advanced"),
            supportsStructuredOutput: true,
            priority: 90,
            isConfigured: true,
            hasCredentials: true,
            source: .foundation,
            statusDescription: "On-Device Available (Chat Mode Only)"
        )
    }

    public static func rankModels(_ models: [AssistCandidateModel], preferredIdentifier: String? = nil) -> [AssistCandidateModel] {
        rankModels(models: models, preferredIdentifier: preferredIdentifier, failedAttemptsCount: [:])
    }

    public static func rankModels(
        models: [AssistCandidateModel],
        preferredIdentifier: String?,
        failedAttemptsCount: [String: Int]
    ) -> [AssistCandidateModel] {
        models.sorted { lhs, rhs in
            let lhsIsPref = (lhs.id == preferredIdentifier || lhs.modelIdentifier == preferredIdentifier)
            let rhsIsPref = (rhs.id == preferredIdentifier || rhs.modelIdentifier == preferredIdentifier)
            if lhsIsPref != rhsIsPref { return lhsIsPref }

            let lhsFailures = failedAttemptsCount[lhs.id] ?? 0
            let rhsFailures = failedAttemptsCount[rhs.id] ?? 0
            if lhsFailures != rhsFailures { return lhsFailures < rhsFailures }

            if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }

            if lhs.supportsSubagents != rhs.supportsSubagents { return lhs.supportsSubagents }

            return lhs.contextWindow > rhs.contextWindow
        }
    }

    public func ranked(_ models: [AssistCandidateModel], preferredIdentifier: String? = nil) -> [AssistCandidateModel] {
        Self.rankModels(models: models, preferredIdentifier: preferredIdentifier, failedAttemptsCount: failedAttemptsCount)
    }

    public static func isQuotaOrRateLimit(errorText: String) -> Bool {
        let desc = errorText.lowercased()
        return desc.contains("429") || desc.contains("resource_exhausted") || desc.contains("quota exceeded")
            || desc.contains("rate limit") || desc.contains("rate_limit") || desc.contains("too many requests")
    }

    public func isModelQuarantined(modelIdentifier: String) -> Bool {
        if let unquarantine = quarantinedModels[modelIdentifier], Date() < unquarantine { return true }
        return false
    }

    public static func classify(error: Error) -> ModelRoutingFailureClass {
        let desc = error.localizedDescription.lowercased()

        if isQuotaOrRateLimit(errorText: desc) {
            return .quotaExhausted
        }

        if desc.contains("401") || desc.contains("403") || desc.contains("invalid api key")
            || desc.contains("authentication") || desc.contains("unauthorized") {
            return .authenticationFailed
        }

        if desc.contains("timed out") || desc.contains("timeout") {
            return .timeout
        }

        if desc.contains("network") || desc.contains("cannot connect") || desc.contains("connection refused") {
            return .networkFailure
        }

        if desc.contains("model not found") || desc.contains("does not exist") || desc.contains("404") {
            return .modelUnavailable
        }

        if desc.contains("500") || desc.contains("502") || desc.contains("503") || desc.contains("504") || desc.contains("overloaded") {
            return .providerUnavailable
        }

        return .internalAntigravityFailure
    }

    public func markRateLimited(modelID: String, retryAfter: TimeInterval? = nil) {
        let duration = retryAfter ?? Self.rateLimitQuarantine
        quarantinedModels[modelID] = Date().addingTimeInterval(duration)
    }

    public func markAuthenticationFailed(modelID: String) {
        quarantinedModels[modelID] = Date().addingTimeInterval(Self.authenticationQuarantine)
    }

    public func markModelUnavailable(modelID: String, reason: String) {
        failedAttemptsCount[modelID, default: 0] += 1
        quarantinedModels[modelID] = Date().addingTimeInterval(Self.unavailableQuarantine)
    }

    public func markModelHealthy(modelID: String) {
        quarantinedModels.removeValue(forKey: modelID)
        failedAttemptsCount.removeValue(forKey: modelID)
    }

    public func clearAllQuarantines() {
        quarantinedModels.removeAll()
        failedAttemptsCount.removeAll()
    }

    public static func buildContinuationPrompt(originalPrompt: String, priorTurnOutput: String, failedModelName: String) -> String {
        var handoff = "CONTINUATION DIRECTIVE:\n"
        handoff += "The previous model (\(failedModelName)) encountered an interruption or rate limit and failed.\n"
        if !priorTurnOutput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            handoff += "\nPartial response from previous model:\n\"\"\"\n\(priorTurnOutput)\n\"\"\"\n"
            handoff += "DO NOT repeat or overwrite work that has already been successfully accomplished.\n"
        }
        handoff += "\nOriginal Objective:\n\(originalPrompt)\n"
        handoff += "\nINSTRUCTION: Inspect the repository's current disk state and continue fulfilling the user's objective without repeating already completed work."
        return handoff
    }

    public static func isUserProvidedModel(_ model: AssistCandidateModel) -> Bool {
        model.source == .custom
    }

    public static func isUserProvidedSelectedModelID(
        _ selectedID: String,
        discovered: AssistCandidateModel?,
        customModelID: String
    ) -> Bool {
        if let discovered {
            return isUserProvidedModel(discovered)
        }
        let trimmed = selectedID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if SCCloudProvider.isCloudModelID(trimmed) { return false }
        if HermesModelID.isHermesModelID(trimmed) { return false }
        if OpenCodeModelID.isOpenCodeModelID(trimmed) { return false }
        return trimmed == customModelID && !customModelID.isEmpty
    }

    public func handleTurnFailure(
        failedModel: AssistCandidateModel,
        error: Error,
        completedTurnContent: String,
        executedToolsCount: Int,
        objective: String = "",
        automaticallySwitchModels: Bool,
        eligibleCandidates: [AssistCandidateModel]
    ) -> (nextModel: AssistCandidateModel, continuationPrompt: String)? {
        let failureClass = Self.classify(error: error)

        switch failureClass {
        case .rateLimited, .quotaExhausted:
            markRateLimited(modelID: failedModel.id)
            markRateLimited(modelID: failedModel.modelIdentifier)
        case .authenticationFailed:
            markAuthenticationFailed(modelID: failedModel.id)
            markAuthenticationFailed(modelID: failedModel.modelIdentifier)
        default:
            markModelUnavailable(modelID: failedModel.id, reason: error.localizedDescription)
            markModelUnavailable(modelID: failedModel.modelIdentifier, reason: error.localizedDescription)
        }

        guard automaticallySwitchModels else { return nil }

        var excluding = Set<String>()
        excluding.insert(failedModel.id)
        excluding.insert(failedModel.modelIdentifier)

        if failureClass == .quotaExhausted || failureClass == .authenticationFailed {
            for m in eligibleCandidates where m.provider == failedModel.provider {
                excluding.insert(m.id)
                excluding.insert(m.modelIdentifier)
            }
        }

        guard let nextModel = Self.selectNextModel(excluding: excluding, from: eligibleCandidates) else {
            return nil
        }

        let reasonString = error.localizedDescription.isEmpty ? failureClass.rawValue : error.localizedDescription
        let event = ModelFailoverEvent(
            failedModelID: failedModel.modelIdentifier,
            failedProviderID: failedModel.provider.displayName,
            newModelID: nextModel.modelIdentifier,
            newProviderID: nextModel.provider.displayName,
            failureClass: failureClass,
            reason: reasonString
        )
        lastFailoverEvent = event
        failoverHistory.append(event)

        var handoff = "CONTINUATION DIRECTIVE:\n"
        handoff += "The previous model (\(failedModel.displayName)) encountered a \(failureClass.rawValue) and failed.\n"
        if executedToolsCount > 0 {
            handoff += "Previous actions executed \(executedToolsCount) tool calls. All files modified on disk remain intact.\n"
        }
        if !completedTurnContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            handoff += "\nPartial response from previous model:\n\"\"\"\n\(completedTurnContent)\n\"\"\"\n"
        }
        handoff += "\nINSTRUCTION: Inspect the repository's current disk state and continue fulfilling the user's objective without repeating already completed work."

        return (nextModel, handoff)
    }
}
