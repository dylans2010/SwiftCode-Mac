import Foundation
import AppKit

/// Real navigation + dispatch for every "Fix with Assist" style action in the
/// app (Build Center, Artboard simulator, device console, …).
///
/// Previously these buttons posted a `com.swiftcode.assist.triggerQuickFix`
/// notification that nothing observed — a dead placeholder. The router instead:
///  1. reveals the real Assist main view (via the established toolbar-tool
///     activation path WorkspaceView already observes),
///  2. optionally starts a brand-new Assist session, and
///  3. dispatches the diagnostic prompt through AssistManager.
@MainActor
public enum AssistNavigationRouter {

    /// Reveals the Assist main view without touching the session.
    public static func revealAssistPanel() {
        NotificationCenter.default.post(
            name: .toolbarToolActivated,
            object: nil,
            userInfo: ["toolID": "assist_view"]
        )
    }

    /// Opens the Assist main view in a NEW session, then sends the prompt.
    public static func openAssistWithNewSession(prompt: String) {
        revealAssistPanel()
        Task { @MainActor in
            AssistManager.shared.clearSession()
            await AssistManager.shared.sendMessage(prompt)
        }
    }

    /// Sends a follow-up prompt to the current Assist session (no session reset),
    /// revealing the panel first so the user can watch.
    public static func sendFollowUpToAssist(prompt: String) {
        revealAssistPanel()
        Task { @MainActor in
            await AssistManager.shared.sendMessage(prompt)
        }
    }

    /// Opens a file in the editor via the workspace's established open-file path.
    /// Relative paths are resolved against the active project directory.
    public static func openFileInEditor(resolving path: String) {
        guard let url = resolvedFileURL(for: path) else { return }
        NotificationCenter.default.post(
            name: NSNotification.Name("com.swiftcode.openFileInWorkspace"),
            object: nil,
            userInfo: ["filePath": url.path]
        )
    }

    /// Resolves a diagnostic-reported file reference to an existing file URL,
    /// or nil when it cannot be opened (e.g. "Active Document", "Build Logs").
    public static func resolvedFileURL(for path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let url: URL
        if trimmed.hasPrefix("/") {
            url = URL(fileURLWithPath: trimmed)
        } else if trimmed.hasPrefix("~") {
            url = URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
        } else {
            let base = DocumentCoordinator.shared.projectURL
                ?? ProjectSessionStore.shared.activeProject?.directoryURL
                ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            // Compiler diagnostics often report paths like
            // ".../Project/Sources/Foo.swift"; try the raw path first, then
            // the last few components relative to the project root.
            let direct = URL(fileURLWithPath: trimmed)
            if FileManager.default.fileExists(atPath: direct.path) {
                return direct
            }
            let comps = trimmed.split(separator: "/").suffix(3).joined(separator: "/")
            url = base.appendingPathComponent(comps)
        }

        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }
}
