import Foundation

public enum GoogleAuthError: Error, LocalizedError, Equatable, Sendable {
    case http(status: Int, message: String)
    case network(String)
    case decoding(String)
    case browserSignInUnavailable
    case loopbackUnavailable
    case authorizationDenied(String)
    case stateMismatch
    case missingAuthorizationCode
    case invalidCallbackURL
    case missingClientSecret
    case refreshFailed(String)
    case userCancelled
    case agyCLINotFound
    case agyCLITimedOut
    case cliSignInUnavailable

    public var errorDescription: String? {
        switch self {
        case .http(_, let message):
            return message
        case .network(let detail):
            return "Could not reach Google: \(detail)"
        case .decoding(let detail):
            return "Google returned an unreadable response: \(detail)"
        case .browserSignInUnavailable:
            return "Sign in with Google needs a browser sign-in session, which is not available on this platform."
        case .loopbackUnavailable:
            return "Could not start the local sign-in listener. Another process may be using the sign-in ports."
        case .authorizationDenied(let detail):
            return "Google authentication error: \(detail)"
        case .stateMismatch:
            return "Security verification failed: OAuth state mismatch."
        case .missingAuthorizationCode:
            return "No authorization code returned from Google."
        case .invalidCallbackURL:
            return "Invalid callback URL structure."
        case .missingClientSecret:
            return "Google sign-in needs your OAuth client's secret: the browser authorization succeeded, "
                + "but Google refused the token exchange (\"client_secret is missing.\")."
        case .refreshFailed(let detail):
            return "Could not refresh the Google access token: \(detail)"
        case .userCancelled:
            return "Google sign-in was cancelled."
        case .agyCLINotFound:
            return "The 'agy' CLI binary was not found. Please install it in ~/.local/bin/agy or use standard Sign in with Google."
        case .agyCLITimedOut:
            return "Authentication timed out. Please finish signing in via the Terminal window and try again."
        case .cliSignInUnavailable:
            return "Interactive sign-in through the 'agy' CLI needs macOS Terminal. Use standard Sign in with Google instead."
        }
    }

    public var userFacingMessage: String {
        switch self {
        case .missingClientSecret:
            return Self.actionableSignInError(for: self)
        case .network:
            return "Unable to connect to Google. Please check your network connection."
        default:
            return errorDescription ?? "Google sign-in failed."
        }
    }

    public static func actionableSignInError(for error: Error) -> String {
        let description = error.localizedDescription
        let classification = GoogleAuthErrorClassification.classify(description, storedScopes: nil)
        guard classification.kind == .missingClientSecret else { return description }
        return "Google sign-in needs your OAuth client's secret: the browser authorization succeeded, "
            + "but Google refused the token exchange (\"client_secret is missing.\"). "
            + "Enter the client secret in Settings → Accounts → Google Account — it is stored securely in "
            + "Keychain and only ever sent to Google's token endpoint. Find it in Google Cloud Console → "
            + "APIs & Services → Credentials → your OAuth client."
    }
}
