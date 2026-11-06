import Foundation
import Testing
@testable import SwiftCodeAssistant

// MARK: - Provider model discovery (Wave 16, Slice D)
//
// Stub transport only: no live network, no real API keys. Fake
// keys are assembled from parts so no source line carries a
// key-shaped literal (see scan-public).

@Suite struct AssistModelDiscoveryTests {
    /// A stub transport keyed by host, counting calls.
    final class StubTransport: ModelDiscoveryTransport, @unchecked Sendable {
        private let lock = NSLock()
        var stubbed: [String: (Data, Int)] = [:]
        var calls: [URL] = []

        func get(url: URL, headers: [String: String], timeout: TimeInterval) async throws -> (data: Data, status: Int) {
            let response = lock.withLock {
                calls.append(url)
                return stubbed[url.host() ?? ""]
            }
            guard let response else { throw URLError(.badURL) }
            return response
        }

        var callCount: Int {
            lock.lock(); defer { lock.unlock() }
            return calls.count
        }
    }

    static func fakeKey(_ tag: String) -> String {
        "test-" + "key-" + tag + String(repeating: "9", count: 20)
    }

    static func storeWithKeys() -> MemorySecretStore {
        let store = MemorySecretStore()
        for (account, tag) in [
            (SecretAccount.geminiKey, "gemini"),
            (SecretAccount.anthropicKey, "anthropic"),
            (SecretAccount.openAIKey, "openai"),
            (SecretAccount.mistralKey, "mistral"),
            (SecretAccount.qwenKey, "qwen"),
        ] {
            try? store.write(Data(fakeKey(tag).utf8), for: account)
        }
        return store
    }

    static func service(store: MemorySecretStore? = nil, transport: StubTransport? = nil) -> (AssistModelDiscoveryService, StubTransport) {
        let t = transport ?? StubTransport()
        let s = AssistModelDiscoveryService(
            store: store ?? storeWithKeys(),
            transport: t,
            catalog: AntigravitySDKCatalog()
        )
        return (s, t)
    }

    // MARK: - Per-provider parsing

    @Test func geminiParsesFiltersAndStripsPrefix() {
        let body = """
        {"models": [
          {"name": "models/gemini-2.5-flash", "displayName": "Gemini 2.5 Flash", "supportedGenerationMethods": ["generateContent"], "inputTokenLimit": 1000000},
          {"name": "models/gemini-2.5-pro", "displayName": "Gemini 2.5 Pro", "supportedGenerationMethods": ["generateContent"], "inputTokenLimit": 2000000},
          {"name": "models/text-embedding-004", "displayName": "Embedding", "supportedGenerationMethods": ["embedContent"], "inputTokenLimit": 8000},
          {"name": "models/gemini-imagen-1", "displayName": "Imagen", "supportedGenerationMethods": ["generateContent"], "inputTokenLimit": 1000},
          {"name": "models/gemini-2.5-flash-lite", "displayName": "Flash Lite", "supportedGenerationMethods": [], "inputTokenLimit": 1000000}
        ]}
        """.data(using: .utf8)!
        let models = AssistModelDiscoveryService.parseGeminiModels(body)
        #expect(models.map { $0.id } == ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-2.5-flash-lite"])
        #expect(models[0].priority == 10)
        #expect(models[1].priority == 20)
        #expect(models[1].contextWindow == 2_000_000)
        #expect(models.allSatisfy { $0.providerID == "gemini" && !$0.isSynthetic })
    }

    @Test func claudeParsesWithPriorities() {
        let body = """
        {"data": [
          {"id": "claude-sonnet-4-5", "display_name": "Claude Sonnet 4.5"},
          {"id": "claude-haiku-4-5"},
          {"id": "claude-opus-4-1", "display_name": "Claude Opus 4.1"}
        ]}
        """.data(using: .utf8)!
        let models = AssistModelDiscoveryService.parseClaudeModels(body)
        #expect(models.map { $0.id } == ["claude-sonnet-4-5", "claude-haiku-4-5", "claude-opus-4-1"])
        #expect(models[0].displayName == "Claude Sonnet 4.5")
        #expect(models[1].displayName == "claude-haiku-4-5")
        #expect(models[0].priority == 15)
        #expect(models[1].priority == 14)
        #expect(models[2].priority == 25)
        #expect(models.allSatisfy { $0.contextWindow == 200_000 && $0.providerID == "anthropic" })
    }

    @Test func openAIParsesWithLegacyExclusions() {
        let body = """
        {"data": [
          {"id": "gpt-4o"},
          {"id": "gpt-4o-mini"},
          {"id": "text-embedding-3-small"},
          {"id": "dall-e-3"},
          {"id": "whisper-1"},
          {"id": "gpt-4o-audio-preview"},
          {"id": "o3-mini"}
        ]}
        """.data(using: .utf8)!
        let models = AssistModelDiscoveryService.parseOpenAIModels(body)
        #expect(models.map { $0.id } == ["gpt-4o", "gpt-4o-mini", "o3-mini"])
        #expect(models[0].supportsVision == true)
        #expect(models[1].priority == 18)
        #expect(models[2].priority == 12)
        #expect(models.allSatisfy { $0.contextWindow == 128_000 })
    }

