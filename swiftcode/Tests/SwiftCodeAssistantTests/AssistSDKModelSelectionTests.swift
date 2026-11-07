import Foundation
import Testing
@testable import SwiftCodeAssistant

@Suite struct AssistSDKModelSelectionTests {
    static func candidate(
        _ id: String,
        provider: ProviderKind = .openRouter,
        priority: Int = 10,
        isConfigured: Bool = true,
        hasCredentials: Bool = true,
        supportsSubagents: Bool = true
    ) -> AssistCandidateModel {
        AssistCandidateModel(
            id: id,
            provider: provider,
            modelIdentifier: id,
            supportsSubagents: supportsSubagents,
            priority: priority,
            isConfigured: isConfigured,
            hasCredentials: hasCredentials
        )
    }

    static func catalog() -> AntigravitySDKCatalog {
        AntigravitySDKCatalog()
    }

    @Test func buildConfigForGeminiModel() {
        let model = Self.candidate("google/gemini-2.5-flash", supportsSubagents: true)
        let config = SDKSessionConfigurationBuilder.build(for: model)
        #expect(config.model == "google/gemini-2.5-flash")
        #expect(config.provider == .openRouter)
        #expect(config.thinkingLevel == "Medium")
        #expect(config.enableSubagents == true)
        #expect(config.executionMode == "api_key")
        #expect(config.hasAPIKey == true)
        #expect(config.isOAuthAuthenticated == false)
    }

    @Test func buildConfigThinkingLevelFromID() {
        let high = SDKSessionConfigurationBuilder.build(for: Self.candidate("gemini-3.8-flash-high"))
        #expect(high.thinkingLevel == "High")
        let low = SDKSessionConfigurationBuilder.build(for: Self.candidate("gemini-3.8-flash-low"))
        #expect(low.thinkingLevel == "Low")
        let minimal = SDKSessionConfigurationBuilder.build(for: Self.candidate("gemini-minimal"))
        #expect(minimal.thinkingLevel == "Minimal")
    }

    @Test func buildConfigOAuthWinsForGoogleModels() {
        let model = Self.candidate("google/gemini-2.5-flash", hasCredentials: false)
        let config = SDKSessionConfigurationBuilder.build(
            for: model,
            isGoogleOAuthAuthenticated: true
        )
        #expect(config.executionMode == "antigravity")
        #expect(config.isOAuthAuthenticated == true)
        #expect(config.hasAPIKey == false)
    }

    @Test func buildConfigWithoutKeyOrOAuthHasNoExecutionMode() {
        let model = Self.candidate("anthropic/claude-sonnet-4-5", hasCredentials: false)
        let config = SDKSessionConfigurationBuilder.build(for: model)
        #expect(config.executionMode == nil)
        #expect(config.hasAPIKey == false)
    }

    @Test func buildConfigRotationModeIsAPIKey() {
        let model = Self.candidate("google/gemini-2.5-flash")
        let config = SDKSessionConfigurationBuilder.build(for: model, alternativeKeysEnabled: true)
        #expect(config.executionMode == "api_key")
    }

    @Test func selectModelForSDKCloudShortCircuit() async {
        let router = AssistModelRouter()
        let result = await router.selectModelForSDK(
            preferredID: "swiftcode-cloud",
            strategy: .providerDefault,
            candidates: [],
            useCloudModel: true,
            cloudConfigured: true,
            catalog: Self.catalog()
        )
        #expect(result.model.provider == .scCloud)
        #expect(result.model.id == "swiftcode-cloud")
        #expect(result.config.provider == .scCloud)
    }

    @Test func selectModelForSDKDefaultRestrictsToCatalog() async {
        let router = AssistModelRouter()
        let candidates = [
            Self.candidate("gemini-3.8-flash"),
            Self.candidate("claude-sonnet-4-6"),
            Self.candidate("gemini-3.8-flash-high"),
        ]
        let result = await router.selectModelForSDK(
            preferredID: "some-unlisted-model",
            strategy: .providerDefault,
            candidates: candidates,
            useCloudModel: false,
            catalog: Self.catalog()
        )
        #expect(result.model.id == "gemini-3.8-flash-high")
        #expect(result.model.isSynthetic == true)
        #expect(result.config.model == "gemini-3.8-flash-high")
    }

    @Test func selectModelForSDKDefaultHonoursCatalogSelection() async {
        let router = AssistModelRouter()
        let candidates = [Self.candidate("gemini-3.8-flash")]
        let result = await router.selectModelForSDK(
            preferredID: "gemini-3.8-flash",
            strategy: .providerDefault,
            candidates: candidates,
            useCloudModel: false,
            catalog: Self.catalog()
        )
        #expect(result.model.id == "gemini-3.8-flash")
        #expect(result.model.isSynthetic == true)
        #expect(result.model.displayName == "Gemini 3.8 Flash")
    }

    @Test func selectModelForSDKDefaultHonoursExplicitThirdPartyID() async {
        let router = AssistModelRouter()
        let result = await router.selectModelForSDK(
            preferredID: "anthropic/claude-sonnet-4-5",
            strategy: .providerDefault,
            candidates: [],
            useCloudModel: false,
            catalog: Self.catalog()
        )
        #expect(result.model.id == "anthropic/claude-sonnet-4-5")
        #expect(result.model.isSynthetic == true)
    }

