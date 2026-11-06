import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Provider model discovery (Wave 16, Slice D)
//
// Ported from Legacy (Dylan's own code; direct port authorised under
// MIT, spec-first where it costs nothing):
//   * `SwiftCode/Backend/Assist/AssistModelDiscoveryService.swift` —
//     the Gemini / Anthropic / OpenAI / Mistral / Qwen discovery
//     functions, their list endpoints, request headers, response
//     shapes, filters and priorities. Wave 9 ported only the
//     OpenRouter leg (into `OpenRouterProvider.listModels`); this
//     file ports the other five.
//
// Discovery feeds the router's discovered set
// (`AssistModelRouting.swift`): `candidates(from:)` converts
// discovered models to `AssistCandidateModel`s, and the host
// passes those to `AssistModelRouter.eligibleCandidates` /
// `resolveDefaultModel`. There is no parallel registry: the
// service holds no selection state and picks nothing.
//
// Endpoints (all real list-models endpoints; nothing invented):
//   * Gemini:    GET https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000&key=<key>
//   * Anthropic: GET https://api.anthropic.com/v1/models?limit=1000
//                (headers `x-api-key`, `anthropic-version: 2023-06-01`)
//   * OpenAI:    GET https://api.openai.com/v1/models (Bearer)
//   * Mistral:   GET https://api.mistral.ai/v1/models (Bearer)
//   * Qwen:      GET https://dashscope.aliyuncs.com/compatible-mode/v1/models (Bearer)
//
// Adaptations:
//   * No `@Observable` / `@MainActor` singleton: this is an actor
//     the host owns (`AssistModelDiscoveryService(store:)`). There
//     is no `shared` — the host creates one per secret store and
//     transport, which is what makes the service testable with a
//     stub transport and `MemorySecretStore`.
//   * No `CustomEndpointManager` / `OfflineModelManager` /
//     `SCCloudModelDiscovery` legs: custom & local endpoints and
//     the cloud catalog belong to other slices; the host's
//     `survey()` covers Apple Foundation Models, OpenCode,
//     Hermes, Meta and the local servers. This service covers
//     exactly the five direct-provider legs named above, plus
//     the Antigravity-catalog fallback for Gemini (below).
//   * Keys come from the `SecretStore` (`gemini.api-key` etc.),
//     one canonical account per provider. Legacy also tried
//     several alternate keychain keys and `APIKeyManager`; SwiftCode
//     keeps one account per provider, so a key stored under a
//     Legacy-era name must be re-entered in Settings.
//   * `hiddenProviderNames` / `removedModelIDs` are session
//     state in this service (Legacy persisted them in
//     UserDefaults). Persisting them in `AssistantSettings` is
//     follow-up work; a removal still hides the model for the
//     rest of the session, and Foundation Models can never be
//     removed, as in Legacy.
//   * Gemini with no key, with Google OAuth, or with a failed /
//     empty live fetch falls back to the Antigravity catalog
//     (Legacy `fallbackAntigravityModels`, verbatim): the catalog
//     models are returned marked synthetic, configured only when
//     the host reports a Google OAuth session. The sign-in flow
//     itself is not model fetching — the host owns it and passes
//     `isGoogleOAuthAuthenticated`.
//   * A provider whose list endpoint fails (non-200, network
//     error, unparseable body, empty after filtering — except
//     Gemini, which falls back to the catalog) contributes no
//     models and records its error in `lastDiscoveryErrors`.
//     Discovery never invents a model to fill the gap.

// MARK: - Transport

/// One HTTP GET, injectable so tests can stub the network
/// without live calls or real credentials.
public protocol ModelDiscoveryTransport: Sendable {
    /// Returns the response body and HTTP status. Throws only
    /// for transport failures (no connection, timeout).
    func get(url: URL, headers: [String: String], timeout: TimeInterval) async throws -> (data: Data, status: Int)
}

/// The live transport: `HTTP.send` (the same minimal HTTP the
/// providers use), 8s per request like Legacy.
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

// MARK: - Discovered model

/// Which direct provider a discovered model came from.
public enum ModelDiscoveryProvider: String, Sendable, CaseIterable {
    case gemini
    case anthropic
    case openAI
    case mistral
    case qwen
}

