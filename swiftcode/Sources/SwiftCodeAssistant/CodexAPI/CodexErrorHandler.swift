import Foundation

public enum CodexAPIError: LocalizedError, Equatable {
    case invalidKey
    case rateLimited
    case networkError(String)
    case modelNotFound
    case unknown(String)

    public var errorDescription: String? {
        switch self {
        case .invalidKey:
            return "The OpenAI API key is invalid or expired."
        case .rateLimited:
            return "The current Codex key has reached its limit."
        case .networkError(let message):
            return "Network issue: \(message)"
        case .modelNotFound:
            return "The selected Codex model is unavailable."
        case .unknown(let message):
            return message
        }
    }
}

public enum CodexErrorHandler {
    public static func parseHTTPError(data: Data, statusCode: Int) -> Error {
        if statusCode == 401 { return CodexAPIError.invalidKey }
        if statusCode == 429 { return CodexAPIError.rateLimited }

        if let envelope = try? JSONDecoder().decode(CodexErrorEnvelope.self, from: data) {
            return CodexAPIError.unknown(envelope.error.message)
        }

        let text = String(data: data, encoding: .utf8) ?? HTTPURLResponse.localizedString(forStatusCode: statusCode)
        return CodexAPIError.networkError(text)
    }

    public static func userFacingMessage(for error: Error) -> String {
        if let codexError = error as? CodexAPIError {
            switch codexError {
            case .invalidKey: return "The OpenAI API key is invalid or expired."
            case .rateLimited: return "The current Codex key has reached its limit."
            case .networkError(let message): return "Network issue: \(message)"
            case .modelNotFound: return "The selected Codex model is unavailable."
            case .unknown(let message): return message
            }
        }
        return error.localizedDescription
    }
}
