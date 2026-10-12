//
//  AssistModelRouter.swift
//  SwiftCode
//
//  Intelligent, fault-tolerant model routing and automatic failover engine for Assist and Antigravity.
//

import Foundation
import os

private let logger = Logger(subsystem: "com.swiftcode.Assist", category: "ModelRouter")

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
}

@Observable
@MainActor
public final class AssistModelRouter: Sendable {
    public static let shared = AssistModelRouter()

    public var currentRuntimeModel: AssistAvailableModel?
    public var lastFailoverEvent: ModelFailoverEvent?
    public var failoverHistory: [ModelFailoverEvent] = []
    public var quarantinedModels: [String: Date] = [:] // modelId -> unquarantineDate
    public var failedAttemptsCount: [String: Int] = [:]

    private init() {}

    // MARK: - Model Selection & Ranking

    public func resolveCapabilities(for modelId: String) -> ModelCapabilities {
        return AgentModelAdapter.shared.specification(for: modelId).capabilities
    }

    public func resolveDefaultModel() async -> AssistAvailableModel {
        let preferredID = AppSettings.shared.selectedAssistModelID
        // Model discovery is an optional metadata refresh, not a prerequisite
        // for dispatching a request. The selected model's provider and
        // capabilities are already known locally, so never hold a normal
        // Assist turn behind slow/unreachable provider model-list endpoints.
        let all = AssistModelDiscoveryService.shared.discoveredModels
        if let match = all.first(where: { $0.id == preferredID || $0.modelIdentifier == preferredID }) {
            return match
        }

        if preferredID == AppleFoundationModel.afm3Core.rawValue || preferredID == AppleFoundationModel.afm3CoreAdvanced.rawValue || preferredID.lowercased().contains("afm") {
            return AssistAvailableModel(
                id: preferredID,
                displayName: "Apple \(preferredID) (On-Device)",
                providerID: "apple",
                providerName: "Apple Foundation Models",
                modelIdentifier: preferredID,
                capabilities: .localFoundation,
                source: .appleFoundation,
                isConfigured: true,
                isAvailable: true,
                supportsStreaming: true,
                supportsToolCalling: false,
                supportsVision: preferredID.contains("Advanced"),
                supportsStructuredOutput: true,
                supportsAgenticUse: false,
                supportsSubagents: false,
                priority: 90,
                statusDescription: "On-Device Available (Chat Mode Only)",
                status: .available,
                contextWindow: 16_000
            )
        }

        let spec = AgentModelAdapter.shared.specification(for: preferredID)
        let providerID: String
        let providerName: String
        let source: AssistModelSource
        var endpointURL: String? = nil

        switch spec.provider {
        case .anthropic:
            providerID = "anthropic"
            providerName = "Claude"
            source = .claude
        case .openAI:
            providerID = "openai"
            providerName = "OpenAI"
            source = .openAI
        case .gemini:
            providerID = "google"
            providerName = "Gemini"
            source = .gemini
        case .mistral:
            providerID = "mistral"
            providerName = "Mistral"
            source = .openRouter
            endpointURL = "https://api.mistral.ai/v1"
        case .openRouter:
            providerID = "openrouter"
            providerName = "OpenRouter"
            source = .openRouter
        case .codex:
            providerID = "codex"
            providerName = "Codex"
            source = .openRouter
            endpointURL = "http://localhost:3003/v1"
        default:
            providerID = spec.provider.rawValue.lowercased()
            providerName = spec.provider.rawValue
            source = .openRouter
        }

        return AssistAvailableModel(
            id: preferredID,
            displayName: spec.displayName,
            providerID: providerID,
            providerName: providerName,
            modelIdentifier: preferredID,
            capabilities: spec.capabilities,
            source: source,
            isConfigured: true,
            isAvailable: true,
            supportsStreaming: spec.capabilities.contains(.streaming),
            supportsToolCalling: spec.capabilities.contains(.toolCalling),
            supportsVision: spec.capabilities.contains(.vision),
            supportsStructuredOutput: spec.capabilities.contains(.structuredOutput),
            supportsAgenticUse: spec.capabilities.contains(.toolCalling),
            supportsSubagents: spec.capabilities.contains(.subagents),
            priority: 10,
            contextWindow: spec.contextWindowTokens,
            endpointURL: endpointURL
        )
    }

