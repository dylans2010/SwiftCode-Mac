//
//  GoogleAccountAuthService.swift
//  SwiftCode
//
//  Authentication service for Google Accounts using ASWebAuthenticationSession,
//  local loopback HTTP listener (RFC 8252 for Google OAuth Desktop Policy),
//  PKCE (RFC 7636), and fallback to ambient Application Default Credentials (ADC).
//

import Foundation
import AuthenticationServices
import CryptoKit
import Security
import Network
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

    // MARK: - OAuth Flow Session & Loopback
    private var authSession: ASWebAuthenticationSession?
    private var pendingCodeVerifier: String?
    private var pendingState: String?
    private var loopbackServer: OAuthLoopbackServer?
    private var activeRedirectURI: String = "http://127.0.0.1:8085"
    private var hasProcessedCallback: Bool = false

    // MARK: - OAuth Configuration
    private let callbackScheme = "swiftcode"
    private let scopes = [
        "email",
        "profile",
        "openid",
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

    // MARK: - Sign In (PKCE RFC 7636 + Loopback RFC 8252)

    public func signIn() {
        guard !isAuthenticating else { return }

        authError = nil
        isAuthenticating = true
        hasProcessedCallback = false
        UserDefaults.standard.set(false, forKey: Self.explicitlySignedOutKey)

        let verifier = generateCodeVerifier()
        let challenge = generateCodeChallenge(for: verifier)
        let state = UUID().uuidString

        self.pendingCodeVerifier = verifier
        self.pendingState = state

        // Start local loopback HTTP listener to comply with Google OAuth 2.0 policy for Desktop Apps
        let server = OAuthLoopbackServer()
        let port = server.start()
        self.loopbackServer = server

        let redirectURI = "http://127.0.0.1:\(port)"
        self.activeRedirectURI = redirectURI

        guard let authURL = buildAuthorizationURL(challenge: challenge, state: state, redirectURI: redirectURI) else {
            isAuthenticating = false
            loopbackServer?.stop()
            loopbackServer = nil
            authError = "Failed to construct Google OAuth authorization URL."
            return
        }

        server.onCallback = { [weak self] callbackURL in
            self?.processLoopbackCallback(url: callbackURL, verifier: verifier, state: state, redirectURI: redirectURI)
        }

        let session = ASWebAuthenticationSession(url: authURL, callbackURLScheme: "http") { [weak self] callbackURL, error in
            self?.processSessionCallback(callbackURL: callbackURL, error: error, verifier: verifier, state: state, redirectURI: redirectURI)
        }

        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        self.authSession = session

        if !session.start() {
            // Fallback: Open auth URL directly in system default browser if session fails to start
            NSWorkspace.shared.open(authURL)
        }
    }

    private nonisolated func processSessionCallback(callbackURL: URL?, error: (any Error)?, verifier: String, state: String, redirectURI: String) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }

            if let callbackURL = callbackURL {
                await self.handleCallbackURL(callbackURL, verifier: verifier, state: state, redirectURI: redirectURI)
                self.loopbackServer?.stop()
                self.loopbackServer = nil
                return
            }

            if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                logger.info("User cancelled Google sign in session.")
                self.isAuthenticating = false
                self.loopbackServer?.stop()
                self.loopbackServer = nil
                return
            }

            if let error = error {
                logger.warning("ASWebAuthenticationSession notification: \(error.localizedDescription)")
            }
        }
    }

    private nonisolated func processLoopbackCallback(url: URL, verifier: String, state: String, redirectURI: String) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            await self.handleCallbackURL(url, verifier: verifier, state: state, redirectURI: redirectURI)
            self.loopbackServer?.stop()
            self.loopbackServer = nil
            self.authSession?.cancel()
            self.authSession = nil
        }
    }

    // MARK: - Sign Out

    public func signOut() {
        KeychainService.shared.delete(forKey: Self.accessTokenKey)
        KeychainService.shared.delete(forKey: Self.refreshTokenKey)
        KeychainService.shared.delete(forKey: Self.userEmailKey)
        KeychainService.shared.delete(forKey: Self.expiresAtKey)

        UserDefaults.standard.set(true, forKey: Self.explicitlySignedOutKey)

        self.loopbackServer?.stop()
        self.loopbackServer = nil

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

    private func handleCallbackURL(_ url: URL, verifier: String, state: String, redirectURI: String) async {
        guard !hasProcessedCallback else { return }
        hasProcessedCallback = true

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            self.authError = "Invalid callback URL structure."
            self.isAuthenticating = false
            return
        }

        let queryItems = components.queryItems ?? []

        if let errorParam = queryItems.first(where: { $0.name == "error" })?.value {
            self.authError = "Google authentication error: \(errorParam)"
            self.isAuthenticating = false
            return
        }

        guard let returnedState = queryItems.first(where: { $0.name == "state" })?.value,
              returnedState == state else {
            self.authError = "Security verification failed: OAuth state mismatch."
            self.isAuthenticating = false
            return
        }

        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            self.authError = "No authorization code returned from Google."
            self.isAuthenticating = false
            return
        }

        do {
            let tokens = try await exchangeCodeForTokens(code: code, verifier: verifier, redirectURI: redirectURI)

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

            Task {
                try? await GoogleCloudSDKLifecycleManager.shared.restartEngine()
            }
        } catch {
            self.isAuthenticating = false
            self.authError = error.localizedDescription
            logger.error("Token exchange failed: \(error.localizedDescription)")
        }
    }

    private func exchangeCodeForTokens(code: String, verifier: String, redirectURI: String) async throws -> GoogleOAuthTokens {
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

    private func buildAuthorizationURL(challenge: String, state: String, redirectURI: String) -> URL? {
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
        if url.scheme == callbackScheme || url.scheme == "http" || url.host == "127.0.0.1" || url.host == "localhost" {
            Task { @MainActor in
                if let verifier = self.pendingCodeVerifier, let state = self.pendingState {
                    await self.handleCallbackURL(url, verifier: verifier, state: state, redirectURI: self.activeRedirectURI)
                    self.loopbackServer?.stop()
                    self.loopbackServer = nil
                }
            }
            return true
        }
        return false
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

#if canImport(AppKit)
extension GoogleAccountAuthService: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let window = NSApplication.shared.mainWindow ?? NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first(where: { $0.isVisible }) {
            return window
        }
        if let window = NSApplication.shared.windows.first {
            return window
        }
        return NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
    }
}
#endif

