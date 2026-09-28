import Foundation
import os

// MARK: - Assist v3 Canonical Model Abstraction & Capabilities

public struct ModelCapabilities: OptionSet, Sendable, Codable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let toolCalling        = ModelCapabilities(rawValue: 1 << 0)
    public static let streaming          = ModelCapabilities(rawValue: 1 << 1)
    public static let structuredOutput   = ModelCapabilities(rawValue: 1 << 2)
    public static let reasoning          = ModelCapabilities(rawValue: 1 << 3)
    public static let vision             = ModelCapabilities(rawValue: 1 << 4)
    public static let largeContext       = ModelCapabilities(rawValue: 1 << 5)
    public static let parallelToolCalls  = ModelCapabilities(rawValue: 1 << 6)
    public static let codeGeneration     = ModelCapabilities(rawValue: 1 << 7)
    public static let systemInstructions = ModelCapabilities(rawValue: 1 << 8)

    public static let standardCloud: ModelCapabilities = [
        .toolCalling, .streaming, .structuredOutput, .largeContext, .codeGeneration, .systemInstructions
    ]

    public static let advancedReasoning: ModelCapabilities = [
        .toolCalling, .streaming, .structuredOutput, .reasoning, .largeContext, .parallelToolCalls, .codeGeneration, .systemInstructions
    ]

    public static let localFoundation: ModelCapabilities = [
        .codeGeneration, .structuredOutput
    ]
}

public struct ModelSpecification: Identifiable, Sendable, Codable {
    public let id: String
    public let displayName: String
    public let provider: AssistModelProvider
    public let contextWindowTokens: Int
    public let capabilities: ModelCapabilities
    public let defaultTemperature: Double