    // MARK: - SDK Default Model Identifiers (Dynamically Fetched from Antigravity SDK)
    public static var sdkDefaultModelIDs: [String] {
        let list = AntigravitySDKModelFetcher.shared.allModelIDs
        if !list.isEmpty {
            return list
        }
        return AntigravitySDKModelFetcher.seedModels.map { $0.id }
    }

    public func resolveSavedModel() async -> AssistAvailableModel? {
        let candidates = await getEligibleCandidates()
        return candidates.first
    }

    public func selectModelForSDK(objective: String = "") async -> (model: AssistAvailableModel, config: GoogleCloudSDKConfiguration)? {
        let strategy = AppSettings.shared.assistModelRoutingStrategy
        let selectedId = AppSettings.shared.selectedAssistModelID

        let targetModel: AssistAvailableModel

        switch strategy {
        case "default", "rotation":
            // Antigravity SDK Default / Gemini Key Rotation: ONLY use models
            // listed in the SDK, NOTHING ELSE. ("rotation" additionally rotates
            // API keys; the model-selection contract is identical.)
            //
            // Hot-path fast path: the SDK's own model registry (fetched live
            // from the Antigravity SDK at startup, in-memory afterwards) is
            // the authoritative source for SDK models. When it confirms the
            // effective model, resolve it directly instead of running the
            // full multi-provider network discovery (getEligibleCandidates)
            // on every request — that discovery exists to populate the model
            // picker UI, not to re-validate an already-confirmed SDK model,
            // and its cold-cache cost is the dominant "Preparing request…"
            // delay.
            let validIds = Self.sdkDefaultModelIDs
            let effectiveModelID: String
            if validIds.contains(selectedId) {
                effectiveModelID = selectedId
            } else if let first = validIds.first {
                effectiveModelID = first
            } else {
                effectiveModelID = selectedId
            }
            if AntigravitySDKModelFetcher.shared.getModel(byID: effectiveModelID) != nil {
                targetModel = createSyntheticSDKModel(modelID: effectiveModelID)
            } else {
                // Registry does not know this model (stale selection or SDK
                // fetch not completed): fall back to the full discovery path
                // so a live candidate can still be found.
                let candidates = await getEligibleCandidates()
                if let match = candidates.first(where: { $0.id == effectiveModelID || $0.modelIdentifier == effectiveModelID }) {
                    targetModel = match
                } else if let firstSdk = candidates.first {
                    targetModel = firstSdk
                } else {
                    targetModel = createSyntheticSDKModel(modelID: effectiveModelID)
                }
            }

        case "app_models":
            // App Model Catalog: try ALL the models that will be on the Available Models card.
            let discovery = AssistModelDiscoveryService.shared
            let cachedCandidates = eligibleCandidates(from: discovery.discoveredModels)
            if let match = cachedCandidates.first(where: { $0.id == selectedId || $0.modelIdentifier == selectedId }) {
                targetModel = match
            } else {
                let candidates: [AssistAvailableModel]
                if discovery.hasFreshDiscoveryCache {
                    candidates = cachedCandidates
                } else {
                    candidates = await getEligibleCandidates()
                }
                if let best = candidates.first {
                    targetModel = best
                } else {
                    targetModel = await resolveDefaultModel()
                }
            }

        default:
            targetModel = await resolveDefaultModel()
        }

        self.currentRuntimeModel = targetModel
        let config = buildSDKConfiguration(for: targetModel, objective: objective)
        return (targetModel, config)
    }

    public func selectNextModel(excluding: Set<String>) async -> AssistAvailableModel? {
        let candidates = await getEligibleCandidates()
        let filtered = candidates.filter { !excluding.contains($0.id) && !excluding.contains($0.modelIdentifier) }
        return filtered.first
    }

    public func getEligibleCandidates() async -> [AssistAvailableModel] {
        let allModels = await AssistModelDiscoveryService.shared.discoverAllModels()
        return eligibleCandidates(from: allModels)
    }

