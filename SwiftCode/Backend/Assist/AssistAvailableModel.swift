//
//  AssistAvailableModel.swift
//  SwiftCode
//
//  Unified model provider abstraction and dynamic discovery engine for SwiftCode Assist.
//

import Foundation
import os

private let logger = Logger(subsystem: "com.swiftcode.Assist", category: "ModelDiscovery")

public enum ModelSource: String, Codable, Sendable, CaseIterable {
    case gemini = "Gemini"
    case claude = "Claude"
    case openai = "OpenAI"
    case appleFoundation = "Apple Foundation Models"
    case custom = "Custom Models"
    case ollamaLocal = "Local / Ollama"
    case other = "Other"
}

public enum ModelStatus: Equatable, Sendable {
    case available
    case rateLimited(until: Date?)
    case unavailable(reason: String)
    case authenticationRequired
    case unsupported(reason: String)

    public var isUsableForAgent: Bool {
        switch self {
        case .available:
            return true
        default:
            return false
        }
    }

    public var displayBadgeText: String {
        switch self {
        case .available:
            return "Available"
        case .rateLimited(let until):
            if let until = until {
                let formatter = RelativeDateTimeFormatter()
                return "Rate Limited (\(formatter.localizedString(for: until, relativeTo: Date())))"
            }
            return "Rate Limited"
        case .unavailable(let reason):
            return "Unavailable (\(reason))"
        case .authenticationRequired:
            return "Auth Required"
        case .unsupported(let reason):
            return "Unsupported (\(reason))"
        }
    }
}

public struct ModelCapabilities: Codable, Equatable, Sendable {
    public var supportsStreaming: Bool
    public var supportsToolCalling: Bool
    public var supportsVision: Bool
    public var supportsStructuredOutput: Bool
    public var supportsAgenticUse: Bool
    public var supportsSubagents: Bool
    public var maxContextTokens: Int

    public init(
        supportsStreaming: Bool = true,
        supportsToolCalling: Bool = true,
        supportsVision: Bool = false,
        supportsStructuredOutput: Bool = true,
        supportsAgenticUse: Bool = true,
        supportsSubagents: Bool = true,
        maxContextTokens: Int = 128000
    ) {
        self.supportsStreaming = supportsStreaming
        self.supportsToolCalling = supportsToolCalling
        self.supportsVision = supportsVision
        self.supportsStructuredOutput = supportsStructuredOutput
        self.supportsAgenticUse = supportsAgenticUse
        self.supportsSubagents = supportsSubagents
        self.maxContextTokens = maxContextTokens
    }
}

public struct AssistAvailableModel: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let providerID: String
    public let providerName: String
    public let modelIdentifier: String

    public let capabilities: ModelCapabilities
    public let source: ModelSource
    public let isConfigured: Bool
    public var status: ModelStatus
    public let priority: Int

    public var isAvailable: Bool {
        status == .available
    }

    public var isAgenticCapable: Bool {
        isAvailable && capabilities.supportsAgenticUse && capabilities.supportsToolCalling
    }

    public init(
        id: String,
        displayName: String,
        providerID: String,
        providerName: String,
        modelIdentifier: String,
        capabilities: ModelCapabilities,
        source: ModelSource,
        isConfigured: Bool,
        status: ModelStatus,
        priority: Int = 50
    ) {
        self.id = id
        self.displayName = displayName
        self.providerID = providerID
        self.providerName = providerName
        self.modelIdentifier = modelIdentifier
        self.capabilities = capabilities
        self.source = source
        self.isConfigured = isConfigured
        self.status = status
        self.priority = priority
    }
}

// MARK: - Provider Model Discovery Engine

public final class ProviderModelDiscovery: Sendable {
    public static let shared = ProviderModelDiscovery()

    private let cacheLock = NSLock()
    private var cachedModels: [AssistAvailableModel] = []
    private var lastDiscoveryDate: Date? = nil
    private let cacheTTL: TimeInterval = 300 // 5 minutes cache

