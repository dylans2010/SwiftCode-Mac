import AppKit
import Foundation
import SwiftUI
import SwiftCodeAssistant
import SwiftCodeCloud
import SwiftCodeGitHub
import SwiftCodeGoogleAuth
import SwiftCodeIDECore

/// The SwiftCode account section of Settings ▸ Accounts (specs/ide/
/// cloud-accounts.md §7, slice B): the auth sheet, the account / sync /
/// status tabs, and the change-email / change-password sheets.
///
/// The pane's App Store Connect key list (the `AccountsSettingsPane`
/// build in `SettingsPanes.swift`) is untouched; this file only adds
/// the SwiftCode section below it, in the same settings form style
/// (grouped cards, rows, help text). Every action here calls the
/// slice A API exactly as written (`CloudAuthManager`,
/// `CloudManager`, `CloudSyncEngine`, `AppwriteAccountClient`); no
/// auth logic is re-implemented in the UI, and the error text shown
/// is `authError` / `AppwriteError.userFacingMessage`, never a
/// re-implementation of the mapping.
///
/// OAuth (Google / GitHub) is honestly unavailable pending URL-scheme
/// plumbing (spec §4.4/§8): the buttons are present, tapping one
/// opens the authorize URL and waits for the callback, and the sheet
/// shows the pending state. When no callback arrives the wait times
/// out with `.oauthCallbackTimeout` and the sheet shows that error;
/// a completed sign-in is never faked.

// MARK: - Tabs and formatting

/// The SwiftCode section's tabs (Legacy's `CloudManagementView`
/// segmented picker: Account & Setup / Cloud Sync / System
/// Telemetry), in Mac settings style.
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

/// Pure formatting for the cloud rows, so tests can check the text
/// without a window.
public enum CloudAccountsFormatting {
    /// `syncState.rawValue` uppercased, as Legacy's `CloudSyncView`
    /// showed it.
    public static func syncStateText(_ state: SyncState) -> String { state.rawValue.uppercased() }

    /// `lastSyncTime` (abbreviated date, shortened time), or "Never"
    /// when nothing has synced yet.
    public static func lastSyncText(_ date: Date?) -> String {
        date.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? "Never"
    }

    /// The verification badge from `emailVerification`.
    public static func verificationText(verified: Bool) -> String { verified ? "Verified" : "Unverified" }

    /// The status tab's authentication badge, driven by
    /// `isAuthenticated`.
    public static func authStatusText(authenticated: Bool) -> String { authenticated ? "Authenticated" : "Unauthenticated" }

    /// The status tab's connection badge, also driven by
    /// `isAuthenticated` (Legacy's `CloudStatusView`).
    public static func connectionStatusText(authenticated: Bool) -> String { authenticated ? "Connected" : "Offline" }
}

// MARK: - Auth sheet

/// The sign-in / register / reset-password sheet (Legacy's
/// `CloudAuthViews`), in Mac style: an `NSViewController` presented
/// as a sheet, with an email field, secure password fields, Google
/// and GitHub buttons, and success/error text.
///
/// The sheet drives the auth manager directly. `performAuth()` and
/// `beginOAuth(provider:)` are the test seams: they do the work
/// without a window, and `dismissed` records that the sheet would
/// have closed, so tests can drive the whole flow headlessly.
@MainActor
public final class CloudAuthSheetController: NSViewController {
    public enum Mode {
        case login
        case createAccount
        case forgotPassword
    }

    /// "Passwords do not match." — checked client-side before any
    /// call, exactly as Legacy did.
    public static let passwordsDoNotMatch = "Passwords do not match."
    /// The forgot-password success text (Legacy's wording).
    public static let resetLinkSent = "A password reset link has been successfully dispatched to your email."
    /// The honest OAuth pending state: the flow starts in the
    /// browser and waits for a callback the app cannot yet receive.
    public static let oauthPending = "Continue in your browser… SwiftCode is waiting for the sign-in to return. "
        + "The app callback for this flow is not wired up yet, so the wait will time out instead of completing."

    public let authManager: CloudAuthManager
    public private(set) var mode: Mode
    public let isGate: Bool
    /// Called on a successful sign-in or registration (the pane
    /// reloads stats and rebuilds). Not called for a password reset.
    public var onSuccess: (() -> Void)?
    /// Opens the OAuth authorize URL in the browser. The OpenAI
    /// account pattern: injected so tests can refuse it.
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
    /// True once the sheet has dismissed (or would have, when no
    /// window presented it — the headless test path).
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

    /// Refreshes titles, field visibility, and messages for the
    /// current mode.
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