    private func eligibleCandidates(from allModels: [AssistAvailableModel]) -> [AssistAvailableModel] {
        let strategy = AppSettings.shared.assistModelRoutingStrategy

        var baseModels: [AssistAvailableModel]
        if strategy == "default" || strategy == "rotation" {
            // STRICT SDK ONLY: Restrict exclusively to models listed in the SDK
            let filtered = allModels.filter { model in
                Self.sdkDefaultModelIDs.contains(model.modelIdentifier) || Self.sdkDefaultModelIDs.contains(model.id)
            }
            if filtered.isEmpty {
                // Ensure default SDK models are always present even before provider sync completes
                baseModels = Self.sdkDefaultModelIDs.map { createSyntheticSDKModel(modelID: $0) }
            } else {
                // Ensure all filtered SDK default models are marked as configured and agentic
                baseModels = filtered.map { model in
                    if model.isConfigured && model.supportsAgenticUse && model.supportsToolCalling {
                        return model
                    }
                    return AssistAvailableModel(
                        id: model.id,
                        displayName: model.displayName,
                        providerID: model.providerID,
                        providerName: model.providerName,
                        modelIdentifier: model.modelIdentifier,
                        capabilities: model.capabilities.union([.streaming, .toolCalling, .vision, .structuredOutput, .subagents]),
                        source: model.source,
                        isConfigured: true,
                        isAvailable: true,
                        supportsStreaming: model.supportsStreaming,
                        supportsToolCalling: true,
                        supportsVision: model.supportsVision,
                        supportsStructuredOutput: model.supportsStructuredOutput,
                        supportsAgenticUse: true,
                        supportsSubagents: model.supportsSubagents,
                        priority: model.priority,
                        statusDescription: model.statusDescription,
                        status: .available,
                        contextWindow: model.contextWindow,
                        endpointURL: model.endpointURL
                    )
                }
            }
        } else {
            // App Model Catalog: try ALL models from the Available Models card
            baseModels = allModels
        }

        // Filter: must support agentic use and tool calling, must be configured, must not be quarantined
        let eligible = baseModels.filter { model in
            guard model.supportsAgenticUse && model.supportsToolCalling else { return false }
            guard model.isConfigured else { return false }

            // Check quarantine
            if let unquarantine = quarantinedModels[model.id], Date() < unquarantine {
                return false
            }
            if let unquarantine = quarantinedModels[model.modelIdentifier], Date() < unquarantine {
                return false
            }

            return true
        }

        return rankModels(eligible)
    }

    public func createSyntheticSDKModel(modelID: String) -> AssistAvailableModel {
        if let sdkModel = AntigravitySDKModelFetcher.shared.getModel(byID: modelID) {
            return AssistAvailableModel(
                id: sdkModel.id,
                displayName: sdkModel.displayName,
                providerID: sdkModel.category.lowercased(),
                providerName: sdkModel.category == "Google" ? "Google" : sdkModel.category,
                modelIdentifier: sdkModel.id,
                capabilities: [.streaming, .toolCalling, .vision, .structuredOutput, .subagents],
                source: .gemini,
                isConfigured: true,
                isAvailable: true,
                supportsStreaming: true,
                supportsToolCalling: true,
                supportsVision: true,
                supportsStructuredOutput: true,
                supportsAgenticUse: true,
                supportsSubagents: !sdkModel.isImageModel,
                priority: 1,
                statusDescription: "\(sdkModel.thinkingLevel) Thinking",
                status: .available,
                contextWindow: sdkModel.contextWindow
            )
        }

        let level = AntigravitySDKModelFetcher.deriveThinkingLevel(modelID: modelID, displayName: modelID)
        let contextWindow = AntigravitySDKModelFetcher.deriveContextWindow(modelID: modelID)
        let category = AntigravitySDKModelFetcher.deriveCategory(modelID: modelID)

        let formattedName = modelID
            .split(separator: "-")
            .map { $0.capitalized }
            .joined(separator: " ")

        return AssistAvailableModel(
            id: modelID,
            displayName: "\(formattedName) (\(level))",
            providerID: category.lowercased(),
            providerName: category == "Google" ? "Google" : category,
            modelIdentifier: modelID,
            capabilities: [.streaming, .toolCalling, .vision, .structuredOutput, .subagents],
            source: .gemini,
            isConfigured: true,
            isAvailable: true,
            supportsStreaming: true,
            supportsToolCalling: true,
            supportsVision: true,
            supportsStructuredOutput: true,
            supportsAgenticUse: true,
            supportsSubagents: !modelID.contains("image"),
            priority: 5,
            statusDescription: "\(level) Thinking",
            status: .available,
            contextWindow: contextWindow
        )
    }

