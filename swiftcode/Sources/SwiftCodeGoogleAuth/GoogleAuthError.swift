import Foundation

/// What can go wrong signing in to Google, refreshing a token, or
/// verifying a session.
///
/// The transport cases mirror `AppwriteError`'s shape (the Wave 12
/// error style): the server's status and message are preserved
/// verbatim in `.http` so callers can map them, and
/// `userFacingMessage` carries Legacy's
/// `CloudAuthViews`-style mapping plus the sign-in remediation
/// Legacy's `actionableSignInError` gave for a missing client
/// secret. Secrets are never included in any message.
public enum GoogleAuthError: Error, LocalizedError, Equatable, Sendable {
    /// The token endpoint (or userinfo/tokeninfo) answered with a
    /// non-2xx status. `message` is the server's `error_description`
    /// (or `error`) when the body parsed.
    case http(status: Int, message: String)
    /// The request never reached Google (no network, DNS, TLS).
    case network(String)
    /// A 2xx response whose body did not decode.
    case decoding(String)
    /// The browser flow cannot run here: `ASWebAuthenticationSession`
    /// (and the `Network` loopback listener) are Apple-only, so on
    /// Linux — and anywhere without them — sign-in fails honestly
    /// instead of pretending a browser opened.
    case browserSignInUnavailable
    /// The loopback listener could not bind any port (all preferred
    /// ports busy and no ephemeral port available).
    case loopbackUnavailable
    /// Google's authorize endpoint reported the flow failed
    /// (the `error` query item on the redirect).
    case authorizationDenied(String)
    /// The redirect's `state` did not match the one the flow sent.
    case stateMismatch
    /// The redirect carried no authorization code.
    case missingAuthorizationCode
    /// The redirect URL itself was malformed.
    case invalidCallbackURL
    /// The token endpoint refused the code exchange because the
    /// OAuth client's secret was not sent (400 invalid_request:
    /// "client_secret is missing."). Fixable by configuring the
    /// secret; see `actionableSignInError(for:)`.
    case missingClientSecret
    /// A refresh-token grant failed; the stored session is dead.
    /// `lastTokenRefreshError` on the service carries the detail.
    case refreshFailed(String)
    /// The user cancelled the browser sign-in.
    case userCancelled
    /// The `agy` CLI is not installed anywhere it is looked for.
    case agyCLINotFound
    /// The `agy` CLI sign-in did not produce credentials in time.
    case agyCLITimedOut
    /// The `agy` CLI is installed but its interactive login cannot
    /// be driven here: launching it in Terminal is macOS-only.
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

    /// The sentence the UI shows. Specific failures get specific
    /// remediation (a missing client secret names the fix); a
    /// network failure says so; anything else passes the server's
    /// message through unchanged.
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

    /// Maps a sign-in failure to the message the user actually sees.
    /// A missing client secret gets specific remediation instead of
    /// Google's terse "client_secret is missing."; every other
    /// failure passes through with its original details preserved.
    /// Ported from Legacy's `actionableSignInError(for:)`, with the
    /// Settings path updated to where the secret field lives in
    /// SwiftCode (Settings → Accounts → Google Account, not Legacy's
    /// Settings → Assist → Google Account).
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
