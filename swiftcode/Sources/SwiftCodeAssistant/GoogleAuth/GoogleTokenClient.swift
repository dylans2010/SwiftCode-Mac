import Foundation

public struct GoogleTokenClient: Sendable {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

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

    private func tokenHTTPError(status: Int, data: Data) -> GoogleAuthError {
        let body = try? JSONDecoder().decode(GoogleOAuthErrorBody.self, from: data)
        let message = body?.message(fallback: "Token request returned HTTP status \(status).") ?? "Token request returned HTTP status \(status)."
        if GoogleAuthErrorClassification.classify(message, storedScopes: nil).kind == .missingClientSecret {
            return .missingClientSecret
        }
        return .http(status: status, message: message)
    }

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

    static func formBody(_ pairs: [(String, String?)]) -> Data {
        let encoded = pairs.compactMap { (name, value) -> String? in
            guard let value else { return nil }
            let escaped = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(name)=\(escaped)"
        }
        return Data(encoded.joined(separator: "&").utf8)
    }
}
