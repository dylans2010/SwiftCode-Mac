import AppKit
import Foundation
import SwiftUI
import YcodeAssistant
import SwiftCodeCloud
import SwiftCodeGitHub
import YcodeIDECore

public enum CloudAccountsTab: Int, CaseIterable, Sendable {
    case account
    case sync
    case status

    public var title: String {
        switch self {
        case .account: return "Account"
        case .sync: return "Sync"
        case .status: return "Status"
        }
    }
}

public enum CloudAccountsFormatting {
    public static func syncStateText(_ state: SyncState) -> String { state.rawValue.uppercased() }

    public static func lastSyncText(_ date: Date?) -> String {
        date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never"
    }

    public static func verificationText(verified: Bool) -> String { verified ? "Verified" : "Unverified" }

    public static func authStatusText(authenticated: Bool) -> String { authenticated ? "Authenticated" : "Unauthenticated" }

    public static func connectionStatusText(authenticated: Bool) -> String { authenticated ? "Connected" : "Offline" }
}

@MainActor
public final class CloudAuthSheetController: NSViewController {
    public enum Mode {
        case login
        case createAccount
        case forgotPassword
    }

    public static let passwordsDoNotMatch = "Passwords do not match."
    public static let resetLinkSent = "A password reset link has been successfully dispatched to your email."
    public static let oauthPending = "Continue in your browser… SwiftCode is waiting for the sign-in to return. "
        + "The app callback for this flow is not wired up yet, so the wait will time out instead of completing."

    public let authManager: CloudAuthManager
    public private(set) var mode: Mode
    public let isGate: Bool
    public var onSuccess: (() -> Void)?
    public var openURL: @Sendable (URL) -> Bool = { NSWorkspace.shared.open($0) }

    public private(set) var emailField = NSTextField()
    public private(set) var passwordField = NSSecureTextField()
    public private(set) var confirmPasswordField = NSSecureTextField()
    public private(set) var errorLabel = NSTextField(wrappingLabelWithString: "")
    public private(set) var successLabel = NSTextField(wrappingLabelWithString: "")
    public private(set) var oauthLabel = NSTextField(wrappingLabelWithString: "")
    public private(set) var googleButton = NSButton()
    public private(set) var gitHubButton = NSButton()
    public private(set) var primaryButton = NSButton()
    public private(set) var modeButton = NSButton()
    public private(set) var forgotButton = NSButton()
    public private(set) var cancelButton = NSButton()

    public private(set) var errorMessage: String?
    public private(set) var successMessage: String?
    public private(set) var oauthMessage: String?
    public private(set) var isLoading = false
    public private(set) var dismissed = false

    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(wrappingLabelWithString: "")

