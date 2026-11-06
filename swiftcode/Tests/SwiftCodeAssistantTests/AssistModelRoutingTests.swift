import Foundation
import Testing
@testable import SwiftCodeAssistant

// MARK: - SDK provider paths / router / selection (Wave 15)
//
// Fixtures only: no live network, no real API keys, no real
// providers. Candidates are hand-built values; the router never
// touches the secret store or the network.

@Suite struct AssistModelRoutingTests {
    // A small eligible set: two OpenRouter models, one OpenAI
    // model, one custom (user-provided) model, one unconfigured
    // model, one tool-less model.
    static func candidates() -> [AssistCandidateModel] {
        [
            AssistCandidateModel(id: "anthropic/claude-sonnet-4-5", displayName: "Claude Sonnet", provider: .openRouter, priority: 5, source: .provider),
            AssistCandidateModel(id: "gpt-4o", displayName: "GPT-4o", provider: .openAI, priority: 10, contextWindow: 128_000, source: .provider),
            AssistCandidateModel(id: "my-fine-tune", displayName: "My fine-tune", provider: .openRouter, priority: 1, source: .custom),
            AssistCandidateModel(id: "unconfigured/model", displayName: "Unconfigured", provider: .openRouter, isConfigured: false, source: .provider),
            AssistCandidateModel(id: "chat-only/model", displayName: "Chat only", provider: .openRouter, supportsToolCalling: false, supportsAgenticUse: false, source: .provider),
        ]
    }

    static func openRouterCandidates() -> [AssistCandidateModel] {
        [
            AssistCandidateModel(id: "anthropic/claude-sonnet-4-5", displayName: "Claude Sonnet", provider: .openRouter, priority: 5, source: .provider),
            AssistCandidateModel(id: "anthropic/claude-haiku-4-5", displayName: "Claude Haiku", provider: .openRouter, priority: 5, source: .provider),
            AssistCandidateModel(id: "google/gemini-2.5-pro", displayName: "Gemini Pro", provider: .openRouter, priority: 10, contextWindow: 1_000_000, source: .provider),
        ]
    }

    // MARK: - Specification (name-based catalog)

    @Test func specificationPrefixesWin() {
        #expect(AssistModelSpecification.specification(for: "opencode:anthropic/claude-sonnet-4-5").provider == .openCode)
        #expect(AssistModelSpecification.specification(for: "hermes:openrouter:meta-llama/llama-4").provider == .hermes)
        #expect(AssistModelSpecification.specification(for: "swiftcode-cloud:qwen3").provider == .scCloud)
        #expect(AssistModelSpecification.specification(for: "swiftcode-cloud").provider == .scCloud)
    }

    @Test func specificationBranches() {
        let claude = AssistModelSpecification.specification(for: "claude-sonnet-4-5")
        #expect(claude.provider == .openRouter && claude.contextWindowTokens == 200_000)
        #expect(claude.displayName == "Claude 3.5 Sonnet")
        #expect(AssistModelSpecification.specification(for: "claude-3-7-sonnet").displayName == "Claude 3.7 Sonnet")
        #expect(AssistModelSpecification.specification(for: "claude-3-haiku").displayName == "Claude 3.5 Haiku")

        let gpt = AssistModelSpecification.specification(for: "gpt-4o")
        #expect(gpt.provider == .openAI && gpt.displayName == "GPT-4o" && gpt.contextWindowTokens == 128_000)
        #expect(gpt.capabilities.contains(.parallelToolCalls))
        #expect(AssistModelSpecification.specification(for: "gpt-4o-mini").displayName == "GPT-4o Mini")
        #expect(AssistModelSpecification.specification(for: "o3-mini").displayName == "o3-mini")

        let gemini = AssistModelSpecification.specification(for: "gemini-2.5-pro")
        #expect(gemini.provider == .openRouter && gemini.contextWindowTokens == 1_000_000)
        #expect(AssistModelSpecification.specification(for: "gemini-flash").displayName == "Gemini 3.8 Flash")

        #expect(AssistModelSpecification.specification(for: "codestral-latest").displayName == "Codestral")
        #expect(AssistModelSpecification.specification(for: "mistral-large").displayName == "Mistral Large")
        #expect(AssistModelSpecification.specification(for: "deepseek-chat").displayName == "DeepSeek V3")
        #expect(AssistModelSpecification.specification(for: "deepseek-chat").contextWindowTokens == 64_000)

        let codex = AssistModelSpecification.specification(for: "codex")
        #expect(codex.provider == .codex && codex.contextWindowTokens == 32_000)
        #expect(!codex.capabilities.contains(.toolCalling))

        let ollama = AssistModelSpecification.specification(for: "ollama:qwen2.5-coder")
        #expect(ollama.provider == .ollama && ollama.contextWindowTokens == 32_000)

        let apple = AssistModelSpecification.specification(for: "apple-foundation")
        #expect(apple.provider == .foundationModels && apple.capabilities == .localFoundation)

        let unknown = AssistModelSpecification.specification(for: "some-future-model-9")
        #expect(unknown.provider == .openRouter && unknown.contextWindowTokens == 128_000)
        #expect(unknown.capabilities == .standardCloud)
    }

