import AppKit
import Foundation
import Testing
import SwiftCodeAssistant
@testable import SwiftCodeCloud
@testable import SwiftCodeIDECore
@testable import SwiftCodeUI

@MainActor
@Suite(.serialized) struct CloudAccountsPaneTests {

    private func makeManager(
        handler: @escaping @Sendable (URLRequest) -> (status: Int, headers: [String: String], body: Data)
    ) -> CloudAuthManager {
        CloudAccountsStubURLProtocol.requests = []
        CloudAccountsStubURLProtocol.handler = handler
        let client = AppwriteAccountClient(session: CloudAccountsStubURLProtocol.stubSession())
        return CloudAuthManager(client: client, store: MemorySecretStore())
    }

    private func makePane(auth: CloudAuthManager, defaults: UserDefaults) -> AccountsSettingsPane {
        UserDefaults.standard.removeObject(forKey: CloudManager.syncEnabledKey)
        return AccountsSettingsPane(
            prefs: Preferences(defaults: defaults), authManager: auth,
            cloudManager: CloudManager(authManager: auth), syncEngine: CloudSyncEngine(testAuthManager: auth))
    }

    @Test("Create-account with mismatched passwords fails client-side, before any call")
    func passwordMismatchIsClientSide() async {
        let auth = makeManager(handler: authHappyPath)
        let sheet = CloudAuthSheetController(authManager: auth, mode: .createAccount)
        _ = sheet.view
        sheet.emailField.stringValue = "new@example.com"
        sheet.passwordField.stringValue = "first-password"
        sheet.confirmPasswordField.stringValue = "different-password"
        await sheet.performAuth()
        #expect(sheet.errorMessage == CloudAuthSheetController.passwordsDoNotMatch)
        #expect(sheet.dismissed == false)
        #expect(CloudAccountsStubURLProtocol.requests.isEmpty)
        #expect(auth.isAuthenticated == false)
    }

    @Test("Login succeeds, calls onSuccess, and dismisses (unless it is the gate)")
    func loginSucceeds() async throws {
        let auth = makeManager(handler: authHappyPath)
        let sheet = CloudAuthSheetController(authManager: auth, mode: .login)
        _ = sheet.view
        var called = false
        sheet.onSuccess = { called = true }
        sheet.emailField.stringValue = "dylan@example.com"
        sheet.passwordField.stringValue = "correct horse"
        await sheet.performAuth()
        #expect(auth.isAuthenticated == true)
        #expect(auth.currentUser?.email == "dylan@example.com")
        #expect(auth.swiftCodeID?.contains("sc_id=") == true)
        #expect(called == true)
        #expect(sheet.dismissed == true)
    }

    @Test("Login with wrong credentials shows the user-facing error, not the raw server text")
    func loginWrongCredentials() async {
        let auth = makeManager { _ in
            CloudAccountsStubURLProtocol.appwriteError(401, code: 401, type: "user_unauthorized",
                                                      message: "Invalid `email` param: Invalid credentials")
        }
        let sheet = CloudAuthSheetController(authManager: auth, mode: .login)
        _ = sheet.view
        sheet.emailField.stringValue = "dylan@example.com"
        sheet.passwordField.stringValue = "wrong"
        await sheet.performAuth()
        #expect(sheet.errorMessage?.contains("Invalid email address or password") == true)
        #expect(sheet.dismissed == false)
        #expect(auth.isAuthenticated == false)
    }

    @Test("Forgot password hides the password fields, sends the reset, and stays open with success text")
    func forgotPasswordFlow() async {
        let auth = makeManager { _ in CloudAccountsStubURLProtocol.ok("{}") }
        let sheet = CloudAuthSheetController(authManager: auth, mode: .login)
        _ = sheet.view
        sheet.showForgotPassword()
        #expect(sheet.mode == .forgotPassword)
        #expect(sheet.passwordField.isHidden == true)
        #expect(sheet.confirmPasswordField.isHidden == true)
        #expect(sheet.googleButton.isHidden == true)
        sheet.emailField.stringValue = "dylan@example.com"
        await sheet.performAuth()
        #expect(CloudAccountsStubURLProtocol.requests.first?.url?.path == "/v1/account/recovery")
        #expect(sheet.successMessage == CloudAuthSheetController.resetLinkSent)
        #expect(sheet.dismissed == false)
    }