    public init(authManager: CloudAuthManager, mode: Mode = .login, isGate: Bool = false) {
        self.authManager = authManager
        self.mode = mode
        self.isGate = isGate
        super.init(nibName: nil, bundle: nil)
        emailField.placeholderString = "name@example.com"
        passwordField.placeholderString = "Enter secure password"
        confirmPasswordField.placeholderString = "Re-enter secure password"
        errorLabel.textColor = .systemRed
        successLabel.textColor = .systemGreen
        oauthLabel.textColor = .secondaryLabelColor
        titleLabel.font = .boldSystemFont(ofSize: 15)
        subtitleLabel.textColor = .secondaryLabelColor
        googleButton = makeButton("Continue with Google") { [weak self] in Task { await self?.beginOAuth(provider: .google) } }
        gitHubButton = makeButton("Continue with GitHub") { [weak self] in Task { await self?.beginOAuth(provider: .github) } }
        primaryButton = makeButton(actionButtonTitle) { [weak self] in Task { await self?.performAuth() } }
        modeButton = makeButton(modeButtonTitle) { [weak self] in self?.switchMode() }
        modeButton.bezelStyle = .inline
        forgotButton = makeButton("Forgot password?") { [weak self] in self?.showForgotPassword() }
        forgotButton.bezelStyle = .inline
        cancelButton = makeButton("Cancel") { [weak self] in self?.dismissSheet() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func makeButton(_ title: String, _ action: @escaping () -> Void) -> NSButton {
        let b = ClosureButton(title: title, target: nil, action: nil)
        b.bezelStyle = .rounded
        b.onChange = { _ in action() }
        return b
    }

    public override func loadView() {
        let root = NSView()
        root.frame = NSRect(x: 0, y: 0, width: 460, height: 520)
        let stack = NSStackView(views: [titleLabel, subtitleLabel, emailField, passwordField, confirmPasswordField,
                                        errorLabel, successLabel, oauthLabel, primaryButton,
                                        googleButton, gitHubButton, modeButton, forgotButton, cancelButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor), stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            emailField.widthAnchor.constraint(equalToConstant: 420),
            passwordField.widthAnchor.constraint(equalToConstant: 420),
            confirmPasswordField.widthAnchor.constraint(equalToConstant: 420),
        ])
        view = root
        updateModeViews()
    }

    public var navigationTitle: String {
        switch mode {
        case .login: return "Sign In"
        case .createAccount: return "Register"
        case .forgotPassword: return "Reset Password"
        }
    }

    private var headerTitle: String {
        switch mode {
        case .login: return "Welcome to SwiftCode"
        case .createAccount: return "Create Cloud Account"
        case .forgotPassword: return "Recover Account"
        }
    }

    private var headerSubtitle: String {
        switch mode {
        case .login: return "Access secure cloud synchronization and automatic backups for all your developer tools."
        case .createAccount: return "Unlock real-time synchronization, template sharing, and on-device offline models metadata syncing."
        case .forgotPassword: return "Enter your registered email address and we will dispatch a secure link to reset your account password."
        }
    }

    private var actionButtonTitle: String {
        switch mode {
        case .login: return "Sign In with Password"
        case .createAccount: return "Register Secure Account"
        case .forgotPassword: return "Send Password Reset Link"
        }
    }

    private var modeButtonTitle: String {
        switch mode {
        case .login: return "Don't have an account? Sign Up"
        case .createAccount: return "Already registered? Sign In"
        case .forgotPassword: return "Back to Sign In"
        }
    }

    public func updateModeViews() {
        titleLabel.stringValue = headerTitle
        subtitleLabel.stringValue = headerSubtitle
        primaryButton.title = actionButtonTitle
        modeButton.title = modeButtonTitle
        passwordField.isHidden = mode == .forgotPassword
        confirmPasswordField.isHidden = mode != .createAccount
        googleButton.isHidden = mode == .forgotPassword
        gitHubButton.isHidden = mode == .forgotPassword
        forgotButton.isHidden = mode != .login
        cancelButton.isHidden = isGate
        preferredContentSize = NSSize(width: 460, height: mode == .forgotPassword ? 420 : 560)
        updateLabels()
    }

    private func updateLabels() {
        errorLabel.stringValue = errorMessage ?? ""
        errorLabel.isHidden = errorMessage == nil
        successLabel.stringValue = successMessage ?? ""
        successLabel.isHidden = successMessage == nil
        oauthLabel.stringValue = oauthMessage ?? ""
        oauthLabel.isHidden = oauthMessage == nil
        primaryButton.isEnabled = !isLoading
        googleButton.isEnabled = !isLoading
        gitHubButton.isEnabled = !isLoading
    }

    public func switchMode() {
        errorMessage = nil
        successMessage = nil
        oauthMessage = nil
        switch mode {
        case .login: mode = .createAccount
        case .createAccount: mode = .login
        case .forgotPassword: mode = .login
        }
        if isViewLoaded { updateModeViews() }
    }

    public func showForgotPassword() {
        errorMessage = nil
        successMessage = nil
        oauthMessage = nil
        mode = .forgotPassword
        if isViewLoaded { updateModeViews() }
    }

    public func performAuth() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        successMessage = nil
        oauthMessage = nil
        updateLabels()

        let email = emailField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if mode == .createAccount, passwordField.stringValue != confirmPasswordField.stringValue {
            errorMessage = Self.passwordsDoNotMatch
            isLoading = false
            updateLabels()
            return
        }

        do {
            switch mode {
            case .login:
                try await authManager.login(email: email, password: SecureString(passwordField.stringValue))
                onSuccess?()
                if !isGate { dismissSheet() }
            case .createAccount:
                try await authManager.createAccount(email: email, password: SecureString(passwordField.stringValue))
                onSuccess?()
                if !isGate { dismissSheet() }
            case .forgotPassword:
                try await authManager.forgotPassword(email: email)
                successMessage = Self.resetLinkSent
            }
        } catch {
            errorMessage = authManager.authError
                ?? (error as? AppwriteError)?.userFacingMessage
                ?? error.localizedDescription
        }
        isLoading = false
        updateLabels()
    }