    @Test func specificationNormalizesPrompts() {
        let withSystem = AssistModelSpecification.normalizePrompt(systemPrompt: "SYS", userInstructions: "DO", for: "gpt-4o")
        #expect(withSystem == "SYS\n\n# TASK EXECUTION INSTRUCTIONS\nDO")
        let merged = AssistModelSpecification.normalizePrompt(systemPrompt: "SYS", userInstructions: "DO", for: "codex")
        #expect(merged == "SYSTEM DIRECTIVES:\nSYS\n\nUSER REQUEST:\nDO")
    }

    // MARK: - Context budget

    @Test func contextBudget() {
        let budget = AgentModelContextBudget(modelId: "gpt-4o", contextWindowTokens: 128_000)
        #expect(budget.maxInputTokens == 128_000 - 4096)
        #expect(budget.estimatedTokenCount(for: "abcd") == 1)
        #expect(budget.estimatedTokenCount(for: String(repeating: "x", count: 400)) == 100)
        #expect(budget.fitsContext(estimatedTokens: budget.maxInputTokens))
        #expect(!budget.fitsContext(estimatedTokens: budget.maxInputTokens + 1))
        #expect(AssistModelSpecification.contextBudget(for: "claude-sonnet-4-5").contextWindowTokens == 200_000)
    }

    // MARK: - Free-only eligibility

