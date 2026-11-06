import AppKit
import SwiftUI
import SwiftCodeAssistant
import SwiftCodeIDECore

/// The first-run setup window (wiring-views): hosts `SCSetupOnboard`
/// (Overview → Git Executable → GitHub Token) in its own window, shown
/// once at launch by `offerIfNeeded()` when git is not installed or no
/// GitHub token is stored — the hook `SCSetupOnboard`'s header names.
/// "Continue" (`onFinished`) closes the window into the workspace; the
/// window is closable without finishing, in which case the offer
/// recurs on the next launch until git and a token are both present.
@MainActor
public final class SCSetupOnboardWindowController: NSWindowController, NSWindowDelegate {
    private static var retained: SCSetupOnboardWindowController?

    /// Shows the setup wizard when its precondition holds; false when
    /// git is installed and a GitHub token is already stored.
    @discardableResult
    public static func offerIfNeeded() -> Bool {
        guard !GitRepository.isGitInstalled()
            || defaultSecretStore().readString(SecretAccount.githubToken) == nil
        else { return false }
        let controller = SCSetupOnboardWindowController()
        retained = controller
        controller.window?.center()
        controller.window?.makeKeyAndOrderFront(nil)
        return true
    }

    public init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 560, height: 520)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Set Up SwiftCode"
        window.minSize = NSSize(width: 480, height: 440)
        window.isReleasedWhenClosed = false
        let hosting = NSHostingController(rootView: SCSetupOnboard { [weak window] in
            window?.performClose(nil)
        })
        window.contentViewController = hosting
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public func windowWillClose(_ notification: Notification) {
        Self.retained = nil
    }
}