    public func beginOAuth(provider: AppwriteOAuthProvider) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        successMessage = nil
        oauthMessage = Self.oauthPending
        updateLabels()
        do {
            _ = try await authManager.beginOAuth(provider: provider, openURL: openURL)
            oauthMessage = nil
            onSuccess?()
            if !isGate { dismissSheet() }
        } catch {
            oauthMessage = nil
            errorMessage = authManager.authError
                ?? (error as? AppwriteError)?.userFacingMessage
                ?? error.localizedDescription
        }
        isLoading = false
        updateLabels()
    }

    public func dismissSheet() {
        dismissed = true
        if presentingViewController != nil { dismiss(nil) }
    }
}

@MainActor
public final class CloudChangeEmailSheetController: NSViewController {
    public let authManager: CloudAuthManager
    public var onSuccess: (() -> Void)?
    public private(set) var newEmailField = NSTextField()
    public private(set) var passwordField = NSSecureTextField()
    public private(set) var errorLabel = NSTextField(wrappingLabelWithString: "")
    public private(set) var errorMessage: String?
    public private(set) var saved = false
    public private(set) var dismissed = false
    private let saveButton: NSButton

    public init(authManager: CloudAuthManager) {
        self.authManager = authManager
        let save = ClosureButton(title: "Save Email", target: nil, action: nil)
        save.bezelStyle = .rounded
        self.saveButton = save
        super.init(nibName: nil, bundle: nil)
        save.onChange = { [weak self] _ in Task { await self?.save() } }
        newEmailField.placeholderString = "New Email Address"
        passwordField.placeholderString = "Current Password"
        errorLabel.textColor = .systemRed
        errorLabel.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public override func loadView() {
        let stack = NSStackView(views: [NSTextField(labelWithString: "Change Email Address"), newEmailField, passwordField,
                                        errorLabel, saveButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let root = NSView()
        root.frame = NSRect(x: 0, y: 0, width: 380, height: 280)
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor), stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            newEmailField.widthAnchor.constraint(equalToConstant: 340),
            passwordField.widthAnchor.constraint(equalToConstant: 340),
        ])
        view = root
        preferredContentSize = NSSize(width: 380, height: 280)
    }

    public func save() async {
        errorMessage = nil
        errorLabel.stringValue = ""
        errorLabel.isHidden = true
        do {
            try await authManager.changeEmail(
                newEmail: newEmailField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines),
                password: SecureString(passwordField.stringValue))
            saved = true
            onSuccess?()
            dismissSheet()
        } catch {
            errorMessage = (error as? AppwriteError)?.userFacingMessage ?? error.localizedDescription
            errorLabel.stringValue = errorMessage ?? ""
            errorLabel.isHidden = false
        }
    }

    public func dismissSheet() {
        dismissed = true
        if presentingViewController != nil { dismiss(nil) }
    }
}

@MainActor
public final class CloudChangePasswordSheetController: NSViewController {
    public let authManager: CloudAuthManager
    public var onSuccess: (() -> Void)?
    public private(set) var oldPasswordField = NSSecureTextField()
    public private(set) var newPasswordField = NSSecureTextField()
    public private(set) var errorLabel = NSTextField(wrappingLabelWithString: "")
    public private(set) var errorMessage: String?
    public private(set) var saved = false
    public private(set) var dismissed = false
    private let saveButton: NSButton