    private init() {}

    /// Discovers and normalizes all available models across configured SwiftCode providers.
    public func discoverModels(forceRefresh: Bool = false) async -> [AssistAvailableModel] {
        cacheLock.lock()
        if !forceRefresh, let lastDate = lastDiscoveryDate, Date().timeIntervalSince(lastDate) < cacheTTL, !cachedModels.isEmpty {
            let result = cachedModels
            cacheLock.unlock()
            return result
        }
        cacheLock.unlock()

        var discovered: [AssistAvailableModel] = []

        // 1. Gemini Models
        let geminiModels = await discoverGeminiModels()
        discovered.append(contentsOf: geminiModels)

        // 2. Claude Models
        let claudeModels = await discoverClaudeModels()
        discovered.append(contentsOf: claudeModels)

        // 3. OpenAI Models
        let openaiModels = await discoverOpenAIModels()
        discovered.append(contentsOf: openaiModels)

        // 4. Apple Foundation Models
        let appleModels = await discoverAppleFoundationModels()
        discovered.append(contentsOf: appleModels)

        // 5. Custom Models & Endpoints (OpenRouter / Together / Local)
        let customModels = await discoverCustomModels()
        discovered.append(contentsOf: customModels)

        cacheLock.lock()
        self.cachedModels = discovered
        self.lastDiscoveryDate = Date()
        cacheLock.unlock()

        return discovered
    }

    // MARK: - Provider Specific Discovery Routines