    @Test func selectModelForSDKAppModelsUsesDiscoveredSet() async {
        let router = AssistModelRouter()
        let candidates = [
            Self.candidate("anthropic/claude-sonnet-4-5", priority: 5),
            Self.candidate("google/gemini-2.5-pro", priority: 10),
        ]
        let result = await router.selectModelForSDK(
            preferredID: "anthropic/claude-sonnet-4-5",
            strategy: .appModels,
            candidates: candidates,
            useCloudModel: false,
            catalog: Self.catalog()
        )
        #expect(result.model.id == "anthropic/claude-sonnet-4-5")
        #expect(result.model.isSynthetic == false)
        let fallback = await router.selectModelForSDK(
            preferredID: "no-such-model",
            strategy: .appModels,
            candidates: candidates,
            useCloudModel: false,
            catalog: Self.catalog()
        )
        #expect(fallback.model.id == "anthropic/claude-sonnet-4-5")
    }

    static func fakeKey(_ tag: String) -> String {
        "AI" + "za" + tag + String(repeating: "7", count: 28)
    }

    @Test func failoverRotatesKeyInsteadOfModel() async {
        let router = AssistModelRouter()
        let rotation = GeminiKeyRotationManager(store: MemorySecretStore())
        _ = await rotation.importKeys(Self.fakeKey("alpha") + "," + Self.fakeKey("beta"))
        let failed = Self.candidate("google/gemini-2.5-flash")
        let next = Self.candidate("anthropic/claude-sonnet-4-5")
        let result = await router.handleTurnFailureWithKeyRotation(
            failedModel: failed,
            error: NSError(domain: "test", code: 429, userInfo: [NSLocalizedDescriptionKey: "429 quota exceeded"]),
            completedTurnContent: "partial work",
            executedToolsCount: 0,
            automaticallySwitchModels: true,
            eligibleCandidates: [failed, next],
            keyRotation: rotation,
            alternativeKeysEnabled: true
        )
        #expect(result != nil)
        #expect(result?.nextModel.id == "google/gemini-2.5-flash")
        #expect(result?.keyRotated == true)
        #expect(result?.continuationPrompt.contains("Rotated to next Gemini API key") == true)
        #expect(result?.continuationPrompt.contains("partial work") == true)
        #expect(result?.config.executionMode == "api_key")
        #expect(await rotation.activeKeyId != nil)
        #expect(await rotation.keys.first { $0.maskedValue.hasSuffix("7777") && $0.state == .rateLimited } != nil)
    }

    @Test func failoverFallsThroughWhenNoOtherKey() async {
        let router = AssistModelRouter()
        let rotation = GeminiKeyRotationManager(store: MemorySecretStore())
        _ = await rotation.importKeys(Self.fakeKey("solo"))
        let failed = Self.candidate("google/gemini-2.5-flash")
        let next = Self.candidate("gpt-4o", provider: .openAI)
        let result = await router.handleTurnFailureWithKeyRotation(
            failedModel: failed,
            error: NSError(domain: "test", code: 429, userInfo: [NSLocalizedDescriptionKey: "429 quota exceeded"]),
            completedTurnContent: "",
            executedToolsCount: 0,
            automaticallySwitchModels: true,
            eligibleCandidates: [failed, next],
            keyRotation: rotation,
            alternativeKeysEnabled: true
        )
        #expect(result?.nextModel.id == "gpt-4o")
        #expect(result?.keyRotated == false)
    }

    @Test func failoverReturnsNilWhenAutoSwitchOffAndNoRotation() async {
        let router = AssistModelRouter()
        let failed = Self.candidate("google/gemini-2.5-flash")
        let next = Self.candidate("anthropic/claude-sonnet-4-5")
        let result = await router.handleTurnFailureWithKeyRotation(
            failedModel: failed,
            error: NSError(domain: "test", code: 429, userInfo: [NSLocalizedDescriptionKey: "429 quota exceeded"]),
            completedTurnContent: "",
            executedToolsCount: 0,
            automaticallySwitchModels: false,
            eligibleCandidates: [failed, next],
            keyRotation: nil,
            alternativeKeysEnabled: false
        )
        #expect(result == nil)
    }

    @Test func failoverDoesNotRotateForNonRateLimitErrors() async {
        let router = AssistModelRouter()
        let rotation = GeminiKeyRotationManager(store: MemorySecretStore())
        _ = await rotation.importKeys(Self.fakeKey("alpha") + "," + Self.fakeKey("beta"))
        let failed = Self.candidate("google/gemini-2.5-flash")
        let next = Self.candidate("anthropic/claude-sonnet-4-5")
        let before = await rotation.activeKeyId
        let result = await router.handleTurnFailureWithKeyRotation(
            failedModel: failed,
            error: NSError(domain: "test", code: 500, userInfo: [NSLocalizedDescriptionKey: "internal error"]),
            completedTurnContent: "",
            executedToolsCount: 0,
            automaticallySwitchModels: true,
            eligibleCandidates: [failed, next],
            keyRotation: rotation,
            alternativeKeysEnabled: true
        )
        #expect(result?.keyRotated == false)
        #expect(result?.nextModel.id == "anthropic/claude-sonnet-4-5")
        #expect(await rotation.activeKeyId == before)
    }
}