    public init(authManager: CloudAuthManager) {
        self.authManager = authManager
        let save = ClosureButton(title: "Change Password", target: nil, action: nil)
        save.bezelStyle = .rounded
        self.saveButton = save
        super.init(nibName: nil, bundle: nil)
        save.onChange = { [weak self] _ in Task { await self?.save() } }
        oldPasswordField.placeholderString = "Current Password"
        newPasswordField.placeholderString = "New Password"
        errorLabel.textColor = .systemRed
        errorLabel.isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public override func loadView() {
        let stack = NSStackView(views: [NSTextField(labelWithString: "Update Credentials"), oldPasswordField, newPasswordField,
                                        errorLabel, saveButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let root = NSView()
        root.frame = NSRect(x: 0, y: 0, width: 380, height: 280)
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: root.topAnchor), stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            oldPasswordField.widthAnchor.constraint(equalToConstant: 340),
            newPasswordField.widthAnchor.constraint(equalToConstant: 340),
        ])
        view = root
        preferredContentSize = NSSize(width: 380, height: 280)
    }

    public func save() async {
        errorMessage = nil
        errorLabel.stringValue = ""
        errorLabel.isHidden = true
        do {
            try await authManager.changePassword(
                oldPassword: SecureString(oldPasswordField.stringValue),
                newPassword: SecureString(newPasswordField.stringValue))
            saved = true
            onSuccess?()
            dismissSheet()
        } catch {
            errorMessage = (error as? AppwriteError)?.userFacingMessage ?? error.localizedDescription
            errorLabel.stringValue = errorMessage ?? ""
            errorLabel.isHidden = false
        }
    }

    public func dismissSheet() {
        dismissed = true
        if presentingViewController != nil { dismiss(nil) }
    }
}

@MainActor
extension AccountsSettingsPane {
    func cloudButton(_ title: String, _ action: @escaping () -> Void) -> NSButton {
        let b = ClosureButton(title: title, target: nil, action: nil)
        b.bezelStyle = .rounded
        b.onChange = { _ in action() }
        return b
    }

