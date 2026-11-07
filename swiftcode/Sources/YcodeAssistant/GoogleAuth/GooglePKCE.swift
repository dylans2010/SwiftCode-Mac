import Crypto
import Foundation

public enum GooglePKCE: Sendable {
    public static func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 64)
        for index in buffer.indices { buffer[index] = UInt8.random(in: UInt8.min...UInt8.max) }
        return base64URLEncode(Data(buffer))
    }

    public static func generateCodeChallenge(for verifier: String) -> String {
        guard let asciiData = verifier.data(using: .ascii) else { return "" }
        return base64URLEncode(SHA256.hash(asciiData))
    }


    public static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

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
