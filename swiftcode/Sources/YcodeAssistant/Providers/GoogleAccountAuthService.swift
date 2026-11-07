import Foundation

#if canImport(AuthenticationServices)
import AuthenticationServices
#endif
#if canImport(AppKit)
import AppKit
#endif

@MainActor
public final class GoogleAccountAuthService: NSObject {
    public static let shared = GoogleAccountAuthService()

    public private(set) var isAuthenticated = false
    public private(set) var userEmail: String?
    public private(set) var isAuthenticating = false
    public private(set) var authError: String?

    public private(set) var lastTokenRefreshError: String?

    public var onStateChange: (() -> Void)?

    private var isScopeUpgradeReauth = false

    private let store: any SecretStore
    private let session: URLSession
    private let tokenClient: GoogleTokenClient
    private let configuration: GoogleOAuthConfiguration
    private let environment: [String: String]
    private let homeDirectory: URL
    private let userDefaults: UserDefaults
    private let antigravityFetcher: @Sendable () -> GoogleAmbientCredentials.AntigravityCredentials?
    private let gcloudTokenProvider: @Sendable (String) -> String?

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

    public static let requiredScopes: [String] = [
        "https://www.googleapis.com/auth/cloud-platform",
        "https://www.googleapis.com/auth/generative-language.retriever",
        "https://www.googleapis.com/auth/userinfo.email",
        "https://www.googleapis.com/auth/userinfo.profile",
        "openid"
    ]

    public static let swiftCodeClientID = "1074744318790-25m937v7u4c7f041k925v8v2h8j370s6.apps.googleusercontent.com"

    public static func actionableSignInError(for error: Error) -> String {
        let msg = error.localizedDescription
        if msg.localizedCaseInsensitiveContains("client_secret is missing") || msg.localizedCaseInsensitiveContains("client secret") {
            return "A Google OAuth client secret is required for token exchange. Please configure it in Settings or save it in Keychain."
        }
        return msg
    }

    public func fetchAntigravityCredentialsFromKeychain() -> GoogleAmbientCredentials.AntigravityCredentials? {
        antigravityFetcher()
    }

    public var clientID: String {
        if let env = environment["GOOGLE_CLIENT_ID"], !env.isEmpty { return env }
        if let info = Bundle.main.infoDictionary?["GOOGLE_CLIENT_ID"] as? String, !info.isEmpty { return info }
        let override = (userDefaults.string(forKey: GoogleDefaultsKey.clientIDOverride) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !override.isEmpty { return override }
        return configuration.clientID
    }

    public var clientSecret: String? {
        if let stored = store.readString(GoogleSecretAccount.clientSecret), !stored.isEmpty { return stored }
        if let env = environment["GOOGLE_CLIENT_SECRET"], !env.isEmpty { return env }
        if let info = Bundle.main.infoDictionary?["GOOGLE_CLIENT_SECRET"] as? String, !info.isEmpty { return info }
        return nil
    }

    public var hasClientSecret: Bool { clientSecret != nil }

    public var hasKeychainClientSecret: Bool {
        if let stored = store.readString(GoogleSecretAccount.clientSecret), !stored.isEmpty { return true }
        return false
    }

    public func setClientSecret(_ secret: String) {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            try? store.delete(GoogleSecretAccount.clientSecret)
        } else {
            try? store.write(Data(trimmed.utf8), for: GoogleSecretAccount.clientSecret)
        }
        notifyStateChange()
    }

    public func clearClientSecret() {
        try? store.delete(GoogleSecretAccount.clientSecret)
        notifyStateChange()
    }

    public func setClientIDOverride(_ id: String) {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        userDefaults.set(trimmed, forKey: GoogleDefaultsKey.clientIDOverride)
        notifyStateChange()
    }