    func buildSwiftCodeSection() {
        footnote(Self.appStoreConnectScopeNote)
        heading("SwiftCode Account")
        note(Self.swiftCodeExplanation)
        let seg = NSSegmentedControl(labels: CloudAccountsTab.allCases.map(\.title), trackingMode: .selectOne,
                                     target: self, action: #selector(cloudTabChosen(_:)))
        seg.selectedSegment = selectedCloudTab.rawValue
        loose(seg)
        switch selectedCloudTab {
        case .account: buildCloudAccountTab()
        case .sync: buildCloudSyncTab()
        case .status: buildCloudStatusTab()
        }
        buildGoogleAccountSection()
        buildGitHubSection()
        buildSupabaseSection()
        ensureStatsLoaded()
    }

    @objc func cloudTabChosen(_ c: NSSegmentedControl) {
        selectedCloudTab = CloudAccountsTab(rawValue: c.selectedSegment) ?? .account
    }

    func buildCloudAccountTab() {
        if authManager.isAuthenticated, let user = authManager.currentUser {
            row("Signed in as:", value(user.email))
            let badge = value(CloudAccountsFormatting.verificationText(verified: user.emailVerification))
            badge.textColor = user.emailVerification ? .systemGreen : .systemOrange
            row("Email verification:", badge)
            if let id = authManager.swiftCodeID {
                let field = NSTextField(labelWithString: id)
                field.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
                field.isSelectable = true
                field.isEditable = false
                swiftCodeIDField = field
                let copy = cloudButton("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(id, forType: .string)
                }
                row("SwiftCode ID:", NSStackView(views: [field, copy]))
            }
            var buttons: [NSView] = [
                cloudButton("Change Email") { [weak self] in self?.showChangeEmailSheet() },
                cloudButton("Change Password") { [weak self] in self?.showChangePasswordSheet() },
            ]
            if !user.emailVerification {
                buttons.append(cloudButton("Verify Email") { [weak self] in Task { await self?.sendVerification() } })
            }
            buttons.append(cloudButton("Refresh") { [weak self] in Task { await self?.refreshAccount() } })
            buttons.append(cloudButton("Sign Out") { [weak self] in Task { await self?.signOut() } })
            let stack = NSStackView(views: buttons)
            stack.spacing = 8
            row("Account:", stack)
            let delete = cloudButton("Permanently Delete Account") { [weak self] in self?.confirmDeleteAccount() }
            row("", delete)
            if let message = accountMessage { note(message) }
        } else {
            note("Sign in to your SwiftCode Cloud account to enable automatic data sync and point-in-time cloud backups.")
            let signIn = cloudButton("Sign In or Register") { [weak self] in self?.showAuthSheet() }
            row("SwiftCode Account:", signIn)
        }
        endCard()
        heading("Server Connection")
        note("Test responsiveness to the hosted Appwrite authentication server.")
        let test = cloudButton(isTestingConnection ? "Testing Connection…" : "Test Connection") { [weak self] in
            Task { await self?.testConnection() }
        }
        test.isEnabled = !isTestingConnection
        var controls: [NSView] = [test]
        if let result = connectionResult {
            let label = NSTextField(labelWithString: result)
            label.textColor = connectionSucceeded == true ? .systemGreen : .systemRed
            label.font = .boldSystemFont(ofSize: 12)
            controls.append(label)
        }
        let stack = NSStackView(views: controls)
        stack.spacing = 8
        row("Appwrite Server:", stack)
    }

    func buildCloudSyncTab() {
        row("Sync state:", value(CloudAccountsFormatting.syncStateText(cloudManager.syncState)))
        row("Last sync:", value(CloudAccountsFormatting.lastSyncText(cloudManager.lastSyncTime)))
        let toggle = check("Enable Sync Engine", UserDefaults.standard.bool(forKey: CloudManager.syncEnabledKey)) { [weak self] on in
            Task { await self?.syncEngine.setSyncEnabled(on) }
        }
        toggle.isEnabled = authManager.isAuthenticated
        row("", toggle)
        note("Automatically keep your projects, AI chat histories, snippets, preferences, and workspace settings synchronized across all your devices.")
        if !authManager.isAuthenticated {
            note("Sign in to enable cloud synchronization options.")
        }
        let syncNowButton = cloudButton("Sync Now") { [weak self] in Task { await self?.syncNow() } }
        syncNowButton.isEnabled = authManager.isAuthenticated && cloudManager.syncState != .syncing
        row("Manual sync:", syncNowButton)
        if let error = cloudManager.currentError {
            let label = NSTextField(labelWithString: error)
            label.textColor = .systemRed
            row("Last error:", label)
        }
    }

    func buildCloudStatusTab() {
        let authed = authManager.isAuthenticated
        let authBadge = value(CloudAccountsFormatting.authStatusText(authenticated: authed))
        authBadge.textColor = authed ? .systemGreen : .systemRed
        row("Appwrite Authentication:", authBadge)
        let connBadge = value(CloudAccountsFormatting.connectionStatusText(authenticated: authed))
        connBadge.textColor = authed ? .systemGreen : .systemRed
        row("Cloud Connection:", connBadge)
        row("Sync Engine:", value(cloudManager.isSyncEnabled ? "Active" : "Disabled"))
        row("Last Sync:", value(CloudAccountsFormatting.lastSyncText(cloudManager.lastSyncTime)))
        endCard()
        heading("Telemetry Metrics")
        row("Uploaded records:", value("\(statistics.totalUploadCount)"))
        row("Downloaded records:", value("\(statistics.totalDownloadCount)"))
        row("Pending changes:", value("\(statistics.pendingUploadsCount)"))
        row("Conflicts:", value("\(statistics.conflictCount)"))
        footnote("Record syncing has no backend yet: sync stamps the last-sync time and queues changes, but nothing is uploaded or downloaded.")
    }

    func buildGoogleAccountSection() {
        if !googleRestoreAttempted {
            googleRestoreAttempted = true
            googleAuthService.restoreSessionFromKeychain()
        }
        endCard()
        heading("Google Account")
        note(Self.googleExplanation)
        let service = googleAuthService
        if service.isAuthenticated {
            if let email = service.userEmail {
                row("Signed in as:", value(email))
            }
            let scopesReady = service.hasRequiredAssistScopes()
            let scopes = value(scopesReady ? Self.googleScopesReadyText : Self.googleScopesMissingText)
            scopes.textColor = scopesReady ? .systemGreen : .systemOrange
            row("Assist scopes:", scopes)
            var buttons: [NSView] = []
            if !scopesReady {
                buttons.append(cloudButton("Re-authenticate for Assist Scopes") { [weak self] in
                    self?.reAuthenticateGoogleForAssistScopes()
                })
            }
            buttons.append(cloudButton("Sign Out") { [weak self] in self?.signOutGoogle() })
            let stack = NSStackView(views: buttons)
            stack.spacing = 8
            row("Google Account:", stack)
        } else {
            note("Sign in with Google to use the Gemini / Antigravity models in Assist without an API key.")
            let signIn = cloudButton(service.isAuthenticating ? "Signing In…" : "Sign in with Google") { [weak self] in
                self?.signInWithGoogle()
            }
            signIn.isEnabled = !service.isAuthenticating
            let cli = cloudButton("Sign in via agy CLI") { [weak self] in self?.signInGoogleViaCLI() }
            cli.isEnabled = !service.isAuthenticating
            let stack = NSStackView(views: [signIn, cli])
            stack.spacing = 8
            row("Google Account:", stack)
        }
        if !service.hasClientSecret {
            note(Self.googleMissingSecretNote)
        }
        let secretField = NSSecureTextField()
        secretField.placeholderString = service.hasKeychainClientSecret
            ? "Client secret saved in Keychain — enter a new one to replace it"
            : "OAuth client secret"
        let saveSecret = cloudButton("Save Client Secret") { [weak self] in
            self?.saveGoogleClientSecret(secretField.stringValue)
        }
        let secretStack = NSStackView(views: [secretField, saveSecret])
        secretStack.spacing = 8
        row("Client Secret:", secretStack)
        let idField = NSTextField()
        idField.placeholderString = "Empty = SwiftCode's built-in client"
        idField.stringValue = UserDefaults.standard.string(forKey: GoogleDefaultsKey.clientIDOverride) ?? ""
        let saveID = cloudButton("Save Client ID") { [weak self] in
            self?.saveGoogleClientIDOverride(idField.stringValue)
        }
        let idStack = NSStackView(views: [idField, saveID])
        idStack.spacing = 8
        row("Client ID Override:", idStack)
        note("Only needed if you must use a different OAuth client than SwiftCode's built-in one. Applies to the next sign-in.")
        if let error = service.authError {
            let label = NSTextField(wrappingLabelWithString: error)
            label.textColor = .systemRed
            row("Last error:", label)
        } else if let refreshError = service.lastTokenRefreshError {
            note("The last token refresh failed: \(refreshError)")
        }
    }

    func buildGitHubSection() {
        endCard()
        heading("GitHub Account")
        note("The GitHub account behind the Source Control and CI views. Add the token in the first-run setup (GitHub Token step); this section shows the signed-in account once one is stored.")
        gitHubAccountHosting?.view.removeFromSuperview()
        gitHubAccountHosting?.removeFromParent()
        let client = GitHubClient(tokenProvider: { defaultSecretStore().readString(SecretAccount.githubToken) })
        let hosting = NSHostingController(rootView: GitHubAccountView(client: client) { [weak self] in
            if self?.isViewLoaded == true { self?.rebuild() }
        })
        gitHubAccountHosting = hosting
        addChild(hosting)
        let view = hosting.view
        loose(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -2 * SettingsMetrics.cardInset).isActive = true
        view.heightAnchor.constraint(equalToConstant: 440).isActive = true
    }

    func buildSupabaseSection() {
        endCard()
        heading("Supabase")
        supabaseHosting?.view.removeFromSuperview()
        supabaseHosting?.removeFromParent()
        let hosting = NSHostingController(rootView: SupabaseCloudView())
        supabaseHosting = hosting
        addChild(hosting)
        let view = hosting.view
        loose(view)
        view.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -2 * SettingsMetrics.cardInset).isActive = true
        view.heightAnchor.constraint(equalToConstant: 420).isActive = true
    }

