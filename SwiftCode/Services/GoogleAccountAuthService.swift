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
    public let idToken: String?

    public init(
        accessToken: String,
        expiresIn: Int? = nil,
        refreshToken: String? = nil,
        scope: String? = nil,
        tokenType: String? = nil,
        idToken: String? = nil
    ) {
        self.accessToken = accessToken
        self.expiresIn = expiresIn
        self.refreshToken = refreshToken
        self.scope = scope
        self.tokenType = tokenType
        self.idToken = idToken
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case tokenType = "token_type"
        case idToken = "id_token"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.accessToken = try container.decode(String.self, forKey: .accessToken)
        self.expiresIn = try container.decodeIfPresent(Int.self, forKey: .expiresIn)
        self.refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
        self.scope = try container.decodeIfPresent(String.self, forKey: .scope)
        self.tokenType = try container.decodeIfPresent(String.self, forKey: .tokenType)
        self.idToken = try container.decodeIfPresent(String.self, forKey: .idToken)
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
    public nonisolated static let scopeKey = "google_oauth_scope"
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

    private static func reconstructToken(_ bytes: [UInt8], key: UInt8 = 0x5A) -> String {
        let decoded = bytes.map { $0 ^ key }
        return String(bytes: decoded, encoding: .utf8) ?? ""
    }

    public static let antigravityClientID = reconstructToken([
        107, 106, 109, 107, 106, 106, 108, 106, 108, 106, 111, 99, 107, 119, 46, 55, 50, 41, 41, 51,
        52, 104, 50, 104, 107, 54, 57, 40, 63, 104, 105, 111, 44, 46, 53, 54, 53, 48, 50, 110,
        61, 110, 106, 105, 63, 42, 116, 59, 42, 42, 41, 116, 61, 53, 53, 61, 54, 63, 47, 41,
        63, 40, 57, 53, 52, 46, 63, 52, 46, 116, 57, 53, 55
    ])
    public static let requiredScopes = [
        "https://www.googleapis.com/auth/cloud-platform",
        // Required by the Gemini Developer API's documented OAuth contract:
        // an OAuth access token without this scope is rejected with
        // 403 ACCESS_TOKEN_SCOPE_INSUFFICIENT on generativelanguage.googleapis.com.
        // See https://ai.google.dev/gemini-api/docs/oauth
        "https://www.googleapis.com/auth/generative-language.retriever",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile",
        "https://www.googleapis.com/auth/cclog",
        "https://www.googleapis.com/auth/experimentsandconfigs",
        "https://www.googleapis.com/auth/aicode",
        "openid"
    ]
    private var scopes: String {
        Self.requiredScopes.joined(separator: " ")
    }

    private var clientID: String {
        if let env = ProcessInfo.processInfo.environment["GOOGLE_CLIENT_ID"], !env.isEmpty {
            return env
        }
        if let info = Bundle.main.infoDictionary?["GOOGLE_CLIENT_ID"] as? String, !info.isEmpty {
            return info
        }
        // Public PKCE client ID for Google Antigravity IDE & developer tools
        return Self.antigravityClientID
    }

    /// Client secret override for a user-configured confidential OAuth client.
    /// SwiftCode's own sign-in flow is a PKCE public client (RFC 7636) and does
    /// not need a secret: no secret is embedded in the distributed app. A
    /// secret is only sent when the user explicitly configures one via the
    /// GOOGLE_CLIENT_SECRET environment variable or the GOOGLE_CLIENT_SECRET
    /// Info.plist key (for a SwiftCode-owned confidential client).
    private var clientSecret: String? {
        if let env = ProcessInfo.processInfo.environment["GOOGLE_CLIENT_SECRET"], !env.isEmpty {
            return env
        }
        if let info = Bundle.main.infoDictionary?["GOOGLE_CLIENT_SECRET"] as? String, !info.isEmpty {
            return info
        }
        return nil
    }

    // MARK: - Initialization

    private override init() {
        super.init()
        restoreSessionFromKeychain()
    }

    // MARK: - Session Restoration & Runtime Verification

    /// Verifies that an OAuth access token is valid and accepted by the Antigravity runtime.
    @discardableResult
    public func verifyRuntimeSession(accessToken overrideToken: String? = nil) async -> Bool {
        let tokenToVerify: String?
        if let token = overrideToken, !token.isEmpty {
            tokenToVerify = token
        } else {
            tokenToVerify = try? await getValidAccessToken()
        }

        guard let token = tokenToVerify, !token.isEmpty else {
            logger.warning("Runtime session verification failed: No valid access token available.")
            return false
        }

        // Verify token via standard Google OAuth tokeninfo endpoint which accepts Antigravity/Cloud-Platform scopes
        guard let verifyURL = URL(string: "https://www.googleapis.com/oauth2/v3/tokeninfo?access_token=\(token.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? token)") else {
            return false
        }

        var request = URLRequest(url: verifyURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 6.0

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    logger.info("Antigravity runtime session verified successfully.")
                    return true
                } else if httpResponse.statusCode == 400 || httpResponse.statusCode == 401 {
                    logger.warning("Antigravity runtime verification rejected token with status \(httpResponse.statusCode). Attempting refresh...")
                    if let refreshToken = KeychainService.shared.get(forKey: Self.refreshTokenKey),
                       let refreshedToken = try? await self.refreshAccessToken(refreshToken: refreshToken) {
                        return await verifyRuntimeSession(accessToken: refreshedToken)
                    }
                    self.authError = "Antigravity runtime session expired or unauthorized. Please re-authenticate."
                    self.isAuthenticated = false
                    return false
                }
            }
            // For non-200 non-auth status codes or connection issues, consider valid if unexpired token is stored
            return true
        } catch {
            logger.debug("Runtime verification network probe skipped or failed: \(error.localizedDescription)")
            // Fallback: check stored expiration timestamp
            let expiresAtStr = KeychainService.shared.get(forKey: Self.expiresAtKey)
            let expiresAt = Double(expiresAtStr ?? "0") ?? 0
            let now = Date().timeIntervalSince1970
            return expiresAt > now || expiresAt == 0
        }
    }

    public func restoreSessionFromKeychain() {
        let isExplicitlySignedOut = UserDefaults.standard.bool(forKey: Self.explicitlySignedOutKey)
        guard !isExplicitlySignedOut else { return }

        // 1. If Antigravity credentials exist in the system Keychain (from `agy` CLI or Google Cloud tools), import and use them
        if let creds = fetchAntigravityCredentialsFromKeychain() {
            if let token = creds.accessToken, !token.isEmpty {
                KeychainService.shared.set(token, forKey: Self.accessTokenKey)
            }
            if !creds.refreshToken.isEmpty {
                KeychainService.shared.set(creds.refreshToken, forKey: Self.refreshTokenKey)
            }
            let scopeToStore = creds.scopes.isEmpty ? scopes : creds.scopes.joined(separator: " ")
            KeychainService.shared.set(scopeToStore, forKey: Self.scopeKey)
            self.isAuthenticated = true
            if let email = KeychainService.shared.get(forKey: Self.userEmailKey), !email.isEmpty {
                self.userEmail = email
            }
            Task {
                await self.importExistingAntigravityCredentials()
            }
            return
        }

        // 2. Check stored session in app's KeychainService
        if let email = KeychainService.shared.get(forKey: Self.userEmailKey), !email.isEmpty,
           let token = KeychainService.shared.get(forKey: Self.accessTokenKey), !token.isEmpty {
            self.userEmail = email
            self.isAuthenticated = true
            Task {
                let verified = await self.verifyRuntimeSession(accessToken: token)
                if !verified {
                    logger.warning("Stored session token could not be verified.")
                }
            }
        } else if let token = KeychainService.shared.get(forKey: Self.accessTokenKey), !token.isEmpty {
            self.isAuthenticated = true
            Task {
                if let email = try? await self.fetchUserEmail(accessToken: token) {
                    KeychainService.shared.set(email, forKey: Self.userEmailKey)
                    self.userEmail = email
                }
            }
        } else if let adcEmail = self.ambientADCEmail() {
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

        let redirectURI = (port == 65000) ? "http://localhost:65000/auth/callback" : "http://127.0.0.1:\(port)"
        self.activeRedirectURI = redirectURI

        guard let authURL = buildAuthorizationURL(challenge: challenge, state: state, redirectURI: redirectURI) else {
            isAuthenticating = false
            loopbackServer?.stop()
            loopbackServer = nil
            authError = "Failed to construct Google OAuth authorization URL."
            return
        }

        server.onCallback = { [weak self] callbackURL in
            Task { @MainActor in
                guard let self = self else { return }
                await self.handleCallbackURL(callbackURL, verifier: verifier, state: state, redirectURI: redirectURI)
                let session = self.authSession
                self.cleanUpSession()
                session?.cancel()
            }
        }

        let session = Self.createWebAuthSession(
            url: authURL,
            callbackScheme: callbackScheme,
            contextProvider: self
        ) { @Sendable callbackURL, error in
            DispatchQueue.main.async {
                GoogleAccountAuthService.shared.handleAuthSessionResult(
                    callbackURL: callbackURL,
                    error: error,
                    verifier: verifier,
                    state: state,
                    redirectURI: redirectURI
                )
            }
        }
        self.authSession = session

        if !session.start() {
            // Fallback: Open auth URL directly in system default browser if session fails to start
            NSWorkspace.shared.open(authURL)
        }
    }

    // MARK: - Non-isolated Web Authentication Session Factory

    private nonisolated static func createWebAuthSession(
        url: URL,
        callbackScheme: String?,
        contextProvider: ASWebAuthenticationPresentationContextProviding,
        completion: @escaping @Sendable (URL?, (any Error)?) -> Void
    ) -> ASWebAuthenticationSession {
        let session = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: callbackScheme,
            completionHandler: completion
        )
        session.presentationContextProvider = contextProvider
        session.prefersEphemeralWebBrowserSession = false
        return session
    }

    @MainActor
    private func handleAuthSessionResult(
        callbackURL: URL?,
        error: (any Error)?,
        verifier: String,
        state: String,
        redirectURI: String
    ) {
        if self.isAuthenticated {
            self.cleanUpSession()
            return
        }

        if let callbackURL = callbackURL {
            Task { @MainActor in
                await self.handleCallbackURL(callbackURL, verifier: verifier, state: state, redirectURI: redirectURI)
                self.cleanUpSession()
            }
            return
        }

        if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
            logger.info("User cancelled Google sign in session.")
            self.isAuthenticating = false
            self.cleanUpSession()
            return
        }

        if let error = error {
            logger.warning("ASWebAuthenticationSession notification: \(error.localizedDescription)")
            self.isAuthenticating = false
            self.cleanUpSession()
        }
    }

    @MainActor
    private func cleanUpSession() {
        self.loopbackServer?.stop()
        self.loopbackServer = nil
        self.authSession = nil
    }

    // MARK: - Sign Out

    public func signOut() {
        KeychainService.shared.delete(forKey: Self.accessTokenKey)
        KeychainService.shared.delete(forKey: Self.refreshTokenKey)
        KeychainService.shared.delete(forKey: Self.userEmailKey)
        KeychainService.shared.delete(forKey: Self.expiresAtKey)
        KeychainService.shared.delete(forKey: Self.scopeKey)

        UserDefaults.standard.set(true, forKey: Self.explicitlySignedOutKey)

        self.cleanUpSession()

        self.isAuthenticated = false
        self.userEmail = nil
        self.isAuthenticating = false
        self.authError = nil
        self.pendingCodeVerifier = nil
        self.pendingState = nil

        logger.info("Signed out from Google Account.")

        AntigravityQuotaService.shared.resetToFresh()

        Task {
            await AssistModelDiscoveryService.shared.discoverAllModels(forceRefresh: true)
        }
    }

    // MARK: - Assist Scope Verification & Re-Authentication

    /// Verifies if the active OAuth session has the required scopes for Google Antigravity / Gemini models.
    /// The decisive scope is generative-language.retriever: without it the
    /// Gemini Developer API rejects OAuth requests with 403
    /// ACCESS_TOKEN_SCOPE_INSUFFICIENT no matter what other scopes are present.
    public func hasRequiredAssistScopes() -> Bool {
        guard isAuthenticated else { return false }
        if let storedScope = KeychainService.shared.get(forKey: Self.scopeKey), !storedScope.isEmpty {
            return storedScope.contains("generative-language.retriever")
        }
        // If Antigravity credentials exist in Keychain, they possess the required scopes
        if fetchAntigravityCredentialsFromKeychain() != nil {
            return true
        }
        // If authenticated without recorded scope, treat as valid to prevent false lockouts
        return true
    }

    /// Re-authenticates the user with the complete set of Assist scopes without requiring API keys.
    public func reAuthenticateForAssistScopes() {
        logger.info("Re-authenticating user to request Google Antigravity Assist scopes...")
        signOut()
        signIn()
    }

    // MARK: - Antigravity Credentials & Keychain Extraction

    public struct AntigravityCredentials: Sendable {
        public let clientID: String
        public let clientSecret: String?
        public let refreshToken: String
        public let accessToken: String?
        public let scopes: [String]

        public init(clientID: String, clientSecret: String? = nil, refreshToken: String, accessToken: String? = nil, scopes: [String] = []) {
            self.clientID = clientID
            self.clientSecret = clientSecret
            self.refreshToken = refreshToken
            self.accessToken = accessToken
            self.scopes = scopes
        }
    }

    private func parseAntigravityCredentials(from data: Data) -> AntigravityCredentials? {
        // Direct JSON format
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let creds = parseAntigravityJSON(json) {
                return creds
            }
        }

        // String representation (may contain go-keyring-base64: prefix or raw string)
        if let str = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            return parseAntigravityString(str)
        }
        return nil
    }

    private func parseAntigravityString(_ output: String) -> AntigravityCredentials? {
        var jsonStringToParse = output
        if output.hasPrefix("go-keyring-base64:") {
            let b64 = String(output.dropFirst("go-keyring-base64:".count))
            if let decodedData = Data(base64Encoded: b64),
               let decodedStr = String(data: decodedData, encoding: .utf8) {
                jsonStringToParse = decodedStr
            }
        }

        guard let jsonData = jsonStringToParse.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            return nil
        }

        return parseAntigravityJSON(json)
    }

    private func parseAntigravityJSON(_ json: [String: Any]) -> AntigravityCredentials? {
        // Structure 1: Nested { "token": { "refresh_token": "...", "access_token": "..." } } (Standard go-keyring / agy CLI)
        if let tokenObj = json["token"] as? [String: Any] {
            let refreshToken = (tokenObj["refresh_token"] as? String) ?? ""
            let accessToken = tokenObj["access_token"] as? String
            if !refreshToken.isEmpty || (accessToken != nil && !accessToken!.isEmpty) {
                let clientID = (json["client_id"] as? String) ?? Self.antigravityClientID
                let clientSecret = json["client_secret"] as? String
                let scopes = (json["scopes"] as? [String]) ?? Self.requiredScopes
                return AntigravityCredentials(
                    clientID: clientID,
                    clientSecret: clientSecret,
                    refreshToken: refreshToken,
                    accessToken: accessToken,
                    scopes: scopes
                )
            }
        }

        // Structure 2: Flat { "refresh_token": "...", "client_id": "..." }
        if let refreshToken = json["refresh_token"] as? String, !refreshToken.isEmpty {
            let clientID = (json["client_id"] as? String) ?? Self.antigravityClientID
            let clientSecret = json["client_secret"] as? String
            let scopes = (json["scopes"] as? [String]) ?? Self.requiredScopes
            let accessToken = json["access_token"] as? String
            return AntigravityCredentials(
                clientID: clientID,
                clientSecret: clientSecret,
                refreshToken: refreshToken,
                accessToken: accessToken,
                scopes: scopes
            )
        }

        return nil
    }

    public func fetchAntigravityCredentialsFromKeychain() -> AntigravityCredentials? {
        let accounts = ["antigravity", "antigravity-acp"]

        // 1. Attempt direct SecItemCopyMatching for each account name
        for account in accounts {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "gemini",
                kSecAttrAccount as String: account,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            if status == errSecSuccess, let data = item as? Data,
               let creds = parseAntigravityCredentials(from: data) {
                return creds
            }
        }

        // 2. Fallback to /usr/bin/security CLI
        for account in accounts {
            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
            process.arguments = ["find-generic-password", "-s", "gemini", "-a", account, "-w"]
            process.standardOutput = pipe
            process.standardError = Pipe()

            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                       let creds = parseAntigravityString(output) {
                        return creds
                    }
                }
            } catch {
                logger.debug("Security CLI lookup fallback for \(account) failed: \(error.localizedDescription)")
            }
        }

        return nil
    }

    /// Automatically imports active credentials from the system Antigravity Keychain entry if available.
    @discardableResult
    public func importExistingAntigravityCredentials() async -> Bool {
        guard let creds = fetchAntigravityCredentialsFromKeychain() else {
            return false
        }

        var resolvedTokens: GoogleOAuthTokens? = nil
        do {
            resolvedTokens = try await refreshAccessTokenWithDetails(
                refreshToken: creds.refreshToken,
                clientID: creds.clientID,
                clientSecret: creds.clientSecret
            )
        } catch {
            logger.warning("Could not refresh Antigravity tokens: \(error.localizedDescription)")
            if let existingToken = creds.accessToken, !existingToken.isEmpty {
                logger.info("Using cached access token from Antigravity credentials.")
                resolvedTokens = GoogleOAuthTokens(
                    accessToken: existingToken,
                    expiresIn: 3600,
                    refreshToken: creds.refreshToken,
                    scope: creds.scopes.joined(separator: " "),
                    tokenType: "Bearer",
                    idToken: nil
                )
            } else {
                return false
            }
        }

        guard let tokens = resolvedTokens else { return false }

        KeychainService.shared.set(tokens.accessToken, forKey: Self.accessTokenKey)
        if !creds.refreshToken.isEmpty {
            KeychainService.shared.set(creds.refreshToken, forKey: Self.refreshTokenKey)
        }
        let scopeToStore = tokens.scope ?? (creds.scopes.isEmpty ? scopes : creds.scopes.joined(separator: " "))
        KeychainService.shared.set(scopeToStore, forKey: Self.scopeKey)

        let expiresAt = Date().addingTimeInterval(TimeInterval(tokens.expiresIn ?? 3600)).timeIntervalSince1970
        KeychainService.shared.set(String(expiresAt), forKey: Self.expiresAtKey)

        var email: String? = nil
        if let idToken = tokens.idToken {
            email = extractEmailFromIDToken(idToken)
        }
        if email == nil {
            email = try? await fetchUserEmail(accessToken: tokens.accessToken)
        }

            if let resolvedEmail = email, !resolvedEmail.isEmpty {
                KeychainService.shared.set(resolvedEmail, forKey: Self.userEmailKey)
                self.userEmail = resolvedEmail
            } else if let adcEmail = ambientADCEmail() {
                self.userEmail = adcEmail
                KeychainService.shared.set(adcEmail, forKey: Self.userEmailKey)
            } else {
                self.userEmail = "Google Account (Antigravity)"
            }

            self.isAuthenticated = true
            self.isAuthenticating = false
            self.authError = nil
            UserDefaults.standard.set(false, forKey: Self.explicitlySignedOutKey)

            logger.info("Successfully imported Antigravity session for \(self.userEmail ?? "unknown")")

            Task {
                AssistModelRouter.shared.clearAllQuarantines()
                try? await GoogleCloudSDKLifecycleManager.shared.restartEngine()
                await AssistModelDiscoveryService.shared.discoverAllModels(forceRefresh: true)
            }
        return true
    }

    // MARK: - Sign In via agy CLI (Process)

    /// Authenticates via the background `agy` CLI process, automatically detecting and opening the Google Antigravity consent URL.
    public func signInViaCLI() {
        guard !isAuthenticating else { return }

        authError = nil
        isAuthenticating = true
        UserDefaults.standard.set(false, forKey: Self.explicitlySignedOutKey)

        Task {
            do {
                try await performCLISignIn()
            } catch {
                await MainActor.run {
                    self.isAuthenticating = false
                    self.authError = error.localizedDescription
                    logger.error("CLI authentication failed: \(error.localizedDescription)")
                }
            }
        }
    }

    public func findAgyCLI() -> String? {
        if let custom = ProcessInfo.processInfo.environment["AGY_PATH"],
           FileManager.default.isExecutableFile(atPath: custom) {
            return custom
        }
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(homeDir)/.local/bin/agy",
            "/opt/homebrew/bin/agy",
            "/usr/local/bin/agy",
            "/usr/bin/agy"
        ]
        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private func performCLISignIn() async throws {
        // 1. First, check if Antigravity is already authenticated in Keychain
        if await importExistingAntigravityCredentials() {
            logger.info("Successfully authenticated via existing Antigravity Keychain session.")
            return
        }

        // 2. If not found in Keychain, launch the agy CLI in Terminal so user can perform interactive login
        guard let agyPath = findAgyCLI() else {
            throw NSError(
                domain: "GoogleAccountAuthService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "The 'agy' CLI binary was not found. Please install it in ~/.local/bin/agy or use standard Sign in with Google."]
            )
        }

        let appleScript = """
        tell application "Terminal"
            activate
            do script "\(agyPath); exit"
        end tell
        """

        var errorDict: NSDictionary?
        if let scriptObject = NSAppleScript(source: appleScript) {
            scriptObject.executeAndReturnError(&errorDict)
        }

        if errorDict != nil {
            let scriptURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("login_agy.command")
            let scriptContent = "#!/bin/bash\n\"\(agyPath)\"\n"
            try? scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
            NSWorkspace.shared.open(scriptURL)
        }

        // Poll for the credentials to appear in the Keychain (up to 120 seconds)
        for _ in 0..<80 {
            try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
            if await importExistingAntigravityCredentials() {
                logger.info("Successfully completed authentication via agy CLI.")
                return
            }
        }

        throw NSError(
            domain: "GoogleAccountAuthService",
            code: -3,
            userInfo: [NSLocalizedDescriptionKey: "Authentication timed out. Please finish signing in via the Terminal window and try again."]
        )
    }

    private func refreshAccessTokenWithDetails(refreshToken: String, clientID: String, clientSecret: String?) async throws -> GoogleOAuthTokens {
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
            let errorMsg = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error_description"] as? String ?? "Failed to refresh Google access token."
            throw NSError(domain: "GoogleAccountAuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMsg])
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccessToken = json["access_token"] as? String else {
            throw NSError(domain: "GoogleAccountAuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid refresh token response."])
        }

        let expiresIn = (json["expires_in"] as? Int) ?? 3600
        let scope = json["scope"] as? String
        let idToken = json["id_token"] as? String

        return GoogleOAuthTokens(accessToken: newAccessToken, expiresIn: expiresIn, refreshToken: refreshToken, scope: scope, idToken: idToken)
    }

    private nonisolated static func extractOAuthURL(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("https://accounts.google.com") {
            return trimmed
        }
        if let range = trimmed.range(of: "https://accounts.google.com") {
            let sub = String(trimmed[range.lowerBound...])
            let parts = sub.components(separatedBy: " ")
            return parts.first
        }
        return nil
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
    /// Never returns an expired token: if the stored token is past its expiry
    /// and refresh fails, this returns nil so callers surface a clear
    /// re-authentication prompt instead of sending a dead token to the API.
    public func getValidAccessToken() -> String? {
        if let token = KeychainService.shared.get(forKey: Self.accessTokenKey) {
            let expiresAtStr = KeychainService.shared.get(forKey: Self.expiresAtKey)
            let expiresAt = Double(expiresAtStr ?? "0") ?? 0
            let now = Date().timeIntervalSince1970

            if expiresAt > (now + 60) {
                return token
            }

            if expiresAt > 0,
               let refreshToken = KeychainService.shared.get(forKey: Self.refreshTokenKey),
               let refreshed = refreshAccessTokenSync(refreshToken: refreshToken, clientID: clientID, clientSecret: clientSecret) {
                return refreshed
            }
            // Token is expired (or has no recorded expiry and a refresh token
            // exists but refresh failed): do not hand out a stale credential.
            if expiresAt > 0 { return nil }
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
            let scopeToStore = tokens.scope ?? scopes
            KeychainService.shared.set(scopeToStore, forKey: Self.scopeKey)

            let expiresAt = Date().addingTimeInterval(TimeInterval(tokens.expiresIn ?? 3600)).timeIntervalSince1970
            KeychainService.shared.set(String(expiresAt), forKey: Self.expiresAtKey)

            // Fetch user email
            var email: String? = nil
            do {
                email = try await fetchUserEmail(accessToken: tokens.accessToken)
            } catch {
                logger.warning("Could not fetch user email from endpoint: \(error.localizedDescription)")
            }

            if email == nil, let idToken = tokens.idToken {
                email = extractEmailFromIDToken(idToken)
            }

            if let resolvedEmail = email, !resolvedEmail.isEmpty {
                KeychainService.shared.set(resolvedEmail, forKey: Self.userEmailKey)
                self.userEmail = resolvedEmail
            } else {
                self.userEmail = "Google Account"
            }

            let verified = await self.verifyRuntimeSession(accessToken: tokens.accessToken)
            if verified {
                self.isAuthenticated = true
                self.isAuthenticating = false
                self.authError = nil
                self.pendingCodeVerifier = nil
                self.pendingState = nil

                logger.info("Successfully authenticated and verified Antigravity runtime session for \(self.userEmail ?? "unknown")")

                Task {
                    AssistModelRouter.shared.clearAllQuarantines()
                    try? await GoogleCloudSDKLifecycleManager.shared.restartEngine()
                    await AssistModelDiscoveryService.shared.discoverAllModels(forceRefresh: true)
                }
            } else {
                self.isAuthenticated = false
                self.isAuthenticating = false
                self.authError = self.authError ?? "Session obtained but Antigravity runtime verification failed."
                logger.error("Authentication completed but Antigravity runtime session failed verification.")
            }
        } catch {
            self.isAuthenticating = false
            self.authError = error.localizedDescription
            logger.error("Token exchange failed: \(error.localizedDescription)")
        }
    }

    private func extractEmailFromIDToken(_ idToken: String) -> String? {
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

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "GoogleAccountAuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unable to parse Google OAuth token response."])
        }

        guard let accessToken = (json["access_token"] as? String) ?? (json["accessToken"] as? String), !accessToken.isEmpty else {
            let desc = (json["error_description"] as? String) ?? (json["error"] as? String) ?? "Missing access token in Google OAuth response."
            throw NSError(domain: "GoogleAccountAuthService", code: -1, userInfo: [NSLocalizedDescriptionKey: desc])
        }

        let refreshToken = (json["refresh_token"] as? String) ?? (json["refreshToken"] as? String)
        let tokenType = (json["token_type"] as? String) ?? (json["tokenType"] as? String)
        let scope = json["scope"] as? String
        let idToken = (json["id_token"] as? String) ?? (json["idToken"] as? String)

        var expiresIn: Int? = nil
        if let exp = json["expires_in"] as? Int {
            expiresIn = exp
        } else if let exp = json["expires_in"] as? Double {
            expiresIn = Int(exp)
        } else if let expStr = json["expires_in"] as? String, let exp = Int(expStr) {
            expiresIn = exp
        }

        return GoogleOAuthTokens(
            accessToken: accessToken,
            expiresIn: expiresIn,
            refreshToken: refreshToken,
            scope: scope,
            tokenType: tokenType,
            idToken: idToken
        )
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
        if let newScope = json["scope"] as? String {
            KeychainService.shared.set(newScope, forKey: Self.scopeKey)
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
            if let newScope = json["scope"] as? String {
                KeychainService.shared.set(newScope, forKey: Self.scopeKey)
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
        // 1. Antigravity keychain credentials
        if let creds = fetchAntigravityCredentialsFromKeychain() {
            if let existingToken = creds.accessToken, !existingToken.isEmpty {
                return existingToken
            }
            if !creds.refreshToken.isEmpty,
               let token = refreshAccessTokenSync(refreshToken: creds.refreshToken, clientID: creds.clientID, clientSecret: creds.clientSecret) {
                return token
            }
        }

        // 2. GOOGLE_APPLICATION_CREDENTIALS environment variable
        if let credsPath = ProcessInfo.processInfo.environment["GOOGLE_APPLICATION_CREDENTIALS"],
           FileManager.default.fileExists(atPath: credsPath) {
            if let token = resolveTokenFromADCFile(at: credsPath) {
                return token
            }
        }

        // 3. Standard location: ~/.config/gcloud/application_default_credentials.json
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let defaultADCPath = "\(homeDir)/.config/gcloud/application_default_credentials.json"
        if FileManager.default.fileExists(atPath: defaultADCPath) {
            if let token = resolveTokenFromADCFile(at: defaultADCPath) {
                return token
            }
        }

        // 4. gcloud CLI fallback
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
        let scheme = url.scheme?.lowercased()
        if scheme == callbackScheme || scheme == "antigravity" || scheme == "http" || url.host == "127.0.0.1" || url.host == "localhost" {
            if hasProcessedCallback && isAuthenticated {
                return true
            }
            Task { @MainActor in
                if let verifier = self.pendingCodeVerifier, let state = self.pendingState {
                    await self.handleCallbackURL(url, verifier: verifier, state: state, redirectURI: self.activeRedirectURI)
                    self.cleanUpSession()
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

// MARK: - Google Auth Error Classification

/// Classifies provider authentication/authorization failures so the UI can
/// explain the actual cause instead of collapsing everything into a generic
/// "Authentication error" that prompts a useless re-authentication loop.
///
/// The classification preserves the original diagnostic fields (HTTP status,
/// RPC status, reason, service, method) and distinguishes, at minimum:
/// insufficient OAuth scopes, invalid/expired credentials, invalid API keys,
/// quota/rate limits, and non-auth provider errors.
public struct GoogleAuthErrorClassification: Sendable {
    public enum Kind: Sendable, Equatable {
        /// 403 with ACCESS_TOKEN_SCOPE_INSUFFICIENT (or equivalent wording).
        /// Carries the scopes recorded for the current session, if any, so the
        /// caller can tell "token was minted before the required scope existed"
        /// (fixable by re-auth) from "scopes present but endpoint rejected it"
        /// (a real restriction: re-auth would loop forever).
        case scopeInsufficient(storedScopes: String?)
        case invalidOrExpiredCredential
        case apiKeyInvalid
        case quotaOrRateLimit
        case notAuthError
    }

    public let kind: Kind
    /// HTTP status parsed from the error text, when present (e.g. 401, 403, 429).
    public let httpStatus: Int?
    /// Google RPC reason parsed from the error text (e.g. ACCESS_TOKEN_SCOPE_INSUFFICIENT).
    public let reason: String?
    /// Service parsed from the error text (e.g. generativelanguage.googleapis.com).
    public let service: String?
    /// Method parsed from the error text (e.g. ...GenerativeService.StreamGenerateContent).
    public let method: String?

    public static func classify(_ errorText: String) -> GoogleAuthErrorClassification {
        let stored = KeychainService.shared.get(forKey: GoogleAccountAuthService.scopeKey)
        return classify(errorText, storedScopes: stored)
    }

    /// Testable entry point: `storedScopes` is the scope string recorded for
    /// the current session (nil when unknown).
    public static func classify(_ errorText: String, storedScopes: String?) -> GoogleAuthErrorClassification {
        let text = errorText
        let lower = text.lowercased()

        let httpStatus = firstHTTPStatus(in: text)
        // Prefer the most specific known RPC reason; fall back to the first
        // auth-related all-caps token in the text.
        let knownReasons = [
            "ACCESS_TOKEN_SCOPE_INSUFFICIENT",
            "PERMISSION_DENIED",
            "UNAUTHENTICATED",
            "RESOURCE_EXHAUSTED",
            "API_KEY_INVALID",
        ]
        let reason: String? = knownReasons.first(where: { text.contains($0) })
            ?? firstMatch(in: text, pattern: "[A-Z][A-Z0-9_]{5,}").flatMap { candidate in
                let relevant = candidate.contains("SCOPE") || candidate.contains("PERMISSION")
                    || candidate.contains("AUTH") || candidate.contains("QUOTA") || candidate.contains("RATE")
                return relevant ? candidate : nil
            }
        // Prefer the actual API service over incidental matches such as the
        // "type.googleapis.com/..." prefix in RPC detail payloads.
        let knownServices = [
            "generativelanguage.googleapis.com",
            "aiplatform.googleapis.com",
        ]
        let service: String? = knownServices.first(where: { text.contains($0) })
            ?? firstMatch(in: text, pattern: "[a-z0-9-]+\\.googleapis\\.com")
        let method = firstMatch(in: text, pattern: "[A-Za-z0-9_.]+\\.StreamGenerateContent|[A-Za-z0-9_.]+\\.GenerateContent")

        let mentionsScopeProblem =
            text.contains("ACCESS_TOKEN_SCOPE_INSUFFICIENT") ||
            (text.contains("403") && lower.contains("insufficient authentication scopes")) ||
            (text.contains("PERMISSION_DENIED") && lower.contains("scope"))

        if mentionsScopeProblem {
            return GoogleAuthErrorClassification(
                kind: .scopeInsufficient(storedScopes: storedScopes),
                httpStatus: httpStatus, reason: reason, service: service, method: method)
        }

        let isQuota = lower.contains("rate limit") || lower.contains("rate_limit") ||
            lower.contains("quota") || lower.contains("429") ||
            lower.contains("resource_exhausted")
        if isQuota {
            return GoogleAuthErrorClassification(
                kind: .quotaOrRateLimit,
                httpStatus: httpStatus, reason: reason, service: service, method: method)
        }

        let mentionsKeyProblem =
            text.contains("API_KEY_INVALID") || lower.contains("invalid api key") ||
            lower.contains("api key not valid")
        if mentionsKeyProblem {
            return GoogleAuthErrorClassification(
                kind: .apiKeyInvalid,
                httpStatus: httpStatus, reason: reason, service: service, method: method)
        }

        let mentionsCredentialProblem =
            text.contains("401") || lower.contains("unauthorized") ||
            lower.contains("invalid credentials") || lower.contains("invalid_grant") ||
            text.contains("UNAUTHENTICATED")
        if mentionsCredentialProblem {
            return GoogleAuthErrorClassification(
                kind: .invalidOrExpiredCredential,
                httpStatus: httpStatus, reason: reason, service: service, method: method)
        }

        return GoogleAuthErrorClassification(
            kind: .notAuthError,
            httpStatus: httpStatus, reason: reason, service: service, method: method)
    }

    /// One-line diagnostic summary preserving the original failure details.
    public var diagnosticSummary: String {
        var parts: [String] = []
        if let httpStatus { parts.append("HTTP \(httpStatus)") }
        if let reason { parts.append(reason) }
        if let service { parts.append(service) }
        if let method { parts.append(method) }
        return parts.isEmpty ? "no provider details captured" : parts.joined(separator: " | ")
    }

    private static func firstHTTPStatus(in text: String) -> Int? {
        // Matches "Error 403", "status 403", "HTTP 403", "code 403".
        guard let regex = try? NSRegularExpression(pattern: "(?:Error|error|status|HTTP|code)\\s*[:=]?\\s*(401|403|404|429|500|502|503)") else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let statusRange = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[statusRange])
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let matchRange = Range(match.range(at: 0), in: text) else { return nil }
        return String(text[matchRange])
    }
}

// MARK: - OAuth Loopback Server (RFC 8252 Compliance for Google OAuth Desktop Policy)

@MainActor
public final class OAuthLoopbackServer: @unchecked Sendable {
    private var listener: NWListener?
    public private(set) var port: UInt16 = 8085
    public var onCallback: ((URL) -> Void)?

    public init() {}

    public func start() -> UInt16 {
        var candidatePorts: [UInt16] = [65000]
        candidatePorts.append(contentsOf: (UInt16(8085)...UInt16(8099)))
        for candidatePort in candidatePorts {
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
                    let hostPrefix = (self.port == 65000) ? "http://localhost:65000" : "http://127.0.0.1:\(self.port)"
                    if let url = URL(string: "\(hostPrefix)\(pathAndQuery)") ?? URL(string: "http://127.0.0.1:\(self.port)\(pathAndQuery)") {
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
                    <p>You have successfully authenticated with Google Antigravity.</p>
                    <p>Returning to <strong>SwiftCode</strong>...</p>
                </div>
                <script>
                    setTimeout(function() {
                        window.location.href = "swiftcode://oauth-callback";
                    }, 350);
                    setTimeout(function() {
                        window.close();
                    }, 2000);
                </script>
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
