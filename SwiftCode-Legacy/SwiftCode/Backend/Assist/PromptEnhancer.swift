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

    /// Primary async-throwing entry point for AssistAPIRouter compatibility.
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

    /// Primary Result-returning entry point for AssistMainView compatibility.
    @MainActor
    public static func enhancePrompt(userInput: String, modelID: String? = nil) async -> Result<String, PromptEnhancementError> {
        let trimmedInput = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else { return .success(userInput) }

        logger.log("[enhancePrompt] Initiating prompt enhancement. Validating Apple Foundation Models configuration...")
        DiagnosticEventBus.shared.logEvent(
            component: "PromptEnhancer",
            model: "AFM 3 Core",
            severity: "INFO",
            category: "validation",
            message: "Validating Apple Foundation Models availability and required capabilities."
        )

        // --- 8. FOUNDATION MODELS VALIDATION ---
        // Verify Apple Foundation Models are available/enabled
        guard FoundationModels.shared.isEnabled else {
            logger.error("[enhancePrompt] Apple Foundation Models are not enabled.")
            DiagnosticEventBus.shared.logEvent(
                component: "PromptEnhancer",
                model: "AFM 3 Core",
                severity: "ERROR",
                category: "validation",
                message: "Apple Foundation Models are disabled."
            )
            return .failure(.modelUnavailable)
        }

        // Verify Core Model (afm3Core) can be initialized
        let coreModel = AppleFoundationModel.afm3Core
        logger.log("[enhancePrompt] Apple Foundation Models are available. Initializing Core model: \(coreModel.rawValue).")

        let systemPrompt = """
        You are a highly professional prompt enhancer. Your task is to rewrite the user's input prompt into an enhanced, technically clear, structured, and professional instruction for an AI coding agent while preserving their original intent.

        You MUST return ONLY a valid JSON object matching this schema, with absolutely no other text, markdown formatting blocks (like ```json), explanations, or surrounding commentary:
        {
          "updatedPrompt": "your enhanced prompt here"
        }
        """

        let finalPrompt = "\(systemPrompt)\n\nUser Input:\n\"\(trimmedInput)\"\n\nJSON Output:"

        logger.log("[enhancePrompt] Temporarily binding active Foundation Model to Core model \(coreModel.rawValue)...")

        // Temporarily bind active on-device model to afm3Core
        let originalModel = FoundationModels.shared.selectedModel
        FoundationModels.shared.selectedModel = .afm3Core

        defer {
            logger.log("[enhancePrompt] Restoring original Foundation Model selection: \(originalModel.rawValue)")
            FoundationModels.shared.selectedModel = originalModel
        }

        DiagnosticEventBus.shared.logEvent(
            component: "PromptEnhancer",
            model: "AFM 3 Core",
            severity: "INFO",
            category: "generation",
            message: "Requesting prompt enhancement directly from Apple Foundation Models Core Model (\(coreModel.rawValue))"
        )

        do {
            // Generate private response directly using Apple Foundation Models
            let rawResponse = try await FoundationModels.shared.generatePrivateResponse(prompt: finalPrompt)
            logger.log("[enhancePrompt] Received response. Parsing JSON result...")

            if let parsed = parseEnhancedPrompt(from: rawResponse) {
                if parsed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    logger.warning("[enhancePrompt] Decoded prompt is empty.")
                    return .failure(.invalidResponse)
                }
                logger.log("[enhancePrompt] Successfully decoded enhanced prompt.")
                DiagnosticEventBus.shared.logEvent(
                    component: "PromptEnhancer",
                    model: "AFM 3 Core",
                    severity: "SUCCESS",
                    category: "generation",
                    message: "Successfully decoded enhanced prompt."
                )
                return .success(parsed)
            } else {
                logger.warning("[enhancePrompt] Safe JSON parsing failed.")
                DiagnosticEventBus.shared.logEvent(
                    component: "PromptEnhancer",
                    model: "AFM 3 Core",
                    severity: "ERROR",
                    category: "json",
                    message: "Safe JSON parsing failed. Missing expected updatedPrompt key."
                )
                return .failure(.parsingFailed("Safe JSON parsing failed. Expected JSON schema keys were not found in response: \(rawResponse)"))
            }
        } catch {
            logger.error("[enhancePrompt] Direct Apple Foundation Models generation failed: \(error.localizedDescription)")
            DiagnosticEventBus.shared.logEvent(
                component: "PromptEnhancer",
                model: "AFM 3 Core",
                severity: "ERROR",
                errorDescription: error.localizedDescription,
                category: "generation",
                message: "Direct Apple Foundation Models generation failed: \(error.localizedDescription)"
            )
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