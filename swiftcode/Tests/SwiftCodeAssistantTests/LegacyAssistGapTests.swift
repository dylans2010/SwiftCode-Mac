import Foundation
import Testing
@testable import SwiftCodeAssistant

// MARK: - Legacy Assist gap tests (Wave 18)
//
// The portable leftovers of Legacy's Assist provider/router tests
// (Dylan's own code; direct port authorised under MIT) that the
// Wave 9/15/16 ports did not already cover:
//
//   - `HermesProviderTests.testConfigurationRoundTrip`: SwiftCode's
//     `HermesConfiguration` has no `load()`/`save()` (persistence
//     lives in `AssistantSettings`), so only the pure half ports —
//     `normalisedToolsets` ("file,web" preserved, whitespace-only
//     means Hermes defaults).
//   - `AssistProviderTests.testPersistedProviderRoundTrip`: the
//     `AssistantSettings.provider` JSON round-trip for `.openCode`
//     (Legacy's `assist.selectedProvider` key).
//   - `AssistModelRouterTests.testDefaultAssistModelClaudeRouting` /
//     `testDefaultAssistModelOpenAIRouting`: the "never Gemini" half —
//     an explicit Claude/GPT selection must yield a non-Antigravity
//     SDK config whose model is not a Gemini id. (The selection
//     itself is already covered by
//     `selectModelForSDKDefaultHonoursExplicitThirdPartyID`.)
//   - `AssistModelRouterTests.testNoSilentGeminiFallback`: after a
//     Claude turn failure the failover event still attributes the
//     failure to the Claude model, and the failover target is the
//     other Claude candidate — never the Gemini candidate that was
//     eligible. (Legacy asserted the provider id contained
//     "claude"; SwiftCode's event records the serving provider's display
//     name, so the assertion is on the model ids instead.)
//
// Deliberately NOT ported from the same Legacy files:
//   - `HermesProviderTests.testExecutableResolution`: covered —
//     `CLIToolLocator.find` is tested in `CLIAgentTests` (nvm
//     ordering, override, missing tool).
//   - `HermesProviderTests.testProviderSelectionAndSDKGuard` and
//     `SDKProviderTests` (all 8): SwiftCode has no
//     `AssistSDKSessionRunner` / `SDKToolEventStore` /
//     `SDKToolSourceSetting`; the routing half is covered by
//     `providerKindForModelID` and `specificationPrefixesWin`.
//   - `AssistModelRouterTests.testAlternativeKeySettingsPersistence`:
//     SwiftCode has no persisted `alternativeKeysEnabled` toggle (it is
//     a `buildConfig` parameter); the rotation behaviour itself is
//     covered by `GeminiKeyRotationTests` and
//     `AssistSDKModelSelectionTests`.
//   - `AssistModelRouterTests.testDiscoveryServiceCachingAndStats`:
//     caching is covered by `cacheIsReusedUntilForced`; SwiftCode's
//     discovery exposes no stats API.
//
// No Swift toolchain exists in this environment, so these tests have
// NOT been compiled or run — statically verified only. On Dylan's Mac:
// run with `swift test --filter LegacyAssistGapTests`.

@Suite struct LegacyAssistGapTests {

    @Test func hermesConfigurationNormalisedToolsets() {
        #expect(HermesConfiguration(toolsets: "file,web").normalisedToolsets == "file,web")
        #expect(HermesConfiguration(toolsets: "  file,web  ").normalisedToolsets == "file,web")
        #expect(HermesConfiguration(toolsets: "   ").normalisedToolsets == nil)
        #expect(HermesConfiguration(toolsets: "").normalisedToolsets == nil)
        #expect(HermesConfiguration().normalisedToolsets == nil)
    }

    @Test func assistantSettingsProviderOpenCodeRoundTrips() throws {
        var settings = AssistantSettings()
        settings.provider = .openCode
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AssistantSettings.self, from: data)
        #expect(decoded.provider == .openCode)
        #expect(ProviderKind(rawValue: "openCode") == .openCode)
    }

    @Test func sdkConfigForExplicitClaudeAndGPTNeverUsesGemini() async {
        let router = AssistModelRouter()
        let claude = await router.selectModelForSDK(
            preferredID: "anthropic/claude-sonnet-4-5",
            strategy: .providerDefault,
            candidates: [],
            useCloudModel: false,
            catalog: AntigravitySDKCatalog())
        #expect(claude.model.id == "anthropic/claude-sonnet-4-5")
        #expect(claude.config.provider != .antigravity)
        #expect(!claude.config.model.contains("gemini"))

        let gpt = await router.selectModelForSDK(
            preferredID: "gpt-4o",
            strategy: .providerDefault,
            candidates: [],
            useCloudModel: false,
            catalog: AntigravitySDKCatalog())
        #expect(gpt.model.id == "gpt-4o")
        #expect(gpt.config.provider != .antigravity)
        #expect(!gpt.config.model.contains("gemini"))
    }

    @Test func failoverNeverSilentlyFallsBackToGemini() async throws {
        struct E: LocalizedError { let message: String; var errorDescription: String? { message } }
        let candidates = [
            AssistCandidateModel(id: "anthropic/claude-sonnet-4-5", displayName: "Claude Sonnet",
                                 provider: .openRouter, priority: 5, source: .provider),
            AssistCandidateModel(id: "anthropic/claude-haiku-4-5", displayName: "Claude Haiku",
                                 provider: .openRouter, priority: 5, source: .provider),
            AssistCandidateModel(id: "google/gemini-2.5-pro", displayName: "Gemini Pro",
                                 provider: .openRouter, contextWindow: 1_000_000, priority: 10,
                                 source: .provider),
        ]
        let router = AssistModelRouter()
        let failed = candidates[0]
        let result = await router.handleTurnFailure(
            failedModel: failed, error: E(message: "boom"), completedTurnContent: "half the fix",
            executedToolsCount: 2, objective: "Fix the bug", automaticallySwitchModels: true,
            eligibleCandidates: candidates)
        let next = try #require(result)
        // The Gemini candidate was eligible but must not be the
        // silent fallback: failover goes to the other Claude model.
        #expect(next.nextModel.id == "anthropic/claude-haiku-4-5")
        #expect(!next.nextModel.id.contains("gemini"))
        let event = await router.lastFailoverEvent
        #expect(event?.failedModelID == failed.id)
        #expect(event?.failedModelID.contains("claude") == true)
        #expect(event?.newModelID == "anthropic/claude-haiku-4-5")
        #expect(event?.newModelID.contains("gemini") == false)
        #expect(await router.failoverHistory.count == 1)
    }
}
