import AppKit
import SwiftCodeCloud

/// The password-reset completion sheet (gap closure, specs/ide/
/// gap-closure-misc.md §6).
///
/// The flow: Appwrite emails a reset link (`createRecovery`); opening
/// it posts `.appwriteRecoveryLinkReceived` with `userId` / `secret`
/// in `userInfo` (`AppSupport.handleOpenedURL`); this controller asks
/// for the new password and completes the reset with
/// `AppwriteAccountClient.updateRecovery(userId:secret:password:)`.
///
/// The reset itself runs through the injectable `resetPassword`
/// closure (default: the live Appwrite client), so tests drive the
/// sheet's state machine without network or credentials. No password
/// is ever stored: the fields are cleared on success, on cancel, and
/// when the window closes.
@MainActor
public final class PasswordResetWindowController: NSWindowController {
    /// Appwrite's minimum password length.
    public nonisolated static let minimumPasswordLength = 8

    /// Completes the reset for `userId` / `secret` with the new
    /// password. Defaults to the live Appwrite client.
    public var resetPassword: (String, String, String) async throws -> Void = { userId, secret, password in
        try await CloudAuthManager.shared.client.updateRecovery(userId: userId, secret: secret, password: password)
    }

    private let userId: String
    private let secret: String
    private let newField = NSSecureTextField()
    private let confirmField = NSSecureTextField()
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let resetButton = NSButton(title: "Reset Password", target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
    private var isResetting = false
    /// The success text shown after a completed reset, or nil (tests).
    private(set) public var shownSuccess: String?

    /// The controller for the currently shown sheet, if any. Held
    /// statically so the window does not deallocate its controller
    /// while open.
    private static var current: PasswordResetWindowController?
    private static var installed = false

    /// Starts listening for recovery links (once). Call from
    /// `applicationDidFinishLaunching`.
    public static func installIfNeeded() {
        guard !installed else { return }
        installed = true
        // swiftlint:disable:next discarded_notification_center_observer - lives as long as the app
        NotificationCenter.default.addObserver(
            forName: .appwriteRecoveryLinkReceived, object: nil, queue: .main
        ) { note in
            // Read the payload before crossing to the main actor: the
            // Notification is not Sendable.
            guard let userId = note.userInfo?["userId"] as? String,
                  let secret = note.userInfo?["secret"] as? String else { return }
            MainActor.assumeIsolated {
                show(userId: userId, secret: secret)
            }
        }
    }

    /// Shows the reset sheet for one recovery link.
    public static func show(userId: String, secret: String) {
        let controller = PasswordResetWindowController(userId: userId, secret: secret)
        current = controller
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    public init(userId: String, secret: String) {
        self.userId = userId
        self.secret = secret
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 360, height: 250)),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Reset Your Password"
        super.init(window: window)
        window.delegate = self
        buildContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func buildContent() {
        guard let contentView = window?.contentView else { return }
        let info = NSTextField(wrappingLabelWithString: "Choose a new password for your SwiftCode account.")
        info.font = .systemFont(ofSize: 12)
        info.textColor = .secondaryLabelColor
        newField.placeholderString = "New password"
        confirmField.placeholderString = "Confirm new password"
        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        errorLabel.isHidden = true
        resetButton.bezelStyle = .rounded
        resetButton.keyEquivalent = "\r"
        resetButton.target = self
        resetButton.action = #selector(resetClicked)
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancelClicked)
        let stack = NSStackView(views: [info, newField, confirmField, errorLabel, NSView(),
                                        NSStackView(views: [NSView(), cancelButton, resetButton])])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])
    }

    /// The current validation problem, or nil when the fields are
    /// ready to submit (tests).
    public var validationProblem: String? {
        PasswordResetValidation.problem(newPassword: newField.stringValue, confirmation: confirmField.stringValue)
    }

    /// The error text currently shown, or nil (tests).
    public var shownError: String? { errorLabel.isHidden ? nil : errorLabel.stringValue }

    @objc private func resetClicked() {
        if let problem = validationProblem {
            showError(problem)
            return
        }
        let password = newField.stringValue
        setResetting(true)
        Task {
            do {
                try await resetPassword(userId, secret, password)
                showSuccess()
            } catch {
                showError((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                setResetting(false)
            }
        }
    }

    @objc private func cancelClicked() {
        close()
    }

    private func showError(_ text: String) {
        errorLabel.stringValue = text
        errorLabel.isHidden = false
    }

    private func showSuccess() {
        clearFields()
        setResetting(false)
        errorLabel.isHidden = true
        newField.isHidden = true
        confirmField.isHidden = true
        resetButton.isHidden = true
        cancelButton.title = "Close"
        window?.title = "Password Reset"
        let text = "Your password was reset. You can now sign in with the new password."
        shownSuccess = text
        if let stack = window?.contentView?.subviews.first as? NSStackView {
            let done = NSTextField(wrappingLabelWithString: text)
            done.font = .systemFont(ofSize: 12)
            stack.insertArrangedSubview(done, at: 0)
        }
    }

    private func setResetting(_ resetting: Bool) {
        isResetting = resetting
        newField.isEnabled = !resetting
        confirmField.isEnabled = !resetting
        resetButton.isEnabled = !resetting
        cancelButton.isEnabled = !resetting
    }

    private func clearFields() {
        newField.stringValue = ""
        confirmField.stringValue = ""
    }

    public override func close() {
        clearFields()
        super.close()
        if Self.current === self { Self.current = nil }
    }
}

extension PasswordResetWindowController: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        clearFields()
        if Self.current === self { Self.current = nil }
    }
}

/// The new-password rules, factored out so tests check them without
/// opening a window.
public enum PasswordResetValidation {
    /// The problem with the two fields, or nil when they are ready
    /// to submit.
    public static func problem(newPassword: String, confirmation: String) -> String? {
        if newPassword.count < PasswordResetWindowController.minimumPasswordLength {
            return "The new password must be at least \(PasswordResetWindowController.minimumPasswordLength) characters."
        }
        if newPassword != confirmation {
            return "The passwords do not match."
        }
        return nil
    }
}