    public func signInWithGoogle() {
        googleAuthService.signIn()
        if isViewLoaded { rebuild() }
    }

    public func signOutGoogle() {
        googleAuthService.signOut()
        if isViewLoaded { rebuild() }
    }

    public func reAuthenticateGoogleForAssistScopes() {
        googleAuthService.reAuthenticateForAssistScopes()
        if isViewLoaded { rebuild() }
    }

    public func signInGoogleViaCLI() {
        googleAuthService.signInViaCLI()
        if isViewLoaded { rebuild() }
    }

    public func saveGoogleClientSecret(_ secret: String) {
        googleAuthService.setClientSecret(secret)
        if isViewLoaded { rebuild() }
    }

    public func saveGoogleClientIDOverride(_ id: String) {
        googleAuthService.setClientIDOverride(id)
        if isViewLoaded { rebuild() }
    }

    func ensureStatsLoaded() {
        guard statsTask == nil else { return }
        statsTask = Task {
            await loadStats()
            if isViewLoaded { rebuild() }
        }
    }

    public func loadStats() async {
        statistics = await syncEngine.getStatistics()
    }

    public func testConnection() async {
        isTestingConnection = true
        connectionResult = nil
        connectionSucceeded = nil
        if isViewLoaded { rebuild() }
        do {
            _ = try await authManager.client.ping()
            connectionSucceeded = true
            connectionResult = Self.connectionSucceededText
        } catch {
            connectionSucceeded = false
            connectionResult = "Connection Failed: \(error.localizedDescription)"
        }
        isTestingConnection = false
        if isViewLoaded { rebuild() }
    }