    /// Cycles login ↔ create account (forgot password returns to
    /// login), clearing messages — Legacy's `switchMode`.
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

    /// Opens the forgot-password mode.
    public func showForgotPassword() {
        errorMessage = nil
        successMessage = nil
        oauthMessage = nil
        mode = .forgotPassword
        if isViewLoaded { updateModeViews() }
    }

    /// Runs the current mode's auth action. The
    /// password-confirmation check happens client-side before any
    /// call. On success calls `onSuccess` and dismisses (unless this
    /// is the gate); a password reset only sets the success text.
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

    /// Starts a Google or GitHub OAuth sign-in: opens the authorize
    /// URL in the browser and waits for the callback. Honest about
    /// the missing plumbing — the sheet shows the pending state, and
    /// a wait that never completes surfaces the timeout error rather
    /// than a faked sign-in.
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

    /// Closes the sheet; records `dismissed` when no window
    /// presented it.
    public func dismissSheet() {
        dismissed = true
        if presentingViewController != nil { dismiss(nil) }
    }
}

// MARK: - Change email / change password sheets

/// The change-email sheet (Legacy's `ChangeEmailSheet`): a new email
/// address plus the current password.
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

    /// Saves the new email; on success marks `saved` and dismisses.
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

/// The change-password sheet (Legacy's `ChangePasswordSheet`): the
/// current password plus the new one.
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

    /// Saves the new password; on success marks `saved` and dismisses.
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

// MARK: - The SwiftCode section of the Accounts pane

@MainActor
extension AccountsSettingsPane {
    /// A rounded button in the pane's style.
    func cloudButton(_ title: String, _ action: @escaping () -> Void) -> NSButton {
        let b = ClosureButton(title: title, target: nil, action: nil)
        b.bezelStyle = .rounded
        b.onChange = { _ in action() }
        return b
    }

    /// The SwiftCode section, below the App Store Connect key list:
    /// a scoped note (the + button's "never asks for credentials"
    /// explanation is about App Store Connect keys), the account
    /// explanation, the tab picker, and the selected tab.
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

    // MARK: Account tab

    /// Legacy's `CloudManagementView` account tab: the signed-in
    /// email, the verification badge, the canonical SwiftCode id,
    /// change-email / change-password / send-verification / refresh /
    /// sign-out, delete-account, and the server test.
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

    // MARK: Sync tab

    /// Legacy's `CloudSyncView`: the sync state, the last sync time,
    /// the `com.swiftcode.cloud.syncEnabled` toggle wired to
    /// `CloudSyncEngine.setSyncEnabled`, a manual trigger, and the
    /// last error.
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

    // MARK: Status tab

    /// Legacy's `CloudStatusView`: authenticated/unauthenticated and
    /// connected/offline badges (both driven by `isAuthenticated`),
    /// the last sync time, and statistics from
    /// `CloudSyncEngine.getStatistics()`.
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

    // MARK: Google account

    /// Legacy's Google account section (the Google Account card in
    /// `AssistSettingsView`): the signed-in email, the Assist-scope
    /// status, sign-in / sign-out, re-authentication for Assist
    /// scopes, the `agy` CLI path, and the OAuth client id/secret
    /// fields. This is the separate Google Cloud / Antigravity
    /// identity — not the Appwrite SwiftCode account above — and it
    /// calls the `GoogleAccountAuthService` API exactly as written;
    /// no auth logic is re-implemented in the UI. The section
    /// triggers the service's one session restore on first build
    /// (the service does not restore in `init`).
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
        // OAuth client configuration (Legacy's Assist settings
        // fields): the id override and the secret. The secret field
        // never shows a stored value — it only sets a new one.
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

    /// Wiring (wiring-views): Settings ▸ Accounts ▸ GitHub Account —
    /// `GitHubAccountView` (the signed-in profile, stats and Sign Out)
    /// hosted as the pane's GitHub section. The client reads the token
    /// fresh from the secret store (the same account
    /// `GitHubClient(tokenProvider:)` reads), so the token added in the
    /// first-run setup (`SCSetupOnboard`) takes effect here with no
    /// extra step; signing out deletes it and rebuilds the pane back to
    /// the could-not-load state. The hosted view gets a fixed height:
    /// its body is a `VStack` with a `Spacer`, so it has no intrinsic
    /// height for the form stack.
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

    /// Wiring (wiring-views): Settings ▸ Accounts ▸ Supabase —
    /// `SupabaseCloudView` (endpoint, sync stats, per-conflict
    /// resolution) hosted as the pane's Supabase section. Same fixed
    /// hosting height as the GitHub section above.
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

