import Foundation

/// Errors from the GitHub REST API client. Messages name the fix where
/// there is one (a missing or rejected token points at the settings pane
/// that holds it); they never include the token.
public enum GitHubError: Error, LocalizedError, Equatable {
    case missingToken
    case unauthorized
    case forbidden(message: String, rateLimited: Bool, resetAt: Date?)
    case notFound
    case unprocessable(message: String)
    case http(status: Int, message: String)
    case decoding
    case network
    case invalidRepo(String)

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            return "No GitHub token saved. Add a personal access token in Settings ▸ Coding Assistant ▸ GitHub."
        case .unauthorized:
            return "GitHub rejected the token. Check the personal access token in Settings ▸ Coding Assistant ▸ GitHub."
        case let .forbidden(message, rateLimited, resetAt):
            if rateLimited {
                if let resetAt {
                    return "GitHub rate limit exhausted; resets at \(resetAt). \(message)"
                }
                return "GitHub rate limit exhausted. \(message)"
            }
            return message
        case .notFound:
            return "Not found on GitHub. Check the repository name and that the token can access it."
        case let .unprocessable(message):
            return message
        case let .http(status, message):
            return "GitHub request failed (HTTP \(status)): \(message)"
        case .decoding:
            return "GitHub returned a response SwiftCode could not understand."
        case .network:
            return "Could not reach GitHub. Check the network connection and try again."
        case let .invalidRepo(value):
            return "Invalid repository \"\(value)\". Use the form owner/repo."
        }
    }
}
