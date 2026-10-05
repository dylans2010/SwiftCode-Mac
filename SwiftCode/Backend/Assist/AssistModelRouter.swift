//
//  AssistModelRouter.swift
//  SwiftCode
//
//  Real-time model router, capability validator, deterministic ranker, rate-limit tracker,
//  and Antigravity configuration factory for SwiftCode Assist.
//

import Foundation
import os

private let logger = Logger(subsystem: "com.swiftcode.Assist", category: "ModelRouter")

@MainActor
public final class AssistModelRouter: ObservableObject {
    public static let shared = AssistModelRouter()

    @Published public private(set) var availableModels: [AssistAvailableModel] = []
    @Published public private(set) var currentRuntimeModel: AssistAvailableModel?
    @Published public private(set) var lastRoutingNotice: String?
    @Published public private(set) var isDiscovering: Bool = false

    private var rateLimitedModels: [String: Date] = [:] // model.id -> rateLimitedUntil
    private var modelFailureCounts: [String: Int] = [:]

    private init() {}

    /// Main entry point to refresh and discover all models from providers
    public func discoverModels(forceRefresh: Bool = false) async -> [AssistAvailableModel] {
        isDiscovering = true
        defer { isDiscovering = false }

        let models = await ProviderModelDiscovery.shared.discoverModels(forceRefresh: forceRefresh)

        // Apply temporary rate limit states to models
        let now = Date()
        var updatedModels: [AssistAvailableModel] = []

        for var model in models {
            if let until = rateLimitedModels[model.id] {
                if until > now {
                    model.status = .rateLimited(until: until)
                } else {
                    rateLimitedModels.removeValue(forKey: model.id)
                }
            }
            updatedModels.append(model)
        }

        self.availableModels = updatedModels
        return updatedModels
    }

    /// Validates whether a model has required capabilities for Antigravity agentic loop
    public func validateModelCapabilities(_ model: AssistAvailableModel) -> Bool {
        guard model.isConfigured else { return false }
        guard model.isAvailable else { return false }
        guard model.capabilities.supportsAgenticUse else { return false }
        guard model.capabilities.supportsToolCalling else { return false }

        // Raw Anthropic direct API lacks OpenAI-compatible chat completions endpoint for LocalOpenAIAgentConfig
        if model.source == .claude && model.providerID == "anthropic" {
            return false
        }

        return true
    }

    /// Deterministically ranks models considering preferences, agentic capabilities, health, and priority
    public func rankModels(candidates: [AssistAvailableModel]) -> [AssistAvailableModel] {
        let userPreferredModelID = AppSettings.shared.selectedAssistModelID

        return candidates.sorted { m1, m2 in
            // 1. User preferred model comes first if usable
            let m1IsPref = m1.modelIdentifier == userPreferredModelID || m1.id == userPreferredModelID
            let m2IsPref = m2.modelIdentifier == userPreferredModelID || m2.id == userPreferredModelID
            if m1IsPref != m2IsPref {
                return m1IsPref
            }

            // 2. Usable / Available status
            if m1.isAvailable != m2.isAvailable {
                return m1.isAvailable
            }

            // 3. Agentic capability
            let m1Capable = validateModelCapabilities(m1)
            let m2Capable = validateModelCapabilities(m2)
            if m1Capable != m2Capable {
                return m1Capable
            }

            // 4. Failure history penalty
            let m1Failures = modelFailureCounts[m1.id] ?? 0
            let m2Failures = modelFailureCounts[m2.id] ?? 0
            if m1Failures != m2Failures {
                return m1Failures < m2Failures
            }

            // 5. Explicit model priority
            if m1.priority != m2.priority {
                return m1.priority > m2.priority
            }

            return m1.displayName < m2.displayName
        }
    }