    private func discoverGeminiModels() async -> [AssistAvailableModel] {
        let key = KeychainService.shared.get(forKey: LLMProvider.google.keychainKey) ?? APIKeyManager.shared.retrieveKey(service: .google) ?? ""
        let isConfigured = !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if !isConfigured {
            return []
        }

        do {
            let fetchedIDs = try await LLMService.shared.fetchAvailableModels(provider: .google, key: key)
            return fetchedIDs.map { modelID in
                let cleanID = modelID.hasPrefix("models/") ? String(modelID.dropFirst(7)) : modelID
                let isAgentic = cleanID.contains("gemini")
                return AssistAvailableModel(
                    id: "google:\(cleanID)",
                    displayName: "Gemini (\(cleanID))",
                    providerID: "google",
                    providerName: "Gemini",
                    modelIdentifier: cleanID,
                    capabilities: ModelCapabilities(
                        supportsStreaming: true,
                        supportsToolCalling: isAgentic,
                        supportsVision: true,
                        supportsStructuredOutput: true,
                        supportsAgenticUse: isAgentic,
                        supportsSubagents: true,
                        maxContextTokens: 1000000
                    ),
                    source: .gemini,
                    isConfigured: true,
                    status: .available,
                    priority: cleanID.contains("flash") ? 100 : 90
                )
            }
        } catch {
            logger.warning("[ProviderModelDiscovery] Gemini fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    private func discoverClaudeModels() async -> [AssistAvailableModel] {
        let key = KeychainService.shared.get(forKey: LLMProvider.anthropic.keychainKey) ?? APIKeyManager.shared.retrieveKey(service: .anthropic) ?? ""
        let isConfigured = !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if !isConfigured {
            return []
        }

        do {
            let fetchedIDs = try await LLMService.shared.fetchAvailableModels(provider: .anthropic, key: key)
            return fetchedIDs.map { modelID in
                AssistAvailableModel(
                    id: "anthropic:\(modelID)",
                    displayName: "Claude (\(modelID))",
                    providerID: "anthropic",
                    providerName: "Claude",
                    modelIdentifier: modelID,
                    capabilities: ModelCapabilities(
                        supportsStreaming: true,
                        supportsToolCalling: true,
                        supportsVision: true,
                        supportsStructuredOutput: true,
                        supportsAgenticUse: true,
                        supportsSubagents: true,
                        maxContextTokens: 200000
                    ),
                    source: .claude,
                    isConfigured: true,
                    status: .available,
                    priority: modelID.contains("sonnet") ? 98 : 85
                )
            }
        } catch {
            logger.warning("[ProviderModelDiscovery] Claude fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    private func discoverOpenAIModels() async -> [AssistAvailableModel] {
        let key = KeychainService.shared.get(forKey: LLMProvider.openai.keychainKey) ?? APIKeyManager.shared.retrieveKey(service: .openai) ?? ""
        let isConfigured = !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        if !isConfigured {
            return []
        }

        do {
            let fetchedIDs = try await LLMService.shared.fetchAvailableModels(provider: .openai, key: key)
            let relevantIDs = fetchedIDs.filter { id in
                id.hasPrefix("gpt-4") || id.hasPrefix("gpt-3.5") || id.hasPrefix("o1") || id.hasPrefix("o3")
            }
            return relevantIDs.map { modelID in
                AssistAvailableModel(
                    id: "openai:\(modelID)",
                    displayName: "OpenAI (\(modelID))",
                    providerID: "openai",
                    providerName: "OpenAI",
                    modelIdentifier: modelID,
                    capabilities: ModelCapabilities(
                        supportsStreaming: true,
                        supportsToolCalling: true,
                        supportsVision: modelID.contains("4o") || modelID.contains("vision"),
                        supportsStructuredOutput: true,
                        supportsAgenticUse: true,
                        supportsSubagents: true,
                        maxContextTokens: 128000
                    ),
                    source: .openai,
                    isConfigured: true,
                    status: .available,
                    priority: modelID.hasPrefix("gpt-4o") ? 96 : 80
                )
            }
        } catch {
            logger.warning("[ProviderModelDiscovery] OpenAI fetch failed: \(error.localizedDescription)")
            return []
        }
    }

    private func discoverAppleFoundationModels() async -> [AssistAvailableModel] {
        let isEnabled = await MainActor.run { FoundationModels.shared.isEnabled }
        if !isEnabled {
            return []
        }

        let models = [
            ("AFM 3 Core", "AFM 3 Core (On-Device)", 60, false, 32000),
            ("AFM 3 Core Advanced", "AFM 3 Core Advanced (On-Device)", 65, false, 32000)
        ]

        return models.map { (id, name, prio, sub, ctx) in
            AssistAvailableModel(
                id: "apple:\(id)",
                displayName: name,
                providerID: "apple",
                providerName: "Apple Foundation Models",
                modelIdentifier: id,
                capabilities: ModelCapabilities(supportsStreaming: true, supportsToolCalling: false, supportsVision: false, supportsStructuredOutput: false, supportsAgenticUse: false, supportsSubagents: false, maxContextTokens: ctx),
                source: .appleFoundation,
                isConfigured: isEnabled,
                status: .unsupported(reason: "On-device AFM lacks native tool-calling JSON schema support"),
                priority: prio
            )
        }
    }

    private func discoverCustomModels() async -> [AssistAvailableModel] {
        var result: [AssistAvailableModel] = []
        let endpoints = await MainActor.run { CustomEndpointManager.shared.endpoints }

        for endpoint in endpoints {
            let isLocal = endpoint.isLocal
            let providerID = "custom:\(endpoint.id.uuidString)"
            let source: ModelSource = isLocal ? .ollamaLocal : .custom

            for modelID in endpoint.models {
                result.append(
                    AssistAvailableModel(
                        id: "\(providerID):\(modelID)",
                        displayName: "\(modelID) (\(endpoint.name))",
                        providerID: providerID,
                        providerName: endpoint.name,
                        modelIdentifier: modelID,
                        capabilities: ModelCapabilities(supportsStreaming: true, supportsToolCalling: true, supportsVision: false, supportsStructuredOutput: true, supportsAgenticUse: true, supportsSubagents: isLocal, maxContextTokens: 64000),
                        source: source,
                        isConfigured: true,
                        status: .available,
                        priority: isLocal ? 88 : 82
                    )
                )
            }
        }

        return result
    }
}