    @Test func freeOnlyEligibility() {
        #expect(AssistModelEligibilityPolicy.isEligible(modelID: "openai/gpt-oss-120b:free", onlyUseFreeModels: true))
        #expect(AssistModelEligibilityPolicy.isEligible(modelID: "FREE-model", onlyUseFreeModels: true))
        #expect(!AssistModelEligibilityPolicy.isEligible(modelID: "gpt-4o", onlyUseFreeModels: true))
        #expect(!AssistModelEligibilityPolicy.isEligible(modelID: "", onlyUseFreeModels: true))
        #expect(!AssistModelEligibilityPolicy.isEligible(modelID: "   ", onlyUseFreeModels: true))
        #expect(AssistModelEligibilityPolicy.isEligible(modelID: "gpt-4o", onlyUseFreeModels: false))
        #expect(AssistModelEligibilityPolicy.filterEligibleModelIDs(["a:free", "b", "c:FREE"], onlyUseFreeModels: true) == ["a:free", "c:FREE"])
        #expect(throws: AssistModelEligibilityError.self) {
            try AssistModelEligibilityPolicy.validateExecutionEligibility(modelID: "gpt-4o", provider: "openai", onlyUseFreeModels: true)
        }
        try? AssistModelEligibilityPolicy.validateExecutionEligibility(modelID: "gpt-4o", onlyUseFreeModels: false)
    }

    // MARK: - Stored model identifiers

    @Test func openCodeModelID() {
        let parsed = OpenCodeModelID.parse("opencode:anthropic/claude-sonnet-4-5")
        #expect(parsed?.providerID == "anthropic" && parsed?.modelID == "claude-sonnet-4-5")
        #expect(parsed?.storedID == "opencode:anthropic/claude-sonnet-4-5")
        #expect(parsed?.displayName == "anthropic/claude-sonnet-4-5")
        #expect(OpenCodeModelID.parse("anthropic/claude-sonnet-4-5") == nil)
        #expect(OpenCodeModelID.parse("opencode:") == nil)
        #expect(OpenCodeModelID.parse("opencode:anthropic/") == nil)
        #expect(OpenCodeModelID.parse("opencode:/model") == nil)
        #expect(OpenCodeModelID.isOpenCodeModelID("opencode:a/b"))
        #expect(!OpenCodeModelID.isOpenCodeModelID("openrouter/a/b"))
    }

    @Test func hermesModelID() {
        let parsed = HermesModelID.parse("hermes:openrouter:meta-llama/llama-4")
        #expect(parsed?.spec == "openrouter:meta-llama/llama-4")
        #expect(parsed?.provider == "openrouter")
        #expect(parsed?.model == "meta-llama/llama-4")
        #expect(parsed?.storedID == "hermes:openrouter:meta-llama/llama-4")
        let bare = HermesModelID.parse("hermes:llama-4")
        #expect(bare?.provider == nil && bare?.model == "llama-4")
        #expect(HermesModelID.parse("hermes:") == nil)
        #expect(HermesModelID.parse("hermes:openrouter:") == nil)
        #expect(HermesModelID.parse("gpt-4o") == nil)
        #expect(HermesModelID.isHermesModelID("hermes:x"))
    }

    @Test func openCodeConfiguration() {
        var settings = AssistantSettings()
        settings.openCodeURL = "http://127.0.0.1:4096"
        settings.openCodeAgentName = "swiftcode"
        let config = OpenCodeConfiguration(settings: settings)
        #expect(config.serverURL.absoluteString == "http://127.0.0.1:4096")
        #expect(config.agentName == "swiftcode")
        #expect(config.isLoopback)
        #expect(config.port == 4096)

        var other = AssistantSettings()
        var custom = OpenCodeConfiguration(serverURL: URL(string: "https://example.invalid:8443")!, agentName: "custom", managedServerEnabled: true)
        #expect(!custom.isLoopback)
        #expect(custom.port == 8443)
        custom.apply(to: &other)
        #expect(other.openCodeURL == "https://example.invalid:8443")
        #expect(other.openCodeAgentName == "custom")

        #expect(OpenCodeConfiguration.swiftcodeAgentDefinition.contains("\"*\": deny"))
        #expect(OpenCodeConfiguration.swiftcodeAgentDefinition.contains("never runs tools itself"))
        #expect(OpenCodeConfiguration.defaultServerURL.absoluteString == "http://127.0.0.1:4096")
        #expect(OpenCodeConfiguration.defaultAgentName == "swiftcode")

        // A bad URL falls back to the default instead of crashing.
        var broken = AssistantSettings()
        broken.openCodeURL = "not a url"
        #expect(OpenCodeConfiguration(settings: broken).serverURL == OpenCodeConfiguration.defaultServerURL)
    }

    // MARK: - Ranking

    @Test func rankModelsPrefersSelectedThenFewestFailures() {
        let models = Self.openRouterCandidates()
        let ranked = AssistModelRouter.rankModels(models, preferredIdentifier: "google/gemini-2.5-pro")
        #expect(ranked.first?.id == "google/gemini-2.5-pro")
        // Without a preference: lower priority first, then subagents,
        // then the larger context window.
        let plain = AssistModelRouter.rankModels(models)
        #expect(plain.map(\.id) == ["anthropic/claude-sonnet-4-5", "anthropic/claude-haiku-4-5", "google/gemini-2.5-pro"])
        // A failure count demotes the model below its priority peer.
        let withFailures = AssistModelRouter.rankModels(models: models, preferredIdentifier: nil, failedAttemptsCount: ["anthropic/claude-sonnet-4-5": 3])
        #expect(withFailures.map(\.id) == ["anthropic/claude-haiku-4-5", "anthropic/claude-sonnet-4-5", "google/gemini-2.5-pro"])
    }

    // MARK: - Eligibility & selection

    @Test func eligibleCandidatesFilter() async {
        let router = AssistModelRouter()
        let eligible = await router.eligibleCandidates(
            from: Self.candidates(), strategy: .providerDefault,
            useProviderModelsOnly: false, useCloudModel: false
        )
        // Tool-less, unconfigured, and custom models are all
        // eligible here (custom is only excluded by the
        // provider-models-only flag); the unconfigured and
        // tool-less ones are not.
        #expect(eligible.map(\.id) == ["my-fine-tune", "anthropic/claude-sonnet-4-5", "gpt-4o"])
    }

    @Test func eligibleCandidatesExcludeCustomWhenProviderModelsOnly() async {
        let router = AssistModelRouter()
        let eligible = await router.eligibleCandidates(
            from: Self.candidates(), strategy: .providerDefault,
            useProviderModelsOnly: true, useCloudModel: false
        )
        #expect(!eligible.contains { $0.source == .custom })
        #expect(eligible.map(\.id) == ["anthropic/claude-sonnet-4-5", "gpt-4o"])
    }

    @Test func eligibleCandidatesAppendCloudAfterAgenticFilter() async {
        let router = AssistModelRouter()
        let eligible = await router.eligibleCandidates(
            from: Self.openRouterCandidates(), strategy: .appModels,
            useProviderModelsOnly: false, useCloudModel: true, cloudConfigured: true
        )
        // One synthetic cloud entry, last, even though it supports
        // no tool calling (it never goes through the agentic filter).
        let cloud = eligible.last
        #expect(cloud?.provider == .scCloud)
        #expect(cloud?.id == "swiftcode-cloud")
        #expect(cloud?.supportsToolCalling == false)
        #expect(cloud?.statusDescription.contains("left today") == true)
    }

    @Test func eligibleCandidatesExcludeQuarantined() async {
        let router = AssistModelRouter()
        await router.markRateLimited(modelID: "anthropic/claude-sonnet-4-5")
        let eligible = await router.eligibleCandidates(
            from: Self.openRouterCandidates(), strategy: .providerDefault,
            useProviderModelsOnly: false, useCloudModel: false
        )
        #expect(!eligible.contains { $0.id == "anthropic/claude-sonnet-4-5" })
        await router.markModelHealthy(modelID: "anthropic/claude-sonnet-4-5")
        let back = await router.eligibleCandidates(
            from: Self.openRouterCandidates(), strategy: .providerDefault,
            useProviderModelsOnly: false, useCloudModel: false
        )
        #expect(back.contains { $0.id == "anthropic/claude-sonnet-4-5" })
    }

    @Test func resolveDefaultModel() {
        let discovered = Self.openRouterCandidates()
        // Cloud short-circuit: never subject to discovery.
        let cloud = AssistModelRouter.resolveDefaultModel(
            preferredID: "swiftcode-cloud:qwen3", discovered: discovered,
            useCloudModel: true, cloudConfigured: true, cloudRemainingToday: 7
        )
        #expect(cloud.provider == .scCloud)
        #expect(cloud.modelIdentifier == "qwen3")
        #expect(cloud.statusDescription == "SwiftCode Cloud · 7/10 left today")
        // Discovered match wins over the spec catalog.
        let match = AssistModelRouter.resolveDefaultModel(
            preferredID: "anthropic/claude-haiku-4-5", discovered: discovered,
            useCloudModel: false
        )
        #expect(match.id == "anthropic/claude-haiku-4-5" && match.displayName == "Claude Haiku")
        // Apple Foundation synthetic model.
        let afm = AssistModelRouter.resolveDefaultModel(
            preferredID: "afm-3-core", discovered: [], useCloudModel: false
        )
        #expect(afm.provider == .foundationModels)
        #expect(afm.contextWindow == 16_000)
        #expect(afm.statusDescription == "On-Device Available (Chat Mode Only)")
        // Unknown id: synthesized from the name-based specification.
        let spec = AssistModelRouter.resolveDefaultModel(
            preferredID: "gpt-4o", discovered: [], useCloudModel: false
        )
        #expect(spec.provider == .openAI && spec.displayName == "GPT-4o")
    }

    @Test func selectNextModel() {
        let models = Self.openRouterCandidates()
        #expect(AssistModelRouter.selectNextModel(excluding: ["anthropic/claude-sonnet-4-5"], from: models)?.id == "anthropic/claude-haiku-4-5")
        #expect(AssistModelRouter.selectNextModel(excluding: Set(models.map(\.id)), from: models) == nil)
    }

    // MARK: - Failure classification & quarantine

    @Test func classifyFailures() {
        struct E: LocalizedError { let message: String; var errorDescription: String? { message } }
        #expect(AssistModelRouter.classify(error: E(message: "HTTP 429 too many requests")) == .quotaExhausted)
        #expect(AssistModelRouter.classify(error: E(message: "rate_limit exceeded")) == .quotaExhausted)
        #expect(AssistModelRouter.classify(error: E(message: "quota exceeded for model")) == .quotaExhausted)
        #expect(AssistModelRouter.classify(error: E(message: "401 invalid api key")) == .authenticationFailed)
        #expect(AssistModelRouter.classify(error: E(message: "unauthorized")) == .authenticationFailed)
        #expect(AssistModelRouter.classify(error: E(message: "request timed out")) == .timeout)
        #expect(AssistModelRouter.classify(error: E(message: "cannot connect to server")) == .networkFailure)
        #expect(AssistModelRouter.classify(error: E(message: "model not found")) == .modelUnavailable)
        #expect(AssistModelRouter.classify(error: E(message: "HTTP 404")) == .modelUnavailable)
        #expect(AssistModelRouter.classify(error: E(message: "HTTP 503 overloaded")) == .providerUnavailable)
        // Anything else falls through to the faithful default.
        #expect(AssistModelRouter.classify(error: E(message: "something strange happened")) == .internalAntigravityFailure)
        #expect(AssistModelRouter.isQuotaOrRateLimit(errorText: "429 Too Many Requests"))
        #expect(!AssistModelRouter.isQuotaOrRateLimit(errorText: "bad request"))
    }

    @Test func quarantineLifecycle() async {
        let router = AssistModelRouter()
        #expect(await router.isModelQuarantined(modelIdentifier: "gpt-4o") == false)
        await router.markRateLimited(modelID: "gpt-4o")
        #expect(await router.isModelQuarantined(modelIdentifier: "gpt-4o"))
        await router.markModelHealthy(modelID: "gpt-4o")
        #expect(await router.isModelQuarantined(modelIdentifier: "gpt-4o") == false)

        await router.markAuthenticationFailed(modelID: "gpt-4o")
        #expect(await router.isModelQuarantined(modelIdentifier: "gpt-4o"))
        await router.markModelUnavailable(modelID: "gpt-4o", reason: "gone")
        #expect(await router.failedAttemptsCount["gpt-4o"] == 1)
        await router.clearAllQuarantines()
        #expect(await router.isModelQuarantined(modelIdentifier: "gpt-4o") == false)
        #expect(await router.failedAttemptsCount.isEmpty)
        #expect(await router.quarantinedModels.isEmpty)
    }

    // MARK: - Failover

    @Test func handleTurnFailureRespectsAutoSwitchOff() async {
        struct E: LocalizedError { let message: String; var errorDescription: String? { message } }
        let router = AssistModelRouter()
        let models = Self.openRouterCandidates()
        let failed = models[0]
        let result = await router.handleTurnFailure(
            failedModel: failed, error: E(message: "HTTP 429"), completedTurnContent: "partial",
            executedToolsCount: 2, objective: "Fix the bug", automaticallySwitchModels: false,
            eligibleCandidates: models
        )
        #expect(result == nil)
        // The failure is still recorded even when switching is off.
        #expect(await router.isModelQuarantined(modelIdentifier: failed.id))
    }

    @Test func handleTurnFailureFailsOverWithHandoff() async {
        struct E: LocalizedError { let message: String; var errorDescription: String? { message } }
        let router = AssistModelRouter()
        let models = Self.openRouterCandidates()
        let failed = models[0]
        let result = await router.handleTurnFailure(
            failedModel: failed, error: E(message: "boom"), completedTurnContent: "half the fix",
            executedToolsCount: 2, objective: "Fix the bug", automaticallySwitchModels: true,
            eligibleCandidates: models
        )
        let next = try #require(result)
        #expect(next.nextModel.id == "anthropic/claude-haiku-4-5")
        #expect(next.continuationPrompt.contains("CONTINUATION DIRECTIVE:"))
        #expect(next.continuationPrompt.contains("half the fix"))
        #expect(next.continuationPrompt.contains("Previous actions executed 2 tool calls"))
        #expect(next.continuationPrompt.contains("Fix the bug"))
        #expect(next.continuationPrompt.contains("without repeating already completed work"))
        let event = await router.lastFailoverEvent
        #expect(event?.failedModelID == failed.id)
        #expect(event?.newModelID == "anthropic/claude-haiku-4-5")
        #expect(await router.failoverHistory.count == 1)
    }

    @Test func handleTurnFailureQuotaExcludesWholeProvider() async {
        struct E: LocalizedError { let message: String; var errorDescription: String? { message } }
        let router = AssistModelRouter()
        let models = Self.openRouterCandidates()
        // All three candidates are .openRouter, so a quota failure
        // on one excludes the provider and failover is exhausted.
        let result = await router.handleTurnFailure(
            failedModel: models[0], error: E(message: "HTTP 429"), completedTurnContent: "",
            executedToolsCount: 0, objective: "x", automaticallySwitchModels: true,
            eligibleCandidates: models
        )
        #expect(result == nil)
    }

    @Test func handleTurnFailureExhaustedReturnsNil() async {
        struct E: LocalizedError { let message: String; var errorDescription: String? { message } }
        let router = AssistModelRouter()
        let models = [Self.openRouterCandidates()[0]]
        let result = await router.handleTurnFailure(
            failedModel: models[0], error: E(message: "boom"), completedTurnContent: "",
            executedToolsCount: 0, objective: "x", automaticallySwitchModels: true,
            eligibleCandidates: models
        )
        #expect(result == nil)
    }

    @Test func continuationPrompt() {
        let prompt = AssistModelRouter.buildContinuationPrompt(
            originalPrompt: "Fix the bug", priorTurnOutput: "half the fix", failedModelName: "GPT-4o"
        )
        #expect(prompt.hasPrefix("CONTINUATION DIRECTIVE:\n"))
        #expect(prompt.contains("The previous model (GPT-4o) encountered an interruption or rate limit and failed."))
        #expect(prompt.contains("DO NOT repeat or overwrite work"))
        #expect(prompt.contains("Original Objective:\nFix the bug"))
        let empty = AssistModelRouter.buildContinuationPrompt(originalPrompt: "x", priorTurnOutput: "  ", failedModelName: "m")
        #expect(!empty.contains("Partial response"))
    }

    // MARK: - User-provided models

    @Test func userProvidedModels() {
        let custom = AssistCandidateModel(id: "my-model", displayName: "Mine", provider: .openRouter, source: .custom)
        #expect(AssistModelRouter.isUserProvidedModel(custom))
        let cloud = AssistCandidateModel(id: "swiftcode-cloud", displayName: "Cloud", provider: .scCloud, source: .cloud)
        #expect(!AssistModelRouter.isUserProvidedModel(cloud))
        #expect(AssistModelRouter.isUserProvidedSelectedModelID("my-model", discovered: nil, customModelID: "my-model"))
        #expect(!AssistModelRouter.isUserProvidedSelectedModelID("my-model", discovered: nil, customModelID: "other-model"))
        #expect(!AssistModelRouter.isUserProvidedSelectedModelID("", discovered: nil, customModelID: "my-model"))
        #expect(!AssistModelRouter.isUserProvidedSelectedModelID("swiftcode-cloud:qwen3", discovered: nil, customModelID: "swiftcode-cloud:qwen3"))
        #expect(!AssistModelRouter.isUserProvidedSelectedModelID("hermes:llama", discovered: nil, customModelID: "hermes:llama"))
        #expect(!AssistModelRouter.isUserProvidedSelectedModelID("opencode:a/b", discovered: nil, customModelID: "opencode:a/b"))
        #expect(AssistModelRouter.isUserProvidedSelectedModelID("whatever", discovered: custom, customModelID: ""))
    }

    // MARK: - Provider dispatch by stored model id

    @Test func providerKindForModelID() {
        let backends = AssistantBackends(settings: AssistantSettings(), store: MemorySecretStore(), account: nil)
        #expect(backends.providerKind(forModelID: "hermes:llama-4") == .hermes)
        #expect(backends.providerKind(forModelID: "opencode:anthropic/claude-sonnet-4-5") == .openCode)
        #expect(backends.providerKind(forModelID: "swiftcode-cloud:qwen3") == .scCloud)
        #expect(backends.providerKind(forModelID: "swiftcode-cloud") == .scCloud)
        #expect(backends.providerKind(forModelID: "gpt-4o") == .openAI)
        #expect(backends.providerKind(forModelID: "claude-sonnet-4-5") == .openRouter)
        #expect(backends.providerKind(forModelID: "codex") == .codex)
        #expect(backends.providerKind(forModelID: "ollama:qwen2.5-coder") == .ollama)
        #expect(backends.providerKind(forModelID: "apple-foundation") == .foundationModels)
        #expect(backends.provider(forModelID: "opencode:a/b").kind == .openCode)
        #expect(backends.provider(forModelID: "hermes:x").kind == .hermes)
        #expect(backends.provider(forModelID: "swiftcode-cloud").kind == .scCloud)
        #expect(backends.provider(forModelID: "muse-wonder-1.0").kind == .openRouter)
    }

    // MARK: - Settings persistence

    @Test func assistantSettingsRoutingDefaults() {
        let settings = AssistantSettings()
        #expect(settings.routingStrategy == .providerDefault)
        #expect(settings.automaticallySwitchModels == true)
        #expect(settings.useProviderModelsOnly == false)
        #expect(settings.onlyUseFreeModels == false)
        #expect(settings.useSwiftCodeCloudModel == false)
        #expect(settings.openCodeAgentName == "swiftcode")
        #expect(settings.customModelID == "")
    }

    @Test func assistantSettingsRoutingRoundTrip() throws {
        var settings = AssistantSettings()
        settings.routingStrategy = .appModels
        settings.automaticallySwitchModels = false
        settings.useProviderModelsOnly = true
        settings.onlyUseFreeModels = true
        settings.useSwiftCodeCloudModel = true
        settings.openCodeAgentName = "custom-agent"
        settings.customModelID = "my-model"
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AssistantSettings.self, from: data)
        #expect(decoded == settings)
    }

    @Test func assistantSettingsUnknownStrategyDecodesToDefault() throws {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(AssistantSettings())) as! [String: Any]
        json["routingStrategy"] = "rotation"
        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(AssistantSettings.self, from: data)
        #expect(decoded.routingStrategy == .providerDefault)
        #expect(AssistRoutingStrategy.lenient("rotation") == .providerDefault)
        #expect(AssistRoutingStrategy.lenient("app_models") == .appModels)
        #expect(AssistRoutingStrategy.lenient(nil) == .providerDefault)
        #expect(AssistRoutingStrategy.lenient("nonsense") == .providerDefault)
    }

    @Test func assistantSettingsMissingKeysKeepDefaults() throws {
        let data = try JSONSerialization.data(withJSONObject: ["provider": "openAI"])
        let decoded = try JSONDecoder().decode(AssistantSettings.self, from: data)
        #expect(decoded.provider == .openAI)
        #expect(decoded.routingStrategy == .providerDefault)
        #expect(decoded.automaticallySwitchModels == true)
    }
}

