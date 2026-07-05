import Foundation

enum CodexErrorHandler {
    static func parseHTTPError(data: Data, statusCode: Int) -> Error {
        if statusCode == 401 { return LLMError.invalidKey }
        if statusCode == 429 { return LLMError.rateLimited }

        if let envelope = try? JSONDecoder().decode(CodexErrorEnvelope.self, from: data) {
            return LLMError.unknown(envelope.error.message)
        }

        let text = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: statusCode)
        return LLMError.networkError(text)
    }

    static func userFacingMessage(for error: Error) -> String {
        if let llmError = error as? LLMError {
            switch llmError {
            case .invalidKey: return "The OpenAI API key is invalid or expired."
            case .rateLimited: return "The current Codex key has reached its limit."
            case .networkError(let message): return "Network issue: \(message)"
            case .modelNotFound: return "The selected Codex model is unavailable."
            case .unknown(let message): return message
            case .missingOfflineDefaultModel: return "No offline model is configured."
            case .offlineFallbackUnavailable: return "No Codex or offline fallback is available."
            }
        }
        return error.localizedDescription
    }
}
