// Moved from SwiftCodeGoogleAuth by R-GOOGLE-MOVE (W-V2 decision 1, 2026-11-06):
// SwiftCodeAssistant cannot depend on SwiftCodeGoogleAuth, so the types AssistManager
// needs live here. Still in SwiftCodeGoogleAuth (follow-up move): GoogleTokenClient,
// GoogleOAuthConfiguration (+ GoogleSecretAccount, GoogleDefaultsKey), GoogleOAuthTokens,
// GooglePKCE, GoogleLoopbackServer, GoogleAuthError (+ GoogleAuthErrorClassification),
// GoogleAmbientCredentials. OAuthLoopbackServer stays in the GoogleAuth file.

import Foundation

#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if canImport(AppKit)
import AppKit
#endif


/// Authentication for a Google account, using
/// `ASWebAuthenticationSession`, a local loopback HTTP listener
/// (RFC 8252, Google's OAuth desktop policy), PKCE (RFC 7636), and
/// fallback to ambient Application Default Credentials (ADC).
///
/// Ported from Legacy's `GoogleAccountAuthService` (1,773 lines).
/// Same observable state (`isAuthenticated`, `userEmail`,
/// `isAuthenticating`, `authError`, `lastTokenRefreshError`), same
/// flows, same order of operations, same endpoint shapes — with
/// SwiftCode's seams instead of Legacy's globals:
///
/// - tokens live in the injected `SecretStore` (Keychain on macOS,
///   a 0600 file on Linux — see `SecretStore`), never in files or
///   logs; Legacy's `KeychainService.shared` is gone;
/// - the client-id override Legacy read from
///   `AppSettings.shared` is read from the same UserDefaults key
///   directly (SwiftCode has no `AppSettings`);
/// - the token HTTP calls go through the injected
///   `GoogleTokenClient` (stubbed transport in tests);
/// - the environment, home directory, and user defaults are
///   injectable so ADC/CLI discovery is testable with fixtures;
///   the Antigravity keychain fetch and the `gcloud` runner are
///   injectable closures for the same reason (the defaults read
///   the real keychain / run the real CLI, which tests must never
///   do).
/// - Legacy restored the session in `init`; this port does not by
///   default (`restoreSession: false`) — the host triggers
///   `restoreSessionFromKeychain()` explicitly (the Accounts pane
///   does so once when its Google section first builds), matching
///   `CloudAuthManager`, whose restore is also explicit. Restoring
///   in `init` would make merely constructing the shared service
///   read the keychain and probe the network.
///
/// Deliberate deviations (see spec §10):
/// - a plain `@MainActor` class, not `NSObject` + `ObservableObject`
///   with `@Published`: the Accounts pane is AppKit and rebuilds
///   imperatively; hosts observe state through `onStateChange`;
/// - `getValidAccessToken()` is non-throwing (Legacy's `throws`
///   was vestigial — no path threw);
/// - the three Legacy app-internal callouts after auth have no
///   SwiftCode counterpart and are not made:
///   `AntigravityQuotaService.resetToFresh()`,
///   `AssistModelRouter.clearAllQuarantines()`, and
///   `GoogleCloudSDKLifecycleManager.restartEngine()`;
/// - Legacy's `extractOAuthURL(from:)` helper was dead code (defined
///   but never called) and is not ported;
/// - `GoogleAuthErrorClassification.classify(_:)` no longer reads
///   the keychain itself — the service passes the stored scopes in.
///
/// On platforms without `AuthenticationServices` and `Network`
/// (Linux) the browser flow fails honestly with
/// `.browserSignInUnavailable`: no browser is faked, and no token
/// is ever invented. The portable pieces — PKCE, token exchange and
/// refresh, ADC file discovery, Antigravity parsing, error
/// classification — work everywhere.
@MainActor
public final class GoogleAccountAuthService: NSObject {
    public static let shared = GoogleAccountAuthService()

    // MARK: - Observable state

    public private(set) var isAuthenticated = false
    public private(set) var userEmail: String?
    public private(set) var isAuthenticating = false
    public private(set) var authError: String?

    /// The most recent token-refresh failure reason, for user-facing
    /// diagnostics ("session expired" messages name the refresh
    /// failure instead of blaming a missing API key). Set on refresh
    /// failure, cleared on success. (Legacy C-1.)
    public private(set) var lastTokenRefreshError: String?

    /// Called after state changes (sign-in, sign-out, restore,
    /// verification failure) so an imperative host such as the
    /// Accounts pane can rebuild. SwiftCode's replacement for Legacy's
    /// `@Published` observation.
    public var onStateChange: (() -> Void)?

    /// True while a scope-upgrade re-authentication is in flight.
    /// The existing session is kept until the new sign-in succeeds,
    /// so a cancelled or failed upgrade leaves the previous session
    /// intact. (Legacy M-2.)
    private var isScopeUpgradeReauth = false