@Suite struct MetaAssistProviderTests {
    /// A locator that never finds anything.
    static func absentLocator() -> CLIToolLocator {
        CLIToolLocator(environment: ["PATH": ""], home: "/nonexistent-home", isExecutable: { _ in false })
    }

    /// A locator that finds `muse`, with a fake home directory.
    static func presentLocator(home: String) -> CLIToolLocator {
        CLIToolLocator(environment: ["PATH": ""], home: home, isExecutable: { _ in true })
    }

    @Test func fallbackCatalog() {
        #expect(MetaAssistProvider.fallbackModels.count == 3)
        #expect(MetaAssistProvider.defaultModelID == "muse-wonder-1.0")
        let first = MetaAssistProvider.fallbackModels[0]
        #expect(first.modelId == "muse-wonder-1.0" && first.isDefault)
        #expect(first.contextLimit == 1_007_997 && first.outputLimit == 128_000)
        #expect(first.defaultReasoningEffort == "high")
        #expect(MetaAssistProvider.fallbackModels[1].defaultReasoningEffort == "max")
        #expect(MetaAssistProvider.providerID == "meta_assist")
        #expect(MetaAssistProvider.providerName == "Assist with Meta")
        #expect(ProviderKind.metaAssist.displayName == "Assist with Meta")
    }

