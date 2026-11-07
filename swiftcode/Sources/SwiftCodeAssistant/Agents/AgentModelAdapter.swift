import Foundation
import os

@MainActor
public final class AgentModelAdapter: Sendable {
    public static let shared = AgentModelAdapter()
    private let logger = Logger(subsystem: "com.swiftcode.app", category: "AgentModelAdapter")

    private init() {}

    public func specification(for modelId: String) -> ModelSpecification {
        AssistModelSpecification.specification(for: modelId)
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

    public func normalizePrompt(systemPrompt: String, userInstructions: String, for modelId: String) -> String {
        let spec = specification(for: modelId)

        if spec.capabilities.contains(.systemInstructions) {
            return "\(systemPrompt)\n\n# TASK EXECUTION INSTRUCTIONS\n\(userInstructions)"
        } else {
            return "SYSTEM DIRECTIVES:\n\(systemPrompt)\n\nUSER REQUEST:\n\(userInstructions)"
        }
    }

    public func extractJSON(from response: String) -> [String: Any]? {
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return json
        }

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

        if let firstBrace = trimmed.firstIndex(of: "{"),
           let lastBrace = trimmed.lastIndex(of: "}"),
           firstBrace < lastBrace {
            let block = String(trimmed[firstBrace...lastBrace])
            if let data = block.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return json
            }

            let sanitized = sanitizeJSONString(block)
            if let data = sanitized.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return json
            }
        }

        return nil
    }

    private func sanitizeJSONString(_ raw: String) -> String {
        var cleaned = raw
        cleaned = cleaned.replacingOccurrences(of: ",\\s*}", with: "}", options: .regularExpression)
        cleaned = cleaned.replacingOccurrences(of: ",\\s*]", with: "]", options: .regularExpression)
        return cleaned
    }

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

    public func streamQueryModel(prompt: String, modelId: String, attachments: [AIMessageAttachment]? = nil, systemPrompt: String = "", directory: String? = nil) async throws -> AsyncThrowingStream<String, Error> {
        if let openCode = OpenCodeModelID.parse(modelId) {
            return try await OpenCodeClient.shared.streamPrompt(
                prompt: prompt,
                systemPrompt: systemPrompt.isEmpty ? nil : systemPrompt,
                model: OpenCodeModel(providerID: openCode.providerID, modelID: openCode.modelID),
                directory: directory
            )
        }

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await LLMService.shared.streamChat(
                        messages: [AIMessage(role: .user, content: prompt, attachments: attachments)],
                        model: modelId,
                        systemPrompt: "",
                        onToken: { token in continuation.yield(token) }
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in task.cancel() }
        }
    }

    public func extractStreamedStringValue(named key: String, from partialJSON: String) -> String? {
        let keyToken = "\"\(key)\""
        guard let keyRange = partialJSON.range(of: keyToken) else { return nil }

        var cursor = keyRange.upperBound
        while cursor < partialJSON.endIndex, partialJSON[cursor].isWhitespace {
            cursor = partialJSON.index(after: cursor)
        }
        guard cursor < partialJSON.endIndex, partialJSON[cursor] == ":" else { return nil }
        cursor = partialJSON.index(after: cursor)

        while cursor < partialJSON.endIndex, partialJSON[cursor].isWhitespace {
            cursor = partialJSON.index(after: cursor)
        }
        guard cursor < partialJSON.endIndex, partialJSON[cursor] == "\"" else { return nil }

        let valueStart = cursor
        cursor = partialJSON.index(after: cursor)
        var isEscaped = false
        while cursor < partialJSON.endIndex {
            let character = partialJSON[cursor]
            if isEscaped {
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else if character == "\"" {
                let literal = String(partialJSON[valueStart...cursor])
                guard let data = literal.data(using: .utf8) else { return nil }
                return try? JSONDecoder().decode(String.self, from: data)
            }
            cursor = partialJSON.index(after: cursor)
        }
        return nil
    }
}

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

public typealias AssistModelCapabilities = ModelCapabilities
