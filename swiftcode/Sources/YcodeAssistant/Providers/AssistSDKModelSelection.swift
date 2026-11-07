import Foundation

public struct SDKSessionConfiguration: Sendable, Equatable {
    public var model: String
    public var provider: ProviderKind
    public var thinkingLevel: String?
    public var enableSubagents: Bool
    public var executionMode: String?
    public var hasAPIKey: Bool
    public var isOAuthAuthenticated: Bool
    public var baseURL: String?

    public init(
        model: String,
        provider: ProviderKind,
        thinkingLevel: String? = nil,
        enableSubagents: Bool = true,
        executionMode: String? = nil,
        hasAPIKey: Bool = false,
        isOAuthAuthenticated: Bool = false,
        baseURL: String? = nil
    ) {
        self.model = model
        self.provider = provider
        self.thinkingLevel = thinkingLevel
        self.enableSubagents = enableSubagents
        self.executionMode = executionMode
        self.hasAPIKey = hasAPIKey
        self.isOAuthAuthenticated = isOAuthAuthenticated
        self.baseURL = baseURL
    }
}

public enum SDKSessionConfigurationBuilder {
    public static func build(
        for model: AssistCandidateModel,
        objective: String = "",
        isGoogleOAuthAuthenticated: Bool = false,
        alternativeKeysEnabled: Bool = false,
        isAntigravityCatalogModel: Bool = false
    ) -> SDKSessionConfiguration {
        _ = objective
        let lowerID = model.modelIdentifier.lowercased()
        let isGoogleProvider = lowerID.contains("gemini") || model.id.lowercased().contains("gemini")
        let hasDirectKey = model.hasCredentials
        let derivedLevel = AntigravitySDKCatalog.deriveThinkingLevel(modelID: model.modelIdentifier, displayName: model.displayName)

        let executionMode: String?
        let oauth: Bool
        if isGoogleOAuthAuthenticated && (isGoogleProvider || isAntigravityCatalogModel || !hasDirectKey) {
            executionMode = "antigravity"
            oauth = true
        } else if isGoogleProvider && alternativeKeysEnabled {
            executionMode = "api_key"
            oauth = false
        } else {
            executionMode = hasDirectKey ? "api_key" : (isGoogleOAuthAuthenticated ? "antigravity" : nil)
            oauth = executionMode == "antigravity"
        }

        return SDKSessionConfiguration(
            model: model.modelIdentifier,
            provider: model.provider,
            thinkingLevel: derivedLevel,
            enableSubagents: model.supportsSubagents,
            executionMode: executionMode,
            hasAPIKey: executionMode == "api_key" && hasDirectKey,
            isOAuthAuthenticated: oauth,
            baseURL: model.endpointURL
        )
    }
}

