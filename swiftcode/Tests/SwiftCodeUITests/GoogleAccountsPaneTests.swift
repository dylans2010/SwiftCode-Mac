import AppKit
import Foundation
import Testing
import SwiftCodeAssistant
@testable import SwiftCodeCloud
@testable import SwiftCodeGoogleAuth
@testable import SwiftCodeIDECore
@testable import SwiftCodeUI

// The Google account section of Settings ▸ Accounts
// (specs/ide/cloud-accounts.md §10): the signed-in email and
// Assist-scope status, the client id/secret actions, and sign-out.
// The browser sign-in itself is never driven here — on macOS it
// would open a real `ASWebAuthenticationSession`. All fixtures are
// synthetic; no live network, no real credentials, and the secret
// store is always a MemorySecretStore, never the keychain. The
// Antigravity and gcloud seams are neutralized, so tests never
// touch the real keychain or CLI.

@MainActor
@Suite(.serialized) struct GoogleAccountsPaneTests {

    private func makeGoogleService(
        store: MemorySecretStore = MemorySecretStore(),
        home: URL,
        defaults: UserDefaults
    ) -> GoogleAccountAuthService {
        CloudAccountsStubURLProtocol.requests = []
        CloudAccountsStubURLProtocol.handler = { request in
            switch request.url?.path {
            case "/token":
                return CloudAccountsStubURLProtocol.ok(
                    "{\"access_token\":\"stub-access-token\",\"expires_in\":3600,"
                    + "\"refresh_token\":\"stub-refresh-token\",\"scope\":\"openid\",\"token_type\":\"Bearer\"}")
            case "/oauth2/v2/userinfo":
                return CloudAccountsStubURLProtocol.ok("{\"email\":\"dylan@example.com\"}")
            case "/oauth2/v3/tokeninfo":
                return CloudAccountsStubURLProtocol.ok("{}")
            default:
                return CloudAccountsStubURLProtocol.ok("{}")
            }
        }
        return GoogleAccountAuthService(
            store: store,
            session: CloudAccountsStubURLProtocol.stubSession(),
            tokenClient: GoogleTokenClient(session: CloudAccountsStubURLProtocol.stubSession()),
            environment: [:],
            homeDirectory: home,
            userDefaults: defaults,
            antigravityFetcher: { nil },
            gcloudTokenProvider: { _ in nil },
            restoreSession: false)
    }

    private func makePane(google: GoogleAccountAuthService, defaults: UserDefaults) -> AccountsSettingsPane {
        let auth = CloudAuthManager(
            client: AppwriteAccountClient(session: CloudAccountsStubURLProtocol.stubSession()),
            store: MemorySecretStore())
        return AccountsSettingsPane(
            prefs: Preferences(defaults: defaults), authManager: auth,
            cloudManager: CloudManager(authManager: auth),
            syncEngine: CloudSyncEngine(testAuthManager: auth),
            googleAuthService: google)
    }

    private func makeTempHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("GoogleAccountsPaneTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    private func storeGoogleSession(in store: MemorySecretStore, scope: String) {
        try? store.write(Data("stub-access-token".utf8), for: GoogleSecretAccount.accessToken)
        try? store.write(Data(String(Date().addingTimeInterval(3600).timeIntervalSince1970).utf8),
                         for: GoogleSecretAccount.expiresAt)
        try? store.write(Data("stub-refresh-token".utf8), for: GoogleSecretAccount.refreshToken)
        try? store.write(Data(scope.utf8), for: GoogleSecretAccount.scope)
        try? store.write(Data("dylan@example.com".utf8), for: GoogleSecretAccount.userEmail)
    }

