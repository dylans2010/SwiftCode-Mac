import Foundation
import Testing
@testable import YcodeAssistant

// MARK: - Antigravity SDK catalog (Wave 16, Slice D)
//
// Fixtures only: the `agy` binary is never executed here (the
// seed catalog and the pure parsers are what is tested).

@Suite struct AntigravitySDKCatalogTests {
    @Test func seedCatalogIsLegacyVerbatim() {
        let seeds = AntigravitySDKCatalog.seedModels
        #expect(seeds.count == 9)
        #expect(seeds.map { $0.id } == [
            "gemini-3.8-flash-high",
            "gemini-3.8-flash-medium",
            "gemini-3.8-flash-low",
            "claude-sonnet-4-6",
            "claude-opus-4-6-thinking",
            "gpt-oss-120b-medium",
            "gemini-3.8-flash",
            "gemini-3.1-pro",
            "gemini-3-flash",
        ])
        #expect(seeds[3].category == "Anthropic")
        #expect(seeds[3].contextWindow == 200_000)
        #expect(seeds[5].category == "OpenAI")
        #expect(seeds[7].contextWindow == 2_097_152)
    }

    @Test func sdkDefaultModelIDsFallBackToSeeds() async {
        let catalog = AntigravitySDKCatalog()
        #expect(await catalog.sdkDefaultModelIDs == AntigravitySDKCatalog.seedModels.map { $0.id })
        #expect(await catalog.allModelIDs.count == 9)
    }

    @Test func getModelFallsBackToSeeds() async {
        let catalog = AntigravitySDKCatalog(models: [])
        #expect(await catalog.getModel(byID: "gemini-3.8-flash")?.displayName == "Gemini 3.8 Flash")
        #expect(await catalog.getModel(byID: "no-such-model") == nil)
    }

    @Test func catalogMembershipIsCaseInsensitive() async {
        let catalog = AntigravitySDKCatalog()
        #expect(await catalog.isAntigravityCatalogModel("GEMINI-3.8-FLASH") == true)
        #expect(await catalog.isAntigravityCatalogModel("gpt-4o") == false)
    }

    @Test func parseAgyOutputStripsAnsiAndBraille() {
        let output = """
        \u{1B}[32mFetching available models...\u{1B}[0m
        gemini-3.8-flash-high ⠋ Gemini 3.8 Flash (High)
        claude-sonnet-4-6 Claude Sonnet 4.6 (Thinking)
        gpt-oss-120b-medium GPT-OSS 120B (Medium)

        """
        let models = AntigravitySDKCatalog.parseAgyModelsOutput(output)
        #expect(models.map { $0.id } == ["gemini-3.8-flash-high", "claude-sonnet-4-6", "gpt-oss-120b-medium"])
        #expect(models[0].displayName == "Gemini 3.8 Flash (High)")
        #expect(models[0].thinkingLevel == "High")
        #expect(models[1].category == "Anthropic")
        #expect(models[1].contextWindow == 200_000)
        #expect(models[2].category == "OpenAI")
    }

    @Test func deriveHelpersMatchLegacyRules() {
        #expect(AntigravitySDKCatalog.deriveThinkingLevel(modelID: "gemini-3.8-flash-high", displayName: "") == "High")
        #expect(AntigravitySDKCatalog.deriveThinkingLevel(modelID: "gemini-3.8-flash-low", displayName: "") == "Low")
        #expect(AntigravitySDKCatalog.deriveThinkingLevel(modelID: "gemini-minimal", displayName: "") == "Minimal")
        #expect(AntigravitySDKCatalog.deriveThinkingLevel(modelID: "claude-opus-4-6-thinking", displayName: "") == "High")
        #expect(AntigravitySDKCatalog.deriveThinkingLevel(modelID: "gemini-3-flash", displayName: "") == "Medium")
        #expect(AntigravitySDKCatalog.deriveContextWindow(modelID: "gemini-3.1-pro") == 2_097_152)
        #expect(AntigravitySDKCatalog.deriveContextWindow(modelID: "gemini-3-flash") == 1_048_576)
        #expect(AntigravitySDKCatalog.deriveContextWindow(modelID: "claude-sonnet-4-6") == 200_000)
        #expect(AntigravitySDKCatalog.deriveContextWindow(modelID: "gpt-oss-120b-medium") == 128_000)
        #expect(AntigravitySDKCatalog.deriveCategory(modelID: "claude-sonnet-4-6") == "Anthropic")
        #expect(AntigravitySDKCatalog.deriveCategory(modelID: "gpt-oss-120b-medium") == "OpenAI")
        #expect(AntigravitySDKCatalog.deriveCategory(modelID: "gemini-3-flash") == "Google")
        #expect(AntigravitySDKCatalog.deriveCategory(modelID: "acme/some-model") == "Acme")
    }

    @Test func syntheticCandidateIsMarkedSynthetic() async {
        let catalog = AntigravitySDKCatalog()
        let candidate = await catalog.createSyntheticCandidate(modelID: "gemini-3.8-flash-high", isConfigured: true)
        #expect(candidate.isSynthetic == true)
        #expect(candidate.id == "gemini-3.8-flash-high")
        #expect(candidate.displayName == "Gemini 3.8 Flash (High)")
        #expect(candidate.provider == .openRouter)
        #expect(candidate.isConfigured == true)
        #expect(candidate.hasCredentials == true)
        #expect(candidate.statusDescription.contains("synthetic"))
        #expect(candidate.supportsSubagents == true)
        #expect(candidate.contextWindow == 1_048_576)
    }

    @Test func syntheticCandidateForUnknownIDDerivesFields() async {
        let catalog = AntigravitySDKCatalog()
        let candidate = await catalog.createSyntheticCandidate(modelID: "gemini-9-ultra-high", isConfigured: false)
        #expect(candidate.isSynthetic == true)
        #expect(candidate.displayName == "Gemini 9 Ultra High (High)")
        #expect(candidate.isConfigured == false)
        #expect(candidate.hasCredentials == false)
        #expect(candidate.contextWindow == 1_048_576)
    }

    @Test func syntheticCandidateForImageModelHasNoSubagents() async {
        let catalog = AntigravitySDKCatalog(models: [
            AntigravitySDKModel(id: "gemini-image-1", displayName: "Gemini Image", thinkingLevel: "Medium", isImageModel: true),
        ])
        let candidate = await catalog.createSyntheticCandidate(modelID: "gemini-image-1", isConfigured: true)
        #expect(candidate.supportsSubagents == false)
    }
}