    // MARK: - Dependencies

    private let store: any SecretStore
    private let session: URLSession
    private let tokenClient: GoogleTokenClient
    private let configuration: GoogleOAuthConfiguration
    private let environment: [String: String]
    private let homeDirectory: URL
    private let userDefaults: UserDefaults
    /// Reads Antigravity credentials from the system keychain
    /// (default), or a test double. Injectable because the real
    /// fetch reads the user's actual keychain — tests must never do
    /// that, and must never refresh a real token.
    private let antigravityFetcher: @Sendable () -> GoogleAmbientCredentials.AntigravityCredentials?
    /// Runs `gcloud auth print-access-token` (default), or a test
    /// double. Injectable for the same reason: a real gcloud
    /// install would return a real token in tests.
    private let gcloudTokenProvider: @Sendable (String) -> String?

    // MARK: - Flow state

    #if canImport(AuthenticationServices)
    private var authSession: ASWebAuthenticationSession?
    #endif
    private var pendingCodeVerifier: String?
    private var pendingState: String?
    private var loopbackServer: GoogleLoopbackServer?
    private var activeRedirectURI: String = GoogleOAuthConfiguration.redirectURI(forLoopbackPort: 8085)
    private var hasProcessedCallback = false

    public init(
        store: any SecretStore = defaultSecretStore(),
        session: URLSession = .shared,
        tokenClient: GoogleTokenClient? = nil,
        configuration: GoogleOAuthConfiguration = GoogleOAuthConfiguration(),
        environment: [String: String]? = nil,
        homeDirectory: URL? = nil,
        userDefaults: UserDefaults = .standard,
        antigravityFetcher: (@Sendable () -> GoogleAmbientCredentials.AntigravityCredentials?)? = nil,
        gcloudTokenProvider: (@Sendable (String) -> String?)? = nil,
        restoreSession: Bool = false
    ) {
        self.store = store
        self.session = session
        self.tokenClient = tokenClient ?? GoogleTokenClient(session: session)
        self.configuration = configuration
        self.environment = environment ?? ProcessInfo.processInfo.environment
        self.homeDirectory = homeDirectory ?? FileManager.default.homeDirectoryForCurrentUser
        self.userDefaults = userDefaults
        self.antigravityFetcher = antigravityFetcher ?? GoogleAmbientCredentials.fetchAntigravityCredentialsFromKeychain
        self.gcloudTokenProvider = gcloudTokenProvider ?? GoogleAmbientCredentials.gcloudAccessToken
        super.init()
        if restoreSession {
            restoreSessionFromKeychain()
        }
    }

    // MARK: - Client id and secret

    /// The OAuth client id: the `GOOGLE_CLIENT_ID` environment
    /// variable, then the `GOOGLE_CLIENT_ID` Info.plist key, then
    /// the user-editable override from Settings → Accounts →
    /// Google Account (Legacy's
    /// `assist_google_oauth_client_id_override` key), then
    /// SwiftCode's own client id.
    public var clientID: String {
        if let env = environment["GOOGLE_CLIENT_ID"], !env.isEmpty { return env }
        if let info = Bundle.main.infoDictionary?["GOOGLE_CLIENT_ID"] as? String, !info.isEmpty { return info }
        let override = (userDefaults.string(forKey: GoogleDefaultsKey.clientIDOverride) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !override.isEmpty { return override }
        return configuration.clientID
    }

    /// The OAuth client secret. Google's token endpoint rejects the
    /// authorization-code exchange without it for this client (400
    /// invalid_request: "client_secret is missing."), even though
    /// the browser authorization step succeeds and Google's
    /// installed-app docs label the parameter "Optional". The secret
    /// is never embedded in the distributed app: it comes from the
    /// user's own OAuth client, entered in Settings and stored
    /// securely in the secret store, or from the
    /// `GOOGLE_CLIENT_SECRET` environment variable / Info.plist key
    /// (for testing and advanced setups).
    ///
    /// A desktop app cannot keep a secret truly confidential — anyone
    /// can extract it from the installed app or its keychain. That is
    /// accepted here because Google requires the secret for the
    /// exchange; the secret alone grants nothing without the user's
    /// own authorization grant, and shipping it would let anyone
    /// impersonate SwiftCode's OAuth client. The user enters their
    /// own client's secret, so the exposure is theirs to manage,
    /// exactly as with an API key. (Legacy's comment, kept.)
    public var clientSecret: String? {
        if let stored = store.readString(GoogleSecretAccount.clientSecret), !stored.isEmpty { return stored }
        if let env = environment["GOOGLE_CLIENT_SECRET"], !env.isEmpty { return env }
        if let info = Bundle.main.infoDictionary?["GOOGLE_CLIENT_SECRET"] as? String, !info.isEmpty { return info }
        return nil
    }

    /// Whether a client secret is available from any configured source.
    public var hasClientSecret: Bool { clientSecret != nil }

    /// Whether the secret is stored in the secret store
    /// (user-entered via Settings), as opposed to an environment /
    /// Info.plist override.
    public var hasKeychainClientSecret: Bool {
        if let stored = store.readString(GoogleSecretAccount.clientSecret), !stored.isEmpty { return true }
        return false
    }

    /// Stores the OAuth client's secret securely. The secret is
    /// never logged and never embedded in the app bundle. An empty
    /// string removes the stored secret.
    public func setClientSecret(_ secret: String) {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try? store.delete(GoogleSecretAccount.clientSecret)
        } else {
            try? store.write(Data(trimmed.utf8), for: GoogleSecretAccount.clientSecret)
        }
        notifyStateChange()
    }