    public func syncNow() async {
        await cloudManager.sync()
        await loadStats()
        if isViewLoaded { rebuild() }
    }

    public func signOut() async {
        await authManager.logout()
        await syncEngine.setSyncEnabled(false)
        await loadStats()
        if isViewLoaded { rebuild() }
    }

    public func sendVerification() async {
        do {
            try await authManager.sendVerificationEmail()
            accountMessage = Self.verificationSentText
        } catch {
            accountMessage = (error as? AppwriteError)?.userFacingMessage ?? error.localizedDescription
        }
        if isViewLoaded { rebuild() }
    }

    public func refreshAccount() async {
        await authManager.restoreSession()
        await loadStats()
        if isViewLoaded { rebuild() }
    }

    public func deleteAccountConfirmed() async {
        do {
            try await authManager.deleteAccount()
            await syncEngine.setSyncEnabled(false)
            await loadStats()
        } catch {
            accountMessage = authManager.authError
                ?? (error as? AppwriteError)?.userFacingMessage
                ?? error.localizedDescription
        }
        if isViewLoaded { rebuild() }
    }

    public func makeDeleteAccountAlert() -> NSAlert {
        let a = NSAlert()
        a.messageText = Self.deleteAccountTitle
        a.informativeText = Self.deleteAccountMessage
        a.addButton(withTitle: "Delete Account")
        a.addButton(withTitle: "Cancel")
        a.alertStyle = .critical
        return a
    }

    public func confirmDeleteAccount() {
        shownDeleteConfirmation = Self.deleteAccountMessage
        guard let w = view.window, w.isVisible else { return }
        makeDeleteAccountAlert().beginSheetModal(for: w) { [weak self] r in
            if r == .alertFirstButtonReturn { Task { await self?.deleteAccountConfirmed() } }
        }
    }

    public func makeAuthSheet(mode: CloudAuthSheetController.Mode = .login, isGate: Bool = false) -> CloudAuthSheetController {
        let sheet = CloudAuthSheetController(authManager: authManager, mode: mode, isGate: isGate)
        sheet.onSuccess = { [weak self] in
            Task {
                await self?.loadStats()
                self?.rebuild()
            }
        }
        return sheet
    }

    public func showAuthSheet(mode: CloudAuthSheetController.Mode = .login, isGate: Bool = false) {
        let sheet = makeAuthSheet(mode: mode, isGate: isGate)
        presentedAuthSheet = sheet
        guard let w = view.window, w.isVisible else { return }
        presentAsSheet(sheet)
    }

    public func makeChangeEmailSheet() -> CloudChangeEmailSheetController {
        let sheet = CloudChangeEmailSheetController(authManager: authManager)
        sheet.onSuccess = { [weak self] in Task { await self?.refreshAccount() } }
        return sheet
    }

    public func showChangeEmailSheet() {
        let sheet = makeChangeEmailSheet()
        presentedChangeEmailSheet = sheet
        guard let w = view.window, w.isVisible else { return }
        presentAsSheet(sheet)
    }

    public func makeChangePasswordSheet() -> CloudChangePasswordSheetController {
        CloudChangePasswordSheetController(authManager: authManager)
    }

    public func showChangePasswordSheet() {
        let sheet = makeChangePasswordSheet()
        presentedChangePasswordSheet = sheet
        guard let w = view.window, w.isVisible else { return }
        presentAsSheet(sheet)
    }
}
