import Foundation

public struct GoogleOAuthConfiguration: Sendable, Equatable {
    public static let defaultClientID = "671720100031-tkph1mke7c5bj3l93t5eemrplti78i77.apps.googleusercontent.com"

    public static let requiredScopes = [
        "https://www.googleapis.com/auth/cloud-platform",
        "https://www.googleapis.com/auth/generative-language.retriever",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile",
        "openid",
    ]

    public static let authorizationEndpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    public static let tokenEndpoint = URL(string: "https://oauth2.googleapis.com/token")!
    public static let tokeninfoEndpoint = URL(string: "https://www.googleapis.com/oauth2/v3/tokeninfo")!
    public static let userinfoEndpoint = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!

    public static let callbackScheme = "swiftcode"

    public static let preferredLoopbackPorts: [UInt16] = [65000] + Array(8085...8099)

    public var clientID: String
    public var scopes: [String]

    public init(clientID: String = Self.defaultClientID, scopes: [String] = Self.requiredScopes) {
        self.clientID = clientID
        self.scopes = scopes
    }

    public var scopeString: String { scopes.joined(separator: " ") }

    public static func redirectURI(forLoopbackPort port: UInt16) -> String {
        port == 65000 ? "http://localhost:65000/auth/callback" : "http://127.0.0.1:\(port)"
    }
}

public enum GoogleSecretAccount {
    public static let accessToken = "google.oauth.access-token"
    public static let refreshToken = "google.oauth.refresh-token"
    public static let userEmail = "google.oauth.email"
    public static let expiresAt = "google.oauth.expires-at"
    public static let scope = "google.oauth.scope"
    public static let clientSecret = "google.oauth.client-secret"
}

public enum GoogleDefaultsKey {
    public static let clientIDOverride = "assist_google_oauth_client_id_override"
    public static let explicitlySignedOut = "google_oauth_explicitly_signed_out"
}
