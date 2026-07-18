import Foundation
import os

private let logger = Logger(subsystem: "com.swiftcode.PromptEnhancer", category: "PromptEnhancer")

public final class PromptEnhancer {

    struct EnhancedPromptJSON: Codable {
        let updatedPrompt: String
    }

    @MainActor
    public static func enhancePrompt(userInput: String) async -> String {
        let trimmedInput = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return userInput }

        let systemPrompt = """
        You are a highly professional prompt enhancer. Your task is to rewrite the user's input prompt into an enhanced, technically clear, structured, and professional instruction for an AI coding agent while preserving their original intent.

        You MUST return ONLY a valid JSON object matching this schema, with absolutely no other text, markdown formatting blocks (like ```json), explanations, or surrounding commentary:
        {
          "updatedPrompt": "your enhanced prompt here"
        }
        """

        let finalPrompt = "\(systemPrompt)\n\nUser Input:\n\"\(trimmedInput)\"\n\nJSON Output:"

        logger.log("[enhancePrompt] Requesting prompt enhancement from central LLMService...")
        do {
            // Send request to LLMService using currently selected model
            let rawResponse = try await LLMService.shared.generateResponse(prompt: finalPrompt, useContext: false)
            logger.log("[enhancePrompt] Received response. Parsing JSON result...")

            if let parsed = parseEnhancedPrompt(from: rawResponse) {
                logger.log("[enhancePrompt] Successfully decoded enhanced prompt.")
                return parsed
            } else {
                logger.warning("[enhancePrompt] Safe JSON parsing failed. Falling back to raw response.")
                // If it's not JSON but seems like an enhanced text block, return it directly if clean, otherwise fall back to user input
                let cleanedRaw = rawResponse.trimmingCharacters(in: .whitespacesAndNewlines)
                if !cleanedRaw.isEmpty && !cleanedRaw.contains("{") {
                    return cleanedRaw
                }
                return userInput
            }
        } catch {
            logger.error("[enhancePrompt] LLMService generateResponse threw error: \(error.localizedDescription)")
            return userInput
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
