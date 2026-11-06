import Foundation

/// Where the cloud account backend lives, and which Appwrite project
/// it belongs to.
///
/// The defaults are Legacy's own backend coordinates, taken verbatim
/// from `Services/Appwrite/AppwriteService.swift` (a global `Client`
/// pointed at `https://sfo.cloud.appwrite.io/v1`, project
/// `6a670d0b0022e5f964b4`). They are configuration, not credentials:
/// the project id is a public identifier that every request carries
/// in the `X-Appwrite-Project` header, and the endpoint is a public
/// URL. Nothing secret is stored here — the session secret lives in
/// the secret store (see `SecretAccount.appwriteSessionSecret`).
public struct AppwriteConfiguration: Sendable, Equatable {
    /// Legacy's Appwrite endpoint.
    public static let defaultEndpoint = URL(string: "https://sfo.cloud.appwrite.io/v1")!
    /// Legacy's Appwrite project id.
    public static let defaultProjectID = "6a670d0b0022e5f964b4"

    /// The Appwrite server's base URL, without a trailing slash.
    public var endpoint: URL
    /// The Appwrite project id sent on every request.
    public var projectID: String

    public init(endpoint: URL = Self.defaultEndpoint, projectID: String = Self.defaultProjectID) {
        self.endpoint = endpoint
        self.projectID = projectID
    }

    /// The custom URL scheme Appwrite redirects OAuth, recovery and
    /// verification flows to, e.g.
    /// `appwrite-callback-6a670d0b0022e5f964b4://`. Legacy built this
    /// string inline in `AuthManager` (`loginWithGoogle`,
    /// `loginWithGitHub`, `forgotPassword`, `sendVerificationEmail`);
    /// it is derived from the project id here so the two cannot drift.
    public var callbackScheme: String {
        "appwrite-callback-\(projectID)"
    }

    /// The name of the session cookie Appwrite sets when a session is
    /// created, e.g. `a_session_6a670d0b0022e5f964b4`. The cookie's
    /// value is the session secret.
    public var sessionCookieName: String {
        "a_session_\(projectID)"
    }
}