    @Test func availabilityWithoutBinary() async {
        let provider = MetaAssistProvider(locator: Self.absentLocator())
        let availability = await provider.availability()
        guard case .notInstalled(let hint) = availability else {
            Issue.record("expected notInstalled, got \(availability)")
            return
        }
        #expect(hint.contains("muse"))
    }

    @Test func availabilityWithoutCredentials() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("meta-assist-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let provider = MetaAssistProvider(locator: Self.presentLocator(home: dir.path), homeDirectory: dir.path)
        let availability = await provider.availability()
        guard case .signedOut(let hint) = availability else {
            Issue.record("expected signedOut, got \(availability)")
            return
        }
        #expect(hint.contains("not signed in"))
    }

    @Test func availabilityReadyWithCredentials() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("meta-assist-test-\(UUID().uuidString)")
        let configDir = dir.appendingPathComponent(".config/muse")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try "{}".write(to: configDir.appendingPathComponent("auth.json"), atomically: true, encoding: .utf8)
        let provider = MetaAssistProvider(locator: Self.presentLocator(home: dir.path), homeDirectory: dir.path)
        let availability = await provider.availability()
        guard case .ready(let models) = availability else {
            Issue.record("expected ready, got \(availability)")
            return
        }
        #expect(models.map(\.id) == ["muse-wonder-1.0", "muse-spark-1.3", "muse-spark-1.2"])
        #expect(await provider.contextWindow(model: "muse-wonder-1.0") == 1_007_997)
        #expect(await provider.contextWindow(model: "no-such-model") == nil)
    }

    @Test func sendFailsHonestlyWithoutBinary() async throws {
        // Wave 16: `send` runs a real turn through the bridge, so
        // a missing binary fails as `.failed` with the install
        // hint — it no longer throws `.unsupported` naming the
        // (now ported) bridge.
        let provider = MetaAssistProvider(locator: Self.absentLocator())
        let request = ChatRequest(model: "muse-wonder-1.0", instructions: "Be helpful.", messages: [ChatMessage(.user, "Hello")])
        do {
            for try await _ in provider.send(request) { }
            Issue.record("expected send to throw")
        } catch let error as AssistantError {
            guard case .failed(let message) = error else {
                Issue.record("expected failed, got \(error)")
                return
            }
            #expect(message.contains("muse"))
        }
    }

    @Test func metaAssistIsDispatchedByBackends() {
        let backends = AssistantBackends(settings: AssistantSettings(), store: MemorySecretStore(), account: nil)
        #expect(backends.provider(.metaAssist).kind == .metaAssist)
        #expect(ProviderKind.allCases.contains(.metaAssist))
    }
}
