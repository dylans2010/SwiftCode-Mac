import Foundation

/// The HTTP client for Google's OAuth 2.0 token endpoint and the
/// two identity endpoints the auth service needs.
///
/// A value type following the `GitHubClient` / `AppwriteAccountClient`
/// pattern: an injected `URLSession` (`.shared` by default; tests
/// inject a session backed by a `URLProtocol` stub), no stored secret
/// of its own — the caller passes the client id and secret per call,
/// and the secret is never logged.
///
/// All three calls are `application/x-www-form-urlencoded` POSTs
/// (exchange, refresh) or Bearer GETs (userinfo, tokeninfo), exactly
/// as Legacy built them. Error bodies decode to
/// `GoogleOAuthErrorBody` and surface as `.http(status:message:)`;
/// a body that does not parse falls back to a plain status message.
public struct GoogleTokenClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - Token endpoint

    /// Exchanges an authorization code for tokens (PKCE flow).
    /// Sends `client_id`, `code`, `code_verifier`,
    /// `grant_type=authorization_code`, `redirect_uri`, and
    /// `client_secret` when one is configured. Google's token
    /// endpoint rejects the exchange without the secret for this
    /// client (400 invalid_request: "client_secret is missing."),
    /// even though the browser authorization step succeeds — so a
    /// missing secret surfaces as `.missingClientSecret`, not a
    /// generic HTTP error.
    public func exchangeCode(
        code: String,
        verifier: String,
        redirectURI: String,
        clientID: String,
        clientSecret: String?
    ) async throws -> GoogleOAuthTokens {
        let body = Self.formBody([
            ("client_id", clientID),
            ("code", code),
            ("code_verifier", verifier),
            ("grant_type", "authorization_code"),
            ("redirect_uri", redirectURI),
            ("client_secret", clientSecret),
        ])
        return try await postTokens(body: body)
    }

    /// Refreshes an access token with a refresh-token grant. The
    /// response's new refresh token (when Google rotates one)
    /// replaces the stored one; when the response carries none, the
    /// caller keeps the old refresh token (Legacy's
    /// `refreshAccessTokenWithDetails` returned the original
    /// refresh token in the tokens it built).
    public func refreshToken(
        _ refreshToken: String,
        clientID: String,
        clientSecret: String?
    ) async throws -> GoogleOAuthTokens {
        let body = Self.formBody([
            ("client_id", clientID),
            ("refresh_token", refreshToken),
            ("grant_type", "refresh_token"),
            ("client_secret", clientSecret),
        ])
        let tokens = try await postTokens(body: body)
        return GoogleOAuthTokens(
            accessToken: tokens.accessToken,
            expiresIn: tokens.expiresIn,
            refreshToken: tokens.refreshToken ?? refreshToken,
            scope: tokens.scope,
            tokenType: tokens.tokenType,
            idToken: tokens.idToken
        )
    }

    private func postTokens(body: Data) async throws -> GoogleOAuthTokens {
        var request = URLRequest(url: GoogleOAuthConfiguration.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw GoogleAuthError.network(error.localizedDescription)
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GoogleAuthError.decoding("Invalid server response.")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw tokenHTTPError(status: httpResponse.statusCode, data: data)
        }
        do {
            return try JSONDecoder().decode(GoogleOAuthTokens.self, from: data)
        } catch {
            throw GoogleAuthError.decoding("Unable to parse Google OAuth token response.")
        }
    }

    /// Maps a non-2xx token-endpoint response to an error. A
    /// "client_secret is missing" body becomes
    /// `.missingClientSecret` so the UI can name the fix; anything
    /// else becomes `.http(status:message:)` with the server's
    /// `error_description` (or `error`) text.
    private func tokenHTTPError(status: Int, data: Data) -> GoogleAuthError {
        let body = try? JSONDecoder().decode(GoogleOAuthErrorBody.self, from: data)
        let message = body?.message(fallback: "Token request returned HTTP status \(status).") ?? "Token request returned HTTP status \(status)."
        if GoogleAuthErrorClassification.classify(message, storedScopes: nil).kind == .missingClientSecret {
            return .missingClientSecret
        }
        return .http(status: status, message: message)
    }

    // MARK: - Identity endpoints

    /// The signed-in user's email from the userinfo endpoint.
    /// Returns nil (never throws) when the endpoint rejects the
    /// token or the body has no email — Legacy's `fetchUserEmail`
    /// returned nil on any non-2xx response or missing field, and
    /// its callers fell back to the id token.
    public func fetchUserEmail(accessToken: String) async -> String? {
        var request = URLRequest(url: GoogleOAuthConfiguration.userinfoEndpoint)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await session.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = json["email"] as? String else {
            return nil
        }
        return email
    }

    /// The tokeninfo status for an access token: 200 when Google
    /// accepts it, 400/401 when it is rejected, another status (or
    /// nil when the request never reached Google) otherwise.
    /// Legacy's `verifyRuntimeSession` branched on exactly these
    /// cases (200 valid, 400/401 refresh-and-retry, anything else
    /// fall back to the stored expiry).
    public func tokeninfoStatus(accessToken: String, timeout: TimeInterval = 6.0) async -> Int? {
        var components = URLComponents(url: GoogleOAuthConfiguration.tokeninfoEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "access_token", value: accessToken)]
        guard let url = components?.url else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        guard let (_, response) = try? await session.data(for: request),
              let httpResponse = response as? HTTPURLResponse else {
            return nil
        }
        return httpResponse.statusCode
    }

    // MARK: - Form encoding

    /// `application/x-www-form-urlencoded` body from key/value
    /// pairs, skipping nil values. Each value is percent-encoded
    /// with `.urlQueryAllowed`, exactly as Legacy encoded its
    /// token-request parameters inline.
    static func formBody(_ pairs: [(String, String?)]) -> Data {
        let encoded = pairs.compactMap { (name, value) -> String? in
            guard let value else { return nil }
            let escaped = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(name)=\(escaped)"
        }
        return Data(encoded.joined(separator: "&").utf8)
    }
}
