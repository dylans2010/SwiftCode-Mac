import Foundation

/// What can go wrong talking to the Appwrite Account API over REST.
///
/// The server's error body carries a machine-readable `code` and
/// `type` plus a human `message`; those are preserved verbatim in
/// `.http` so callers (and the settings UI) can map them, exactly as
/// Legacy's `CloudAuthViews.mapErrorToUserMessage` matched on the
/// SDK error's text (`invalid credentials` / `401`, `already exists` /
/// `409`, `network`, `weak password`).
public enum AppwriteError: Error, LocalizedError, Equatable, Sendable {
    /// The server answered with a non-2xx status. `code` and `type`
    /// are the Appwrite error body's fields when the body parsed.
    case http(status: Int, code: Int?, type: String?, message: String)
    /// The request never reached the server (no network, DNS, TLS).
    case network(String)
    /// A 2xx response whose body did not decode.
    case decoding(String)
    /// The configuration itself is unusable (bad endpoint URL).
    case invalidConfiguration(String)
    /// An authenticated call was made with no session secret stored.
    case missingSession
    /// The OAuth provider, or Appwrite, reported the flow failed.
    case oauthFailed(String)
    /// `beginOAuth` waited for the app to deliver the callback and
    /// none arrived within the timeout (see `CloudAuthManager`).
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

    /// The user-facing sentence for this failure, following Legacy's
    /// `CloudAuthViews.mapErrorToUserMessage` mapping. Specific
    /// server messages win over the raw text: a 401 / "invalid
    /// credentials" is a wrong email or password, a 409 / "already
    /// exists" is a registered email, a network failure is a
    /// connection problem, and a weak-password message says so.
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
