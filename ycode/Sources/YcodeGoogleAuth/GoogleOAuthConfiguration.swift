import Foundation

/// Where Google's OAuth endpoints live, which OAuth client Ycode
/// signs in with, and which scopes the sign-in asks for.
///
/// The client id is Legacy's own ("SwiftCode's own Google OAuth
/// client ID (Desktop application type)"), taken verbatim from
/// `Services/GoogleAccountAuthService.swift`. A client id for a
/// PKCE public client is a public identifier by design, not a
/// secret — it is sent in the clear in the authorize URL. No
/// client secret is stored here, ever: see
/// `GoogleOAuthConfiguration.clientSecret`.
///
/// The scopes are Legacy's `requiredScopes`, verbatim: the Gemini
/// Developer API's documented OAuth contract requires
/// `generative-language.retriever` (without it the API rejects the
/// token with 403 ACCESS_TOKEN_SCOPE_INSUFFICIENT), plus
/// `cloud-platform` and the email/profile/openid scopes.
public struct GoogleOAuthConfiguration: Sendable, Equatable {
    /// Legacy's Google OAuth client id (Desktop application type).
    public static let defaultClientID = "671720100031-tkph1mke7c5bj3l93t5eemrplti78i77.apps.googleusercontent.com"

    /// The scopes Legacy's "Sign in with Google" flow requests.
    public static let requiredScopes = [
        "https://www.googleapis.com/auth/cloud-platform",
        "https://www.googleapis.com/auth/generative-language.retriever",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile",
        "openid",
    ]

    /// Google's OAuth 2.0 authorization endpoint.
    public static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    /// Google's OAuth 2.0 token endpoint (code exchange + refresh).
    public static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    /// Google's tokeninfo endpoint (runtime session verification).
    public static let tokeninfoEndpoint = URL(string: "https://www.googleapis.com/oauth2/v3/tokeninfo")!
    /// Google's userinfo endpoint (the signed-in email).
    public static let userinfoEndpoint = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!

    /// The custom URL scheme the browser flow resumes on
    /// (`swiftcode://oauth-callback`), Legacy's `callbackScheme`.
    public static let callbackScheme = "swiftcode"

    /// The loopback listener's preferred ports, in order: 65000
    /// first (its redirect is `http://localhost:65000/auth/callback`),
    /// then 8085...8099, then an ephemeral port. Legacy's
    /// `OAuthLoopbackServer.start()` order, kept so an existing
    /// Google Cloud Console redirect registration keeps working.
    public static let preferredLoopbackPorts: [UInt16] = [65000] + Array(8085...8099)

    /// The OAuth client id this configuration signs in with.
    public var clientID: String
    /// The scopes, space-joined, sent on the authorize URL.
    public var scopes: [String]

    public init(clientID: String = Self.defaultClientID, scopes: [String] = Self.requiredScopes) {
        self.clientID = clientID
        self.scopes = scopes
    }

    /// The scope string sent on the authorize URL.
    public var scopeString: String { scopes.joined(separator: " ") }

    /// The redirect URI for a loopback listener on `port`, exactly
    /// as Legacy built it: port 65000 uses the `localhost` host
    /// with the `/auth/callback` path (the redirect registered for
    /// it), every other port uses `127.0.0.1` with no path.
    public static func redirectURI(forLoopbackPort port: UInt16) -> String {
        port == 65000 ? "http://localhost:65000/auth/callback" : "http://127.0.0.1:\(port)"
    }
}

/// The secret-store accounts (item names) the Google auth service
/// uses. Ycode-style dotted names, mirroring `SecretAccount` in
/// `YcodeAssistant` (which this target does not edit — these keys
/// belong to this service, so they live here). Values never go to
/// user defaults, logs, or files; on macOS the store is the login
/// keychain, on Linux a 0600 file (see `SecretStore`).
public enum GoogleSecretAccount {
    /// The current OAuth access token.
    public static let accessToken = "google.oauth.access-token"
    /// The OAuth refresh token (kept across sign-ins until revoked).
    public static let refreshToken = "google.oauth.refresh-token"
    /// The signed-in Google account's email address.
    public static let userEmail = "google.oauth.email"
    /// The access token's expiry as seconds since the epoch.
    public static let expiresAt = "google.oauth.expires-at"
    /// The scopes granted to the current session, space-joined.
    public static let scope = "google.oauth.scope"
    /// The user-entered OAuth client secret (see
    /// `GoogleOAuthConfiguration` — never embedded in the app).
    public static let clientSecret = "google.oauth.client-secret"
}

/// The UserDefaults keys the Google auth service uses. Legacy's
/// exact key strings, kept so an existing install's override and
/// sign-out state survive the port.
public enum GoogleDefaultsKey {
    /// The user-configured OAuth client-id override (Legacy's
    /// `AppSettings.assistGoogleOAuthClientIDOverride`, stored under
    /// this key; Ycode has no `AppSettings`, so the service reads
    /// the key directly).
    public static let clientIDOverride = "assist_google_oauth_client_id_override"
    /// Set on explicit sign-out; ambient credentials (Antigravity
    /// keychain entries, ADC files, gcloud) must not resurrect the
    /// session while it is set (Legacy H-3).
    public static let explicitlySignedOut = "google_oauth_explicitly_signed_out"
}
