import Foundation
import Testing
@testable import YcodeAssistant

// MARK: - Prompt enhancer (bulk migration, Backend-Assist slice)
//
// Deterministic paths only: empty-input passthrough (which never
// touches the provider) and the JSON reply parser. No test here
// calls the on-device model — whether Apple Foundation Models is
// available depends on the machine running the suite, so the live
// enhancement path is exercised on Dylan's Mac, not asserted here.

@Suite struct PromptEnhancerTests {
    @Test func emptyInputReturnsUnchanged() async {
        let result = await PromptEnhancer.enhancePrompt(userInput: "", modelID: nil)
        #expect(result == .success(""))
    }

    @Test func whitespaceOnlyInputReturnsUnchanged() async {
        let result = await PromptEnhancer.enhancePrompt(userInput: "   \n  ", modelID: nil)
        #expect(result == .success("   \n  "))
    }

    @Test func throwingOverloadPassesEmptyInputThrough() async throws {
        let prompt = try await PromptEnhancer.enhancePrompt(userInput: "")
        #expect(prompt == "")
    }

    @Test func parseDirectJSON() {
        let parsed = PromptEnhancer.parseEnhancedPrompt(from: #"{"updatedPrompt": "Do the thing, then verify it."}"#)
        #expect(parsed == "Do the thing, then verify it.")
    }

    @Test func parseFencedJSON() {
        let parsed = PromptEnhancer.parseEnhancedPrompt(from: "```json\n{\"updatedPrompt\": \"Fenced prompt.\"}\n```")
        #expect(parsed == "Fenced prompt.")
    }

    @Test func parseRegexFallback() {
        let parsed = PromptEnhancer.parseEnhancedPrompt(
            from: "Here is the result:\n{\"updatedPrompt\": \"Fallback prompt.\"}\nHope that helps.")
        #expect(parsed == "Fallback prompt.")
    }

    @Test func parseGarbageReturnsNil() {
        #expect(PromptEnhancer.parseEnhancedPrompt(from: "no json here at all") == nil)
        #expect(PromptEnhancer.parseEnhancedPrompt(from: "") == nil)
        #expect(PromptEnhancer.parseEnhancedPrompt(from: #"{"otherKey": "x"}"#) == nil)
    }

    @Test func parseEmptyUpdatedPrompt() {
        let parsed = PromptEnhancer.parseEnhancedPrompt(from: #"{"updatedPrompt": ""}"#)
        #expect(parsed == "")
    }

    @Test func everyErrorCaseHasADescription() {
        let cases: [PromptEnhancementError] = [
            .serviceError("boom"), .parsingFailed("bad"), .invalidResponse,
            .authenticationFailed, .networkTimeout, .invalidConfiguration, .modelUnavailable,
        ]
        for error in cases {
            #expect(error.errorDescription != nil && !error.errorDescription!.isEmpty)
        }
    }
}
