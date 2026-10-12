//
//  AssistModelDiscoveryService.swift
//  SwiftCode
//
//  Asynchronous, non-blocking discovery service for all configured LLM providers and models.
//

import Foundation
import os

private let logger = Logger(subsystem: "com.swiftcode.Assist", category: "ModelDiscovery")

@Observable
@MainActor
public final class AssistModelDiscoveryService: Sendable {
    public static let shared = AssistModelDiscoveryService()

    public var discoveredModels: [AssistAvailableModel] = []
    public var isDiscovering: Bool = false
    public var lastDiscoveryDate: Date? = nil
    public var lastDiscoveryErrors: [String: String] = [:]
    public var hiddenProviderNames: Set<String> = []
    public var removedModelIDs: Set<String> = []

    var hasFreshDiscoveryCache: Bool {
        guard let lastDiscoveryDate else { return false }
        let age = Date().timeIntervalSince(lastDiscoveryDate)
        return age >= 0 && age < discoveryCacheLifetime
    }

    private let discoveryCacheLifetime: TimeInterval = 300
    private var discoveryTask: Task<[AssistAvailableModel], Never>?

    private let hiddenProvidersKey = "com.swiftcode.assist.hidden_provider_names"
    private let removedModelsKey = "com.swiftcode.assist.removed_model_ids"

    private init() {
        if let savedHidden = UserDefaults.standard.stringArray(forKey: hiddenProvidersKey) {
            self.hiddenProviderNames = Set(savedHidden)
        }
        if let savedRemoved = UserDefaults.standard.stringArray(forKey: removedModelsKey) {
            self.removedModelIDs = Set(savedRemoved)
        }
        // Seed synchronously so that on-device Apple Foundation Models and local custom endpoints show immediately
        self.discoveredModels = self.generateBaselineModels()
        Task { [weak self] in
            await self?.discoverAllModels(forceRefresh: true)
        }
    }

    /// Foundation Models is a system model integration and may NEVER be deleted.
    public func isFoundationModel(id: String, source: AssistModelSource? = nil, providerName: String? = nil) -> Bool {
        if source == .appleFoundationModels || source == .appleFoundation { return true }
        if providerName == "Apple Foundation Models" { return true }
        let lower = id.lowercased()
        if lower.contains("afm") || lower.contains("apple") { return true }
        if id == AppleFoundationModel.afm3Core.rawValue || id == AppleFoundationModel.afm3CoreAdvanced.rawValue { return true }
        return false
    }

    public func isFoundationModel(_ model: AssistAvailableModel) -> Bool {
        return isFoundationModel(id: model.modelIdentifier, source: model.source, providerName: model.providerName)
    }

    /// Permanently removes a model so it is never shown again. No restore option exists.
    public func removeModel(_ modelID: String) {
        guard !isFoundationModel(id: modelID) else {
            logger.warning("Foundation Models is a system model integration and cannot be deleted: \(modelID)")
            return
        }
        removedModelIDs.insert(modelID)
        UserDefaults.standard.set(Array(removedModelIDs), forKey: removedModelsKey)
        discoveredModels.removeAll { $0.modelIdentifier == modelID || $0.id == modelID }
    }

    /// Permanently removes a provider. Foundation Models cannot be removed. No restore option exists.
    public func removeProvider(_ name: String) {
        guard name != "Apple Foundation Models" else {
            logger.warning("Foundation Models is a system model integration and cannot be deleted.")
            return
        }
        hiddenProviderNames.insert(name)
        UserDefaults.standard.set(Array(hiddenProviderNames), forKey: hiddenProvidersKey)
    }

    // MARK: - Baseline Model Generation (Immediate Synchronous Availability)

    public func generateBaselineModels() -> [AssistAvailableModel] {
        var models: [AssistAvailableModel] = []

        // 1. Apple Foundation Models (Always immediately available on device)
        models.append(contentsOf: generateAppleFoundationModels())

        // 2. Custom & Local Endpoints / Models
        models.append(contentsOf: generateCustomBaselineModels())

        return models
    }

    private func generateAppleFoundationModels() -> [AssistAvailableModel] {
        return AppleFoundationModel.allCases.map { model in
            AssistAvailableModel(
                id: model.rawValue,
                displayName: "Apple \(model.rawValue) (On-Device)",
                providerID: "apple",
                providerName: "Apple Foundation Models",
                modelIdentifier: model.rawValue,
                capabilities: .localFoundation,
                source: .appleFoundation,
                isConfigured: true,
                isAvailable: true,
                supportsStreaming: true,
                supportsToolCalling: false,
                supportsVision: model == .afm3CoreAdvanced,
                supportsStructuredOutput: true,
                supportsAgenticUse: true,
                supportsSubagents: false,
                priority: model == .afm3Core ? 90 : 91,
                statusDescription: "On-Device Available",
                status: .available,
                contextWindow: model == .afm3Core ? 8_192 : 32_000
            )
        }
    }