    public var availableCandidates: [AssistAvailableModel] {
        get async {
            await getEligibleCandidates()
        }
    }

    public func rankModels(_ models: [AssistAvailableModel]) -> [AssistAvailableModel] {
        rankModels(models: models, preferredIdentifier: nil)
    }

    public func rankModels(models: [AssistAvailableModel], preferredIdentifier: String? = nil) -> [AssistAvailableModel] {
        let preferredID = preferredIdentifier ?? AppSettings.shared.selectedAssistModelID

        return models.sorted { lhs, rhs in
            // 1. User preferred model always gets top priority if available
            let lhsIsPref = (lhs.id == preferredID || lhs.modelIdentifier == preferredID)
            let rhsIsPref = (rhs.id == preferredID || rhs.modelIdentifier == preferredID)
            if lhsIsPref != rhsIsPref {
                return lhsIsPref
            }

            // 2. Failure penalty: models with fewer failures rank higher
            let lhsFailures = failedAttemptsCount[lhs.id] ?? 0
            let rhsFailures = failedAttemptsCount[rhs.id] ?? 0
            if lhsFailures != rhsFailures {
                return lhsFailures < rhsFailures
            }

            // 3. Provider priority & model priority
            if lhs.priority != rhs.priority {
                return lhs.priority < rhs.priority
            }

            // 4. Subagent capability
            if lhs.supportsSubagents != rhs.supportsSubagents {
                return lhs.supportsSubagents
            }

            // 5. Context window
            return lhs.contextWindow > rhs.contextWindow
        }
    }

    // MARK: - Failure Classification & Quarantine

    public func isQuotaOrRateLimit(errorText: String) -> Bool {
        let desc = errorText.lowercased()
        return desc.contains("429") || desc.contains("resource_exhausted") || desc.contains("quota exceeded") || desc.contains("rate limit") || desc.contains("rate_limit") || desc.contains("too many requests")
    }

    public func isModelQuarantined(modelIdentifier: String) -> Bool {
        if let unquarantine = quarantinedModels[modelIdentifier], Date() < unquarantine {
            return true
        }
        return false
    }