    /// Removes a stored client secret.
    public func clearClientSecret() {
        try? store.delete(GoogleSecretAccount.clientSecret)
        notifyStateChange()
    }

    /// Stores the user-editable OAuth client-id override (Settings
    /// → Accounts → Google Account). Empty clears it; it applies to
    /// the next sign-in.
    public func setClientIDOverride(_ id: String) {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        userDefaults.set(trimmed, forKey: GoogleDefaultsKey.clientIDOverride)
        notifyStateChange()
    }

    // MARK: - Session restoration

    public func restoreSessionFromKeychain() {
        let isExplicitlySignedOut = userDefaults.bool(forKey: GoogleDefaultsKey.explicitlySignedOut)
        guard !isExplicitlySignedOut else { return }

        // 1. If Antigravity credentials exist in the system keychain
        // (from `agy` CLI or Google Cloud tools), import and use them.
        if let creds = antigravityFetcher() {
            if let token = creds.accessToken, !token.isEmpty {
                try? store.write(Data(token.utf8), for: GoogleSecretAccount.accessToken)
                // Record an expiry for the CLI-imported token. The CLI
                // does not tell us the token's real lifetime; assume
                // the standard one hour (matching
                // importExistingAntigravityCredentials) so the
                // accessors refresh it when due instead of serving it
                // unchecked forever. (Legacy C-4.)
                let assumedExpiry = Date().addingTimeInterval(3600).timeIntervalSince1970
                try? store.write(Data(String(assumedExpiry).utf8), for: GoogleSecretAccount.expiresAt)
            }
            if !creds.refreshToken.isEmpty {
                try? store.write(Data(creds.refreshToken.utf8), for: GoogleSecretAccount.refreshToken)
            }
            let scopeToStore = creds.scopes.isEmpty ? configuration.scopeString : creds.scopes.joined(separator: " ")
            try? store.write(Data(scopeToStore.utf8), for: GoogleSecretAccount.scope)
            self.isAuthenticated = true
            if let email = store.readString(GoogleSecretAccount.userEmail), !email.isEmpty {
                self.userEmail = email
            }
            Task {
                await self.importExistingAntigravityCredentials()
            }
            notifyStateChange()
            return
        }

        // 2. Check the stored session in the secret store.
        if let email = store.readString(GoogleSecretAccount.userEmail), !email.isEmpty,
           let token = store.readString(GoogleSecretAccount.accessToken), !token.isEmpty {
            self.userEmail = email
            self.isAuthenticated = true
            Task {
                await self.verifyRuntimeSession(accessToken: token)
            }
            notifyStateChange()
        } else if let token = store.readString(GoogleSecretAccount.accessToken), !token.isEmpty {
            self.isAuthenticated = true
            Task {
                if let email = await self.tokenClient.fetchUserEmail(accessToken: token) {
                    try? self.store.write(Data(email.utf8), for: GoogleSecretAccount.userEmail)
                    self.userEmail = email
                    self.notifyStateChange()
                }
            }
            notifyStateChange()
        } else if let adcEmail = self.ambientADCEmail() {
            self.userEmail = adcEmail
            self.isAuthenticated = true
            notifyStateChange()
        }
    }

    // MARK: - Runtime session verification

    /// Verifies that an OAuth access token is valid and accepted by
    /// the Antigravity runtime.
    @discardableResult
    public func verifyRuntimeSession(accessToken overrideToken: String? = nil, depth: Int = 0) async -> Bool {
        let tokenToVerify: String?
        if let token = overrideToken, !token.isEmpty {
            tokenToVerify = token
        } else {
            tokenToVerify = await getValidAccessToken()
        }

        guard let token = tokenToVerify, !token.isEmpty else {
            return false
        }

        guard let status = await tokenClient.tokeninfoStatus(accessToken: token) else {
            // The probe never reached Google: fall back to the stored
            // expiration timestamp.
            return isStoredTokenUnexpired()
        }
        if status == 200 {
            return true
        }
        if status == 400 || status == 401 {
            if depth < 1,
               let refreshToken = store.readString(GoogleSecretAccount.refreshToken),
               let refreshedToken = try? await self.refreshAccessToken(refreshToken: refreshToken) {
                return await verifyRuntimeSession(accessToken: refreshedToken, depth: depth + 1)
            }
            // The token was rejected and refresh did not recover it:
            // drop the dead access token so the rejection sticks. The
            // refresh token is kept for a later retry, and the next
            // launch will not resurrect this token via restore.
            // (Legacy M-1; the recursion above is bounded by depth.)
            try? store.delete(GoogleSecretAccount.accessToken)
            try? store.delete(GoogleSecretAccount.expiresAt)
            self.lastTokenRefreshError = "the saved sign-in was rejected by Google and the token refresh failed"
            self.authError = "Antigravity runtime session expired or unauthorized. Please re-authenticate."
            self.isAuthenticated = false
            notifyStateChange()
            return false
        }
        // For non-200 non-auth status codes, consider valid if the
        // stored token is unexpired.
        return isStoredTokenUnexpired()
    }

