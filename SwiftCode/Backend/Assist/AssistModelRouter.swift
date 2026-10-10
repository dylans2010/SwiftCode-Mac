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

    public func resolveSavedModel() async -> AssistAvailableModel? {
        let candidates = await getEligibleCandidates()
        return candidates.first
    }

    public func selectModelForSDK(objective: String = "") async -> (model: AssistAvailableModel, config: GoogleCloudSDKConfiguration)? {
        let isSavedModelsEnabled = AppSettings.shared.useSavedModels
        let selectedId = AppSettings.shared.selectedAssistModelID

        let targetModel: AssistAvailableModel
        if isSavedModelsEnabled {
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
        } else {
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
        // Filter: must support agentic use and tool calling, must be configured, must not be quarantined
        let eligible = allModels.filter { model in
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

        let event = ModelFailoverEvent(
            failedModelID: failedModel.modelIdentifier,
            failedProviderID: failedModel.providerName,
            newModelID: nextModel.modelIdentifier,
            newProviderID: nextModel.providerName,
            failureClass: failureClass,
            reason: error.localizedDescription
        )
        self.lastFailoverEvent = event
        self.failoverHistory.append(event)
        self.currentRuntimeModel = nextModel

        logger.info("[ModelRouter] Failover initiated: \(failedModel.displayName) -> \(nextModel.displayName) (\(failureClass.rawValue))")

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
        let apiKey = resolveAPIKey(for: provider)

        return GoogleCloudSDKConfiguration(
            model: model.modelIdentifier,
            apiKey: apiKey,
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
            baseURL: model.endpointURL,
            useSavedModels: AppSettings.shared.useSavedModels,
            toolkit: AppSettings.shared.assistToolkit
        )
    }

    public func resolveAPIKey(for provider: String) -> String? {
        let p = provider.lowercased()
        if p == "gemini" || p == "google" {
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