    private func generateCustomBaselineModels() -> [AssistAvailableModel] {
        var results: [AssistAvailableModel] = []
        let endpoints = CustomEndpointManager.shared.endpoints

        for endpoint in endpoints {
            let isLocal = endpoint.isLocal
            let providerName = isLocal ? "Local (\(endpoint.name))" : "Custom (\(endpoint.name))"
            let providerID = isLocal ? "local" : "custom"
            let source: ModelSource = isLocal ? .local : .custom

            var modelList = endpoint.models
            if modelList.isEmpty {
                let defaultName = endpoint.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (isLocal ? "Local LLM" : "Custom Model") : endpoint.name
                modelList = [defaultName]
            }

            for id in modelList {
                results.append(
                    AssistAvailableModel(
                        id: id,
                        displayName: "\(id) (\(endpoint.name))",
                        providerID: providerID,
                        providerName: providerName,
                        modelIdentifier: id,
                        capabilities: [.toolCalling, .streaming, .structuredOutput, .codeGeneration],
                        source: source,
                        isConfigured: true,
                        isAvailable: true,
                        supportsStreaming: true,
                        supportsToolCalling: true,
                        supportsVision: false,
                        supportsStructuredOutput: true,
                        supportsAgenticUse: true,
                        supportsSubagents: false,
                        priority: 40,
                        statusDescription: "Ready",
                        status: .available,
                        endpointURL: isLocal ? "http://localhost:\(endpoint.localPort)/v1" : endpoint.endpoint
                    )
                )
            }
        }

        let activeCustomModel = AssistModelManager.shared.customModelID.isEmpty ? AppSettings.shared.customModel : AssistModelManager.shared.customModelID
        let trimmedCustom = activeCustomModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCustom.isEmpty && !results.contains(where: { $0.modelIdentifier == trimmedCustom }) {
            results.append(
                AssistAvailableModel(
                    id: trimmedCustom,
                    displayName: "\(trimmedCustom) (Custom)",
                    providerID: "custom",
                    providerName: "Custom Models",
                    modelIdentifier: trimmedCustom,
                    capabilities: [.toolCalling, .streaming, .structuredOutput, .codeGeneration],
                    source: .custom,
                    isConfigured: true,
                    isAvailable: true,
                    supportsStreaming: true,
                    supportsToolCalling: true,
                    supportsVision: false,
                    supportsStructuredOutput: true,
                    supportsAgenticUse: true,
                    supportsSubagents: false,
                    priority: 45,
                    statusDescription: "Ready",
                    status: .available
                )
            )
        }

        let localInstalled = OfflineModelManager.shared.installedModels
        for m in localInstalled where !results.contains(where: { $0.modelIdentifier == m.modelName }) {
            results.append(
                AssistAvailableModel(
                    id: m.modelName,
                    displayName: "\(m.modelName) (HuggingFace)",
                    providerID: "local",
                    providerName: "Local / Ollama",
                    modelIdentifier: m.modelName,
                    capabilities: [.streaming, .codeGeneration],
                    source: .local,
                    isConfigured: true,
                    isAvailable: true,
                    supportsStreaming: true,
                    supportsToolCalling: false,
                    supportsVision: false,
                    supportsStructuredOutput: false,
                    supportsAgenticUse: true,
                    supportsSubagents: false,
                    priority: 50,
                    statusDescription: "Downloaded",
                    status: .available
                )
            )
        }

        return results
    }

    // MARK: - Public Discovery API

    public func discoverAllModels(forceRefresh: Bool = false) async -> [AssistAvailableModel] {
        if !forceRefresh && hasFreshDiscoveryCache {
            return discoveredModels
        }

        if let discoveryTask {
            return await discoveryTask.value
        }

        isDiscovering = true
        lastDiscoveryErrors.removeAll()
        let task = Task { @MainActor in
            await self.performModelDiscovery()
        }
        discoveryTask = task

        let result = await task.value
        discoveredModels = result
        lastDiscoveryDate = Date()
        isDiscovering = false
        discoveryTask = nil
        return result
    }