    @Test func mistralParsesExcludingEmbeddings() {
        let body = """
        {"data": [
          {"id": "mistral-large-2411"},
          {"id": "mistral-embed"},
          {"id": "pixtral-12b-2409"},
          {"id": "codestral-2501"}
        ]}
        """.data(using: .utf8)!
        let models = AssistModelDiscoveryService.parseMistralModels(body)
        #expect(models.map { $0.id } == ["mistral-large-2411", "pixtral-12b-2409", "codestral-2501"])
        #expect(models[1].supportsVision == true)
        #expect(models[0].supportsVision == false)
        #expect(models.allSatisfy { $0.priority == 28 })
    }

    @Test func qwenParsesWithVisionFlag() {
        let body = """
        {"data": [
          {"id": "qwen-max"},
          {"id": "qwen-vl-max"},
          {"id": "text-embedding-v3"}
        ]}
        """.data(using: .utf8)!
        let models = AssistModelDiscoveryService.parseQwenModels(body)
        #expect(models.map { $0.id } == ["qwen-max", "qwen-vl-max"])
        #expect(models[0].supportsVision == false)
        #expect(models[1].supportsVision == true)
        #expect(models.allSatisfy { $0.priority == 30 })
    }

    @Test func malformedBodiesParseToNothing() {
        let bad = "not json".data(using: .utf8)!
        #expect(AssistModelDiscoveryService.parseGeminiModels(bad).isEmpty)
        #expect(AssistModelDiscoveryService.parseClaudeModels(bad).isEmpty)
        #expect(AssistModelDiscoveryService.parseOpenAIModels(bad).isEmpty)
        #expect(AssistModelDiscoveryService.parseMistralModels(bad).isEmpty)
        #expect(AssistModelDiscoveryService.parseQwenModels(bad).isEmpty)
        #expect(AssistModelDiscoveryService.parseClaudeModels("{}".data(using: .utf8)!).isEmpty)
    }

    // MARK: - Discovery runs

    @Test func discoverAllRunsEveryLegConcurrently() async {
        let (service, transport) = Self.service()
        transport.stubbed = [
            "generativelanguage.googleapis.com": ("""
            {"models": [{"name": "models/gemini-2.5-flash", "displayName": "Gemini 2.5 Flash", "supportedGenerationMethods": ["generateContent"], "inputTokenLimit": 1000000}]}
            """.data(using: .utf8)!, 200),
            "api.anthropic.com": ("""
            {"data": [{"id": "claude-sonnet-4-5", "display_name": "Claude Sonnet 4.5"}]}
            """.data(using: .utf8)!, 200),
            "api.openai.com": ("""
            {"data": [{"id": "gpt-4o"}]}
            """.data(using: .utf8)!, 200),
            "api.mistral.ai": ("""
            {"data": [{"id": "mistral-large-2411"}]}
            """.data(using: .utf8)!, 200),
            "dashscope.aliyuncs.com": ("""
            {"data": [{"id": "qwen-max"}]}
            """.data(using: .utf8)!, 200),
        ]
        let models = await service.discoverAllModels()
        #expect(models.map { $0.id } == ["gemini-2.5-flash", "claude-sonnet-4-5", "gpt-4o", "mistral-large-2411", "qwen-max"])
        #expect(transport.callCount == 5)
        #expect(await service.lastDiscoveryErrors.isEmpty)
    }

    @Test func failingLegContributesNothingAndRecordsError() async {
        let (service, transport) = Self.service()
        transport.stubbed = [
            "generativelanguage.googleapis.com": (Data(), 429),
            "api.anthropic.com": ("""
            {"data": [{"id": "claude-sonnet-4-5"}]}
            """.data(using: .utf8)!, 200),
            "api.openai.com": (Data(), 401),
            "api.mistral.ai": (Data(), 500),
            "dashscope.aliyuncs.com": (Data(), 500),
        ]
        let models = await service.discoverAllModels()
        // Gemini falls back to the Antigravity seed catalog (9
        // synthetic models); the other failing legs contribute
        // nothing, and only Gemini records an error (the other
        // legs fail silently, as in Legacy).
        #expect(models.contains { $0.id == "claude-sonnet-4-5" })
        #expect(models.filter { $0.isSynthetic }.count == 9)
        #expect(await service.lastDiscoveryErrors["Gemini"]?.contains("429") == true)
    }

    @Test func noKeysYieldsOnlyTheCatalogFallback() async {
        let (service, _) = Self.service(store: MemorySecretStore())
        let models = await service.discoverAllModels()
        #expect(models.count == 9)
        #expect(models.allSatisfy { $0.isSynthetic })
        #expect(models.allSatisfy { !$0.isConfigured && !$0.isAvailable })
        #expect(models.allSatisfy { $0.statusDescription.contains("Antigravity catalog") })
    }