    /// The stored-expiry fallback: true when no expiry was recorded
    /// or the recorded expiry is still in the future.
    private func isStoredTokenUnexpired() -> Bool {
        let expiresAt = Double(store.readString(GoogleSecretAccount.expiresAt) ?? "0") ?? 0
        return expiresAt > Date().timeIntervalSince1970 || expiresAt == 0
    }

    // MARK: - Sign in (PKCE RFC 7636 + loopback RFC 8252)

    public func signIn() {
        guard !isAuthenticating else { return }

        authError = nil
        isAuthenticating = true
        hasProcessedCallback = false
        userDefaults.set(false, forKey: GoogleDefaultsKey.explicitlySignedOut)
        notifyStateChange()

        #if canImport(AuthenticationServices) && canImport(Network)
        let verifier = GooglePKCE.generateCodeVerifier()
        let challenge = GooglePKCE.generateCodeChallenge(for: verifier)
        let state = UUID().uuidString

        self.pendingCodeVerifier = verifier
        self.pendingState = state

        // Start the local loopback HTTP listener to comply with
        // Google OAuth 2.0 policy for desktop apps.
        let server = GoogleLoopbackServer()
        guard let port = server.start() else {
            isAuthenticating = false
            isScopeUpgradeReauth = false
            authError = GoogleAuthError.loopbackUnavailable.errorDescription
            notifyStateChange()
            return
        }
        self.loopbackServer = server

        let redirectURI = GoogleOAuthConfiguration.redirectURI(forLoopbackPort: port)
        self.activeRedirectURI = redirectURI

        guard let authURL = GooglePKCE.authorizationURL(
            configuration: configurationWithResolvedClientID(),
            challenge: challenge,
            state: state,
            redirectURI: redirectURI
        ) else {
            isAuthenticating = false
            isScopeUpgradeReauth = false
            loopbackServer?.stop()
            loopbackServer = nil
            authError = "Failed to construct Google OAuth authorization URL."
            notifyStateChange()
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
            callbackScheme: GoogleOAuthConfiguration.callbackScheme,
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
            // Fallback: open the auth URL directly in the system
            // default browser if the session fails to start.
            #if canImport(AppKit)
            NSWorkspace.shared.open(authURL)
            #endif
        }
        #else
        // No browser sign-in session exists on this platform: fail
        // honestly instead of pretending a browser opened.
        isAuthenticating = false
        isScopeUpgradeReauth = false
        authError = GoogleAuthError.browserSignInUnavailable.errorDescription
        notifyStateChange()
        #endif
    }

    /// The configuration with the resolved client id (environment /
    /// Info.plist / Settings override / built-in), so the authorize
    /// URL carries the id the user actually configured.
    private func configurationWithResolvedClientID() -> GoogleOAuthConfiguration {
        GoogleOAuthConfiguration(clientID: clientID, scopes: configuration.scopes)
    }

    #if canImport(AuthenticationServices)
    /// The web-auth session factory is non-isolated (Legacy's
    /// `createWebAuthSession`): the session itself is created off
    /// the actor and only its callbacks re-enter it.
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
        if self.isAuthenticated && !self.isScopeUpgradeReauth {
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
            self.isAuthenticating = false
            self.isScopeUpgradeReauth = false
            self.cleanUpSession()
            notifyStateChange()
            return
        }