    @Test("Signed out, the pane shows the Google section with sign-in and agy CLI buttons")
    func paneGoogleSignedOut() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let td = TestDefaults("google-accounts-signed-out")
        defer { td.remove() }
        let google = makeGoogleService(home: home, defaults: td.defaults)
        let pane = makePane(google: google, defaults: td.defaults)
        _ = pane.view
        #expect(pane.googleRestoreAttempted == true)
        #expect(pane.rowTitles.contains("# Google Account"))
        #expect(pane.control(NSButton.self, inRow: "Sign in with Google") != nil)
        #expect(pane.control(NSButton.self, inRow: "Sign in via agy CLI") != nil)
        #expect(AccountsSettingsPane.googleExplanation.contains("only OAuth tokens in the Keychain"))
    }

    @Test("Signed in, the pane shows the email and the Assist-scope status")
    func paneGoogleSignedIn() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let td = TestDefaults("google-accounts-signed-in")
        defer { td.remove() }
        let store = MemorySecretStore()
        storeGoogleSession(in: store, scope: "https://www.googleapis.com/auth/generative-language.retriever openid")
        let google = makeGoogleService(store: store, home: home, defaults: td.defaults)
        let pane = makePane(google: google, defaults: td.defaults)
        _ = pane.view
        #expect(google.isAuthenticated)
        let email = pane.rowView("Signed in as")?.controls.first as? NSTextField
        #expect(email?.stringValue == "dylan@example.com")
        let scopes = pane.rowView("Assist scopes")?.controls.first as? NSTextField
        #expect(scopes?.stringValue == AccountsSettingsPane.googleScopesReadyText)
        #expect(pane.control(NSButton.self, inRow: "Sign Out") != nil)
    }

    @Test("A session without the Assist scopes shows the re-authentication status and button")
    func paneGoogleScopesMissing() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let td = TestDefaults("google-accounts-scopes-missing")
        defer { td.remove() }
        let store = MemorySecretStore()
        storeGoogleSession(in: store, scope: "openid https://www.googleapis.com/auth/userinfo.email")
        let google = makeGoogleService(store: store, home: home, defaults: td.defaults)
        let pane = makePane(google: google, defaults: td.defaults)
        _ = pane.view
        let scopes = pane.rowView("Assist scopes")?.controls.first as? NSTextField
        #expect(scopes?.stringValue == AccountsSettingsPane.googleScopesMissingText)
        #expect(pane.control(NSButton.self, inRow: "Re-authenticate for Assist Scopes") != nil)
    }

    @Test("Saving the client secret stores it; saving an empty secret clears it")
    func saveClientSecret() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let td = TestDefaults("google-accounts-secret")
        defer { td.remove() }
        let google = makeGoogleService(home: home, defaults: td.defaults)
        let pane = makePane(google: google, defaults: td.defaults)
        pane.saveGoogleClientSecret("fixture-secret")
        #expect(google.hasKeychainClientSecret == true)
        #expect(google.clientSecret == "fixture-secret")
        pane.saveGoogleClientSecret("")
        #expect(google.hasClientSecret == false)
    }

    @Test("Saving the client-id override writes the defaults key and the service resolves it")
    func saveClientIDOverride() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let td = TestDefaults("google-accounts-client-id")
        defer { td.remove() }
        let google = makeGoogleService(home: home, defaults: td.defaults)
        let pane = makePane(google: google, defaults: td.defaults)
        pane.saveGoogleClientIDOverride("override-client.apps.googleusercontent.com")
        #expect(td.defaults.string(forKey: GoogleDefaultsKey.clientIDOverride)
            == "override-client.apps.googleusercontent.com")
        #expect(google.clientID == "override-client.apps.googleusercontent.com")
        pane.saveGoogleClientIDOverride("")
        #expect(google.clientID == GoogleOAuthConfiguration.defaultClientID)
    }

    @Test("Sign-out from the pane clears the Google session")
    func paneSignOutGoogle() throws {
        let home = try makeTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        let td = TestDefaults("google-accounts-sign-out")
        defer { td.remove() }
        let store = MemorySecretStore()
        storeGoogleSession(in: store, scope: "openid")
        let google = makeGoogleService(store: store, home: home, defaults: td.defaults)
        let pane = makePane(google: google, defaults: td.defaults)
        _ = pane.view
        #expect(google.isAuthenticated)
        pane.signOutGoogle()
        #expect(google.isAuthenticated == false)
        #expect(store.readString(GoogleSecretAccount.accessToken) == nil)
    }
}
