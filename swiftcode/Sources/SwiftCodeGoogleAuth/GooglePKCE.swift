import Crypto
import Foundation

/// The PKCE (RFC 7636) and loopback-redirect (RFC 8252) pieces of
/// the Google sign-in flow, as pure functions so they are testable
/// without a browser, a listener, or a network.
///
/// Ported from Legacy's `GoogleAccountAuthService` PKCE helpers and
/// `buildAuthorizationURL` / `handleCallbackURL` parsing:
/// - the verifier is 64 random bytes, base64url-encoded without
///   padding (43 characters of output per 32 bytes would be the
///   minimum; Legacy used 64 bytes, so the verifier is 86
///   characters — inside RFC 7636's 43–128 range);
/// - the challenge is base64url(SHA-256(ASCII(verifier))), method
///   `S256`;
/// - the authorize URL carries `access_type=offline` (so Google
///   returns a refresh token) and `prompt=consent` (so it returns
///   one on every sign-in, not just the first).
public enum GooglePKCE: Sendable {
    /// A fresh code verifier: 64 random bytes, base64url-encoded.
    /// Uses the system random-number generator (portable; Legacy's
    /// `SecRandomCopyBytes` is Apple-only and unnecessary here —
    /// the generator cannot fail).
    public static func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 64)
        for index in buffer.indices { buffer[index] = UInt8.random(in: UInt8.min...UInt8.max) }
        return base64URLEncode(Data(buffer))
    }

    /// The S256 code challenge for a verifier: base64url of the
    /// SHA-256 of the verifier's ASCII bytes.
    public static func generateCodeChallenge(for verifier: String) -> String {
        guard let asciiData = verifier.data(using: .ascii) else { return "" }
        return base64URLEncode(Data(SHA256.hash(data: asciiData)))
    }

    /// Base64url encoding: standard base64 with `+` → `-`,
    /// `/` → `_`, and padding stripped (Legacy's
    /// `base64UrlEncode`, including its whitespace trim).
    public static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The Google authorize URL for a sign-in attempt: the
    /// authorization endpoint with the client id, loopback redirect
    /// URI, `response_type=code`, the scopes, the PKCE challenge,
    /// the state, `access_type=offline`, and `prompt=consent`.
    public static func authorizationURL(
        configuration: GoogleOAuthConfiguration,
        challenge: String,
        state: String,
        redirectURI: String
    ) -> URL? {
        var components = URLComponents(url: GoogleOAuthConfiguration.authorizationEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: configuration.scopeString),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]
        return components?.url
    }

    /// Validates a loopback callback URL against the `state` the
    /// flow sent and returns the authorization code. Throws
    /// `.invalidCallbackURL` for a malformed URL,
    /// `.authorizationDenied` when Google reported an error,
    /// `.stateMismatch` when the state differs, and
    /// `.missingAuthorizationCode` when no code is present —
    /// Legacy's `handleCallbackURL` checks, in the same order.
    public static func parseCallback(_ url: URL, expectedState state: String) throws -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw GoogleAuthError.invalidCallbackURL
        }
        let queryItems = components.queryItems ?? []
        if let errorParam = queryItems.first(where: { $0.name == "error" })?.value {
            throw GoogleAuthError.authorizationDenied(errorParam)
        }
        guard let returnedState = queryItems.first(where: { $0.name == "state" })?.value,
              returnedState == state else {
            throw GoogleAuthError.stateMismatch
        }
        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            throw GoogleAuthError.missingAuthorizationCode
        }
        return code
    }

    /// The email inside a JWT id token's payload, if it decodes.
    /// Legacy's `extractEmailFromIDToken`: split on `.`, base64url-
    /// decode the middle part (re-padding as needed), read `email`.
    /// A malformed token yields nil, never a throw.
    public static func extractEmailFromIDToken(_ idToken: String) -> String? {
        let parts = idToken.components(separatedBy: ".")
        guard parts.count >= 2 else { return nil }
        var base64 = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 {
            base64.append("=")
        }
        guard let data = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = json["email"] as? String else {
            return nil
        }
        return email
    }
}