    private func performModelDiscovery() async -> [AssistAvailableModel] {
        var allDiscovered: [AssistAvailableModel] = []

        // Run provider discovery tasks concurrently
        async let geminiTask = discoverGeminiModels()
        async let claudeTask = discoverClaudeModels()
        async let openAITask = discoverOpenAIModels()
        async let mistralTask = discoverMistralModels()
        async let qwenTask = discoverQwenModels()
        async let appleTask = discoverAppleFoundationModels()
        async let customTask = discoverCustomAndLocalEndpoints()
        async let openRouterTask = discoverOpenRouterModels()

        let (geminiModels, claudeModels, openAIModels, mistralModels, qwenModels, appleModels, customModels, openRouterModels) =
            await (geminiTask, claudeTask, openAITask, mistralTask, qwenTask, appleTask, customTask, openRouterTask)

        allDiscovered.append(contentsOf: geminiModels)
        allDiscovered.append(contentsOf: claudeModels)
        allDiscovered.append(contentsOf: openAIModels)
        allDiscovered.append(contentsOf: mistralModels)
        allDiscovered.append(contentsOf: qwenModels)
        allDiscovered.append(contentsOf: appleModels)
        allDiscovered.append(contentsOf: customModels)
        allDiscovered.append(contentsOf: openRouterModels)

        return allDiscovered
    }

    public var agentCompatibleModels: [AssistAvailableModel] {
        discoveredModels.filter {
            !removedModelIDs.contains($0.modelIdentifier) &&
            !removedModelIDs.contains($0.id) &&
            !hiddenProviderNames.contains(getProviderName(for: $0)) &&
            $0.supportsAgenticUse && $0.supportsToolCalling && $0.isAvailable && !$0.isCurrentlyRateLimited
        }
    }

    public var availableProvidersCount: Int {
        Set(discoveredModels.filter {
            !removedModelIDs.contains($0.modelIdentifier) &&
            !removedModelIDs.contains($0.id) &&
            $0.isAvailable
        }.map { $0.providerID }).count
    }

    public var totalModelsCount: Int {
        discoveredModels.filter { !removedModelIDs.contains($0.modelIdentifier) && !removedModelIDs.contains($0.id) }.count
    }

    public var agentCompatibleCount: Int {
        agentCompatibleModels.count
    }

    // MARK: - Gemini Discovery (Dynamic API Call)

