//
//  GoogleAccountAuthService.swift
//  SwiftCode
//
//  Authentication service for Google Accounts using ASWebAuthenticationSession,
//  PKCE (RFC 7636), and fallback to ambient Application Default Credentials (ADC).
//

import Foundation
import AuthenticationServices
import CryptoKit
import Security
import os
#if canImport(AppKit)
import AppKit
#endif

private let logger = Logger(subsystem: "com.swiftcode.auth", category: "GoogleAccountAuthService")

// MARK: - Google OAuth Token Response

public struct GoogleOAuthTokens: Codable, Sendable {
    public let accessToken: String
    public let expiresIn: Int?
    public let refreshToken: String?
    public let scope: String?
    public let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case tokenType = "token_type"
    }
}

// MARK: - Google Account Auth Service

@MainActor
public final class GoogleAccountAuthService: NSObject, ObservableObject {
    public static let shared = GoogleAccountAuthService()

    // MARK: - Keychain Keys
    public nonisolated static let accessTokenKey = "google_oauth_access_token"
    public nonisolated static let refreshTokenKey = "google_oauth_refresh_token"
    public nonisolated static let userEmailKey = "google_account_email"
    public nonisolated static let expiresAtKey = "google_oauth_expires_at"
    private nonisolated static let explicitlySignedOutKey = "google_oauth_explicitly_signed_out"

    // MARK: - Observable State
    @Published public private(set) var isAuthenticated: Bool = false
    @Published public private(set) var userEmail: String? = nil
    @Published public private(set) var isAuthenticating: Bool = false
    @Published public var authError: String? = nil

    // MARK: - OAuth Flow Session
    private var authSession: ASWebAuthenticationSession?
    private var pendingCodeVerifier: String?
    private var pendingState: String?

    // MARK: - OAuth Configuration
    private let redirectURI = "swiftcode://oauth/google"
    private let callbackScheme = "swiftcode"
    private let scopes = [
        "email",
        "profile",
        "https://www.googleapis.com/auth/generative-language",
        "https://www.googleapis.com/auth/cloud-platform"
    ].joined(separator: " ")

    private var clientID: String {
        if let env = ProcessInfo.processInfo.environment["GOOGLE_CLIENT_ID"], !env.isEmpty {
            return env
        }
        if let info = Bundle.main.infoDictionary?["GOOGLE_CLIENT_ID"] as? String, !info.isEmpty {
            return info
        }
        // Public desktop OAuth client ID for developer tools & Google Cloud SDK
        return "764086051850-6qr4p6gpi6hn506pt8ejuq83di341hur.apps.googleusercontent.com"
    }

    private var clientSecret: String? {
        if let env = ProcessInfo.processInfo.environment["GOOGLE_CLIENT_SECRET"], !env.isEmpty {
            return env
        }
        if let info = Bundle.main.infoDictionary?["GOOGLE_CLIENT_SECRET"] as? String, !info.isEmpty {
            return info
        }
        return "d-FL95Q19q7MQmFpd7hHD0Ty"
    }

    // MARK: - Initialization

    private override init() {
        super.init()
        restoreSessionFromKeychain()
    }

    // MARK: - Session Restoration

    public func restoreSessionFromKeychain() {
        let isExplicitlySignedOut = UserDefaults.standard.bool(forKey: Self.explicitlySignedOutKey)

        if let email = KeychainService.shared.get(forKey: Self.userEmailKey), !email.isEmpty {
            self.userEmail = email
            self.isAuthenticated = true
        } else if let token = KeychainService.shared.get(forKey: Self.accessTokenKey), !token.isEmpty {
            self.isAuthenticated = true
            Task {
                if let email = try? await self.fetchUserEmail(accessToken: token) {
                    KeychainService.shared.set(email, forKey: Self.userEmailKey)
                    self.userEmail = email
                }
            }
        } else if !isExplicitlySignedOut, let adcEmail = ambientADCEmail() {
            self.userEmail = adcEmail
            self.isAuthenticated = true
        }
    }

    // MARK: - Sign In (PKCE RFC 7636)

