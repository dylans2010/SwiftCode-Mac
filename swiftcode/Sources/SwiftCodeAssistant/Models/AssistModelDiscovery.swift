import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol ModelDiscoveryTransport: Sendable {
    func get(url: URL, headers: [String: String], timeout: TimeInterval) async throws -> (data: Data, status: Int)
}

public struct URLSessionModelDiscoveryTransport: ModelDiscoveryTransport {
    public init() {}
    public func get(url: URL, headers: [String: String], timeout: TimeInterval) async throws -> (data: Data, status: Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        let response = try await HTTP.send(request, timeout: timeout)
        return (response.body, response.status)
    }
}

public enum ModelDiscoveryProvider: String, Sendable, CaseIterable {
    case gemini
    case anthropic
    case openAI
    case mistral
    case qwen
}

public struct AssistDiscoveredModel: Sendable, Equatable {
    public var id: String
    public var displayName: String
    public var providerID: String
    public var providerName: String
    public var modelIdentifier: String
    public var capabilities: ModelCapabilities
    public var contextWindow: Int
    public var supportsStreaming: Bool
    public var supportsToolCalling: Bool
    public var supportsAgenticUse: Bool
    public var supportsSubagents: Bool
    public var supportsVision: Bool
    public var supportsStructuredOutput: Bool
    public var priority: Int
    public var statusDescription: String
    public var isConfigured: Bool
    public var isAvailable: Bool
    public var isSynthetic: Bool
    public var nativeProvider: ModelDiscoveryProvider

    public init(
        id: String,
        displayName: String? = nil,
        providerID: String,
        providerName: String,
        modelIdentifier: String? = nil,
        capabilities: ModelCapabilities = .advancedReasoning,
        contextWindow: Int = 128_000,
        supportsStreaming: Bool = true,
        supportsToolCalling: Bool = true,
        supportsAgenticUse: Bool = true,
        supportsSubagents: Bool = true,
        supportsVision: Bool = false,
        supportsStructuredOutput: Bool = true,
        priority: Int = 10,
        statusDescription: String = "Available",
        isConfigured: Bool = true,
        isAvailable: Bool = true,
        isSynthetic: Bool = false,
        nativeProvider: ModelDiscoveryProvider
    ) {
        self.id = id
        self.displayName = displayName ?? id
        self.providerID = providerID
        self.providerName = providerName
        self.modelIdentifier = modelIdentifier ?? id
        self.capabilities = capabilities
        self.contextWindow = contextWindow
        self.supportsStreaming = supportsStreaming
        self.supportsToolCalling = supportsToolCalling
        self.supportsAgenticUse = supportsAgenticUse
        self.supportsSubagents = supportsSubagents
        self.supportsVision = supportsVision
        self.supportsStructuredOutput = supportsStructuredOutput
        self.priority = priority
        self.statusDescription = statusDescription
        self.isConfigured = isConfigured
        self.isAvailable = isAvailable
        self.isSynthetic = isSynthetic
        self.nativeProvider = nativeProvider
    }
}