        if error != nil {
            self.isAuthenticating = false
            self.isScopeUpgradeReauth = false
            self.cleanUpSession()
            notifyStateChange()
        }
    }
    #endif

    @MainActor
    private func cleanUpSession() {
        self.loopbackServer?.stop()
        self.loopbackServer = nil
        #if canImport(AuthenticationServices)
        self.authSession = nil
        #endif
    }

    // MARK: - Sign out

    public func signOut() {
        try? store.delete(GoogleSecretAccount.accessToken)
        try? store.delete(GoogleSecretAccount.refreshToken)
        try? store.delete(GoogleSecretAccount.userEmail)
        try? store.delete(GoogleSecretAccount.expiresAt)
        try? store.delete(GoogleSecretAccount.scope)

        userDefaults.set(true, forKey: GoogleDefaultsKey.explicitlySignedOut)

        cleanUpSession()

        self.isAuthenticated = false
        self.userEmail = nil
        self.isAuthenticating = false
        self.authError = nil
        self.pendingCodeVerifier = nil
        self.pendingState = nil
        notifyStateChange()
    }

    // MARK: - Assist scope verification & re-authentication

    /// Verifies if the active OAuth session has the required scopes
    /// for Google Antigravity / Gemini models. The decisive scope is
    /// generative-language.retriever: without it the Gemini Developer
    /// API rejects OAuth requests with 403
    /// ACCESS_TOKEN_SCOPE_INSUFFICIENT no matter what other scopes
    /// are present.
    public func hasRequiredAssistScopes() -> Bool {
        guard isAuthenticated else { return false }
        // If Antigravity credentials exist in the keychain, they possess the required scopes.
        if antigravityFetcher() != nil {
            return true
        }
        if let storedScope = store.readString(GoogleSecretAccount.scope), !storedScope.isEmpty {
            return storedScope.contains("generative-language.retriever") || storedScope.contains("cloud-platform")
        }
        // If authenticated without recorded scope, treat as valid to prevent false lockouts.
        return true
    }

    /// Re-authenticates the user with the complete set of Assist
    /// scopes without requiring API keys. Non-destructive: the
    /// existing session is kept until the new sign-in succeeds. If
    /// the user cancels or the flow fails, the previous
    /// (legacy-scope) session remains intact instead of the user
    /// being signed out. (Legacy M-2.)
    public func reAuthenticateForAssistScopes() {
        guard !isAuthenticating else { return }
        isScopeUpgradeReauth = true
        signIn()
    }

    // MARK: - Antigravity credentials import

    /// Automatically imports active credentials from the system
    /// Antigravity keychain entry if available.
    @discardableResult
    public func importExistingAntigravityCredentials() async -> Bool {
        guard let creds = antigravityFetcher() else {
            return false
        }

        var resolvedTokens: GoogleOAuthTokens?
        do {
            resolvedTokens = try await tokenClient.refreshToken(
                creds.refreshToken, clientID: creds.clientID, clientSecret: creds.clientSecret)
        } catch {
            if let existingToken = creds.accessToken, !existingToken.isEmpty {
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

        try? store.write(Data(tokens.accessToken.utf8), for: GoogleSecretAccount.accessToken)
        if !creds.refreshToken.isEmpty {
            try? store.write(Data(creds.refreshToken.utf8), for: GoogleSecretAccount.refreshToken)
        }
        let scopeToStore = tokens.scope ?? (creds.scopes.isEmpty ? configuration.scopeString : creds.scopes.joined(separator: " "))
        try? store.write(Data(scopeToStore.utf8), for: GoogleSecretAccount.scope)

        let expiresAt = Date().addingTimeInterval(TimeInterval(tokens.expiresIn ?? 3600)).timeIntervalSince1970
        try? store.write(Data(String(expiresAt).utf8), for: GoogleSecretAccount.expiresAt)

        var email: String?
        if let idToken = tokens.idToken {
            email = GooglePKCE.extractEmailFromIDToken(idToken)
        }
        if email == nil {
            email = await tokenClient.fetchUserEmail(accessToken: tokens.accessToken)
        }

        if let resolvedEmail = email, !resolvedEmail.isEmpty {
            try? store.write(Data(resolvedEmail.utf8), for: GoogleSecretAccount.userEmail)
            self.userEmail = resolvedEmail
        } else if let adcEmail = ambientADCEmail() {
            self.userEmail = adcEmail
            try? store.write(Data(adcEmail.utf8), for: GoogleSecretAccount.userEmail)
        } else {
            self.userEmail = "Google Account (Antigravity)"
        }

        self.isAuthenticated = true
        self.isAuthenticating = false
        self.authError = nil
        userDefaults.set(false, forKey: GoogleDefaultsKey.explicitlySignedOut)
        notifyStateChange()
        return true
    }

    // MARK: - Sign in via agy CLI

    /// Authenticates via the background `agy` CLI process,
    /// automatically detecting and opening the Google Antigravity
    /// consent URL.
    public func signInViaCLI() {
        guard !isAuthenticating else { return }

        authError = nil
        isAuthenticating = true
        userDefaults.set(false, forKey: GoogleDefaultsKey.explicitlySignedOut)
        notifyStateChange()

        Task {
            do {
                try await performCLISignIn()
            } catch {
                await MainActor.run {
                    self.isAuthenticating = false
                    self.authError = error.localizedDescription
                    self.notifyStateChange()
                }
            }
        }
    }

    /// The first executable `agy` CLI candidate, or nil when none
    /// is installed.
    public func findAgyCLI() -> String? {
        GoogleAmbientCredentials.findAgyCLI(environment: environment, homeDirectory: homeDirectory)
    }

    private func performCLISignIn() async throws {
        // 1. First, check if Antigravity is already authenticated in the keychain.
        if await importExistingAntigravityCredentials() {
            return
        }

        // 2. If not found in the keychain, launch the agy CLI in
        // Terminal so the user can perform interactive login.
        guard let agyPath = findAgyCLI() else {
            throw GoogleAuthError.agyCLINotFound
        }

        #if canImport(AppKit)
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

        // Poll for the credentials to appear in the keychain (up to 120 seconds).
        for _ in 0..<80 {
            try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5s
            if await importExistingAntigravityCredentials() {
                return
            }
        }

        throw GoogleAuthError.agyCLITimedOut
        #else
        // The CLI exists but there is no Terminal.app / AppleScript
        // to drive its interactive login on this platform.
        throw GoogleAuthError.cliSignInUnavailable
        #endif
    }

    // MARK: - Access token accessors

    /// Returns a valid access token asynchronously, refreshing if
    /// necessary or falling back to ambient ADC. Never returns a
    /// known-expired token: if the stored token is past its expiry
    /// and refresh fails, this tries ambient ADC and then returns
    /// nil so callers surface a clear re-authentication prompt
    /// instead of sending a dead token to the API. (Legacy C-4.)
    public func getValidAccessToken() async -> String? {
        // 1. Check the stored OAuth access token.
        if let token = store.readString(GoogleSecretAccount.accessToken), !token.isEmpty {
            let expiresAt = Double(store.readString(GoogleSecretAccount.expiresAt) ?? "0") ?? 0
            let now = Date().timeIntervalSince1970

            // If the token is valid or no expiration was recorded
            // (expiresAt == 0), use it directly.
            if expiresAt == 0 || expiresAt > (now + 60) {
                return token
            }

            // If expired, attempt token refresh via refresh token.
            if let refreshToken = store.readString(GoogleSecretAccount.refreshToken) {
                do {
                    let refreshedToken = try await refreshAccessToken(refreshToken: refreshToken)
                    self.lastTokenRefreshError = nil
                    return refreshedToken
                } catch {
                    self.lastTokenRefreshError = error.localizedDescription
                }
            }

            if let adcToken = await checkAmbientADC() {
                return adcToken
            }
            // Do not return a known-expired token.
            if expiresAt > 0 && expiresAt <= now {
                return nil
            }
            return token
        }

        // 2. Fall back to ambient Application Default Credentials.
        if let adcToken = await checkAmbientADC() {
            return adcToken
        }

        return nil
    }

    /// Synchronous accessor for an access token, utilizing the
    /// secret store and ADC fallback. Never returns an expired
    /// token: if the stored token is past its expiry and refresh
    /// fails, this returns nil so callers surface a clear
    /// re-authentication prompt instead of sending a dead token to
    /// the API. The refresh here is synchronous (an 8-second
    /// semaphore wait, Legacy's `refreshAccessTokenSync`).
    public func getValidAccessTokenSync() -> String? {
        if let token = store.readString(GoogleSecretAccount.accessToken), !token.isEmpty {
            let expiresAt = Double(store.readString(GoogleSecretAccount.expiresAt) ?? "0") ?? 0
            let now = Date().timeIntervalSince1970

            if expiresAt == 0 || expiresAt > (now + 60) {
                return token
            }

            if let refreshToken = store.readString(GoogleSecretAccount.refreshToken),
               let refreshed = refreshAccessTokenSync(refreshToken: refreshToken, clientID: clientID, clientSecret: clientSecret) {
                self.lastTokenRefreshError = nil
                return refreshed
            }

            if let adcToken = checkAmbientADCSync() {
                return adcToken
            }
            // Do not return a known-expired token.
            if expiresAt > 0 && expiresAt <= now {
                return nil
            }
            return token
        }

        if let adcToken = checkAmbientADCSync() {
            return adcToken
        }

        return nil
    }

    // MARK: - Callback & exchange

    /// Handles the loopback redirect: validates state, exchanges
    /// the code, stores the tokens, resolves the email, and verifies
    /// the runtime session. The scope-upgrade flag ends here
    /// regardless of outcome; it must not leak into a later
    /// unrelated sign-in. (Legacy M-2.)
    func handleCallbackURL(_ url: URL, verifier: String, state: String, redirectURI: String) async {
        guard !hasProcessedCallback else { return }
        hasProcessedCallback = true
        defer { self.isScopeUpgradeReauth = false }

        let code: String
        do {
            code = try GooglePKCE.parseCallback(url, expectedState: state)
        } catch {
            self.authError = error.localizedDescription
            self.isAuthenticating = false
            notifyStateChange()
            return
        }

        do {
            let tokens = try await tokenClient.exchangeCode(
                code: code, verifier: verifier, redirectURI: redirectURI,
                clientID: clientID, clientSecret: clientSecret)

            // Store tokens in the secret store.
            try? store.write(Data(tokens.accessToken.utf8), for: GoogleSecretAccount.accessToken)
            if let refreshToken = tokens.refreshToken {
                try? store.write(Data(refreshToken.utf8), for: GoogleSecretAccount.refreshToken)
            }
            let scopeToStore = tokens.scope ?? configuration.scopeString
            try? store.write(Data(scopeToStore.utf8), for: GoogleSecretAccount.scope)

            let expiresAt = Date().addingTimeInterval(TimeInterval(tokens.expiresIn ?? 3600)).timeIntervalSince1970
            try? store.write(Data(String(expiresAt).utf8), for: GoogleSecretAccount.expiresAt)

            // Fetch the user email.
            var email: String?
            email = await tokenClient.fetchUserEmail(accessToken: tokens.accessToken)
            if email == nil, let idToken = tokens.idToken {
                email = GooglePKCE.extractEmailFromIDToken(idToken)
            }

            if let resolvedEmail = email, !resolvedEmail.isEmpty {
                try? store.write(Data(resolvedEmail.utf8), for: GoogleSecretAccount.userEmail)
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
                notifyStateChange()
            } else {
                self.isAuthenticated = false
                self.isAuthenticating = false
                self.authError = self.authError ?? "Session obtained but Antigravity runtime verification failed."
                notifyStateChange()
            }
        } catch {
            self.isAuthenticating = false
            self.authError = GoogleAuthError.actionableSignInError(for: error)
            notifyStateChange()
        }
    }

    // MARK: - Token refresh

    /// Refreshes an access token with a refresh-token grant and
    /// persists the result (access token, expiry, rotated refresh
    /// token and scope when the response carries them).
    public func refreshAccessToken(refreshToken: String) async throws -> String {
        let tokens = try await tokenClient.refreshToken(
            refreshToken, clientID: clientID, clientSecret: clientSecret)
        persistRefreshedTokens(tokens, refreshToken: refreshToken)
        return tokens.accessToken
    }

    /// The synchronous refresh (8-second semaphore wait), for the
    /// synchronous token accessor. Legacy's
    /// `refreshAccessTokenSync`, verbatim in behaviour.
    func refreshAccessTokenSync(refreshToken: String, clientID: String, clientSecret: String?) -> String? {
        var request = URLRequest(url: GoogleOAuthConfiguration.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = GoogleTokenClient.formBody([
            ("client_id", clientID),
            ("refresh_token", refreshToken),
            ("grant_type", "refresh_token"),
            ("client_secret", clientSecret),
        ])

        let semaphore = DispatchSemaphore(value: 0)
        // A locked box (the `RateLimitBox` / `Box` precedent): the
        // data-task completion runs on another thread, so the result
        // cannot live in a captured local under Swift 6.
        final class TokenBox: @unchecked Sendable {
            let lock = NSLock()
            var tokens: GoogleOAuthTokens?
        }
        let box = TokenBox()

        let task = session.dataTask(with: request) { data, _, _ in
            defer { semaphore.signal() }
            guard let data,
                  let tokens = try? JSONDecoder().decode(GoogleOAuthTokens.self, from: data),
                  !tokens.accessToken.isEmpty else {
                return
            }
            box.lock.lock(); box.tokens = tokens; box.lock.unlock()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 8.0)
        box.lock.lock(); defer { box.lock.unlock() }
        if let tokens = box.tokens {
            persistRefreshedTokens(tokens, refreshToken: refreshToken)
            return tokens.accessToken
        }
        return nil
    }

    private func persistRefreshedTokens(_ tokens: GoogleOAuthTokens, refreshToken: String) {
        try? store.write(Data(tokens.accessToken.utf8), for: GoogleSecretAccount.accessToken)
        let expiresAt = Date().addingTimeInterval(TimeInterval(tokens.expiresIn ?? 3600)).timeIntervalSince1970
        try? store.write(Data(String(expiresAt).utf8), for: GoogleSecretAccount.expiresAt)
        if let newRefreshToken = tokens.refreshToken {
            try? store.write(Data(newRefreshToken.utf8), for: GoogleSecretAccount.refreshToken)
        }
        if let newScope = tokens.scope {
            try? store.write(Data(newScope.utf8), for: GoogleSecretAccount.scope)
        }
    }

    // MARK: - Ambient Application Default Credentials (ADC)

    /// The ambient access token, if any: Antigravity keychain
    /// credentials, then an ADC file, then the `gcloud` CLI. An
    /// explicit sign-out sticks — ambient credentials must not
    /// resurrect the session after the user signed out (Legacy H-3).
    public func checkAmbientADC() async -> String? {
        if userDefaults.bool(forKey: GoogleDefaultsKey.explicitlySignedOut) {
            return nil
        }
        // 1. Antigravity keychain credentials.
        if let creds = antigravityFetcher() {
            if let existingToken = creds.accessToken, !existingToken.isEmpty {
                return existingToken
            }
            // Refresh under the Antigravity client's own id and
            // secret (Legacy's `refreshAccessTokenWithDetails`),
            // not this service's — the two clients differ.
            if !creds.refreshToken.isEmpty,
               let tokens = try? await tokenClient.refreshToken(
                   creds.refreshToken, clientID: creds.clientID, clientSecret: creds.clientSecret) {
                persistRefreshedTokens(tokens, refreshToken: creds.refreshToken)
                return tokens.accessToken
            }
        }

        // 2. ADC files: GOOGLE_APPLICATION_CREDENTIALS, then the
        // standard location.
        for path in GoogleAmbientCredentials.adcFilePaths(environment: environment, homeDirectory: homeDirectory) {
            if let token = await resolveTokenFromADCFile(at: path) {
                return token
            }
        }

        // 3. gcloud CLI fallback.
        return resolveTokenFromGCloudCLI()
    }

    /// The synchronous ambient check, for the synchronous token
    /// accessor. Same sources, same order, synchronous refreshes.
    func checkAmbientADCSync() -> String? {
        if userDefaults.bool(forKey: GoogleDefaultsKey.explicitlySignedOut) {
            return nil
        }
        if let creds = antigravityFetcher() {
            if let existingToken = creds.accessToken, !existingToken.isEmpty {
                return existingToken
            }
            if !creds.refreshToken.isEmpty,
               let token = refreshAccessTokenSync(refreshToken: creds.refreshToken, clientID: creds.clientID, clientSecret: creds.clientSecret) {
                return token
            }
        }
        for path in GoogleAmbientCredentials.adcFilePaths(environment: environment, homeDirectory: homeDirectory) {
            if let token = resolveTokenFromADCFileSync(at: path) {
                return token
            }
        }
        return resolveTokenFromGCloudCLI()
    }

    func resolveTokenFromADCFile(at path: URL) async -> String? {
        guard let data = try? Data(contentsOf: path) else { return nil }
        switch GoogleAmbientCredentials.parseADCFile(data) {
        case .authorizedUser(let adcClientID, let refreshToken, let secret):
            // The ADC file's own client refreshes under its own id
            // and secret, not this service's.
            if let tokens = try? await tokenClient.refreshToken(
                refreshToken, clientID: adcClientID, clientSecret: secret) {
                return tokens.accessToken
            }
            return nil
        case .accessToken(let token):
            return token
        case .none:
            return nil
        }
    }

    func resolveTokenFromADCFileSync(at path: URL) -> String? {
        guard let data = try? Data(contentsOf: path) else { return nil }
        switch GoogleAmbientCredentials.parseADCFile(data) {
        case .authorizedUser(let adcClientID, let refreshToken, let secret):
            return refreshAccessTokenSync(refreshToken: refreshToken, clientID: adcClientID, clientSecret: secret)
        case .accessToken(let token):
            return token
        case .none:
            return nil
        }
    }

    func resolveTokenFromGCloudCLI() -> String? {
        for candidate in GoogleAmbientCredentials.gcloudCLICandidates(homeDirectory: homeDirectory) {
            if let token = gcloudTokenProvider(candidate) {
                return token
            }
        }
        return nil
    }

    /// The email ambient credentials record, if any: the ADC file's
    /// `client_email`, else the `account =` line of gcloud's active
    /// config.
    public func ambientADCEmail() -> String? {
        let defaultADCPath = homeDirectory.appendingPathComponent(".config/gcloud/application_default_credentials.json")
        if let data = try? Data(contentsOf: defaultADCPath),
           let email = GoogleAmbientCredentials.adcEmail(from: data) {
            return email
        }
        let activeConfigPath = homeDirectory.appendingPathComponent(".config/gcloud/configurations/config_default")
        if let content = try? String(contentsOf: activeConfigPath, encoding: .utf8) {
            return GoogleAmbientCredentials.gcloudConfigAccount(from: content)
        }
        return nil
    }

    // MARK: - Open URL handler

    /// Handles a URL opened by the system for this app: the
    /// `swiftcode://` callback scheme, the `antigravity://` scheme,
    /// plain `http(s)` loopback URLs, and `127.0.0.1` / `localhost`
    /// hosts. The app shell must forward opened URLs here (see spec
    /// §10); until it does, the loopback listener is the path that
    /// actually delivers the callback. Returns true when the URL
    /// belongs to this flow.
    @discardableResult
    public func handleOpenURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        if scheme == GoogleOAuthConfiguration.callbackScheme || scheme == "antigravity" || scheme == "http"
            || url.host == "127.0.0.1" || url.host == "localhost" {
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

    // MARK: - Helpers

    private func notifyStateChange() {
        onStateChange?()
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

#if canImport(AppKit) && canImport(AuthenticationServices)
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