    private func discoverGeminiModels() async -> [AssistAvailableModel] {
        var apiKey = KeychainService.shared.get(forKey: LLMProvider.google.keychainKey)
            ?? KeychainService.shared.get(forKey: "gemini-api-key")
            ?? KeychainService.shared.get(forKey: "gemini_api_key")
            ?? APIKeyManager.shared.retrieveKey(service: .google)
            ?? ""

        if apiKey.isEmpty, AppSettings.shared.alternativeKeysEnabled {
            if let alt = AlternativeKeyManager.shared.getActiveOrNextKey() {
                apiKey = alt.key
            }
        }

        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let oauthToken = try? await GoogleAccountAuthService.shared.getValidAccessToken()
        let isOauthActive = GoogleAccountAuthService.shared.isAuthenticated

        guard !trimmedKey.isEmpty || (isOauthActive && oauthToken != nil) else {
            return await fallbackAntigravityModels()
        }

        var request: URLRequest
        if !trimmedKey.isEmpty {
            guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000&key=\(trimmedKey)") else {
                return await fallbackAntigravityModels()
            }
            request = URLRequest(url: url)
        } else if let token = oauthToken {
            guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000") else {
                return await fallbackAntigravityModels()
            }
            request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        } else {
            return await fallbackAntigravityModels()
        }

        request.httpMethod = "GET"
        request.timeoutInterval = 8.0

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                if let httpResponse = response as? HTTPURLResponse {
                    logger.warning("Gemini model discovery returned HTTP \(httpResponse.statusCode)")
                }
                return await fallbackAntigravityModels()
            }

            struct GeminiListResponse: Codable {
                struct ModelEntry: Codable {
                    let name: String
                    let displayName: String?
                    let description: String?
                    let supportedGenerationMethods: [String]?
                    let inputTokenLimit: Int?
                }
                let models: [ModelEntry]?
            }

            let decoded = try JSONDecoder().decode(GeminiListResponse.self, from: data)
            let entries = decoded.models ?? []

            var results: [AssistAvailableModel] = []
            for entry in entries {
                let methods = entry.supportedGenerationMethods ?? []
                guard methods.isEmpty || methods.contains("generateContent") else { continue }

                var cleanId = entry.name
                if cleanId.hasPrefix("models/") {
                    cleanId = String(cleanId.dropFirst(7))
                }

                let lower = cleanId.lowercased()
                if lower.contains("embedding") || lower.contains("aqa") || lower.contains("imagen") {
                    continue
                }

                let dName = entry.displayName ?? cleanId
                let context = entry.inputTokenLimit ?? 1_000_000

                results.append(
                    AssistAvailableModel(
                        id: cleanId,
                        displayName: dName,
                        providerID: "gemini",
                        providerName: "Gemini",
                        modelIdentifier: cleanId,
                        capabilities: .advancedReasoning,
                        source: .gemini,
                        isConfigured: true,
                        isAvailable: true,
                        supportsStreaming: true,
                        supportsToolCalling: true,
                        supportsVision: true,
                        supportsStructuredOutput: true,
                        supportsAgenticUse: true,
                        supportsSubagents: true,
                        priority: lower.contains("flash") ? 10 : 20,
                        statusDescription: "Available",
                        status: .available,
                        contextWindow: context
                    )
                )
            }

            if results.isEmpty {
                return await fallbackAntigravityModels()
            }
            return results
        } catch {
            logger.error("Gemini model discovery error: \(error.localizedDescription)")
            return await fallbackAntigravityModels()
        }
    }

    private func fallbackAntigravityModels() async -> [AssistAvailableModel] {
        let models = await MainActor.run {
            AntigravitySDKModelFetcher.shared.models.isEmpty
                ? AntigravitySDKModelFetcher.seedModels
                : AntigravitySDKModelFetcher.shared.models
        }
        var list: [AssistAvailableModel] = []
        for sdk in models where sdk.category.lowercased() == "google" {
            list.append(
                AssistAvailableModel(
                    id: sdk.id,
                    displayName: sdk.displayName,
                    providerID: "gemini",
                    providerName: "Gemini",
                    modelIdentifier: sdk.id,
                    capabilities: .advancedReasoning,
                    source: .gemini,
                    isConfigured: true,
                    isAvailable: true,
                    supportsStreaming: true,
                    supportsToolCalling: true,
                    supportsVision: true,
                    supportsStructuredOutput: true,
                    supportsAgenticUse: true,
                    supportsSubagents: true,
                    priority: sdk.thinkingLevel.lowercased() == "low" ? 10 : 20,
                    statusDescription: "Available via Google Account",
                    status: .available,
                    contextWindow: sdk.contextWindow
                )
            )
        }
        return list
    }

    // MARK: - Claude / Anthropic Discovery (Dynamic API Call)

    private func discoverClaudeModels() async -> [AssistAvailableModel] {
        var apiKey = KeychainService.shared.get(forKey: LLMProvider.anthropic.keychainKey)
            ?? KeychainService.shared.get(forKey: "anthropic-api-key")
            ?? KeychainService.shared.get(forKey: "anthropic_api_key")
            ?? APIKeyManager.shared.retrieveKey(service: .anthropic)
            ?? ""
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return [] }

        guard let url = URL(string: "https://api.anthropic.com/v1/models?limit=1000") else {
            return []
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(trimmedKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 8.0

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return []
            }

            struct AnthropicModelsResponse: Codable {
                struct Entry: Codable {
                    let id: String
                    let display_name: String?
                }
                let data: [Entry]?
            }

            let decoded = try JSONDecoder().decode(AnthropicModelsResponse.self, from: data)
            guard let entries = decoded.data, !entries.isEmpty else {
                return []
            }

            let results: [AssistAvailableModel] = entries.map { entry in
                let dName = entry.display_name ?? entry.id
                let lower = entry.id.lowercased()
                return AssistAvailableModel(
                    id: entry.id,
                    displayName: dName,
                    providerID: "anthropic",
                    providerName: "Claude",
                    modelIdentifier: entry.id,
                    capabilities: .advancedReasoning,
                    source: .claude,
                    isConfigured: true,
                    isAvailable: true,
                    supportsStreaming: true,
                    supportsToolCalling: true,
                    supportsVision: true,
                    supportsStructuredOutput: true,
                    supportsAgenticUse: true,
                    supportsSubagents: true,
                    priority: lower.contains("sonnet") ? 15 : (lower.contains("haiku") ? 14 : 25),
                    statusDescription: "Available",
                    status: .available,
                    contextWindow: 200_000
                )
            }

            return results
        } catch {
            logger.error("Claude model discovery error: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - OpenAI Discovery (Dynamic API Call)

    private func discoverOpenAIModels() async -> [AssistAvailableModel] {
        var apiKey = KeychainService.shared.get(forKey: LLMProvider.openai.keychainKey)
            ?? KeychainService.shared.get(forKey: "openai-api-key")
            ?? KeychainService.shared.get(forKey: "openai_api_key")
            ?? APIKeyManager.shared.retrieveKey(service: .openai)
            ?? ""
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return [] }

        guard let url = URL(string: "https://api.openai.com/v1/models") else {
            return []
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 8.0

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return []
            }

            struct OpenAIListResponse: Codable {
                struct Entry: Codable {
                    let id: String
                }
                let data: [Entry]?
            }

            let decoded = try JSONDecoder().decode(OpenAIListResponse.self, from: data)
            let entries = decoded.data ?? []

            var results: [AssistAvailableModel] = []
            for entry in entries {
                let id = entry.id
                let lower = id.lowercased()

                if lower.contains("embedding") ||
                   lower.contains("dall-e") ||
                   lower.contains("tts") ||
                   lower.contains("whisper") ||
                   lower.contains("moderation") ||
                   lower.contains("audio") ||
                   lower.contains("realtime") ||
                   lower.hasPrefix("text-search") ||
                   lower.hasPrefix("text-similarity") ||
                   lower.hasPrefix("davinci") ||
                   lower.hasPrefix("babbage") ||
                   lower.hasPrefix("curie") {
                    continue
                }

                let isMini = lower.contains("mini")
                results.append(
                    AssistAvailableModel(
                        id: id,
                        displayName: id,
                        providerID: "openai",
                        providerName: "OpenAI",
                        modelIdentifier: id,
                        capabilities: .advancedReasoning,
                        source: .openAI,
                        isConfigured: true,
                        isAvailable: true,
                        supportsStreaming: true,
                        supportsToolCalling: true,
                        supportsVision: lower.contains("4o") || lower.contains("vision"),
                        supportsStructuredOutput: true,
                        supportsAgenticUse: true,
                        supportsSubagents: true,
                        priority: isMini ? 18 : 12,
                        statusDescription: "Available",
                        status: .available,
                        contextWindow: 128_000
                    )
                )
            }

            return results
        } catch {
            logger.error("OpenAI model discovery error: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Mistral Discovery (Dynamic API Call)

    private func discoverMistralModels() async -> [AssistAvailableModel] {
        var apiKey = KeychainService.shared.get(forKey: LLMProvider.mistral.keychainKey)
            ?? KeychainService.shared.get(forKey: "mistral-api-key")
            ?? KeychainService.shared.get(forKey: "mistral_api_key")
            ?? APIKeyManager.shared.retrieveKey(service: .mistral)
            ?? ""
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return [] }

        guard let url = URL(string: "https://api.mistral.ai/v1/models") else {
            return []
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 8.0

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return []
            }

            struct MistralResponse: Codable {
                struct Entry: Codable {
                    let id: String
                }
                let data: [Entry]?
            }

            let decoded = try JSONDecoder().decode(MistralResponse.self, from: data)
            guard let entries = decoded.data, !entries.isEmpty else {
                return []
            }

            let results: [AssistAvailableModel] = entries.compactMap { entry in
                let lower = entry.id.lowercased()
                if lower.contains("embed") { return nil }
                return AssistAvailableModel(
                    id: entry.id,
                    displayName: entry.id,
                    providerID: "mistral",
                    providerName: "Mistral",
                    modelIdentifier: entry.id,
                    capabilities: .advancedReasoning,
                    source: .custom,
                    isConfigured: true,
                    isAvailable: true,
                    supportsStreaming: true,
                    supportsToolCalling: true,
                    supportsVision: lower.contains("pixtral"),
                    supportsStructuredOutput: true,
                    supportsAgenticUse: true,
                    supportsSubagents: true,
                    priority: 28,
                    statusDescription: "Available",
                    status: .available,
                    contextWindow: 128_000
                )
            }

            return results
        } catch {
            logger.error("Mistral model discovery error: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Qwen Discovery (Dynamic API Call)

    private func discoverQwenModels() async -> [AssistAvailableModel] {
        var apiKey = KeychainService.shared.get(forKey: LLMProvider.qwen.keychainKey)
            ?? KeychainService.shared.get(forKey: "qwen-api-key")
            ?? KeychainService.shared.get(forKey: "qwen_api_key")
            ?? APIKeyManager.shared.retrieveKey(service: .qwen)
            ?? ""
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return [] }

        guard let url = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/models") else {
            return []
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 8.0

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return []
            }

            struct QwenResponse: Codable {
                struct Entry: Codable {
                    let id: String
                }
                let data: [Entry]?
            }

            let decoded = try JSONDecoder().decode(QwenResponse.self, from: data)
            guard let entries = decoded.data, !entries.isEmpty else {
                return []
            }

            let results: [AssistAvailableModel] = entries.compactMap { entry in
                let lower = entry.id.lowercased()
                if lower.contains("embed") { return nil }
                return AssistAvailableModel(
                    id: entry.id,
                    displayName: entry.id,
                    providerID: "qwen",
                    providerName: "Qwen",
                    modelIdentifier: entry.id,
                    capabilities: .advancedReasoning,
                    source: .custom,
                    isConfigured: true,
                    isAvailable: true,
                    supportsStreaming: true,
                    supportsToolCalling: true,
                    supportsVision: lower.contains("vl"),
                    supportsStructuredOutput: true,
                    supportsAgenticUse: true,
                    supportsSubagents: true,
                    priority: 30,
                    statusDescription: "Available",
                    status: .available,
                    contextWindow: 128_000
                )
            }

            return results
        } catch {
            logger.error("Qwen model discovery error: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Apple Foundation Models (On-Device - Always Available)

    private func discoverAppleFoundationModels() async -> [AssistAvailableModel] {
        return generateAppleFoundationModels()
    }

    // MARK: - Custom & Local Endpoints (Dynamic API Call + Guaranteed Fallback)

    private func discoverCustomAndLocalEndpoints() async -> [AssistAvailableModel] {
        let endpoints = CustomEndpointManager.shared.endpoints
        var results: [AssistAvailableModel] = []

        for endpoint in endpoints {
            let isLocal = endpoint.isLocal
            let providerName = isLocal ? "Local (\(endpoint.name))" : "Custom (\(endpoint.name))"
            let providerID = isLocal ? "local" : "custom"
            let source: ModelSource = isLocal ? .local : .custom

            var modelIDs: [String] = []
            do {
                modelIDs = try await fetchModelsFromEndpoint(endpoint)
            } catch {
                lastDiscoveryErrors[providerName] = error.localizedDescription
                logger.warning("Endpoint \(endpoint.name) unreachable: \(error.localizedDescription)")
            }

            var merged = modelIDs
            for m in endpoint.models where !merged.contains(m) {
                merged.append(m)
            }

            if merged.isEmpty {
                let defaultName = endpoint.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? (isLocal ? "Local LLM" : "Custom Model") : endpoint.name
                merged.append(defaultName)
            }

            for id in merged {
                results.append(
                    AssistAvailableModel(
                        id: id,
                        displayName: "\(id) (\(endpoint.name))",
                        providerID: providerID,
                        providerName: providerName,
                        modelIdentifier: id,
                        capabilities: [.toolCalling, .streaming, .structuredOutput, .codeGeneration],
                        source: source,
                        isConfigured: true,
                        isAvailable: true,
                        supportsStreaming: true,
                        supportsToolCalling: true,
                        supportsVision: false,
                        supportsStructuredOutput: true,
                        supportsAgenticUse: true,
                        supportsSubagents: false,
                        priority: 40,
                        statusDescription: "Ready",
                        status: .available,
                        endpointURL: isLocal ? "http://localhost:\(endpoint.localPort)/v1" : endpoint.endpoint
                    )
                )
            }
        }

        let activeCustomModel = AssistModelManager.shared.customModelID.isEmpty ? AppSettings.shared.customModel : AssistModelManager.shared.customModelID
        let trimmedCustom = activeCustomModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCustom.isEmpty && !results.contains(where: { $0.modelIdentifier == trimmedCustom }) {
            results.append(
                AssistAvailableModel(
                    id: trimmedCustom,
                    displayName: "\(trimmedCustom) (Custom)",
                    providerID: "custom",
                    providerName: "Custom Models",
                    modelIdentifier: trimmedCustom,
                    capabilities: [.toolCalling, .streaming, .structuredOutput, .codeGeneration],
                    source: .custom,
                    isConfigured: true,
                    isAvailable: true,
                    supportsStreaming: true,
                    supportsToolCalling: true,
                    supportsVision: false,
                    supportsStructuredOutput: true,
                    supportsAgenticUse: true,
                    supportsSubagents: false,
                    priority: 45,
                    statusDescription: "Ready",
                    status: .available
                )
            )
        }

        let localInstalled = OfflineModelManager.shared.installedModels
        for m in localInstalled where !results.contains(where: { $0.modelIdentifier == m.modelName }) {
            results.append(
                AssistAvailableModel(
                    id: m.modelName,
                    displayName: "\(m.modelName) (HuggingFace)",
                    providerID: "local",
                    providerName: "Local / Ollama",
                    modelIdentifier: m.modelName,
                    capabilities: [.streaming, .codeGeneration],
                    source: .local,
                    isConfigured: true,
                    isAvailable: true,
                    supportsStreaming: true,
                    supportsToolCalling: false,
                    supportsVision: false,
                    supportsStructuredOutput: false,
                    supportsAgenticUse: true,
                    supportsSubagents: false,
                    priority: 50,
                    statusDescription: "Downloaded",
                    status: .available
                )
            )
        }

        return results
    }

    private func fetchModelsFromEndpoint(_ endpoint: SavedCustomEndpoint) async throws -> [String] {
        var base = endpoint.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        if endpoint.isLocal {
            let port = endpoint.localPort.trimmingCharacters(in: .whitespacesAndNewlines)
            base = "http://localhost:\(port.isEmpty ? "11434" : port)"
        }

        var candidateURLs: [URL] = []
        if base.lowercased().hasSuffix("/models") || base.lowercased().hasSuffix("/tags") {
            if let u = URL(string: base) { candidateURLs.append(u) }
        } else {
            let cleanBase = base.hasSuffix("/") ? String(base.dropLast()) : base
            if let u1 = URL(string: "\(cleanBase)/v1/models") { candidateURLs.append(u1) }
            if let u2 = URL(string: "\(cleanBase)/models") { candidateURLs.append(u2) }
            if let u3 = URL(string: "\(cleanBase)/api/tags") { candidateURLs.append(u3) }
        }

        for url in candidateURLs {
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 4.0

            if !endpoint.isLocal && !endpoint.apiKey.isEmpty {
                request.setValue("Bearer \(endpoint.apiKey)", forHTTPHeaderField: "Authorization")
            }
            for header in endpoint.headers {
                let k = header.key.trimmingCharacters(in: .whitespacesAndNewlines)
                let v = header.value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !k.isEmpty && !v.isEmpty {
                    request.setValue(v, forHTTPHeaderField: k)
                }
            }

            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
                continue
            }

            struct OpenAIResponse: Codable {
                struct Entry: Codable { let id: String }
                let data: [Entry]?
            }
            if let decoded = try? JSONDecoder().decode(OpenAIResponse.self, from: data),
               let list = decoded.data, !list.isEmpty {
                return list.map { $0.id }
            }

            struct OllamaResponse: Codable {
                struct Entry: Codable { let name: String; let model: String? }
                let models: [Entry]?
            }
            if let decoded = try? JSONDecoder().decode(OllamaResponse.self, from: data),
               let list = decoded.models, !list.isEmpty {
                return list.map { $0.model ?? $0.name }
            }
        }

        throw NSError(domain: "EndpointAPIError", code: 404, userInfo: [NSLocalizedDescriptionKey: "No models returned by endpoint API."])
    }

    // MARK: - OpenRouter Discovery (Dynamic API Call)

    private func discoverOpenRouterModels() async -> [AssistAvailableModel] {
        var key = OpenRouterClient.resolveOpenRouterAPIKey()
        if key.isEmpty {
            key = KeychainService.shared.get(forKey: KeychainService.openRouterAPIKey)
                ?? KeychainService.shared.get(forKey: "openrouter-api-key")
                ?? APIKeyManager.shared.retrieveKey(service: .openRouter)
                ?? ""
        }
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return [] }

        do {
            let models = try await OpenRouterClient.shared.fetchModels()
            let dynamicList = models.map { m in
                let lower = m.id.lowercased()
                let supportsVision = lower.contains("vision") || lower.contains("4o") || lower.contains("gemini") || lower.contains("claude-3")
                let context = m.contextLength ?? 128_000
                return AssistAvailableModel(
                    id: m.id,
                    displayName: m.name,
                    providerID: "openrouter",
                    providerName: "OpenRouter",
                    modelIdentifier: m.id,
                    capabilities: .advancedReasoning,
                    source: .openRouter,
                    isConfigured: true,
                    isAvailable: true,
                    supportsStreaming: true,
                    supportsToolCalling: true,
                    supportsVision: supportsVision,
                    supportsStructuredOutput: true,
                    supportsAgenticUse: true,
                    supportsSubagents: true,
                    priority: 35,
                    statusDescription: "Ready",
                    status: .available,
                    contextWindow: context
                )
            }
            return dynamicList
        } catch {
            logger.error("OpenRouter model discovery error: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Provider Name & Grouping Resolution

    public func getProviderName(for model: AssistAvailableModel) -> String {
        if model.source == .appleFoundationModels || model.source == .appleFoundation || model.providerID == "apple" || model.providerName.contains("Apple") {
            return "Apple Foundation Models"
        } else if model.source == .local || model.providerID == "local" || model.providerID == "ollama" || model.providerID == "lmstudio" {
            return "Local / Ollama"
        } else if model.providerID == "mistral" {
            return "Mistral"
        } else if model.providerID == "qwen" {
            return "Qwen"
        } else if model.source == .custom || model.providerID == "custom" {
            return "Custom Models"
        } else if model.source == .gemini || model.providerID == "gemini" || model.providerID == "google" {
            return "Gemini"
        } else if model.source == .claude || model.providerID == "anthropic" || model.providerID == "claude" {
            return "Claude"
        } else if model.source == .openAI || model.providerID == "openai" {
            return "OpenAI"
        } else if model.source == .openRouter || model.providerID == "openrouter" {
            return "OpenRouter"
        } else {
            return model.providerName
        }
    }

    public func isProviderExplicitlyActive(_ providerName: String) -> Bool {
        if providerName == "Apple Foundation Models" { return true }
        if providerName.hasPrefix("Custom") || providerName.hasPrefix("Local") {
            return !CustomEndpointManager.shared.endpoints.isEmpty ||
                   !AppSettings.shared.customModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                   !AssistModelManager.shared.customModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                   !OfflineModelManager.shared.installedModels.isEmpty
        }
        if providerName == "Gemini" {
            let key = KeychainService.shared.get(forKey: LLMProvider.google.keychainKey)
                ?? KeychainService.shared.get(forKey: "gemini-api-key")
                ?? KeychainService.shared.get(forKey: "gemini_api_key")
                ?? APIKeyManager.shared.retrieveKey(service: .google)
                ?? ""
            return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || GoogleAccountAuthService.shared.isAuthenticated
        }
        if providerName == "Claude" {
            let key = KeychainService.shared.get(forKey: LLMProvider.anthropic.keychainKey)
                ?? KeychainService.shared.get(forKey: "anthropic-api-key")
                ?? KeychainService.shared.get(forKey: "anthropic_api_key")
                ?? APIKeyManager.shared.retrieveKey(service: .anthropic)
                ?? ""
            return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if providerName == "OpenAI" {
            let key = KeychainService.shared.get(forKey: LLMProvider.openai.keychainKey)
                ?? KeychainService.shared.get(forKey: "openai-api-key")
                ?? KeychainService.shared.get(forKey: "openai_api_key")
                ?? APIKeyManager.shared.retrieveKey(service: .openai)
                ?? ""
            return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if providerName == "OpenRouter" {
            let key = OpenRouterClient.resolveOpenRouterAPIKey()
            return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if providerName == "Mistral" {
            let key = KeychainService.shared.get(forKey: LLMProvider.mistral.keychainKey)
                ?? KeychainService.shared.get(forKey: "mistral-api-key")
                ?? KeychainService.shared.get(forKey: "mistral_api_key")
                ?? APIKeyManager.shared.retrieveKey(service: .mistral)
                ?? ""
            return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        if providerName == "Qwen" {
            let key = KeychainService.shared.get(forKey: LLMProvider.qwen.keychainKey)
                ?? KeychainService.shared.get(forKey: "qwen-api-key")
                ?? KeychainService.shared.get(forKey: "qwen_api_key")
                ?? APIKeyManager.shared.retrieveKey(service: .qwen)
                ?? ""
            return !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }

    public func getDiscoveryStats() -> (total: Int, providers: Int, agentCompatible: Int) {
        let visibleModels = discoveredModels.filter { model in
            let provider = getProviderName(for: model)
            if isProviderExplicitlyActive(provider) { return true }
            return !removedModelIDs.contains(model.modelIdentifier) &&
                   !removedModelIDs.contains(model.id) &&
                   !hiddenProviderNames.contains(provider)
        }
        let total = visibleModels.count
        let providers = Set(visibleModels.filter { $0.isAvailable || $0.isConfigured }.map { getProviderName(for: $0) }).count
        let agent = visibleModels.filter { $0.supportsAgenticUse && $0.supportsToolCalling && $0.isAvailable && !$0.isCurrentlyRateLimited }.count
        return (total, max(1, providers), agent)
    }

    public var unfilteredModelsByProvider: [(providerName: String, models: [AssistAvailableModel])] {
        let order = ["Gemini", "Claude", "OpenAI", "Mistral", "Qwen", "Apple Foundation Models", "Custom Models", "Local / Ollama", "OpenRouter"]
        var grouped: [String: [AssistAvailableModel]] = [:]
        for model in discoveredModels {
            let key = getProviderName(for: model)
            if !isProviderExplicitlyActive(key) {
                if removedModelIDs.contains(model.modelIdentifier) || removedModelIDs.contains(model.id) {
                    continue
                }
            }
            grouped[key, default: []].append(model)
        }

        var result: [(providerName: String, models: [AssistAvailableModel])] = []
        for name in order {
            if let list = grouped[name], !list.isEmpty {
                result.append((name, list))
            }
        }
        for (name, list) in grouped where !order.contains(name) && !list.isEmpty {
            result.append((name, list))
        }
        return result
    }

    public var modelsByProvider: [(providerName: String, models: [AssistAvailableModel])] {
        unfilteredModelsByProvider.filter { group in
            if isProviderExplicitlyActive(group.providerName) {
                return true
            }
            return !hiddenProviderNames.contains(group.providerName)
        }
    }

    public var availableProviderNames: [String] {
        modelsByProvider.map { $0.providerName }
    }
}