/// One model returned by a provider's list endpoint (Legacy
/// `AssistAvailableModel`, reduced to the fields discovery
/// actually fills in).
public struct AssistDiscoveredModel: Sendable, Equatable {
    /// The provider-side model id (what the list endpoint
    /// returned, e.g. `gemini-2.5-flash`).
    public var id: String
    public var displayName: String
    /// Legacy `providerID`: "gemini" / "anthropic" / "openai" /
    /// "mistral" / "qwen".
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
    /// Lower wins (Legacy `priority`).
    public var priority: Int
    public var statusDescription: String
    /// Whether a credential / session exists for this model.
    /// A list-endpoint hit only happens with a key, so a
    /// discovered model is configured. Catalog-fallback models
    /// are configured only when the host reports a Google OAuth
    /// session.
    public var isConfigured: Bool
    /// Whether the model can be used right now. For
    /// list-endpoint models this is always true; for
    /// catalog-fallback models it follows `isConfigured`
    /// (Legacy set both flags from the same credential verdict).
    public var isAvailable: Bool
    /// True when this record came from the Antigravity catalog
    /// fallback, not from the provider's list endpoint.
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

// MARK: - Service

/// Discovers models from the five direct providers' list
/// endpoints and converts them into router candidates.
public actor AssistModelDiscoveryService {
    /// How long a discovery result is reused (Legacy
    /// `discoveryCacheLifetime`: 300s).
    public static let discoveryCacheLifetime: TimeInterval = 300

    private let store: SecretStore
    private let transport: any ModelDiscoveryTransport
    private let catalog: AntigravitySDKCatalog
    private let keyRotation: GeminiKeyRotationManager?

    /// Set by the host when the user is signed in with a Google
    /// account (the `SwiftCodeGoogleAuth` session). The sign-in flow
    /// is not model fetching; this flag only decides whether
    /// catalog-fallback Gemini models count as configured.
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

    /// All discovered models, from the cache when it is fresh.
    /// Provider legs run concurrently; a failing leg contributes
    /// nothing and records its error instead of failing the
    /// whole discovery (Legacy `discoverAllModels`, verbatim in
    /// shape — the OpenRouter / Meta / Apple / custom legs live
    /// in the host's `survey()`, not here).
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

    /// The discovered models the router may actually use
    /// (Legacy `agentCompatibleModels`, verbatim: agentic +
    /// tool-calling + available, minus removed / hidden).
    public var agentCompatibleModels: [AssistDiscoveredModel] {
        discoveredModels.filter {
            !removedModelIDs.contains($0.modelIdentifier) &&
            !removedModelIDs.contains($0.id) &&
            !hiddenProviderNames.contains($0.providerName) &&
            $0.supportsAgenticUse && $0.supportsToolCalling && $0.isAvailable
        }
    }

    /// Permanently removes a model for this session. Foundation
    /// Models can never be removed (Legacy `removeModel`,
    /// verbatim guard).
    public func removeModel(_ modelID: String) {
        guard !isFoundationModel(id: modelID) else { return }
        removedModelIDs.insert(modelID)
        discoveredModels.removeAll { $0.modelIdentifier == modelID || $0.id == modelID }
    }

    /// Hides a provider for this session. Foundation Models can
    /// never be hidden (Legacy `removeProvider`, verbatim guard).
    public func removeProvider(_ name: String) {
        guard name != "Apple Foundation Models" else { return }
        hiddenProviderNames.insert(name)
    }

    /// Foundation Models is a system model integration and may
    /// NEVER be deleted (Legacy `isFoundationModel`, id form).
    public static func isFoundationModel(id: String) -> Bool {
        let lower = id.lowercased()
        return lower.contains("afm") || lower.contains("apple")
    }

    public func isFoundationModel(id: String) -> Bool {
        Self.isFoundationModel(id: id)
    }

    // MARK: - Gemini

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
        // No key, or signed in with Google: strictly use the
        // Antigravity catalog, NOT the direct Gemini endpoint
        // (Legacy `discoverGeminiModels`, verbatim).
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

    /// The Antigravity catalog as discovered models (Legacy
    /// `fallbackAntigravityModels`). Live catalog entries are
    /// marked "Available via Google Account"; seed entries say
    /// so explicitly. Configured only when the host reports a
    /// Google OAuth session.
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

    /// Parses a Gemini `GET /v1beta/models` body (Legacy
    /// `discoverGeminiModels` decoding + filtering, verbatim):
    /// only `generateContent` models (an empty method list is
    /// allowed through), `models/` prefix stripped, embedding /
    /// aqa / imagen excluded, context from `inputTokenLimit`
    /// (default 1,000,000), flash models prioritised.
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

    // MARK: - Anthropic / Claude

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

    /// Parses an Anthropic `GET /v1/models` body (`data[].id` /
    /// `display_name`; context 200,000 for every model, as in
    /// Legacy `discoverClaudeModels`).
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

    // MARK: - OpenAI

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

    /// Parses an OpenAI `GET /v1/models` body (`data[].id`) with
    /// Legacy `discoverOpenAIModels` exclusions, verbatim:
    /// embedding, dall-e, tts, whisper, moderation, audio,
    /// realtime, text-search / text-similarity, davinci,
    /// babbage, curie. Vision when the id mentions `4o` or
    /// `vision`; context 128,000; mini models prioritised.
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

    // MARK: - Mistral

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

    /// Parses a Mistral `GET /v1/models` body (`data[].id`),
    /// excluding embedding models (Legacy
    /// `discoverMistralModels`, verbatim). Vision when the id
    /// mentions `pixtral`; context 128,000.
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

    // MARK: - Qwen

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

    /// Parses a DashScope compatible-mode `GET /v1/models` body
    /// (`data[].id`), excluding embedding models (Legacy
    /// `discoverQwenModels`, verbatim). Vision when the id
    /// mentions `vl`; context 128,000.
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

    // MARK: - Feeding the router

    /// Converts discovered models into router candidates (the
    /// discovered set `AssistModelRouter` consumes). The host
    /// provider mapping follows Wave 15 §23.2: vendors SwiftCode has
    /// no direct provider for (Gemini, Anthropic, Mistral, Qwen)
    /// route through `.openRouter`, the host that can serve those
    /// models; OpenAI routes through `.openAI`.
    ///
    /// Because OpenRouter only serves models in `provider/model`
    /// form, a natively-discovered id is translated to its
    /// OpenRouter id in `modelIdentifier` — `google/<id>` for
    /// Gemini, `anthropic/<id>` for Claude, `mistralai/<id>` for
    /// Mistral, `qwen/<id>` for Qwen — while `id` keeps the
    /// native id the list endpoint returned. Callers must send
    /// `modelIdentifier`, not `id`, when the provider is
    /// OpenRouter. The translation uses OpenRouter's published
    /// provider slugs; it is a routing translation, not a
    /// discovery claim — the model itself was genuinely listed
    /// by its own provider.
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

    /// The router candidates for the last discovery run.
    public func candidates() -> [AssistCandidateModel] {
        Self.candidates(from: discoveredModels)
    }
}
