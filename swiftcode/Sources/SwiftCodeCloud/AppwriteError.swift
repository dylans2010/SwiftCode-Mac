import Foundation

public enum AppwriteError: Error, LocalizedError, Equatable, Sendable {
    case http(status: Int, code: Int?, type: String?, message: String)
    case network(String)
    case decoding(String)
    case invalidConfiguration(String)
    case missingSession
    case oauthFailed(String)
    case oauthCallbackTimeout

    public var errorDescription: String? {
        switch self {
        case .http(_, _, _, let message):
            return message
        case .network(let detail):
            return "Could not reach the authentication server: \(detail)"
        case .decoding(let detail):
            return "The authentication server returned an unreadable response: \(detail)"
        case .invalidConfiguration(let detail):
            return "The cloud configuration is invalid: \(detail)"
        case .missingSession:
            return "There is no active cloud session. Please sign in."
        case .oauthFailed(let detail):
            return "Sign-in with the external provider failed: \(detail)"
        case .oauthCallbackTimeout:
            return "The sign-in did not finish: the app never received the callback from the browser."
        }
    }

    public var userFacingMessage: String {
        switch self {
        case .http(let status, _, _, let message):
            let lower = message.lowercased()
            if status == 401 || lower.contains("invalid credentials") {
                return "Invalid email address or password. Please verify and try again."
            }
            if status == 409 || lower.contains("already exists") {
                return "An account with this email address is already registered on our servers."
            }
            if lower.contains("weak password") || lower.contains("password") && lower.contains("length") {
                return "Your password is too weak. Please ensure it is at least 8 characters long."
            }
            if lower.contains("network") || lower.contains("connection") {
                return "Unable to connect to the authentication server. Please check your network connection."
            }
            return message
        case .network:
            return "Unable to connect to the authentication server. Please check your network connection."
        case .decoding(let detail):
            return detail
        case .invalidConfiguration(let detail):
            return detail
        case .missingSession:
            return "There is no active cloud session. Please sign in."
        case .oauthFailed(let detail):
            return "OAuth Failed: \(detail)"
        case .oauthCallbackTimeout:
            return errorDescription ?? "The sign-in did not finish."
        }
    }
}
