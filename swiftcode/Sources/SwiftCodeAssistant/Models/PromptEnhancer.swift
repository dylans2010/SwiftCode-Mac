import Foundation

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

public enum PromptEnhancer {

    struct EnhancedPromptJSON: Codable {
        let updatedPrompt: String
    }

    static let enhanceSystemPrompt = """
        You are a highly professional prompt enhancer. Your task is to rewrite the user's input prompt into an enhanced, technically clear, structured, and professional instruction for an AI coding agent while preserving their original intent.

        You MUST return ONLY a valid JSON object matching this schema, with absolutely no other text, markdown formatting blocks (like ```json), explanations, or surrounding commentary:
        {
          "updatedPrompt": "your enhanced prompt here"
        }
        """

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

    static func describe(_ error: Error) -> String {
        var detail = error.localizedDescription
        if let assistant = error as? AssistantError,
           let hint = assistant.recoverySuggestion, !hint.isEmpty {
            detail += " \(hint)"
        }
        return detail
    }

    static func parseEnhancedPrompt(from text: String) -> String? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)

        if let data = cleaned.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(EnhancedPromptJSON.self, from: data) {
            return decoded.updatedPrompt
        }

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