// MARK: - OAuth Loopback Server (RFC 8252 Compliance for Google OAuth Desktop Policy)

@MainActor
public final class OAuthLoopbackServer: @unchecked Sendable {
    private var listener: NWListener?
    public private(set) var port: UInt16 = 8085
    public var onCallback: ((URL) -> Void)?

    public init() {}

    public func start() -> UInt16 {
        for candidatePort in UInt16(8085)...UInt16(8099) {
            do {
                let params = NWParameters.tcp
                guard let nwPort = NWEndpoint.Port(rawValue: candidatePort) else { continue }
                let listener = try NWListener(using: params, on: nwPort)

                self.port = candidatePort
                self.listener = listener

                listener.newConnectionHandler = { [weak self] connection in
                    Task { @MainActor in
                        self?.handleConnection(connection)
                    }
                }

                listener.start(queue: .main)
                return candidatePort
            } catch {
                continue
            }
        }

        do {
            let params = NWParameters.tcp
            let listener = try NWListener(using: params, on: .any)
            self.listener = listener
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor in
                    self?.handleConnection(connection)
                }
            }
            listener.start(queue: .main)
            if let assignedPort = listener.port?.rawValue {
                self.port = assignedPort
                return assignedPort
            }
        } catch {
            logger.error("Failed to start OAuth loopback listener: \(error.localizedDescription)")
        }
        return 8085
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, _, _ in
            guard let self = self, let data = data, let requestString = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            let lines = requestString.components(separatedBy: "\r\n")
            if let firstLine = lines.first {
                let parts = firstLine.components(separatedBy: " ")
                if parts.count >= 2 {
                    let pathAndQuery = parts[1]
                    if let url = URL(string: "http://127.0.0.1:\(self.port)\(pathAndQuery)") {
                        Task { @MainActor in
                            self.onCallback?(url)
                        }
                    }
                }
            }

            let html = """
            <!DOCTYPE html>
            <html>
            <head>
                <meta charset="utf-8">
                <title>SwiftCode - Authentication Successful</title>
                <style>
                    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; display: flex; align-items: center; justify-content: center; height: 100vh; margin: 0; background-color: #0d1117; color: #c9d1d9; }
                    .card { text-align: center; padding: 40px; border-radius: 16px; background: #161b22; border: 1px solid #30363d; box-shadow: 0 8px 24px rgba(0,0,0,0.5); max-width: 400px; }
                    h2 { color: #58a6ff; margin-bottom: 12px; }
                    p { color: #8b949e; line-height: 1.5; }
                </style>
            </head>
            <body>
                <div class="card">
                    <h2>Authentication Successful</h2>
                    <p>You have successfully authenticated with Google.</p>
                    <p>You may close this tab and return to <strong>SwiftCode</strong>.</p>
                </div>
                <script>setTimeout(function() { window.close(); }, 2500);</script>
            </body>
            </html>
            """

            let httpResponse = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"

            if let responseData = httpResponse.data(using: .utf8) {
                connection.send(content: responseData, completion: .contentProcessed({ _ in
                    connection.cancel()
                }))
            } else {
                connection.cancel()
            }
        }
    }
}
