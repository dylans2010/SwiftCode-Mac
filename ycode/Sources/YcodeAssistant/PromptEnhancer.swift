import Foundation

// MARK: - Prompt enhancer (bulk migration, Backend-Assist slice)
//
// Ported from Legacy (Dylan's own code; direct port authorised under MIT):
//   * `SwiftCode/Backend/Assist/PromptEnhancer.swift` —
//     `PromptEnhancementError`, `PromptEnhancer.enhancePrompt`,
//     `parseEnhancedPrompt`, and the prompt-enhancement system prompt.
//
// The enhancement itself is unchanged: the user's input is rewritten by
// the on-device model into a structured instruction for a coding agent,
// and the reply must be a JSON object with an `updatedPrompt` key.
//
// Rehosted onto Ycode's provider host instead of Legacy's singletons:
//   * Legacy called `FoundationModels.shared.generatePrivateResponse`
//     after temporarily binding `FoundationModels.shared.selectedModel`
//     to `.afm3Core`. That binding was a no-op in practice — Legacy's
//     own provider doc records that `generatePrivateResponse` always
//     built its session from the system model whatever the selection
//     said — so there is no selection step here at all. The request
//     goes through `FoundationModelsProvider` (the `AssistantProvider`
//     for `ProviderKind.foundationModels`), whose single model is
//     exactly Legacy's default entry (`AFM 3 Core`).
//   * Legacy's `modelID` parameter was never read by its own body
//     either (the body always used `.afm3Core`). It is kept here for
//     source compatibility and likewise ignored: the on-device
//     provider exposes exactly one model, so there is nothing to
//     select between.
//   * Legacy logged every step to `DiagnosticEventBus` (Legacy's
//     `DiagnosticEvent` bus, not ported — see the bulk dispositions).
//     This port logs nothing; failures are carried in the returned
//     `Result` instead.
//   * No fallback provider, no canned text: when Apple Foundation
//     Models is unavailable the call fails with
//     `.modelUnavailable`, exactly as Legacy's
//     `FoundationModels.shared.isEnabled` guard failed it.

/// Why a prompt-enhancement request failed.
public enum PromptEnhancementError: LocalizedError, Equatable {
    case serviceError(String)
    case parsingFailed(String)
    case invalidResponse
    case authenticationFailed
    case networkTimeout
    case invalidConfiguration
    case modelUnavailable

    public var errorDescription: String? {
        switch self {
        case .serviceError(let message):
            return message
        case .parsingFailed(let message):
            return message
        case .invalidResponse:
            return "The response from the model was invalid or empty."
        case .authenticationFailed:
            return "Authentication failed. Please verify your API key."
        case .networkTimeout:
            return "The request timed out. Please check your network connection."
        case .invalidConfiguration:
            return "The provider configuration is invalid."
        case .modelUnavailable:
            return "The selected model is currently unavailable."
        }
    }
}

/// Rewrites a user's free-text request into a structured instruction
/// for a coding agent, using Apple Foundation Models on-device.
///
/// The result is the model's `updatedPrompt` string only; the JSON
/// envelope is stripped by `parseEnhancedPrompt(from:)`. An empty or
/// whitespace-only input is returned unchanged without contacting the
/// model. When Apple Foundation Models is unavailable the call fails
/// with `.modelUnavailable` instead of answering from canned text.
public enum PromptEnhancer {

    struct EnhancedPromptJSON: Codable {
        let updatedPrompt: String
    }

    /// The instruction sent to the on-device model, verbatim from Legacy.
    static let enhanceSystemPrompt = """
        You are a highly professional prompt enhancer. Your task is to rewrite the user's input prompt into an enhanced, technically clear, structured, and professional instruction for an AI coding agent while preserving their original intent.

        You MUST return ONLY a valid JSON object matching this schema, with absolutely no other text, markdown formatting blocks (like ```json), explanations, or surrounding commentary:
        {
          "updatedPrompt": "your enhanced prompt here"
        }
        """

    /// Primary async-throwing entry point.
    @MainActor
    public static func enhancePrompt(userInput: String) async throws -> String {
        let result = await enhancePrompt(userInput: userInput, modelID: nil)
        switch result {
        case .success(let prompt):
            return prompt
        case .failure(let error):
            throw error
        }
    }

    /// Primary Result-returning entry point. `modelID` is accepted for
    /// source compatibility with Legacy and ignored: the on-device
    /// provider exposes exactly one model
    /// (`FoundationModelsProvider.modelID`).
    @MainActor
    public static func enhancePrompt(userInput: String, modelID: String? = nil) async -> Result<String, PromptEnhancementError> {
        _ = modelID
        let trimmedInput = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return .success(userInput) }

        let provider = FoundationModelsProvider()
        let availability = await provider.availability()
        guard case .ready = availability else {
            return .failure(.modelUnavailable)
        }

        let request = ChatRequest(
            model: FoundationModelsProvider.modelID,
            instructions: enhanceSystemPrompt,
            messages: [ChatMessage(.user, trimmedInput)],
            generation: .assistantDefault)
        var rawResponse = ""
        do {
            for try await event in provider.send(request) {
                if case .text(let delta) = event {
                    rawResponse += delta
                }
            }
        } catch {
            return .failure(.serviceError(Self.describe(error)))
        }

        guard let parsed = parseEnhancedPrompt(from: rawResponse) else {
            if rawResponse.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return .failure(.invalidResponse)
            }
            return .failure(.parsingFailed("Safe JSON parsing failed. Expected JSON schema keys were not found in response: \(rawResponse)"))
        }
        guard !parsed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.invalidResponse)
        }
        return .success(parsed)
    }

    /// An error's message plus its recovery suggestion, when it has one.
    static func describe(_ error: Error) -> String {
        var detail = error.localizedDescription
        if let assistant = error as? AssistantError,
           let hint = assistant.recoverySuggestion, !hint.isEmpty {
            detail += " \(hint)"
        }
        return detail
    }

    /// Extracts the `updatedPrompt` value from a model reply, verbatim
    /// from Legacy: direct JSON decode first, then the same decode
    /// after stripping a Markdown JSON fence, then a regex fallback
    /// over the raw text.
    static func parseEnhancedPrompt(from text: String) -> String? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Try parsing directly
        if let data = cleaned.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(EnhancedPromptJSON.self, from: data) {
            return decoded.updatedPrompt
        }

        // 2. Try stripping markdown JSON wrap
        var stripped = cleaned
        if stripped.hasPrefix("```json") {
            stripped = String(stripped.dropFirst(7))
        } else if stripped.hasPrefix("```") {
            stripped = String(stripped.dropFirst(3))
        }
        if stripped.hasSuffix("```") {
            stripped = String(stripped.dropLast(3))
        }
        stripped = stripped.trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = stripped.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(EnhancedPromptJSON.self, from: data) {
            return decoded.updatedPrompt
        }

        // 3. Regex fallback to extract content of updatedPrompt
        let pattern = #"\"updatedPrompt\"\s*:\s*\"((?:[^\"\\]|\\.)*)\"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
           let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            let matchedString = String(text[range])
            return matchedString
                .replacingOccurrences(of: #"\""#, with: "\"")
                .replacingOccurrences(of: #"\n"#, with: "\n")
                .replacingOccurrences(of: #"\t"#, with: "\t")
        }

        return nil
    }
}