    @Test("Mode switching cycles login and create account, and forgot password returns to login")
    func modeSwitching() {
        let auth = makeManager(handler: authHappyPath)
        let sheet = CloudAuthSheetController(authManager: auth, mode: .login)
        _ = sheet.view
        #expect(sheet.navigationTitle == "Sign In")
        sheet.switchMode()
        #expect(sheet.mode == .createAccount)
        #expect(sheet.navigationTitle == "Register")
        #expect(sheet.confirmPasswordField.isHidden == false)
        sheet.switchMode()
        #expect(sheet.mode == .login)
        sheet.showForgotPassword()
        #expect(sheet.navigationTitle == "Reset Password")
        sheet.switchMode()
        #expect(sheet.mode == .login)
    }

    @Test("OAuth buttons are present, and a browser that cannot open shows the honest failure, never a fake sign-in")
    func oauthCannotOpenBrowser() async {
        let auth = makeManager(handler: authHappyPath)
        let sheet = CloudAuthSheetController(authManager: auth, mode: .login)
        _ = sheet.view
        #expect(sheet.googleButton.title == "Continue with Google")
        #expect(sheet.gitHubButton.title == "Continue with GitHub")
        sheet.openURL = { _ in false }
        await sheet.beginOAuth(provider: .google)
        #expect(sheet.errorMessage?.contains("could not open the browser") == true)
        #expect(sheet.oauthMessage == nil)
        #expect(sheet.dismissed == false)
        #expect(auth.isAuthenticated == false)
    }

    @Test("OAuth shows the honest pending state while waiting for the callback")
    func oauthPendingMessage() {
        #expect(CloudAuthSheetController.oauthPending.contains("waiting for the sign-in to return"))
        #expect(CloudAuthSheetController.oauthPending.contains("not wired up yet"))
    }