    @Test func oauthMakesCatalogFallbackConfigured() async {
        let transport = StubTransport()
        let service = AssistModelDiscoveryService(
            store: MemorySecretStore(),
            transport: transport,
            catalog: AntigravitySDKCatalog(),
            isGoogleOAuthAuthenticated: true
        )
        let models = await service.discoverAllModels()
        #expect(models.count == 9)
        #expect(models.allSatisfy { $0.isSynthetic && $0.isConfigured && $0.isAvailable })
    }

    @Test func cacheIsReusedUntilForced() async {
        let (service, transport) = Self.service()
        transport.stubbed = [
            "generativelanguage.googleapis.com": ("""
            {"models": [{"name": "models/gemini-2.5-flash", "supportedGenerationMethods": ["generateContent"]}]}
            """.data(using: .utf8)!, 200),
            "api.anthropic.com": ("""
            {"data": [{"id": "claude-sonnet-4-5"}]}
            """.data(using: .utf8)!, 200),
            "api.openai.com": ("""
            {"data": [{"id": "gpt-4o"}]}
            """.data(using: .utf8)!, 200),
            "api.mistral.ai": ("""
            {"data": [{"id": "mistral-large-2411"}]}
            """.data(using: .utf8)!, 200),
            "dashscope.aliyuncs.com": ("""
            {"data": [{"id": "qwen-max"}]}
            """.data(using: .utf8)!, 200),
        ]
        _ = await service.discoverAllModels()
        #expect(transport.callCount == 5)
        _ = await service.discoverAllModels()
        #expect(transport.callCount == 5)
        _ = await service.discoverAllModels(forceRefresh: true)
        #expect(transport.callCount == 10)
    }

    // MARK: - Removal

    @Test func removeModelRefusesFoundationModels() async {
        let (service, _) = Self.service(store: MemorySecretStore())
        _ = await service.discoverAllModels()
        await service.removeModel("afm3-core")
        #expect(await service.removedModelIDs.isEmpty)
        await service.removeModel("gemini-3.8-flash")
        #expect(await service.removedModelIDs == ["gemini-3.8-flash"])
        #expect(await service.discoveredModels.allSatisfy { $0.id != "gemini-3.8-flash" })
        await service.removeProvider("Apple Foundation Models")
        #expect(await service.hiddenProviderNames.isEmpty)
    }

    @Test func agentCompatibleExcludesRemovedAndUnconfigured() async {
        let (service, _) = Self.service(store: MemorySecretStore())
        _ = await service.discoverAllModels()
        // Catalog fallback without OAuth: unconfigured, so none
        // are agent-compatible.
        #expect(await service.agentCompatibleModels.isEmpty)
    }

    // MARK: - Feeding the router

    @Test func candidatesTranslateToRoutableOpenRouterIDs() {
        let discovered = [
            AssistDiscoveredModel(id: "gemini-2.5-flash", providerID: "gemini", providerName: "Gemini", nativeProvider: .gemini),
            AssistDiscoveredModel(id: "claude-sonnet-4-5", providerID: "anthropic", providerName: "Claude", nativeProvider: .anthropic),
            AssistDiscoveredModel(id: "gpt-4o", providerID: "openai", providerName: "OpenAI", nativeProvider: .openAI),
            AssistDiscoveredModel(id: "mistral-large-2411", providerID: "mistral", providerName: "Mistral", nativeProvider: .mistral),
            AssistDiscoveredModel(id: "qwen-max", providerID: "qwen", providerName: "Qwen", nativeProvider: .qwen),
        ]
        let candidates = AssistModelDiscoveryService.candidates(from: discovered)
        #expect(candidates[0].provider == .openRouter)
        #expect(candidates[0].modelIdentifier == "google/gemini-2.5-flash")
        #expect(candidates[0].id == "gemini-2.5-flash")
        #expect(candidates[1].modelIdentifier == "anthropic/claude-sonnet-4-5")
        #expect(candidates[2].provider == .openAI)
        #expect(candidates[2].modelIdentifier == "gpt-4o")
        #expect(candidates[3].modelIdentifier == "mistralai/mistral-large-2411")
        #expect(candidates[3].endpointURL == "https://api.mistral.ai/v1")
        #expect(candidates[4].modelIdentifier == "qwen/qwen-max")
        #expect(candidates.allSatisfy { $0.hasCredentials && $0.isConfigured && !$0.isSynthetic })
    }

    @Test func candidatesPreserveSyntheticMarking() {
        let discovered = [
            AssistDiscoveredModel(id: "gemini-3.8-flash", providerID: "gemini", providerName: "Gemini", isSynthetic: true, nativeProvider: .gemini),
        ]
        let candidates = AssistModelDiscoveryService.candidates(from: discovered)
        #expect(candidates[0].isSynthetic == true)
        #expect(candidates[0].modelIdentifier == "google/gemini-3.8-flash")
    }
}