    public func classify(error: Error) -> ModelRoutingFailureClass {
        let desc = error.localizedDescription.lowercased()
        let nsError = error as NSError

        if isQuotaOrRateLimit(errorText: desc) {
            return .quotaExhausted
        }

        if desc.contains("401") || desc.contains("403") || desc.contains("invalid api key") || desc.contains("authentication") || desc.contains("unauthorized") {
            return .authenticationFailed
        }

        if nsError.domain == NSURLErrorDomain && (nsError.code == NSURLErrorTimedOut) || desc.contains("timed out") || desc.contains("timeout") {
            return .timeout
        }

        if nsError.domain == NSURLErrorDomain || desc.contains("network") || desc.contains("cannot connect") || desc.contains("connection refused") {
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
        let duration = retryAfter ?? 60.0 // Default 60s quarantine for 429
        let until = Date().addingTimeInterval(duration)
        quarantinedModels[modelID] = until
        logger.warning("[ModelRouter] Quarantined model '\(modelID)' until \(until) due to rate limit/quota.")
    }

    public func markRateLimited(modelIdentifier: String, retryAfterSeconds: TimeInterval? = nil) {
        markRateLimited(modelID: modelIdentifier, retryAfter: retryAfterSeconds)
    }

    public func markAuthenticationFailed(modelID: String) {
        // Quarantine for 10 minutes until user updates credentials
        quarantinedModels[modelID] = Date().addingTimeInterval(600.0)
        logger.error("[ModelRouter] Authentication failed for model '\(modelID)'. Quarantined.")
    }

    public func markModelUnavailable(modelID: String, reason: String) {
        failedAttemptsCount[modelID, default: 0] += 1
        quarantinedModels[modelID] = Date().addingTimeInterval(120.0)
        logger.warning("[ModelRouter] Model '\(modelID)' marked unavailable: \(reason)")
    }

    public func markModelHealthy(modelID: String) {
        quarantinedModels.removeValue(forKey: modelID)
        failedAttemptsCount.removeValue(forKey: modelID)
    }

    public func markHealthy(modelIdentifier: String) {
        markModelHealthy(modelID: modelIdentifier)
    }

    public func clearAllQuarantines() {
        quarantinedModels.removeAll()
        failedAttemptsCount.removeAll()
        logger.info("[ModelRouter] Cleared all model quarantines.")
    }

    public func buildContinuationPrompt(originalPrompt: String, priorTurnOutput: String, failedModelName: String) -> String {
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

    public func handleTurnFailure(
        failedModelIdentifier: String,
        errorText: String,
        originalPrompt: String,
        priorTurnOutput: String
    ) async -> (nextModel: AssistAvailableModel, continuationPrompt: String, nextConfig: GoogleCloudSDKConfiguration)? {
        let allModels = await AssistModelDiscoveryService.shared.discoverAllModels()
        let failedModel: AssistAvailableModel
        if let match = allModels.first(where: { $0.id == failedModelIdentifier || $0.modelIdentifier == failedModelIdentifier }) {
            failedModel = match
        } else {
            let spec = AgentModelAdapter.shared.specification(for: failedModelIdentifier)
            let pID: String
            let pName: String
            let src: AssistModelSource
            switch spec.provider {
            case .anthropic:
                pID = "anthropic"; pName = "Claude"; src = .claude
            case .openAI:
                pID = "openai"; pName = "OpenAI"; src = .openAI
            case .gemini:
                pID = "google"; pName = "Gemini"; src = .gemini
            case .mistral:
                pID = "mistral"; pName = "Mistral"; src = .openRouter
            case .codex:
                pID = "codex"; pName = "Codex"; src = .openRouter
            default:
                pID = spec.provider.rawValue.lowercased(); pName = spec.provider.rawValue; src = .openRouter
            }
            failedModel = AssistAvailableModel(
                id: failedModelIdentifier,
                displayName: spec.displayName,
                providerID: pID,
                providerName: pName,
                modelIdentifier: failedModelIdentifier,
                source: src
            )
        }
        struct GenericError: LocalizedError {
            let errorDescription: String?
        }
        return await handleTurnFailure(
            failedModel: failedModel,
            error: GenericError(errorDescription: errorText),
            completedTurnContent: priorTurnOutput,
            executedToolsCount: 0,
            objective: originalPrompt
        )
    }

    // MARK: - Failover & Task State Continuity

    public func handleTurnFailure(
        failedModel: AssistAvailableModel,
        error: Error,
        completedTurnContent: String,
        executedToolsCount: Int,
        objective: String = ""
    ) async -> (nextModel: AssistAvailableModel, continuationPrompt: String, nextConfig: GoogleCloudSDKConfiguration)? {
        let failureClass = classify(error: error)

        // Record failure
        switch failureClass {
        case .rateLimited, .quotaExhausted:
            markRateLimited(modelID: failedModel.id)
            markRateLimited(modelID: failedModel.modelIdentifier)
        case .authenticationFailed:
            markAuthenticationFailed(modelID: failedModel.id)
            markAuthenticationFailed(modelID: failedModel.modelIdentifier)
        default:
            markModelUnavailable(modelID: failedModel.id, reason: error.localizedDescription)
        }

        // If on Gemini Key Rotation and hit rate limit, rotate key first
        if AppSettings.shared.alternativeKeysEnabled && (failureClass == .rateLimited || failureClass == .quotaExhausted) {
            if let activeId = AlternativeKeyManager.shared.activeKeyId {
                AlternativeKeyManager.shared.markRateLimited(id: activeId, retryAfterSeconds: 60)
            }
            if let nextKeyInfo = AlternativeKeyManager.shared.selectNextAvailableKey() {
                logger.info("[ModelRouter] Key Rotation: Switched to next Gemini key: \(nextKeyInfo.metadata.maskedValue)")
                let nextConfig = buildSDKConfiguration(for: failedModel, objective: objective)
                let handoff = "CONTINUATION DIRECTIVE:\nRotated to next Gemini API key (\(nextKeyInfo.metadata.maskedValue)) due to rate limit.\n\n" + (completedTurnContent.isEmpty ? "" : "Partial output:\n\"\"\"\n\(completedTurnContent)\n\"\"\"\n\n") + "Continue fulfilling the objective without repeating already completed work."
                return (failedModel, handoff, nextConfig)
            }
        }

        var excluding = Set<String>()
        excluding.insert(failedModel.id)
        excluding.insert(failedModel.modelIdentifier)

        // If quota exhausted or auth failed, also exclude all other models from this exact same provider
        if failureClass == .quotaExhausted || failureClass == .authenticationFailed {
            let all = await AssistModelDiscoveryService.shared.discoverAllModels()
            for m in all where m.providerID == failedModel.providerID {
                excluding.insert(m.id)
                excluding.insert(m.modelIdentifier)
            }
        }

        guard let nextModel = await selectNextModel(excluding: excluding) else {
            logger.error("[ModelRouter] Failover exhausted: no additional compatible models available.")
            return nil
        }

        let reasonString = error.localizedDescription.isEmpty ? failureClass.rawValue : error.localizedDescription
        let event = ModelFailoverEvent(
            failedModelID: failedModel.modelIdentifier,
            failedProviderID: failedModel.providerName,
            newModelID: nextModel.modelIdentifier,
            newProviderID: nextModel.providerName,
            failureClass: failureClass,
            reason: reasonString
        )
        self.lastFailoverEvent = event
        self.failoverHistory.append(event)
        self.currentRuntimeModel = nextModel

        logger.warning("[ModelRouter] Failover initiated from '\(failedModel.displayName)' to '\(nextModel.displayName)': Reason: \(reasonString) (\(failureClass.rawValue))")

        // Build continuous task handoff prompt
        var handoff = "CONTINUATION DIRECTIVE:\n"
        handoff += "The previous model (\(failedModel.displayName)) encountered a \(failureClass.rawValue) and failed.\n"
        if executedToolsCount > 0 {
            handoff += "Previous actions executed \(executedToolsCount) tool calls. All files modified on disk remain intact.\n"
        }
        if !completedTurnContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            handoff += "\nPartial response from previous model:\n\"\"\"\n\(completedTurnContent)\n\"\"\"\n"
        }
        handoff += "\nINSTRUCTION: Inspect the repository's current disk state and continue fulfilling the user's objective without repeating already completed work."

        let nextConfig = buildSDKConfiguration(for: nextModel, objective: objective)
        return (nextModel, handoff, nextConfig)
    }

    // MARK: - SDK Configuration Builder

    public func buildSDKConfiguration(for model: AssistAvailableModel, objective: String = "") -> GoogleCloudSDKConfiguration {
        var baseConfig = GoogleCloudSDKConfiguration.resolveDefault(objective: objective)

        baseConfig.model = model.modelIdentifier
        baseConfig.enableSubagents = model.supportsSubagents

        let provider = model.providerID.lowercased()
        let isGoogleProvider = (provider == "google" || provider == "gemini")
        let apiKey: String?
        let oauthToken: String?

        let googleAuthMode = UserDefaults.standard.string(forKey: "assist_google_auth_mode") ?? AppSettings.shared.assistGoogleAuthMode
        let isOAuthAuthenticated = isGoogleProvider && (googleAuthMode == "google_oauth") && GoogleAccountAuthService.shared.isAuthenticated && !AppSettings.shared.alternativeKeysEnabled

        if isOAuthAuthenticated {
            // Strictly rely ONLY on Antigravity allowance / OAuth session. NO API keys.
            apiKey = nil
            oauthToken = GoogleAccountAuthService.shared.getValidAccessToken()
        } else if isGoogleProvider && AppSettings.shared.alternativeKeysEnabled {
            // Gemini Key Rotation: rotate through keys strictly with no OAuth
            apiKey = AlternativeKeyManager.shared.getActiveOrNextKey()?.key
                ?? KeychainService.shared.get(forKey: LLMProvider.google.keychainKey)
                ?? APIKeyManager.shared.retrieveKey(service: .google)
                ?? baseConfig.apiKey
            oauthToken = nil
        } else {
            apiKey = resolveAPIKey(for: provider) ?? baseConfig.apiKey
            oauthToken = isGoogleProvider ? baseConfig.oauthToken : nil
        }

        return GoogleCloudSDKConfiguration(
            model: model.modelIdentifier,
            apiKey: apiKey,
            oauthToken: oauthToken,
            userProject: baseConfig.userProject,
            vertex: false,
            project: nil,
            location: nil,
            systemInstructions: baseConfig.systemInstructions,
            skillsPaths: baseConfig.skillsPaths,
            workspaces: baseConfig.workspaces,
            appDataDir: baseConfig.appDataDir,
            saveDir: baseConfig.saveDir,
            enableSubagents: model.supportsSubagents,
            maxSubagentDepth: baseConfig.maxSubagentDepth,
            allowedSubagents: baseConfig.allowedSubagents,
            serviceTier: baseConfig.serviceTier,
            tools: baseConfig.tools,
            provider: provider,
            baseURL: model.endpointURL ?? baseConfig.baseURL,
            useSavedModels: AppSettings.shared.useSavedModels,
            toolkit: AppSettings.shared.assistToolkit,
            litertModelPath: baseConfig.litertModelPath,
            litertBackend: baseConfig.litertBackend
        )
    }

    /// Resolves an API key for the given provider. This returns *only* API keys.
    /// In Google account ("google_oauth") mode it returns nil: the OAuth
    /// access token travels in the configuration's dedicated oauthToken slot,
    /// never in the apiKey slot. Returning a Bearer token as an "API key"
    /// sends the wrong credential kind to the endpoint and produces
    /// 403 ACCESS_TOKEN_SCOPE_INSUFFICIENT-style failures.
    public func resolveAPIKey(for provider: String) -> String? {
        let p = provider.lowercased()
        if p == "gemini" || p == "google" {
            let authMode = UserDefaults.standard.string(forKey: "assist_google_auth_mode") ?? AppSettings.shared.assistGoogleAuthMode
            if authMode == "google_oauth" {
                return nil
            }
            return KeychainService.shared.get(forKey: LLMProvider.google.keychainKey)
                ?? APIKeyManager.shared.retrieveKey(service: .google)
        } else if p == "anthropic" || p == "claude" {
            return APIKeyManager.shared.retrieveKey(service: .anthropic)
                ?? KeychainService.shared.get(forKey: LLMProvider.anthropic.keychainKey)
        } else if p == "openai" || p == "chatgpt" {
            return APIKeyManager.shared.retrieveKey(service: .openai)
                ?? KeychainService.shared.get(forKey: LLMProvider.openai.keychainKey)
        } else if p == "mistral" {
            return APIKeyManager.shared.retrieveKey(service: .mistral)
                ?? KeychainService.shared.get(forKey: LLMProvider.mistral.keychainKey)
        } else if p == "qwen" {
            return KeychainService.shared.get(forKey: LLMProvider.qwen.keychainKey)
        } else if p == "openrouter" {
            return OpenRouterClient.resolveOpenRouterAPIKey()
                ?? KeychainService.shared.get(forKey: LLMProvider.openRouter.keychainKey)
        } else if p == "codex" {
            return KeychainService.shared.get(forKey: KeychainService.codexUserAPIKey)
        } else if p == "ollama" || p == "lmstudio" || p == "local" {
            return "local-no-key"
        }
        return nil
    }
}