extension AssistModelRouter {
    public func selectModelForSDK(
        objective: String = "",
        preferredID: String,
        strategy: AssistRoutingStrategy,
        candidates: [AssistCandidateModel],
        useCloudModel: Bool,
        cloudConfigured: Bool = false,
        cloudRemainingToday: Int = SCCloudProvider.dailyRequestLimit,
        cloudModels: [AssistCandidateModel] = [],
        catalog: AntigravitySDKCatalog,
        isGoogleOAuthAuthenticated: Bool = false,
        alternativeKeysEnabled: Bool = false
    ) async -> (model: AssistCandidateModel, config: SDKSessionConfiguration) {
        if useCloudModel, SCCloudProvider.isCloudModelID(preferredID) {
            let cloudModel = Self.syntheticCloudModel(
                forCloudModelID: preferredID,
                remainingToday: cloudRemainingToday,
                isConfigured: cloudConfigured,
                firstDiscoveredEndpointName: cloudModels.first?.modelIdentifier
            )
            let config = SDKSessionConfigurationBuilder.build(
                for: cloudModel,
                objective: objective,
                isGoogleOAuthAuthenticated: isGoogleOAuthAuthenticated,
                alternativeKeysEnabled: alternativeKeysEnabled
            )
            return (cloudModel, config)
        }

        let targetModel: AssistCandidateModel
        switch strategy {
        case .providerDefault:
            let catalogIDs = await catalog.sdkDefaultModelIDs
            let validIds = catalogIDs.filter { id in
                candidates.contains { ($0.id == id || $0.modelIdentifier == id) && $0.isConfigured }
                    || isGoogleOAuthAuthenticated
            }
            let lowerPreferred = preferredID.lowercased()
            let isExplicitCustomOrThirdParty = preferredID.contains("/")
                || lowerPreferred.contains("ollama") || lowerPreferred.contains("llama")
                || lowerPreferred.contains("claude") || lowerPreferred.contains("gpt")
            let effectiveModelID: String
            if isExplicitCustomOrThirdParty || validIds.contains(preferredID) {
                effectiveModelID = preferredID
            } else if let first = validIds.first {
                effectiveModelID = first
            } else {
                effectiveModelID = preferredID
            }
            if await catalog.getModel(byID: effectiveModelID) != nil {
                targetModel = await catalog.createSyntheticCandidate(
                    modelID: effectiveModelID,
                    isConfigured: validIds.contains(effectiveModelID) || isGoogleOAuthAuthenticated
                )
            } else if let match = candidates.first(where: { $0.id == effectiveModelID || $0.modelIdentifier == effectiveModelID }) {
                targetModel = match
            } else if isExplicitCustomOrThirdParty {
                targetModel = await catalog.createSyntheticCandidate(modelID: effectiveModelID, isConfigured: false)
            } else if let first = candidates.first {
                targetModel = first
            } else {
                targetModel = await catalog.createSyntheticCandidate(modelID: effectiveModelID, isConfigured: false)
            }
        case .appModels:
            if let match = candidates.first(where: { $0.id == preferredID || $0.modelIdentifier == preferredID }) {
                targetModel = match
            } else if let first = candidates.first {
                targetModel = first
            } else {
                targetModel = Self.resolveDefaultModel(
                    preferredID: preferredID,
                    discovered: candidates,
                    useCloudModel: useCloudModel,
                    cloudConfigured: cloudConfigured,
                    cloudRemainingToday: cloudRemainingToday,
                    cloudModels: cloudModels
                )
            }
        }

        let isCatalog = await catalog.isAntigravityCatalogModel(targetModel.modelIdentifier)
        let config = SDKSessionConfigurationBuilder.build(
            for: targetModel,
            objective: objective,
            isGoogleOAuthAuthenticated: isGoogleOAuthAuthenticated,
            alternativeKeysEnabled: alternativeKeysEnabled,
            isAntigravityCatalogModel: isCatalog
        )
        return (targetModel, config)
    }

    public func handleTurnFailureWithKeyRotation(
        failedModel: AssistCandidateModel,
        error: Error,
        completedTurnContent: String,
        executedToolsCount: Int,
        objective: String = "",
        automaticallySwitchModels: Bool,
        eligibleCandidates: [AssistCandidateModel],
        keyRotation: GeminiKeyRotationManager?,
        alternativeKeysEnabled: Bool,
        isGoogleOAuthAuthenticated: Bool = false
    ) async -> (nextModel: AssistCandidateModel, continuationPrompt: String, keyRotated: Bool, config: SDKSessionConfiguration)? {
        let failureClass = Self.classify(error: error)
        if alternativeKeysEnabled, let rotation = keyRotation,
           failureClass == .rateLimited || failureClass == .quotaExhausted {
            if let activeId = await rotation.activeKeyId {
                await rotation.markRateLimited(id: activeId, retryAfterSeconds: 60)
            }
            if let nextKeyInfo = await rotation.selectNextAvailableKey() {
                markRateLimited(modelID: failedModel.id)
                markRateLimited(modelID: failedModel.modelIdentifier)
                let config = SDKSessionConfigurationBuilder.build(
                    for: failedModel,
                    objective: objective,
                    isGoogleOAuthAuthenticated: isGoogleOAuthAuthenticated,
                    alternativeKeysEnabled: alternativeKeysEnabled,
                    isAntigravityCatalogModel: false
                )
                var handoff = "CONTINUATION DIRECTIVE:\nRotated to next Gemini API key (\(nextKeyInfo.metadata.maskedValue)) due to rate limit.\n\n"
                if !completedTurnContent.isEmpty {
                    handoff += "Partial output:\n\"\"\"\n\(completedTurnContent)\n\"\"\"\n\n"
                }
                handoff += "Continue fulfilling the objective without repeating already completed work."
                return (failedModel, handoff, true, config)
            }
        }

        guard let result = handleTurnFailure(
            failedModel: failedModel,
            error: error,
            completedTurnContent: completedTurnContent,
            executedToolsCount: executedToolsCount,
            objective: objective,
            automaticallySwitchModels: automaticallySwitchModels,
            eligibleCandidates: eligibleCandidates
        ) else {
            return nil
        }
        let config = SDKSessionConfigurationBuilder.build(
            for: result.nextModel,
            objective: objective,
            isGoogleOAuthAuthenticated: isGoogleOAuthAuthenticated,
            alternativeKeysEnabled: alternativeKeysEnabled,
            isAntigravityCatalogModel: false
        )
        return (result.nextModel, result.continuationPrompt, false, config)
    }
}