    public func restoreSessionFromKeychain() {
        let isExplicitlySignedOut = userDefaults.bool(forKey: GoogleDefaultsKey.explicitlySignedOut)
        guard !isExplicitlySignedOut else { return }

        if let creds = antigravityFetcher() {
            if let token = creds.accessToken, !token.isEmpty {
                try? store.write(Data(token.utf8), for: GoogleSecretAccount.accessToken)
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
            try? store.delete(GoogleSecretAccount.accessToken)
            try? store.delete(GoogleSecretAccount.expiresAt)
            self.lastTokenRefreshError = "the saved sign-in was rejected by Google and the token refresh failed"
            self.authError = "Antigravity runtime session expired or unauthorized. Please re-authenticate."
            self.isAuthenticated = false
            notifyStateChange()
            return false
        }
        return isStoredTokenUnexpired()
    }

    private func isStoredTokenUnexpired() -> Bool {
        let expiresAt = Double(store.readString(GoogleSecretAccount.expiresAt) ?? "0") ?? 0
        return expiresAt > Date().timeIntervalSince1970 || expiresAt == 0
    }

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
            #if canImport(AppKit)
            NSWorkspace.shared.open(authURL)
            #endif
        }
        #else
        isAuthenticating = false
        isScopeUpgradeReauth = false
        authError = GoogleAuthError.browserSignInUnavailable.errorDescription
        notifyStateChange()
        #endif
    }

    private func configurationWithResolvedClientID() -> GoogleOAuthConfiguration {
        GoogleOAuthConfiguration(clientID: clientID, scopes: configuration.scopes)
    }

    #if canImport(AuthenticationServices)
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

    public func hasRequiredAssistScopes() -> Bool {
        guard isAuthenticated else { return false }
        if antigravityFetcher() != nil {
            return true
        }
        if let storedScope = store.readString(GoogleSecretAccount.scope), !storedScope.isEmpty {
            return storedScope.contains("generative-language.retriever") || storedScope.contains("cloud-platform")
        }
        return true
    }

    public func reAuthenticateForAssistScopes() {
        guard !isAuthenticating else { return }
        isScopeUpgradeReauth = true
        signIn()
    }

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

    public func findAgyCLI() -> String? {
        GoogleAmbientCredentials.findAgyCLI(environment: environment, homeDirectory: homeDirectory)
    }

    private func performCLISignIn() async throws {
        if await importExistingAntigravityCredentials() {
            return
        }

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

        for _ in 0..<80 {
            try await Task.sleep(nanoseconds: 1_500_000_000)
            if await importExistingAntigravityCredentials() {
                return
            }
        }

        throw GoogleAuthError.agyCLITimedOut
        #else
        throw GoogleAuthError.cliSignInUnavailable
        #endif
    }

    public var currentAccessToken: String? {
        if let token = store.readString(GoogleSecretAccount.accessToken), !token.isEmpty {
            return token
        }
        return nil
    }

    public func getValidAccessToken() async -> String? {
        if let token = store.readString(GoogleSecretAccount.accessToken), !token.isEmpty {
            let expiresAt = Double(store.readString(GoogleSecretAccount.expiresAt) ?? "0") ?? 0
            let now = Date().timeIntervalSince1970

            if expiresAt == 0 || expiresAt > (now + 60) {
                return token
            }

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
            if expiresAt > 0 && expiresAt <= now {
                return nil
            }
            return token
        }

        if let adcToken = await checkAmbientADC() {
            return adcToken
        }

        return nil
    }

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

            try? store.write(Data(tokens.accessToken.utf8), for: GoogleSecretAccount.accessToken)
            if let refreshToken = tokens.refreshToken {
                try? store.write(Data(refreshToken.utf8), for: GoogleSecretAccount.refreshToken)
            }
            let scopeToStore = tokens.scope ?? configuration.scopeString
            try? store.write(Data(scopeToStore.utf8), for: GoogleSecretAccount.scope)

            let expiresAt = Date().addingTimeInterval(TimeInterval(tokens.expiresIn ?? 3600)).timeIntervalSince1970
            try? store.write(Data(String(expiresAt).utf8), for: GoogleSecretAccount.expiresAt)

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

    public func refreshAccessToken(refreshToken: String) async throws -> String {
        let tokens = try await tokenClient.refreshToken(
            refreshToken, clientID: clientID, clientSecret: clientSecret)
        persistRefreshedTokens(tokens, refreshToken: refreshToken)
        return tokens.accessToken
    }

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

    public func checkAmbientADC() async -> String? {
        if userDefaults.bool(forKey: GoogleDefaultsKey.explicitlySignedOut) {
            return nil
        }
        if let creds = antigravityFetcher() {
            if let existingToken = creds.accessToken, !existingToken.isEmpty {
                return existingToken
            }
            if !creds.refreshToken.isEmpty,
               let tokens = try? await tokenClient.refreshToken(
                   creds.refreshToken, clientID: creds.clientID, clientSecret: creds.clientSecret) {
                persistRefreshedTokens(tokens, refreshToken: creds.refreshToken)
                return tokens.accessToken
            }
        }

        for path in GoogleAmbientCredentials.adcFilePaths(environment: environment, homeDirectory: homeDirectory) {
            if let token = await resolveTokenFromADCFile(at: path) {
                return token
            }
        }

        return resolveTokenFromGCloudCLI()
    }

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

    private func notifyStateChange() {
        onStateChange?()
    }
}

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
