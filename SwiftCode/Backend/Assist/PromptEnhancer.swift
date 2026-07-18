import Foundation
import os

private let logger = Logger(subsystem: "com.swiftcode.app", category: "promptEnhancer")

public enum PromptEnhancementError: LocalizedError {
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

public final class PromptEnhancer {

    struct EnhancedPromptJSON: Codable {
        let updatedPrompt: String
    }

    @MainActor
    public static func enhancePrompt(userInput: String, modelID: String) async -> Result<String, PromptEnhancementError> {
        let trimmedInput = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return .success(userInput) }

        let systemPrompt = """
        You are a highly professional prompt enhancer. Your task is to rewrite the user's input prompt into an enhanced, technically clear, structured, and professional instruction for an AI coding agent while preserving their original intent.

        You MUST return ONLY a valid JSON object matching this schema, with absolutely no other text, markdown formatting blocks (like ```json), explanations, or surrounding commentary:
        {
          "updatedPrompt": "your enhanced prompt here"
        }
        """

        let finalPrompt = "\(systemPrompt)\n\nUser Input:\n\"\(trimmedInput)\"\n\nJSON Output:"

        logger.log("[enhancePrompt] Requesting prompt enhancement from central LLMService using model \(modelID)...")
        DiagnosticEventBus.shared.logEvent(
            component: "PromptEnhancer",
            model: modelID,
            severity: "INFO",
            category: "json",
            message: "Requesting prompt enhancement from central LLMService using model \(modelID)"
        )

        do {
            // Send request to LLMService using currently selected model
            let rawResponse = try await LLMService.shared.generateResponse(prompt: finalPrompt, useContext: false, modelOverride: modelID)
            logger.log("[enhancePrompt] Received response. Parsing JSON result...")

            if let parsed = parseEnhancedPrompt(from: rawResponse) {
                if parsed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    logger.warning("[enhancePrompt] Decoded prompt is empty.")
                    return .failure(.invalidResponse)
                }
                logger.log("[enhancePrompt] Successfully decoded enhanced prompt.")
                DiagnosticEventBus.shared.logEvent(
                    component: "PromptEnhancer",
                    model: modelID,
                    severity: "SUCCESS",
                    category: "json",
                    message: "Successfully decoded enhanced prompt"
                )
                return .success(parsed)
            } else {
                logger.warning("[enhancePrompt] Safe JSON parsing failed.")
                DiagnosticEventBus.shared.logEvent(
                    component: "PromptEnhancer",
                    model: modelID,
                    severity: "ERROR",
                    category: "json",
                    message: "Safe JSON parsing failed. Missing expected updatedPrompt key."
                )
                return .failure(.parsingFailed("Safe JSON parsing failed. Expected JSON schema keys were not found in response: \(rawResponse)"))
            }
        } catch {
            logger.error("[enhancePrompt] LLMService generateResponse threw error: \(error.localizedDescription)")
            DiagnosticEventBus.shared.logEvent(
                component: "PromptEnhancer",
                model: modelID,
                severity: "ERROR",
                errorDescription: error.localizedDescription,
                category: "network",
                message: "LLMService generateResponse threw error: \(error.localizedDescription)"
            )

            if let llmError = error as? LLMError {
                switch llmError {
                case .invalidKey:
                    return .failure(.authenticationFailed)
                case .rateLimited:
                    return .failure(.modelUnavailable)
                case .networkError(let desc):
                    return .failure(.serviceError(desc))
                case .modelNotFound:
                    return .failure(.modelUnavailable)
                case .missingOfflineDefaultModel, .offlineFallbackUnavailable:
                    return .failure(.invalidConfiguration)
                case .unknown(let desc):
                    return .failure(.serviceError(desc))
                }
            }
            return .failure(.serviceError(error.localizedDescription))
        }
    }

    private static func parseEnhancedPrompt(from text: String) -> String? {
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
        let pattern = #"\"updatedPrompt\"\s*:\s*\"((?:[^\"\\]|\\.)*)\""#
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]),
           let match = regex.firstMatch(in: text, options: [], range: NSRange(text.startIndex..., in: text)),
           let range = Range(match.range(at: 1), in: text) {
            let matchedString = String(text[range])
            return matchedString
                .replacingOccurrences(of: #"\"#, with: "\"")
                .replacingOccurrences(of: #"\n"#, with: "\n")
                .replacingOccurrences(of: #"\t"#, with: "\t")
        }

        return nil
    }
}