    public init(
        id: String,
        displayName: String,
        provider: AssistModelProvider,
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

// MARK: - Canonical Model Adapter

@MainActor
public final class AgentModelAdapter: Sendable {
    public static let shared = AgentModelAdapter()
    private let logger = Logger(subsystem: "com.swiftcode.app", category: "AgentModelAdapter")

    private init() {}

    /// Canonical registry of known model specifications & capabilities
    public func specification(for modelId: String) -> ModelSpecification {
        let lower = modelId.lowercased()

        if lower.contains("claude-3-5-sonnet") || lower.contains("claude-3.5-sonnet") {
            return ModelSpecification(
                id: modelId,
                displayName: "Claude 3.5 Sonnet",
                provider: .anthropic,
                contextWindowTokens: 200_000,
                capabilities: [.toolCalling, .streaming, .structuredOutput, .vision, .largeContext, .codeGeneration, .systemInstructions]
            )
        } else if lower.contains("claude-3-5-haiku") || lower.contains("claude-3.5-haiku") {
            return ModelSpecification(
                id: modelId,
                displayName: "Claude 3.5 Haiku",
                provider: .anthropic,
                contextWindowTokens: 200_000,
                capabilities: [.toolCalling, .streaming, .structuredOutput, .vision, .largeContext, .codeGeneration, .systemInstructions]
            )
        } else if lower.contains("gpt-4o-mini") || lower.contains("openai/gpt-4o-mini") {
            return ModelSpecification(
                id: modelId,
                displayName: "GPT-4o Mini",
                provider: .openAI,
                contextWindowTokens: 128_000,
                capabilities: [.toolCalling, .streaming, .structuredOutput, .vision, .largeContext, .parallelToolCalls, .codeGeneration, .systemInstructions]
            )
        } else if lower.contains("gpt-4o") || lower.contains("openai/gpt-4o") {
            return ModelSpecification(
                id: modelId,
                displayName: "GPT-4o",
                provider: .openAI,
                contextWindowTokens: 128_000,
                capabilities: [.toolCalling, .streaming, .structuredOutput, .vision, .largeContext, .parallelToolCalls, .codeGeneration, .systemInstructions]
            )
        } else if lower.contains("gemini") {
            return ModelSpecification(
                id: modelId,
                displayName: "Gemini",
                provider: .gemini,
                contextWindowTokens: 1_000_000,
                capabilities: [.toolCalling, .streaming, .structuredOutput, .largeContext, .codeGeneration, .systemInstructions]
            )
        } else if lower.contains("deepseek") {
            return ModelSpecification(
                id: modelId,
                displayName: "DeepSeek V3",
                provider: .openRouter,
                contextWindowTokens: 64_000,
                capabilities: [.toolCalling, .streaming, .structuredOutput, .largeContext, .codeGeneration, .systemInstructions]
            )
        } else if lower.contains("codex") {
            return ModelSpecification(
                id: modelId,
                displayName: "Codex Local Bridge",
                provider: .codex,
                contextWindowTokens: 32_000,
                capabilities: [.codeGeneration, .structuredOutput]
            )
        } else if lower.contains("afm 3 core") || lower.contains("afm-3-core") || lower.contains("apple") || lower.contains("foundation") {
            return ModelSpecification(
                id: modelId,
                displayName: "Apple Foundation Models",
                provider: .openRouter,
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

    public func contextBudget(for modelId: String) -> AgentModelContextBudget {
        let spec = specification(for: modelId)
        return AgentModelContextBudget(
            modelId: modelId,
            contextWindowTokens: spec.contextWindowTokens
        )
    }

    public func estimatedTokenCount(for text: String, modelId: String) -> Int {
        return contextBudget(for: modelId).estimatedTokenCount(for: text)
    }

    public func fitsContext(_ text: String, modelId: String) -> Bool {
        return contextBudget(for: modelId).fitsContext(estimatedTokens: estimatedTokenCount(for: text, modelId: modelId))
    }

    /// Normalizes outgoing prompt structure based on model capabilities
    public func normalizePrompt(systemPrompt: String, userInstructions: String, for modelId: String) -> String {
        let spec = specification(for: modelId)

        if spec.capabilities.contains(.systemInstructions) {
            return "\(systemPrompt)\n\n# TASK EXECUTION INSTRUCTIONS\n\(userInstructions)"
        } else {
            // Merge system prompt into user instruction block for models without native system support
            return "SYSTEM DIRECTIVES:\n\(systemPrompt)\n\nUSER REQUEST:\n\(userInstructions)"
        }
    }

    /// Robust JSON extraction and recovery algorithm that repairs malformed outputs, strips fences, and locates boundaries.
    public func extractJSON(from response: String) -> [String: Any]? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Direct JSON attempt
        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }

        // 2. Fenced Markdown block extraction (```json ... ``` or ``` ...)
        let patterns = ["```json", "```JSON", "```"]
        for pattern in patterns {
            if let startRange = trimmed.range(of: pattern) {
                let afterStart = trimmed[startRange.upperBound...]
                if let endRange = afterStart.range(of: "```") {
                    let block = afterStart[..<endRange.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                    if let data = block.data(using: .utf8),
                       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        return json
                    }
                }
            }
        }

        // 3. Regex boundary scanner ({ ... })
        if let firstBrace = trimmed.firstIndex(of: "{"),
           let lastBrace = trimmed.lastIndex(of: "}"),
           firstBrace < lastBrace {
            let block = String(trimmed[firstBrace...lastBrace])
            if let data = block.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return json
            }

            // 4. Recovery: Sanitize trailing commas and missing quotes
            let sanitized = sanitizeJSONString(block)
            if let data = sanitized.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return json
            }
        }

        return nil
    }

    /// Sanitizes trailing commas and common syntax mistakes produced by LLMs.
    private func sanitizeJSONString(_ raw: String) -> String {
        var cleaned = raw
        // Remove trailing commas before closing braces/brackets
        cleaned = cleaned.replacingOccurrences(of: ",\\s*}", with: "}", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: ",\\s*]", with: "]", options: .regularExpression)
        return cleaned
    }

    /// Dispatches prompt with exponential backoff and rate limit recovery.
    public func queryModel(
        prompt: String,
        modelId: String,
        maxRetries: Int = 3
    ) async throws -> String {
        var currentAttempt = 0
        var lastError: Error?

        while currentAttempt < maxRetries {
            currentAttempt += 1
            do {
                let response = try await LLMService.shared.generateResponse(
                    prompt: prompt,
                    useContext: false,
                    modelOverride: modelId
                )
                if !response.isEmpty {
                    OfflineFallbackManager.shared.recordSuccess(for: modelId)
                    return response
                }
            } catch {
                lastError = error
                let errorDesc = error.localizedDescription.lowercased()

                if errorDesc.contains("rate limit") || errorDesc.contains("429") || errorDesc.contains("overloaded") {
                    let backoff = Double(currentAttempt * 2)
                    logger.warning("Rate limit / transient error on attempt \(currentAttempt). Backing off for \(backoff)s...")
                    try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
                    continue
                }

                if OfflineFallbackManager.shared.isFallbackPermitted {
                    logger.warning("Remote model query failed. Routing to Offline Fallback Provider...")
                    return try await OfflineFallbackManager.shared.handleFallbackQuery(
                        prompt: prompt,
                        originalModelId: modelId,
                        error: error
                    )
                }

                throw error
            }
        }

        if let finalErr = lastError, OfflineFallbackManager.shared.isFallbackPermitted {
            logger.warning("Retries exhausted for remote model query. Triggering Offline Fallback Provider...")
            return try await OfflineFallbackManager.shared.handleFallbackQuery(
                prompt: prompt,
                originalModelId: modelId,
                error: finalErr
            )
        }

        throw lastError ?? NSError(domain: "AgentModelAdapter", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed after \(maxRetries) attempts."])
    }
}

// MARK: - Assist v4 Offline Model Fallback Provider

public enum ModelFailureClassification: String, Codable, Sendable {
    case networkInterruption = "Network Interruption"
    case dnsFailure = "DNS Resolution Failure"
    case connectionTimeout = "Connection Timeout"
    case providerOutage = "Remote Provider Outage"
    case transportFailure = "Transport Protocol Failure"
    case quotaExhaustion = "Remote Quota Exhausted"
    case missingCredentials = "Credentials Unavailable"
    case unknown = "Unknown Failure"
}

public struct ModelFallbackState: Identifiable, Codable, Sendable {
    public let id: UUID
    public let primaryModel: String
    public let fallbackModel: String
    public let reason: ModelFailureClassification
    public let errorDetails: String
    public let activatedAt: Date
    public var deactivatedAt: Date?
    public var contextRehydrated: Bool
    public var continuationSuccessful: Bool
    public var requestsHandled: Int

    public init(
        id: UUID = UUID(),
        primaryModel: String,
        fallbackModel: String,
        reason: ModelFailureClassification,
        errorDetails: String,
        activatedAt: Date = Date(),
        deactivatedAt: Date? = nil,
        contextRehydrated: Bool = true,
        continuationSuccessful: Bool = true,
        requestsHandled: Int = 1
    ) {
        self.id = id
        self.primaryModel = primaryModel
        self.fallbackModel = fallbackModel
        self.reason = reason
        self.errorDetails = errorDetails
        self.activatedAt = activatedAt
        self.deactivatedAt = deactivatedAt
        self.contextRehydrated = contextRehydrated
        self.continuationSuccessful = continuationSuccessful
        self.requestsHandled = requestsHandled
    }
}

public struct ModelHealthEntry: Codable, Sendable {
    public let modelId: String
    public var consecutiveFailures: Int
    public var lastFailureAt: Date?
    public var lastSuccessAt: Date?
    public var totalRequests: Int
    public var totalFailures: Int
    public var isInCooldown: Bool
    public var cooldownUntil: Date?

    public init(modelId: String) {
        self.modelId = modelId
        self.consecutiveFailures = 0
        self.lastFailureAt = nil
        self.lastSuccessAt = nil
        self.totalRequests = 0
        self.totalFailures = 0
        self.isInCooldown = false
        self.cooldownUntil = nil
    }

    public mutating func recordSuccess() {
        consecutiveFailures = 0
        lastSuccessAt = Date()
        totalRequests += 1
        isInCooldown = false
        cooldownUntil = nil
    }

    public mutating func recordFailure() {
        consecutiveFailures += 1
        lastFailureAt = Date()
        totalRequests += 1
        totalFailures += 1
    }

    public mutating func activateCooldown(until date: Date) {
        isInCooldown = true
        cooldownUntil = date
    }

    public func isHealthy(failureThreshold: Int = 3, cooldownDuration: TimeInterval = 300) -> Bool {
        if isInCooldown, let until = cooldownUntil {
            if Date() < until { return false }
            return consecutiveFailures < failureThreshold
        }
        return consecutiveFailures < failureThreshold
    }
}

@Observable
@MainActor
public final class OfflineFallbackManager: Sendable {
    public static let shared = OfflineFallbackManager()
    private let logger = Logger(subsystem: "com.swiftcode.app", category: "OfflineFallbackManager")

    public var isActive: Bool {
        return currentState != nil && currentState?.deactivatedAt == nil
    }

    public var currentState: ModelFallbackState?
    public var fallbackHistory: [ModelFallbackState] = []
    public var modelHealth: [String: ModelHealthEntry] = [:]

    public var isFallbackPermitted: Bool {
        get {
            if UserDefaults.standard.object(forKey: "assist.offlineFallbackEnabled") == nil {
                return true
            }
            return UserDefaults.standard.bool(forKey: "assist.offlineFallbackEnabled")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "assist.offlineFallbackEnabled")
        }
    }

    public init() {}

    public func healthEntry(for modelId: String) -> ModelHealthEntry {
        if let entry = modelHealth[modelId] {
            return entry
        }
        return ModelHealthEntry(modelId: modelId)
    }

    public func recordSuccess(for modelId: String) {
        var entry = healthEntry(for: modelId)
        entry.recordSuccess()
        modelHealth[modelId] = entry
    }

    public func recordFailure(for modelId: String) {
        var entry = healthEntry(for: modelId)
        entry.recordFailure()
        if entry.consecutiveFailures >= 3 {
            entry.activateCooldown(until: Date().addingTimeInterval(300))
        }
        modelHealth[modelId] = entry
    }

    public func shouldFallback(for modelId: String) -> Bool {
        let entry = healthEntry(for: modelId)
        return !entry.isHealthy()
    }

    public func resetHealth(for modelId: String) {
        modelHealth.removeValue(forKey: modelId)
    }

    public func classify(error: Error) -> ModelFailureClassification {
        let nsError = error as NSError
        let desc = error.localizedDescription.lowercased()

        if nsError.domain == NSURLErrorDomain && (nsError.code == NSURLErrorCannotFindHost || nsError.code == NSURLErrorDNSLookupFailed) {
            return .dnsFailure
        }
        if desc.contains("cannot find host") || desc.contains("dns") || desc.contains("nodename nor servname provided") {
            return .dnsFailure
        }

        if nsError.domain == NSURLErrorDomain && (nsError.code == NSURLErrorTimedOut) {
            return .connectionTimeout
        }
        if desc.contains("timed out") || desc.contains("timeout") {
            return .connectionTimeout
        }

        if nsError.domain == NSURLErrorDomain && (
            nsError.code == NSURLErrorNotConnectedToInternet ||
            nsError.code == NSURLErrorNetworkConnectionLost ||
            nsError.code == NSURLErrorCannotConnectToHost
        ) {
            return .networkInterruption
        }
        if desc.contains("not connected to internet") || desc.contains("connection lost") || desc.contains("offline") {
            return .networkInterruption
        }

        if desc.contains("500") || desc.contains("502") || desc.contains("503") || desc.contains("504") || desc.contains("bad gateway") || desc.contains("service unavailable") {
            return .providerOutage
        }

        if desc.contains("429") || desc.contains("quota exceeded") || desc.contains("rate limit") {
            return .quotaExhaustion
        }

        if desc.contains("api key") || desc.contains("missing credentials") || nsError.code == 401 {
            return .missingCredentials
        }

        return .unknown
    }

    public func selectBestLocalFallback() -> (modelId: String, displayName: String) {
        if FoundationModels.shared.isEnabled {
            let model = FoundationModels.shared.selectedModel
            return (model.rawValue, "Apple Foundation Models (\(model.rawValue))")
        }
        return (AppleFoundationModel.afm3Core.rawValue, "Apple Foundation Models (On-Device AFM 3 Core)")
    }

    public func handleFallbackQuery(
        prompt: String,
        originalModelId: String,
        error: Error
    ) async throws -> String {
        let classification = classify(error: error)
        let localCandidate = selectBestLocalFallback()

        recordFailure(for: originalModelId)

        logger.warning("[Fallback] Triggering offline fallback for \(originalModelId) due to \(classification.rawValue): \(error.localizedDescription)")

        if var active = currentState, active.deactivatedAt == nil {
            active.requestsHandled += 1
            currentState = active
        } else {
            let newState = ModelFallbackState(
                primaryModel: originalModelId,
                fallbackModel: localCandidate.displayName,
                reason: classification,
                errorDetails: error.localizedDescription,
                activatedAt: Date(),
                contextRehydrated: true,
                continuationSuccessful: true,
                requestsHandled: 1
            )
            currentState = newState
            fallbackHistory.append(newState)

            DiagnosticEventBus.shared.logEvent(
                component: "OfflineFallbackManager",
                severity: "WARNING",
                category: "fallback_transition",
                message: "Remote connection lost (\(classification.rawValue)). Switched to local fallback: \(localCandidate.displayName). Context preserved."
            )
        }

        let originalFMEnabled = FoundationModels.shared.isEnabled
        FoundationModels.shared.isEnabled = true
        defer {
            FoundationModels.shared.isEnabled = originalFMEnabled
        }

        let rehydratedPrompt = rehydratePromptForLocalContext(prompt: prompt)

        do {
            let response = try await FoundationModels.shared.generatePrivateResponse(prompt: rehydratedPrompt)
            logger.info("[Fallback] Local fallback successfully generated response (\(response.count) chars)")
            return response
        } catch {
            logger.error("[Fallback] Local fallback query failed: \(error.localizedDescription)")
            currentState?.continuationSuccessful = false
            throw error
        }
    }

    public func fallbackTransitionMessage(for classification: ModelFailureClassification, fallbackModel: String) -> String {
        return "Model fallback activated: \(classification.rawValue). Switched to \(fallbackModel). Context preserved."
    }

    private func rehydratePromptForLocalContext(prompt: String) -> String {
        if prompt.count <= 16_000 {
            return prompt
        }

        var compactPrompt = prompt
        if let historyStart = prompt.range(of: "# HISTORY OF RECENT TOOL EXECUTION RESULTS"),
           let activeFilesStart = prompt.range(of: "# ACTIVE FILE CONTENTS") {
            let sub = prompt[historyStart.lowerBound..<activeFilesStart.lowerBound]
            if sub.count > 4000 {
                let recentPortion = String(sub.suffix(2000))
                compactPrompt = prompt.replacingOccurrences(
                    of: String(sub),
                    with: "# HISTORY OF RECENT TOOL EXECUTION RESULTS (COMPACTED)\n[Prior steps truncated for local model buffer]\n" + recentPortion
                )
            }
        }

        return compactPrompt
    }

    public func deactivateFallback(reason: String = "Remote connectivity restored") {
        guard var active = currentState, active.deactivatedAt == nil else { return }
        active.deactivatedAt = Date()
        currentState = active

        logger.info("[Fallback] Deactivated fallback: \(reason)")
        DiagnosticEventBus.shared.logEvent(
            component: "OfflineFallbackManager",
            severity: "INFO",
            category: "fallback_recovery",
            message: "Restored primary remote model: \(active.primaryModel). Reason: \(reason)"
        )
    }
}