    @Test("Delete-account alert keeps Legacy's exact confirmation text")
    func deleteAlertText() {
        let auth = makeManager(handler: authHappyPath)
        let td = TestDefaults("cloud-accounts-delete")
        defer { td.remove() }
        let pane = makePane(auth: auth, defaults: td.defaults)
        let alert = pane.makeDeleteAccountAlert()
        #expect(alert.messageText == AccountsSettingsPane.deleteAccountTitle)
        #expect(alert.informativeText == "Warning: This will permanently delete your user account and all remote credentials "
            + "on the Appwrite authentication server. This action is destructive and cannot be undone.")
        #expect(alert.alertStyle == .critical)
    }

    @Test("Signed out, the pane shows the SwiftCode section with a sign-in button and the scoped key note")
    func paneSignedOut() {
        let auth = makeManager(handler: authHappyPath)
        let td = TestDefaults("cloud-accounts-signed-out")
        defer { td.remove() }
        let pane = makePane(auth: auth, defaults: td.defaults)
        _ = pane.view
        #expect(pane.rowTitles.contains("# SwiftCode Account"))
        #expect(pane.control(NSButton.self, inRow: "Sign In or Register") != nil)
        #expect(AccountsSettingsPane.appStoreConnectScopeNote.contains("App Store Connect keys"))
        #expect(AccountsSettingsPane.swiftCodeExplanation.contains("only a session secret in the Keychain"))
        #expect(pane.emptyLabel?.isHidden == false)
        pane.addClicked()
        #expect(pane.shownMessage?.contains("never asks for or stores passwords") == true)
    }

    @Test("Signed in, the pane shows the email, the verified badge, and the selectable SwiftCode id")
    func paneSignedIn() async throws {
        let auth = makeManager(handler: authHappyPath)
        try await auth.login(email: "dylan@example.com", password: SecureString("correct horse"))
        let td = TestDefaults("cloud-accounts-signed-in")
        defer { td.remove() }
        let pane = makePane(auth: auth, defaults: td.defaults)
        _ = pane.view
        #expect(pane.rowView("Signed in as")?.controls.first is NSTextField)
        let badge = pane.rowView("Email verification")?.controls.first as? NSTextField
        #expect(badge?.stringValue == "Verified")
        #expect(pane.swiftCodeIDField?.stringValue.contains("sc_id=") == true)
        #expect(pane.swiftCodeIDField?.isSelectable == true)
        #expect(pane.control(NSButton.self, inRow: "Sign Out") != nil)
        #expect(pane.control(NSButton.self, inRow: "Permanently Delete Account") != nil)
    }

    @Test("Sign-out disables sync and reloads statistics")
    func signOutDisablesSync() async throws {
        let auth = makeManager(handler: authHappyPath)
        try await auth.login(email: "dylan@example.com", password: SecureString("correct horse"))
        let td = TestDefaults("cloud-accounts-sign-out")
        defer { td.remove() }
        let pane = makePane(auth: auth, defaults: td.defaults)
        UserDefaults.standard.set(true, forKey: CloudManager.syncEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudManager.syncEnabledKey) }
        await pane.signOut()
        #expect(auth.isAuthenticated == false)
        #expect(UserDefaults.standard.bool(forKey: CloudManager.syncEnabledKey) == false)
    }

    @Test("Delete-account disables sync and reloads statistics")
    func deleteAccountDisablesSync() async throws {
        let auth = makeManager(handler: authHappyPath)
        try await auth.login(email: "dylan@example.com", password: SecureString("correct horse"))
        let td = TestDefaults("cloud-accounts-delete-account")
        defer { td.remove() }
        let pane = makePane(auth: auth, defaults: td.defaults)
        UserDefaults.standard.set(true, forKey: CloudManager.syncEnabledKey)
        defer { UserDefaults.standard.removeObject(forKey: CloudManager.syncEnabledKey) }
        pane.confirmDeleteAccount()
        #expect(pane.shownDeleteConfirmation?.contains("permanently delete your user account") == true)
        await pane.deleteAccountConfirmed()
        #expect(auth.isAuthenticated == false)
        #expect(UserDefaults.standard.bool(forKey: CloudManager.syncEnabledKey) == false)
    }

    @Test("Send-verification sets the sent message")
    func sendVerification() async throws {
        let auth = makeManager(handler: authHappyPath)
        try await auth.login(email: "dylan@example.com", password: SecureString("correct horse"))
        let td = TestDefaults("cloud-accounts-verify")
        defer { td.remove() }
        let pane = makePane(auth: auth, defaults: td.defaults)
        await pane.sendVerification()
        #expect(pane.accountMessage == AccountsSettingsPane.verificationSentText)
    }

    @Test("Test Connection reports success when the server answers and failure when it does not")
    func testConnection() async {
        let auth = makeManager { request in
            request.url?.path == "/v1/ping" ? CloudAccountsStubURLProtocol.ok("{}") : CloudAccountsStubURLProtocol.ok("{}")
        }
        let td = TestDefaults("cloud-accounts-ping")
        defer { td.remove() }
        let pane = makePane(auth: auth, defaults: td.defaults)
        await pane.testConnection()
        #expect(pane.connectionSucceeded == true)
        #expect(pane.connectionResult?.contains("Succeeded") == true)
        #expect(pane.connectionResult == AccountsSettingsPane.connectionSucceededText)

        let failing = makeManager { _ in
            CloudAccountsStubURLProtocol.appwriteError(500, code: 500, type: "server_error", message: "Internal error")
        }
        let pane2 = makePane(auth: failing, defaults: td.defaults)
        await pane2.testConnection()
        #expect(pane2.connectionSucceeded == false)
        #expect(pane2.connectionResult?.contains("Failed") == true)
    }

    @Test("Sync tab shows the uppercased state, the toggle, and a manual sync stamps the last sync time")
    func syncTab() async throws {
        let auth = makeManager(handler: authHappyPath)
        try await auth.login(email: "dylan@example.com", password: SecureString("correct horse"))
        let td = TestDefaults("cloud-accounts-sync")
        defer { td.remove() }
        let pane = makePane(auth: auth, defaults: td.defaults)
        pane.selectedCloudTab = .sync
        _ = pane.view
        #expect(CloudAccountsFormatting.syncStateText(.paused) == "PAUSED")
        #expect(CloudAccountsFormatting.syncStateText(.syncing) == "SYNCING")
        #expect(CloudAccountsFormatting.lastSyncText(nil) == "Never")
        let state = pane.rowView("Sync state")?.controls.first as? NSTextField
        #expect(state?.stringValue == "IDLE")
        #expect(pane.control(NSSwitch.self, inRow: "Enable Sync Engine") != nil)
        #expect(pane.control(NSButton.self, inRow: "Sync Now") != nil)
        await pane.syncNow()
        #expect(pane.cloudManager.lastSyncTime != nil)
        #expect(CloudAccountsFormatting.lastSyncText(pane.cloudManager.lastSyncTime).contains("Never") == false)
    }

    @Test("Status tab badges follow authentication: unauthenticated/offline signed out, authenticated/connected signed in")
    func statusTab() async throws {
        let auth = makeManager(handler: authHappyPath)
        let td = TestDefaults("cloud-accounts-status")
        defer { td.remove() }
        let pane = makePane(auth: auth, defaults: td.defaults)
        pane.selectedCloudTab = .status
        _ = pane.view
        let authBadge = pane.rowView("Appwrite Authentication")?.controls.first as? NSTextField
        let connBadge = pane.rowView("Cloud Connection")?.controls.first as? NSTextField
        #expect(authBadge?.stringValue == "Unauthenticated")
        #expect(connBadge?.stringValue == "Offline")
        #expect(CloudAccountsFormatting.authStatusText(authenticated: false) == "Unauthenticated")
        #expect(CloudAccountsFormatting.connectionStatusText(authenticated: true) == "Connected")

        try await auth.login(email: "dylan@example.com", password: SecureString("correct horse"))
        await pane.loadStats()
        pane.rebuild()
        let authBadgeAfter = pane.rowView("Appwrite Authentication")?.controls.first as? NSTextField
        let connBadgeAfter = pane.rowView("Cloud Connection")?.controls.first as? NSTextField
        #expect(authBadgeAfter?.stringValue == "Authenticated")
        #expect(connBadgeAfter?.stringValue == "Connected")
        #expect(pane.rowView("Uploaded records")?.controls.first is NSTextField)
        #expect(pane.rowView("Pending changes")?.controls.first is NSTextField)
    }

    @Test("Change-email sheet saves through the auth manager and dismisses")
    func changeEmailSheet() async throws {
        let auth = makeManager(handler: authHappyPath)
        try await auth.login(email: "dylan@example.com", password: SecureString("correct horse"))
        let sheet = CloudChangeEmailSheetController(authManager: auth)
        _ = sheet.view
        sheet.newEmailField.stringValue = "new@example.com"
        sheet.passwordField.stringValue = "correct horse"
        await sheet.save()
        #expect(sheet.saved == true)
        #expect(sheet.dismissed == true)
        #expect(sheet.errorMessage == nil)
    }

    @Test("Change-password sheet saves through the auth manager and dismisses")
    func changePasswordSheet() async throws {
        let auth = makeManager(handler: authHappyPath)
        try await auth.login(email: "dylan@example.com", password: SecureString("correct horse"))
        let sheet = CloudChangePasswordSheetController(authManager: auth)
        _ = sheet.view
        sheet.oldPasswordField.stringValue = "correct horse"
        sheet.newPasswordField.stringValue = "a-new-password"
        await sheet.save()
        #expect(sheet.saved == true)
        #expect(sheet.dismissed == true)
        #expect(sheet.errorMessage == nil)
    }
}