public actor AssistModelDiscoveryService {
    public static let discoveryCacheLifetime: TimeInterval = 300

    public static let shared = AssistModelDiscoveryService(store: defaultSecretStore())

    private let store: SecretStore
    private let transport: any ModelDiscoveryTransport
    private let catalog: AntigravitySDKCatalog
    private let keyRotation: GeminiKeyRotationManager?

    public var isGoogleOAuthAuthenticated = false

    public private(set) var discoveredModels: [AssistDiscoveredModel] = []
    public private(set) var lastDiscoveryDate: Date?
    public private(set) var lastDiscoveryErrors: [String: String] = [:]
    public var hiddenProviderNames: Set<String> = []
    public var removedModelIDs: Set<String> = []

    public init(
        store: SecretStore,
        transport: any ModelDiscoveryTransport = URLSessionModelDiscoveryTransport(),
        catalog: AntigravitySDKCatalog = .shared,
        keyRotation: GeminiKeyRotationManager? = nil,
        isGoogleOAuthAuthenticated: Bool = false
    ) {
        self.store = store
        self.transport = transport
        self.catalog = catalog
        self.keyRotation = keyRotation
        self.isGoogleOAuthAuthenticated = isGoogleOAuthAuthenticated
    }

    public var hasFreshDiscoveryCache: Bool {
        guard let lastDiscoveryDate else { return false }
        let age = Date().timeIntervalSince(lastDiscoveryDate)
        return age >= 0 && age < Self.discoveryCacheLifetime
    }

    public func discoverAllModels(forceRefresh: Bool = false) async -> [AssistDiscoveredModel] {
        if !forceRefresh && hasFreshDiscoveryCache {
            return discoveredModels
        }
        lastDiscoveryErrors.removeAll()
        async let gemini = discoverGeminiModels()
        async let claude = discoverClaudeModels()
        async let openAI = discoverOpenAIModels()
        async let mistral = discoverMistralModels()
        async let qwen = discoverQwenModels()
        let all = await gemini + claude + openAI + mistral + qwen
        discoveredModels = all
        lastDiscoveryDate = Date()
        return all
    }

    public var agentCompatibleModels: [AssistDiscoveredModel] {
        discoveredModels.filter {
            !removedModelIDs.contains($0.modelIdentifier) &&
            !removedModelIDs.contains($0.id) &&
            !hiddenProviderNames.contains($0.providerName) &&
            $0.supportsAgenticUse && $0.supportsToolCalling && $0.isAvailable
        }
    }

    public func removeModel(_ modelID: String) {
        guard !isFoundationModel(id: modelID) else { return }
        removedModelIDs.insert(modelID)
        discoveredModels.removeAll { $0.modelIdentifier == modelID || $0.id == modelID }
    }

    public func removeProvider(_ name: String) {
        guard name != "Apple Foundation Models" else { return }
        hiddenProviderNames.insert(name)
    }

    public static func isFoundationModel(id: String) -> Bool {
        let lower = id.lowercased()
        return lower.contains("afm") || lower.contains("apple")
    }

    public func isFoundationModel(id: String) -> Bool {
        Self.isFoundationModel(id: id)
    }

    private func geminiKey() async -> String {
        if let key = store.readString(SecretAccount.geminiKey), !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return key
        }
        if let rotation = keyRotation, let alt = await rotation.getActiveOrNextKey() {
            return alt.key
        }
        return ""
    }

    private func discoverGeminiModels() async -> [AssistDiscoveredModel] {
        let trimmedKey = await geminiKey().trimmingCharacters(in: .whitespacesAndNewlines)
        if isGoogleOAuthAuthenticated || trimmedKey.isEmpty {
            return await fallbackAntigravityModels()
        }
        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models")
        components?.queryItems = [
            URLQueryItem(name: "pageSize", value: "1000"),
            URLQueryItem(name: "key", value: trimmedKey),
        ]
        guard let url = components?.url else {
            return await fallbackAntigravityModels()
        }
        do {
            let (data, status) = try await transport.get(url: url, headers: [:], timeout: 8)
            guard status == 200 else {
                lastDiscoveryErrors["Gemini"] = "Live discovery failed (HTTP \(status)). Showing bundled catalog."
                return await fallbackAntigravityModels()
            }
            let results = Self.parseGeminiModels(data)
            if results.isEmpty {
                lastDiscoveryErrors["Gemini"] = "Live discovery returned no models. Showing bundled catalog."
                return await fallbackAntigravityModels()
            }
            return results
        } catch {
            lastDiscoveryErrors["Gemini"] = "Live discovery failed (\(error.localizedDescription)). Showing bundled catalog."
            return await fallbackAntigravityModels()
        }
    }

    private func fallbackAntigravityModels() async -> [AssistDiscoveredModel] {
        let live = await catalog.models
        let isSeedCatalog = live.isEmpty
        let models = isSeedCatalog ? AntigravitySDKCatalog.seedModels : live
        let authed = isGoogleOAuthAuthenticated
        return models.map { sdk in
            let isAnthropic = sdk.category.lowercased() == "anthropic"
            return AssistDiscoveredModel(
                id: sdk.id,
                displayName: sdk.displayName,
                providerID: isAnthropic ? "anthropic" : "gemini",
                providerName: sdk.category == "Google" ? "Gemini" : sdk.category,
                modelIdentifier: sdk.id,
                capabilities: .advancedReasoning,
                contextWindow: sdk.contextWindow,
                supportsStreaming: true,
                supportsToolCalling: true,
                supportsAgenticUse: true,
                supportsSubagents: !sdk.isImageModel,
                supportsVision: true,
                supportsStructuredOutput: true,
                priority: sdk.thinkingLevel.lowercased() == "low" ? 10 : 20,
                statusDescription: isSeedCatalog
                    ? "Available via Google Account · Antigravity catalog"
                    : "Available via Google Account",
                isConfigured: authed,
                isAvailable: authed,
                isSynthetic: true,
                nativeProvider: .gemini
            )
        }
    }

    public nonisolated static func parseGeminiModels(_ data: Data) -> [AssistDiscoveredModel] {
        struct GeminiListResponse: Decodable {
            struct ModelEntry: Decodable {
                let name: String
                let displayName: String?
                let description: String?
                let supportedGenerationMethods: [String]?
                let inputTokenLimit: Int?
            }
            let models: [ModelEntry]?
        }
        guard let decoded = try? JSONDecoder().decode(GeminiListResponse.self, from: data) else { return [] }
        var results: [AssistDiscoveredModel] = []
        for entry in decoded.models ?? [] {
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
            results.append(AssistDiscoveredModel(
                id: cleanId,
                displayName: entry.displayName ?? cleanId,
                providerID: "gemini",
                providerName: "Gemini",
                modelIdentifier: cleanId,
                capabilities: .advancedReasoning,
                contextWindow: entry.inputTokenLimit ?? 1_000_000,
                supportsStreaming: true,
                supportsToolCalling: true,
                supportsAgenticUse: true,
                supportsSubagents: true,
                supportsVision: true,
                supportsStructuredOutput: true,
                priority: lower.contains("flash") ? 10 : 20,
                statusDescription: "Available",
                nativeProvider: .gemini
            ))
        }
        return results
    }

    private func discoverClaudeModels() async -> [AssistDiscoveredModel] {
        guard let key = store.readString(SecretAccount.anthropicKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else { return [] }
        guard let url = URL(string: "https://api.anthropic.com/v1/models?limit=1000") else { return [] }
        do {
            let (data, status) = try await transport.get(url: url, headers: [
                "x-api-key": key,
                "anthropic-version": "2023-06-01",
            ], timeout: 8)
            guard status == 200 else { return [] }
            return Self.parseClaudeModels(data)
        } catch {
            return []
        }
    }

    public nonisolated static func parseClaudeModels(_ data: Data) -> [AssistDiscoveredModel] {
        struct AnthropicModelsResponse: Decodable {
            struct Entry: Decodable {
                let id: String
                let display_name: String?
            }
            let data: [Entry]?
        }
        guard let decoded = try? JSONDecoder().decode(AnthropicModelsResponse.self, from: data),
              let entries = decoded.data, !entries.isEmpty else { return [] }
        return entries.map { entry in
            let lower = entry.id.lowercased()
            return AssistDiscoveredModel(
                id: entry.id,
                displayName: entry.display_name ?? entry.id,
                providerID: "anthropic",
                providerName: "Claude",
                modelIdentifier: entry.id,
                capabilities: .advancedReasoning,
                contextWindow: 200_000,
                supportsStreaming: true,
                supportsToolCalling: true,
                supportsAgenticUse: true,
                supportsSubagents: true,
                supportsVision: true,
                supportsStructuredOutput: true,
                priority: lower.contains("sonnet") ? 15 : (lower.contains("haiku") ? 14 : 25),
                statusDescription: "Available",
                nativeProvider: .anthropic
            )
        }
    }

    private func discoverOpenAIModels() async -> [AssistDiscoveredModel] {
        guard let key = store.readString(SecretAccount.openAIKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else { return [] }
        guard let url = URL(string: "https://api.openai.com/v1/models") else { return [] }
        do {
            let (data, status) = try await transport.get(url: url, headers: [
                "Authorization": "Bearer \(key)",
            ], timeout: 8)
            guard status == 200 else { return [] }
            return Self.parseOpenAIModels(data)
        } catch {
            return []
        }
    }

    public nonisolated static func parseOpenAIModels(_ data: Data) -> [AssistDiscoveredModel] {
        struct OpenAIListResponse: Decodable {
            struct Entry: Decodable { let id: String }
            let data: [Entry]?
        }
        guard let decoded = try? JSONDecoder().decode(OpenAIListResponse.self, from: data) else { return [] }
        var results: [AssistDiscoveredModel] = []
        for entry in decoded.data ?? [] {
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
            results.append(AssistDiscoveredModel(
                id: id,
                displayName: id,
                providerID: "openai",
                providerName: "OpenAI",
                modelIdentifier: id,
                capabilities: .advancedReasoning,
                contextWindow: 128_000,
                supportsStreaming: true,
                supportsToolCalling: true,
                supportsAgenticUse: true,
                supportsSubagents: true,
                supportsVision: lower.contains("4o") || lower.contains("vision"),
                supportsStructuredOutput: true,
                priority: lower.contains("mini") ? 18 : 12,
                statusDescription: "Available",
                nativeProvider: .openAI
            ))
        }
        return results
    }

    private func discoverMistralModels() async -> [AssistDiscoveredModel] {
        guard let key = store.readString(SecretAccount.mistralKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else { return [] }
        guard let url = URL(string: "https://api.mistral.ai/v1/models") else { return [] }
        do {
            let (data, status) = try await transport.get(url: url, headers: [
                "Authorization": "Bearer \(key)",
            ], timeout: 8)
            guard status == 200 else { return [] }
            return Self.parseMistralModels(data)
        } catch {
            return []
        }
    }

    public nonisolated static func parseMistralModels(_ data: Data) -> [AssistDiscoveredModel] {
        struct MistralResponse: Decodable {
            struct Entry: Decodable { let id: String }
            let data: [Entry]?
        }
        guard let decoded = try? JSONDecoder().decode(MistralResponse.self, from: data),
              let entries = decoded.data, !entries.isEmpty else { return [] }
        return entries.compactMap { entry in
            let lower = entry.id.lowercased()
            if lower.contains("embed") { return nil }
            return AssistDiscoveredModel(
                id: entry.id,
                displayName: entry.id,
                providerID: "mistral",
                providerName: "Mistral",
                modelIdentifier: entry.id,
                capabilities: .advancedReasoning,
                contextWindow: 128_000,
                supportsStreaming: true,
                supportsToolCalling: true,
                supportsAgenticUse: true,
                supportsSubagents: true,
                supportsVision: lower.contains("pixtral"),
                supportsStructuredOutput: true,
                priority: 28,
                statusDescription: "Available",
                nativeProvider: .mistral
            )
        }
    }

    private func discoverQwenModels() async -> [AssistDiscoveredModel] {
        guard let key = store.readString(SecretAccount.qwenKey)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty else { return [] }
        guard let url = URL(string: "https://dashscope.aliyuncs.com/compatible-mode/v1/models") else { return [] }
        do {
            let (data, status) = try await transport.get(url: url, headers: [
                "Authorization": "Bearer \(key)",
            ], timeout: 8)
            guard status == 200 else { return [] }
            return Self.parseQwenModels(data)
        } catch {
            return []
        }
    }

    public nonisolated static func parseQwenModels(_ data: Data) -> [AssistDiscoveredModel] {
        struct QwenResponse: Decodable {
            struct Entry: Decodable { let id: String }
            let data: [Entry]?
        }
        guard let decoded = try? JSONDecoder().decode(QwenResponse.self, from: data),
              let entries = decoded.data, !entries.isEmpty else { return [] }
        return entries.compactMap { entry in
            let lower = entry.id.lowercased()
            if lower.contains("embed") { return nil }
            return AssistDiscoveredModel(
                id: entry.id,
                displayName: entry.id,
                providerID: "qwen",
                providerName: "Qwen",
                modelIdentifier: entry.id,
                capabilities: .advancedReasoning,
                contextWindow: 128_000,
                supportsStreaming: true,
                supportsToolCalling: true,
                supportsAgenticUse: true,
                supportsSubagents: true,
                supportsVision: lower.contains("vl"),
                supportsStructuredOutput: true,
                priority: 30,
                statusDescription: "Available",
                nativeProvider: .qwen
            )
        }
    }

    public static func candidates(from discovered: [AssistDiscoveredModel]) -> [AssistCandidateModel] {
        discovered.map { model in
            let provider: ProviderKind
            let routableID: String
            let endpointURL: String?
            switch model.nativeProvider {
            case .gemini:
                provider = .openRouter
                routableID = "google/\(model.id)"
                endpointURL = nil
            case .anthropic:
                provider = .openRouter
                routableID = "anthropic/\(model.id)"
                endpointURL = nil
            case .openAI:
                provider = .openAI
                routableID = model.id
                endpointURL = nil
            case .mistral:
                provider = .openRouter
                routableID = "mistralai/\(model.id)"
                endpointURL = "https://api.mistral.ai/v1"
            case .qwen:
                provider = .openRouter
                routableID = "qwen/\(model.id)"
                endpointURL = nil
            }
            return AssistCandidateModel(
                id: model.id,
                displayName: model.displayName,
                provider: provider,
                modelIdentifier: routableID,
                capabilities: model.capabilities,
                contextWindow: model.contextWindow,
                supportsStreaming: model.supportsStreaming,
                supportsToolCalling: model.supportsToolCalling,
                supportsAgenticUse: model.supportsAgenticUse,
                supportsSubagents: model.supportsSubagents,
                supportsVision: model.supportsVision,
                supportsStructuredOutput: model.supportsStructuredOutput,
                priority: model.priority,
                isConfigured: model.isConfigured,
                hasCredentials: model.isConfigured,
                source: .provider,
                statusDescription: model.statusDescription,
                endpointURL: endpointURL,
                isSynthetic: model.isSynthetic
            )
        }
    }

    public func candidates() -> [AssistCandidateModel] {
        Self.candidates(from: discoveredModels)
    }
}
