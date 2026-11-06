import Foundation
import Testing
import SwiftCodeAssistant
@testable import SwiftCodeGoogleAuth

// The service: session restore, sign-out, token accessors, the
// callback exchange, scope checks, and client id/secret handling.
// Stub transport + in-memory secret store + temp home throughout:
// no live network, no real keychain, no real credentials. The
// Antigravity and gcloud seams are neutralized by makeTestService,
// so tests never touch the real keychain or CLI.

@MainActor
struct GoogleAccountAuthServiceTests {

    @Test("A stored email and token restore the session")
    func restoreStoredSession() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let (defaults, _) = makeTestDefaults()
        let store = MemorySecretStore()
        storeSession(in: store)
        let service = makeTestService(store: store, handler: { request in
            if request.url?.path == "/oauth2/v3/tokeninfo" { return ok("{}") }
            return (404, [:], json("{}"))
        }, home: home, defaults: defaults, restoreSession: true)
        #expect(service.isAuthenticated)
        #expect(service.userEmail == "dylan@example.com")
    }

    @Test("An explicit sign-out blocks restore: no session is resurrected")
    func explicitSignOutBlocksRestore() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let (defaults, _) = makeTestDefaults()
        defaults.set(true, forKey: GoogleDefaultsKey.explicitlySignedOut)
        let store = MemorySecretStore()
        storeSession(in: store)
        let service = makeTestService(store: store, handler: { _ in ok("{}") }, home: home, defaults: defaults,
                                      restoreSession: true)
        #expect(service.isAuthenticated == false)
        #expect(service.userEmail == nil)
    }

    @Test("Sign-out clears every stored token and marks the explicit sign-out flag")
    func signOutClearsStore() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let (defaults, _) = makeTestDefaults()
        let store = MemorySecretStore()
        storeSession(in: store)
        let service = makeTestService(store: store, handler: { _ in ok("{}") }, home: home, defaults: defaults)
        service.signOut()
        #expect(service.isAuthenticated == false)
        #expect(service.userEmail == nil)
        #expect(service.isAuthenticating == false)
        #expect(store.readString(GoogleSecretAccount.accessToken) == nil)
        #expect(store.readString(GoogleSecretAccount.refreshToken) == nil)
        #expect(store.readString(GoogleSecretAccount.userEmail) == nil)
        #expect(store.readString(GoogleSecretAccount.expiresAt) == nil)
        #expect(store.readString(GoogleSecretAccount.scope) == nil)
        #expect(defaults.bool(forKey: GoogleDefaultsKey.explicitlySignedOut) == true)
        // And the sign-out sticks: ambient ADC cannot resurrect it.
        #expect(await service.checkAmbientADC() == nil)
    }

    @Test("An unexpired token is returned as-is; a token with no recorded expiry is treated as valid")
    func validTokenReturnedDirectly() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let (defaults, _) = makeTestDefaults()
        let store = MemorySecretStore()
        storeSession(in: store)
        let service = makeTestService(store: store, handler: { _ in ok("{}") }, home: home, defaults: defaults)
        #expect(await service.getValidAccessToken() == "stub-access-token")
        #expect(StubURLProtocol.requests.isEmpty)

        try? store.delete(GoogleSecretAccount.expiresAt)
        #expect(await service.getValidAccessToken() == "stub-access-token")
    }

    @Test("The synchronous accessor returns an unexpired token without a network call")
    func syncAccessorValidToken() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let (defaults, _) = makeTestDefaults()
        let store = MemorySecretStore()
        storeSession(in: store)
        let service = makeTestService(store: store, handler: { _ in ok("{}") }, home: home, defaults: defaults)
        #expect(service.getValidAccessTokenSync() == "stub-access-token")
        #expect(StubURLProtocol.requests.isEmpty)
    }

    @Test("An expired token refreshes through the stub and the store is updated")
    func expiredTokenRefreshes() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let (defaults, _) = makeTestDefaults()
        let store = MemorySecretStore()
        storeSession(in: store, expiresAt: Date().addingTimeInterval(-100).timeIntervalSince1970)
        let service = makeTestService(store: store, handler: { _ in ok(stubTokensStringExpiryJSON) }, home: home, defaults: defaults)
        #expect(await service.getValidAccessToken() == "stub-refreshed-token")
        #expect(store.readString(GoogleSecretAccount.accessToken) == "stub-refreshed-token")
        #expect(service.lastTokenRefreshError == nil)
        let newExpiry = Double(store.readString(GoogleSecretAccount.expiresAt) ?? "0") ?? 0
        #expect(newExpiry > Date().timeIntervalSince1970)
    }

    @Test("An expired token whose refresh fails returns nil and records the refresh failure (no dead token is served)")
    func expiredTokenRefreshFailureReturnsNil() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let (defaults, _) = makeTestDefaults()
        let store = MemorySecretStore()
        storeSession(in: store, expiresAt: Date().addingTimeInterval(-100).timeIntervalSince1970)
        let service = makeTestService(
            store: store,
            handler: { _ in tokenError(400, error: "invalid_grant", description: "Bad Request") },
            home: home, defaults: defaults)
        #expect(await service.getValidAccessToken() == nil)
        #expect(service.lastTokenRefreshError != nil)
    }

    @Test("No stored token and no ambient credentials returns nil")
    func noTokenReturnsNil() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let (defaults, _) = makeTestDefaults()
        let service = makeTestService(handler: { _ in ok("{}") }, home: home, defaults: defaults)
        #expect(await service.getValidAccessToken() == nil)
        #expect(service.getValidAccessTokenSync() == nil)
    }

    @Test("The callback exchange stores the tokens and email and signs in once tokeninfo accepts the token")
    func callbackExchangeSuccess() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let (defaults, _) = makeTestDefaults()
        let store = MemorySecretStore()
        let service = makeTestService(store: store, handler: { request in
            switch request.url?.path {
            case "/token": return ok(stubTokensJSON)
            case "/oauth2/v2/userinfo": return ok(stubUserinfoJSON)
            case "/oauth2/v3/tokeninfo": return ok("{}")
            default: return (404, [:], json("{}"))
            }
        }, home: home, defaults: defaults)
        let callback = URL(string: "http://127.0.0.1:8085/?code=auth-code-123&state=test-state")!
        await service.handleCallbackURL(callback, verifier: "test-verifier", state: "test-state", redirectURI: "http://127.0.0.1:8085")
        #expect(service.isAuthenticated)
        #expect(service.userEmail == "dylan@example.com")
        #expect(service.authError == nil)
        #expect(store.readString(GoogleSecretAccount.accessToken) == "stub-access-token")
        #expect(store.readString(GoogleSecretAccount.refreshToken) == "stub-refresh-token")
        #expect(store.readString(GoogleSecretAccount.userEmail) == "dylan@example.com")
        let expiry = Double(store.readString(GoogleSecretAccount.expiresAt) ?? "0") ?? 0
        #expect(expiry > Date().timeIntervalSince1970)
    }

    @Test("A callback whose state mismatches is rejected and signs no one in")
    func callbackStateMismatch() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let (defaults, _) = makeTestDefaults()
        let service = makeTestService(handler: { _ in ok("{}") }, home: home, defaults: defaults)
        let callback = URL(string: "http://127.0.0.1:8085/?code=auth-code-123&state=other-state")!
        await service.handleCallbackURL(callback, verifier: "test-verifier", state: "test-state", redirectURI: "http://127.0.0.1:8085")
        #expect(service.isAuthenticated == false)
        #expect(service.authError == "Security verification failed: OAuth state mismatch.")
        #expect(StubURLProtocol.requests.isEmpty)
    }

    @Test("A callback reporting an authorization error surfaces Google's error")
    func callbackAuthorizationError() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let (defaults, _) = makeTestDefaults()
        let service = makeTestService(handler: { _ in ok("{}") }, home: home, defaults: defaults)
        let callback = URL(string: "http://127.0.0.1:8085/?error=access_denied&state=test-state")!
        await service.handleCallbackURL(callback, verifier: "test-verifier", state: "test-state", redirectURI: "http://127.0.0.1:8085")
        #expect(service.isAuthenticated == false)
        #expect(service.authError == "Google authentication error: access_denied")
    }

    @Test("A callback whose exchange fails for a missing client secret names the fix")
    func callbackMissingClientSecret() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let (defaults, _) = makeTestDefaults()
        let service = makeTestService(
            handler: { _ in tokenError(400, error: "invalid_request", description: "client_secret is missing.") },
            home: home, defaults: defaults)
        let callback = URL(string: "http://127.0.0.1:8085/?code=auth-code-123&state=test-state")!
        await service.handleCallbackURL(callback, verifier: "test-verifier", state: "test-state", redirectURI: "http://127.0.0.1:8085")
        #expect(service.isAuthenticated == false)
        #expect(service.authError?.contains("Settings → Accounts → Google Account") == true)
    }

    @Test("A second callback for the same flow is ignored: the code is exchanged once")
    func callbackProcessedOnce() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let (defaults, _) = makeTestDefaults()
        let store = MemorySecretStore()
        let service = makeTestService(store: store, handler: { request in
            switch request.url?.path {
            case "/token": return ok(stubTokensJSON)
            case "/oauth2/v2/userinfo": return ok(stubUserinfoJSON)
            case "/oauth2/v3/tokeninfo": return ok("{}")
            default: return (404, [:], json("{}"))
            }
        }, home: home, defaults: defaults)
        let callback = URL(string: "http://127.0.0.1:8085/?code=auth-code-123&state=test-state")!
        await service.handleCallbackURL(callback, verifier: "test-verifier", state: "test-state", redirectURI: "http://127.0.0.1:8085")
        let exchangeCount = StubURLProtocol.requests.filter { $0.url?.path == "/token" }.count
        await service.handleCallbackURL(callback, verifier: "test-verifier", state: "test-state", redirectURI: "http://127.0.0.1:8085")
        #expect(StubURLProtocol.requests.filter { $0.url?.path == "/token" }.count == exchangeCount)
    }

    @Test("verifyRuntimeSession accepts a 200, and drops a 401 token whose refresh fails")
    func verifyRuntimeSession() async throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let (defaults, _) = makeTestDefaults()
        let store = MemorySecretStore()
        storeSession(in: store)
        let service = makeTestService(store: store, handler: { request in
            if request.url?.path == "/oauth2/v3/tokeninfo" { return ok("{}") }
            return (404, [:], json("{}"))
        }, home: home, defaults: defaults)
        #expect(await service.verifyRuntimeSession(accessToken: "stub-access-token") == true)

        let rejecting = makeTestService(store: store, handler: { request in
            if request.url?.path == "/oauth2/v3/tokeninfo" { return (401, [:], json("{}")) }
            if request.url?.path == "/token" {
                return tokenError(400, error: "invalid_grant", description: "Bad Request")
            }
            return (404, [:], json("{}"))
        }, home: home, defaults: defaults)
        #expect(await rejecting.verifyRuntimeSession(accessToken: "stub-access-token") == false)
        #expect(store.readString(GoogleSecretAccount.accessToken) == nil)
        #expect(rejecting.lastTokenRefreshError != nil)
    }

    @Test("Scope checks: unauthenticated is false; the retriever scope passes; a scope without it fails; no recorded scope passes")
    func requiredAssistScopes() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let (defaults, _) = makeTestDefaults()
        let store = MemorySecretStore()
        let service = makeTestService(handler: { _ in ok("{}") }, home: home, defaults: defaults)
        #expect(service.hasRequiredAssistScopes() == false)

        storeSession(in: store, scope: "openid https://www.googleapis.com/auth/userinfo.email")
        let narrow = makeTestService(store: store, handler: { _ in ok("{}") }, home: home, defaults: defaults,
                                     restoreSession: true)
        #expect(narrow.isAuthenticated)
        #expect(narrow.hasRequiredAssistScopes() == false)

        try? store.write(Data("https://www.googleapis.com/auth/generative-language.retriever".utf8),
                         for: GoogleSecretAccount.scope)
        #expect(narrow.hasRequiredAssistScopes() == true)

        try? store.delete(GoogleSecretAccount.scope)
        #expect(narrow.hasRequiredAssistScopes() == true)
    }

    @Test("The client secret round-trips through the store and reports its source")
    func clientSecretStorage() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let (defaults, _) = makeTestDefaults()
        let service = makeTestService(handler: { _ in ok("{}") }, home: home, defaults: defaults)
        #expect(service.hasClientSecret == false)
        #expect(service.hasKeychainClientSecret == false)
        service.setClientSecret("  fixture-secret  ")
        #expect(service.hasClientSecret == true)
        #expect(service.hasKeychainClientSecret == true)
        #expect(service.clientSecret == "fixture-secret")
        service.setClientSecret("   ")
        #expect(service.hasClientSecret == false)
        service.setClientSecret("fixture-secret")
        service.clearClientSecret()
        #expect(service.hasClientSecret == false)
    }

    @Test("The client secret also resolves from the environment")
    func clientSecretFromEnvironment() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let (defaults, _) = makeTestDefaults()
        let service = makeTestService(
            handler: { _ in ok("{}") }, home: home, defaults: defaults,
            environment: ["GOOGLE_CLIENT_SECRET": "env-secret"])
        #expect(service.clientSecret == "env-secret")
        #expect(service.hasKeychainClientSecret == false)
    }

    @Test("The client id resolves: environment wins, then the Settings override, then the built-in id")
    func clientIDResolution() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let (defaults, _) = makeTestDefaults()
        let plain = makeTestService(handler: { _ in ok("{}") }, home: home, defaults: defaults)
        #expect(plain.clientID == GoogleOAuthConfiguration.defaultClientID)

        defaults.set("override-client.apps.googleusercontent.com", forKey: GoogleDefaultsKey.clientIDOverride)
        #expect(plain.clientID == "override-client.apps.googleusercontent.com")

        let envService = makeTestService(
            handler: { _ in ok("{}") }, home: home, defaults: defaults,
            environment: ["GOOGLE_CLIENT_ID": "env-client.apps.googleusercontent.com"])
        #expect(envService.clientID == "env-client.apps.googleusercontent.com")
    }

    @Test("handleOpenURL accepts the flow's URLs and rejects unrelated ones")
    func handleOpenURL() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let (defaults, _) = makeTestDefaults()
        let service = makeTestService(handler: { _ in ok("{}") }, home: home, defaults: defaults)
        #expect(service.handleOpenURL(URL(string: "swiftcode://oauth-callback?code=x&state=y")!) == true)
        #expect(service.handleOpenURL(URL(string: "http://127.0.0.1:8085/?code=x&state=y")!) == true)
        #expect(service.handleOpenURL(URL(string: "https://example.com/callback")!) == false)
        #expect(service.handleOpenURL(URL(string: "otherapp://open")!) == false)
    }

    #if !canImport(AuthenticationServices)
    @Test("On a platform without ASWebAuthenticationSession, sign-in fails honestly instead of opening a browser")
    func signInFailsHonestlyWithoutBrowserSession() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let (defaults, _) = makeTestDefaults()
        let service = makeTestService(handler: { _ in ok("{}") }, home: home, defaults: defaults)
        service.signIn()
        #expect(service.isAuthenticating == false)
        #expect(service.isAuthenticated == false)
        #expect(service.authError == GoogleAuthError.browserSignInUnavailable.errorDescription)
    }
    #endif
}