    public func signIn() {
        guard !isAuthenticating else { return }

        authError = nil
        isAuthenticating = true
        UserDefaults.standard.set(false, forKey: Self.explicitlySignedOutKey)

        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(for: verifier)
        let state = UUID().uuidString

        self.pendingCodeVerifier = verifier
        self.pendingState = state

        guard let authURL = buildAuthorizationURL(challenge: challenge, state: state) else {
            isAuthenticating = false
            authError = "Failed to construct Google OAuth authorization URL."
            return
        }

        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: callbackScheme) { [weak self] callbackURL, error in
            Task { @MainActor in
                guard let self = self else { return }
                self.isAuthenticating = false

                if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    logger.info("User cancelled Google sign in session.")
                    return
                }

                if let error = error {
                    self.authError = error.localizedDescription
                    logger.error("Google sign in session failed: \(error.localizedDescription)")
                    return
                }

                guard let callbackURL = callbackURL else {
                    self.authError = "Missing callback URL from Google authentication."
                    return
                }

                await self.handleCallbackURL(callbackURL, verifier: verifier, state: state)
            }
        }

        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        self.authSession = session

        if !session.start() {
            isAuthenticating = false
            authError = "Failed to start web authentication session."
        }
    }

    // MARK: - Sign Out

    public func signOut() {
        KeychainService.shared.delete(forKey: Self.accessTokenKey)
        KeychainService.shared.delete(forKey: Self.refreshTokenKey)
        KeychainService.shared.delete(forKey: Self.userEmailKey)
        KeychainService.shared.delete(forKey: Self.expiresAtKey)

        UserDefaults.standard.set(true, forKey: Self.explicitlySignedOutKey)

        self.isAuthenticated = false
        self.userEmail = nil
        self.isAuthenticating = false
        self.authError = nil
        self.pendingCodeVerifier = nil
        self.pendingState = nil

        logger.info("Signed out from Google Account.")
    }

    // MARK: - Access Token Accessors

    /// Returns a valid access token asynchronously, refreshing if necessary or falling back to ambient ADC.
    public func getValidAccessToken() async throws -> String? {
        // 1. Check stored OAuth access token in Keychain
        if let token = KeychainService.shared.get(forKey: Self.accessTokenKey) {
            let expiresAtStr = KeychainService.shared.get(forKey: Self.expiresAtKey)
            let expiresAt = Double(expiresAtStr ?? "0") ?? 0
            let now = Date().timeIntervalSince1970

            // If token is valid for at least 60 seconds, use it
            if expiresAt > (now + 60) {
                return token
            }

            // If expired, attempt token refresh via refresh token
            if let refreshToken = KeychainService.shared.get(forKey: Self.refreshTokenKey) {
                do {
                    let refreshedToken = try await refreshAccessToken(refreshToken: refreshToken)
                    return refreshedToken
                } catch {
                    logger.warning("OAuth token refresh failed: \(error.localizedDescription). Trying ADC...")
                }
            }

            // Return cached token as fallback if available
            return token
        }

        // 2. Fall back to ambient Application Default Credentials
        if let adcToken = checkAmbientADC() {
            return adcToken
        }

        return nil
    }

    /// Synchronous accessor for access token, utilizing Keychain and ADC fallback.
    public func getValidAccessToken() -> String? {
        if let token = KeychainService.shared.get(forKey: Self.accessTokenKey) {
            let expiresAtStr = KeychainService.shared.get(forKey: Self.expiresAtKey)
            let expiresAt = Double(expiresAtStr ?? "0") ?? 0
            let now = Date().timeIntervalSince1970

            if expiresAt > (now + 60) {
                return token
            }

            if let refreshToken = KeychainService.shared.get(forKey: Self.refreshTokenKey),
               let refreshed = refreshAccessTokenSync(refreshToken: refreshToken, clientID: clientID, clientSecret: clientSecret) {
                return refreshed
            }
            return token
        }

        if let adcToken = checkAmbientADC() {
            return adcToken
        }

        return nil
    }

    // MARK: - Callback & Exchange

    private func handleCallbackURL(_ url: URL, verifier: String, state: String) async {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            self.authError = "Invalid callback URL structure."
            return
        }

        let queryItems = components.queryItems ?? []

        if let errorParam = queryItems.first(where: { $0.name == "error" })?.value {
            self.authError = "Google authentication error: \(errorParam)"
            return
        }

        guard let returnedState = queryItems.first(where: { $0.name == "state" })?.value,
              returnedState == state else {
            self.authError = "Security verification failed: OAuth state mismatch."
            return
        }

        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            self.authError = "No authorization code returned from Google."
            return
        }

        do {
            self.isAuthenticating = true
            let tokens = try await exchangeCodeForTokens(code: code, verifier: verifier)

            // Store tokens in Keychain
            KeychainService.shared.set(tokens.accessToken, forKey: Self.accessTokenKey)
            if let refreshToken = tokens.refreshToken {
                KeychainService.shared.set(refreshToken, forKey: Self.refreshTokenKey)
            }
            let expiresAt = Date().addingTimeInterval(TimeInterval(tokens.expiresIn ?? 3600)).timeIntervalSince1970
            KeychainService.shared.set(String(expiresAt), forKey: Self.expiresAtKey)

            // Fetch user email
            let email = try await fetchUserEmail(accessToken: tokens.accessToken)
            if let email = email {
                KeychainService.shared.set(email, forKey: Self.userEmailKey)
                self.userEmail = email
            }

            self.isAuthenticated = true
            self.isAuthenticating = false
            self.authError = nil
            self.pendingCodeVerifier = nil
            self.pendingState = nil

            logger.info("Successfully authenticated with Google account: \(self.userEmail ?? "unknown")")
        } catch {
            self.isAuthenticating = false
            self.authError = error.localizedDescription
            logger.error("Token exchange failed: \(error.localizedDescription)")
        }
    }

    private func exchangeCodeForTokens(code: String, verifier: String) async throws -> GoogleOAuthTokens {
        guard let tokenURL = URL(string: "https://oauth2.googleapis.com/token") else {
            throw NSError(domain: "GoogleAccountAuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid token endpoint URL."])
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var params = [
            "client_id=\(clientID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clientID)",
            "code=\(code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? code)",
            "code_verifier=\(verifier.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? verifier)",
            "grant_type=authorization_code",
            "redirect_uri=\(redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? redirectURI)"
        ]
        if let secret = clientSecret, !secret.isEmpty {
            params.append("client_secret=\(secret.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? secret)")
        }
        request.httpBody = params.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "GoogleAccountAuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid server response."])
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorJson = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let desc = (errorJson["error_description"] as? String) ?? (errorJson["error"] as? String) {
                throw NSError(domain: "GoogleAccountAuthService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: desc])
            }
            throw NSError(domain: "GoogleAccountAuthService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Token exchange returned HTTP status \(httpResponse.statusCode)."])
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GoogleOAuthTokens.self, from: data)
    }

    private func refreshAccessToken(refreshToken: String) async throws -> String {
        guard let tokenURL = URL(string: "https://oauth2.googleapis.com/token") else {
            throw NSError(domain: "GoogleAccountAuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid token endpoint URL."])
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var params = [
            "client_id=\(clientID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clientID)",
            "refresh_token=\(refreshToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? refreshToken)",
            "grant_type=refresh_token"
        ]
        if let secret = clientSecret, !secret.isEmpty {
            params.append("client_secret=\(secret.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? secret)")
        }
        request.httpBody = params.joined(separator: "&").data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "GoogleAccountAuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to refresh Google access token."])
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccessToken = json["access_token"] as? String else {
            throw NSError(domain: "GoogleAccountAuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid refresh token response."])
        }

        let expiresIn = (json["expires_in"] as? Double) ?? 3600
        let expiresAt = Date().addingTimeInterval(expiresIn).timeIntervalSince1970

        KeychainService.shared.set(newAccessToken, forKey: Self.accessTokenKey)
        KeychainService.shared.set(String(expiresAt), forKey: Self.expiresAtKey)
        if let newRefreshToken = json["refresh_token"] as? String {
            KeychainService.shared.set(newRefreshToken, forKey: Self.refreshTokenKey)
        }

        return newAccessToken
    }

    private func refreshAccessTokenSync(refreshToken: String, clientID: String, clientSecret: String?) -> String? {
        guard let tokenURL = URL(string: "https://oauth2.googleapis.com/token") else { return nil }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        var bodyParams = [
            "client_id=\(clientID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clientID)",
            "refresh_token=\(refreshToken.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? refreshToken)",
            "grant_type=refresh_token"
        ]
        if let secret = clientSecret, !secret.isEmpty {
            bodyParams.append("client_secret=\(secret.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? secret)")
        }
        request.httpBody = bodyParams.joined(separator: "&").data(using: .utf8)

        let semaphore = DispatchSemaphore(value: 0)
        var resultToken: String? = nil

        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            defer { semaphore.signal() }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let newAccessToken = json["access_token"] as? String else {
                return
            }
            let expiresIn = (json["expires_in"] as? Double) ?? 3600
            let expiresAt = Date().addingTimeInterval(expiresIn).timeIntervalSince1970

            KeychainService.shared.set(newAccessToken, forKey: Self.accessTokenKey)
            KeychainService.shared.set(String(expiresAt), forKey: Self.expiresAtKey)
            if let newRefreshToken = json["refresh_token"] as? String {
                KeychainService.shared.set(newRefreshToken, forKey: Self.refreshTokenKey)
            }
            resultToken = newAccessToken
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 8.0)
        return resultToken
    }

    private func fetchUserEmail(accessToken: String) async throws -> String? {
        guard let userinfoURL = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo") else {
            return nil
        }
        var request = URLRequest(url: userinfoURL)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            return nil
        }

        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let email = json["email"] as? String {
            return email
        }
        return nil
    }

    // MARK: - PKCE Helpers (RFC 7636)

    private func generateCodeVerifier() -> String {
        var buffer = [UInt8](repeating: 0, count: 64)
        _ = SecRandomCopyBytes(kSecRandomDefault, buffer.count, &buffer)
        return base64UrlEncode(Data(buffer))
    }

    private func generateCodeChallenge(for verifier: String) -> String {
        guard let asciiData = verifier.data(using: .ascii) else { return "" }
        let digest = SHA256.hash(data: asciiData)
        return base64UrlEncode(Data(digest))
    }

    private func base64UrlEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func buildAuthorizationURL(challenge: String, state: String) -> URL? {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        return components?.url
    }

    // MARK: - Ambient Application Default Credentials (ADC)

    public func checkAmbientADC() -> String? {
        // 1. GOOGLE_APPLICATION_CREDENTIALS environment variable
        if let credsPath = ProcessInfo.processInfo.environment["GOOGLE_APPLICATION_CREDENTIALS"],
           FileManager.default.fileExists(atPath: credsPath) {
            if let token = resolveTokenFromADCFile(at: credsPath) {
                return token
            }
        }

        // 2. Standard location: ~/.config/gcloud/application_default_credentials.json
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let defaultADCPath = "\(homeDir)/.config/gcloud/application_default_credentials.json"
        if FileManager.default.fileExists(atPath: defaultADCPath) {
            if let token = resolveTokenFromADCFile(at: defaultADCPath) {
                return token
            }
        }

        // 3. gcloud CLI fallback
        if let gcloudToken = resolveTokenFromGCloudCLI() {
            return gcloudToken
        }

        return nil
    }

    private func resolveTokenFromADCFile(at path: String) -> String? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let clientID = json["client_id"] as? String,
           let refreshToken = json["refresh_token"] as? String {
            let secret = json["client_secret"] as? String
            return refreshAccessTokenSync(refreshToken: refreshToken, clientID: clientID, clientSecret: secret)
        }

        if let accessToken = json["access_token"] as? String, !accessToken.isEmpty {
            return accessToken
        }

        return nil
    }

    private func resolveTokenFromGCloudCLI() -> String? {
        let possiblePaths = [
            "/opt/homebrew/bin/gcloud",
            "/usr/local/bin/gcloud",
            "/usr/bin/gcloud",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("google-cloud-sdk/bin/gcloud").path
        ]

        for gcloudPath in possiblePaths {
            guard FileManager.default.fileExists(atPath: gcloudPath) else { continue }

            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: gcloudPath)
            process.arguments = ["auth", "print-access-token"]
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       output.hasPrefix("ya29.") {
                        return output
                    }
                }
            } catch {
                continue
            }
        }
        return nil
    }

    public func ambientADCEmail() -> String? {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let defaultADCPath = "\(homeDir)/.config/gcloud/application_default_credentials.json"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: defaultADCPath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let clientEmail = json["client_email"] as? String {
                return clientEmail
            }
        }

        let activeConfigPath = "\(homeDir)/.config/gcloud/configurations/config_default"
        if let content = try? String(contentsOfFile: activeConfigPath, encoding: .utf8) {
            for line in content.components(separatedBy: .newlines) {
                if line.starts(with: "account =") {
                    let parts = line.split(separator: "=")
                    if parts.count == 2 {
                        return parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Open URL Handler

    @discardableResult
    public func handleOpenURL(_ url: URL) -> Bool {
        guard url.scheme == callbackScheme,
              url.host == "oauth",
              url.path == "/google" || url.path == "google" else {
            return false
        }

        Task { @MainActor in
            if let verifier = self.pendingCodeVerifier, let state = self.pendingState {
                await self.handleCallbackURL(url, verifier: verifier, state: state)
            }
        }
        return true
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

#if canImport(AppKit)
extension GoogleAccountAuthService: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.mainWindow ?? NSApplication.shared.windows.first ?? ASPresentationAnchor()
    }
}
#endif