    /// Selects the best candidate model for an active Antigravity session
    public func selectModelForSession() async -> AssistAvailableModel? {
        let discovered = await discoverModels(forceRefresh: false)
        let usableCandidates = discovered.filter { validateModelCapabilities($0) }

        let ranked = rankModels(candidates: usableCandidates)

        guard let selected = ranked.first else {
            logger.error("[AssistModelRouter] No usable agentic models found!")
            self.lastRoutingNotice = "No agent-compatible models are currently available."
            return nil
        }

        self.currentRuntimeModel = selected
        if selected.modelIdentifier != AppSettings.shared.selectedAssistModelID {
            self.lastRoutingNotice = "Active model set to \(selected.displayName)"
        }
        return selected
    }

    /// Records model failure (e.g. 429 rate limit or network error) and selects next available fallback
    public func handleModelFailure(model: AssistAvailableModel, error: Error) async -> AssistAvailableModel? {
        let errDesc = error.localizedDescription.lowercased()
        let isRateLimit = errDesc.contains("429") || errDesc.contains("resource_exhausted") || errDesc.contains("quota") || errDesc.contains("rate limit")

        let currentFailures = (modelFailureCounts[model.id] ?? 0) + 1
        modelFailureCounts[model.id] = currentFailures

        if isRateLimit {
            // Quarantine model for 2 minutes
            let quarantineDuration: TimeInterval = 120
            let until = Date().addingTimeInterval(quarantineDuration)
            rateLimitedModels[model.id] = until
            logger.warning("[AssistModelRouter] Model '\(model.displayName)' rate limited. Quarantined until \(until)")
            self.lastRoutingNotice = "\(model.displayName) quota reached — switching model"
        } else {
            logger.error("[AssistModelRouter] Model '\(model.displayName)' failed with error: \(error.localizedDescription)")
            self.lastRoutingNotice = "\(model.displayName) unavailable — attempting failover"
        }

        // Re-discover and select next healthy model
        return await selectModelForSession()
    }

    /// Clears rate limits and failure history for explicit refresh
    public func resetModelHealth() {
        rateLimitedModels.removeAll()
        modelFailureCounts.removeAll()
        lastRoutingNotice = "Model health counters reset"
    }

    /// Resolves and builds GoogleCloudSDKConfiguration for the selected model
    public func createAntigravityConfig(for model: AssistAvailableModel, workspaceURL: URL? = nil) -> GoogleCloudSDKConfiguration {
        var baseConfig = GoogleCloudSDKConfiguration.resolveDefault(for: workspaceURL)

        // Set effective model identifier
        baseConfig.model = model.modelIdentifier

        // Determine API key and endpoint configuration based on provider
        switch model.source {
        case .gemini:
            let key = KeychainService.shared.get(forKey: LLMProvider.google.keychainKey) ?? APIKeyManager.shared.retrieveKey(service: .google)
            baseConfig.apiKey = key
            baseConfig.configType = "local"
            baseConfig.baseUrl = nil

        case .openai:
            let key = KeychainService.shared.get(forKey: LLMProvider.openai.keychainKey) ?? APIKeyManager.shared.retrieveKey(service: .openai)
            baseConfig.apiKey = key
            baseConfig.configType = "openai_local"
            baseConfig.baseUrl = "https://api.openai.com/v1"

        case .ollamaLocal:
            baseConfig.configType = "openai_local"
            baseConfig.baseUrl = "http://localhost:11434/v1"
            baseConfig.apiKey = "ollama"

        case .custom:
            baseConfig.configType = "openai_local"
            if let customEndpoint = CustomEndpointManager.shared.endpoints.first(where: { model.id.contains($0.id.uuidString) }) {
                baseConfig.baseUrl = customEndpoint.isLocal ? "http://localhost:\(customEndpoint.localPort)/v1" : customEndpoint.endpoint
                baseConfig.apiKey = customEndpoint.apiKey.isEmpty ? "custom" : customEndpoint.apiKey
            } else {
                baseConfig.baseUrl = "http://localhost:11434/v1"
            }

        case .claude, .appleFoundation, .other:
            baseConfig.configType = "local"
        }

        return baseConfig
    }
}