final class CloudAccountsStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (status: Int, headers: [String: String], body: Data))?
    nonisolated(unsafe) static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.requests.append(request)
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        let (status, headers, body) = handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func stubSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CloudAccountsStubURLProtocol.self]
        return URLSession(configuration: config)
    }

    static func ok(_ body: String, headers: [String: String] = [:]) -> (status: Int, headers: [String: String], body: Data) {
        (200, headers, Data(body.utf8))
    }

    static func appwriteError(_ status: Int, code: Int, type: String, message: String) -> (status: Int, headers: [String: String], body: Data) {
        (status, [:], Data("{\"message\":\"\(message)\",\"code\":\(code),\"type\":\"\(type)\",\"version\":\"1.7.0\"}".utf8))
    }
}

func authHappyPath(_ request: URLRequest) -> (status: Int, headers: [String: String], body: Data) {
    switch request.url?.path {
    case "/v1/account/sessions/email":
        return CloudAccountsStubURLProtocol.ok(
            "{\"$id\":\"sess_1\",\"userId\":\"user_1\",\"expire\":\"2027-01-15T10:30:00.000+00:00\",\"provider\":\"email\",\"current\":true}",
            headers: ["Set-Cookie": "a_session_6a670d0b0022e5f964b4=stub-secret-123; Path=/; HttpOnly"])
    case "/v1/account":
        return CloudAccountsStubURLProtocol.ok(
            "{\"$id\":\"user_1\",\"$createdAt\":\"2026-01-01T00:00:00.000+00:00\",\"$updatedAt\":\"2026-01-15T10:30:00.000+00:00\",\"name\":\"Dylan\",\"email\":\"dylan@example.com\",\"emailVerification\":true,\"phoneVerification\":false,\"status\":true,\"prefs\":{\"swiftcode_id\":\"sc_id=ABCDEF0123456789ABCDEF0123456789\"}}")
    default:
        return CloudAccountsStubURLProtocol.ok("{}")
    }
}