    /// Starts Google sign-in (the browser flow on macOS; fails
    /// honestly with an error on Linux). State changes rebuild the
    /// pane through `onStateChange`.
    public func signInWithGoogle() {
        googleAuthService.signIn()
        if isViewLoaded { rebuild() }
    }

    /// Signs out of the Google account.
    public func signOutGoogle() {
        googleAuthService.signOut()
        if isViewLoaded { rebuild() }
    }

    /// Re-authenticates with the full Assist scopes, keeping the
    /// existing session until the new sign-in succeeds.
    public func reAuthenticateGoogleForAssistScopes() {
        googleAuthService.reAuthenticateForAssistScopes()
        if isViewLoaded { rebuild() }
    }

    /// Signs in through the `agy` CLI (macOS Terminal).
    public func signInGoogleViaCLI() {
        googleAuthService.signInViaCLI()
        if isViewLoaded { rebuild() }
    }

    /// Stores the OAuth client secret (empty clears it).
    public func saveGoogleClientSecret(_ secret: String) {
        googleAuthService.setClientSecret(secret)
        if isViewLoaded { rebuild() }
    }

    /// Stores the OAuth client-id override (empty clears it).
    public func saveGoogleClientIDOverride(_ id: String) {
        googleAuthService.setClientIDOverride(id)
        if isViewLoaded { rebuild() }
    }

    // MARK: Actions

    /// Starts the one background statistics load (guarded so a
    /// rebuild does not start another); refreshes the pane once the
    /// statistics arrive.
    func ensureStatsLoaded() {
        guard statsTask == nil else { return }
        statsTask = Task {
            await loadStats()
            if isViewLoaded { rebuild() }
        }
    }

    /// Reloads the sync statistics. Callers rebuild afterwards.
    public func loadStats() async {
        statistics = await syncEngine.getStatistics()
    }

    /// "Test Connection": pings the Appwrite server and shows
    /// "Connection Succeeded (Appwrite Server Reachable)" or
    /// "Connection Failed: …" with success/failure styling.
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

    /// A manual sync run, then a statistics reload.
    public func syncNow() async {
        await cloudManager.sync()
        await loadStats()
        if isViewLoaded { rebuild() }
    }

    /// Signs out, disables sync, and reloads statistics.
    public func signOut() async {
        await authManager.logout()
        await syncEngine.setSyncEnabled(false)
        await loadStats()
        if isViewLoaded { rebuild() }
    }

    /// Sends the verification email to the signed-in user.
    public func sendVerification() async {
        do {
            try await authManager.sendVerificationEmail()
            accountMessage = Self.verificationSentText
        } catch {
            accountMessage = (error as? AppwriteError)?.userFacingMessage ?? error.localizedDescription
        }
        if isViewLoaded { rebuild() }
    }

    /// Re-reads the account from the server and reloads statistics.
    public func refreshAccount() async {
        await authManager.restoreSession()
        await loadStats()
        if isViewLoaded { rebuild() }
    }

    /// Deletes the account for real, then disables sync and reloads
    /// statistics. On failure the user-facing error is kept in
    /// `accountMessage` and nothing is signed out.
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

    /// Legacy's exact delete-account confirmation alert.
    public func makeDeleteAccountAlert() -> NSAlert {
        let a = NSAlert()
        a.messageText = Self.deleteAccountTitle
        a.informativeText = Self.deleteAccountMessage
        a.addButton(withTitle: "Delete Account")
        a.addButton(withTitle: "Cancel")
        a.alertStyle = .critical
        return a
    }

    /// Asks for delete confirmation (records the message when no
    /// window is showing, so the confirmation is still testable).
    public func confirmDeleteAccount() {
        shownDeleteConfirmation = Self.deleteAccountMessage
        guard let w = view.window, w.isVisible else { return }
        makeDeleteAccountAlert().beginSheetModal(for: w) { [weak self] r in
            if r == .alertFirstButtonReturn { Task { await self?.deleteAccountConfirmed() } }
        }
    }

    // MARK: Sheets

    /// The auth sheet, wired to reload stats and rebuild on success.
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

    /// Presents the auth sheet (records it when no window is showing).
    public func showAuthSheet(mode: CloudAuthSheetController.Mode = .login, isGate: Bool = false) {
        let sheet = makeAuthSheet(mode: mode, isGate: isGate)
        presentedAuthSheet = sheet
        guard let w = view.window, w.isVisible else { return }
        presentAsSheet(sheet)
    }

    /// The change-email sheet, wired to refresh the account on success.
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

    /// The change-password sheet.
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
