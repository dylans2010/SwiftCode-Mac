import AppKit
import SwiftCodeCloud

@MainActor
public final class PasswordResetWindowController: NSWindowController {
    public nonisolated static let minimumPasswordLength = 8

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
    private(set) public var shownSuccess: String?

    private static var current: PasswordResetWindowController?
    private static var installed = false

    public static func installIfNeeded() {
        guard !installed else { return }
        installed = true
        NotificationCenter.default.addObserver(
            forName: .appwriteRecoveryLinkReceived, object: nil, queue: .main
        ) { note in
            guard let userId = note.userInfo?["userId"] as? String,
                  let secret = note.userInfo?["secret"] as? String else { return }
            MainActor.assumeIsolated {
                show(userId: userId, secret: secret)
            }
        }
    }

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

    public var validationProblem: String? {
        PasswordResetValidation.problem(newPassword: newField.stringValue, confirmation: confirmField.stringValue)
    }

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

public enum PasswordResetValidation {
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
