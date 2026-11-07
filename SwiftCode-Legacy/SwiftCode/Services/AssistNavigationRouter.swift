import Foundation
import AppKit

@MainActor
public enum AssistNavigationRouter {

    public static func revealAssistPanel() {
        NotificationCenter.default.post(
            name: .toolbarToolActivated,
            object: nil,
            userInfo: ["toolID": "assist_view"]
        )
    }

    public static func openAssistWithNewSession(prompt: String) {
        revealAssistPanel()
        Task { @MainActor in
            AssistManager.shared.clearSession()
            await AssistManager.shared.sendMessage(prompt)
        }
    }

    public static func sendFollowUpToAssist(prompt: String) {
        revealAssistPanel()
        Task { @MainActor in
            await AssistManager.shared.sendMessage(prompt)
        }
    }

    public static func openFileInEditor(resolving path: String) {
        guard let url = resolvedFileURL(for: path) else { return }
        NotificationCenter.default.post(
            name: NSNotification.Name("com.swiftcode.openFileInWorkspace"),
            object: nil,
            userInfo: ["filePath": url.path]
        )
    }

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
