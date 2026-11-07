import AppKit
import Foundation
import SwiftUI
import SwiftCodeCollaboration

@MainActor
public final class CollaborationWindowManager: NSObject {
    public static let shared = CollaborationWindowManager()
    private var controllers: [String: NSWindowController] = [:]

    private override init() {}

    public func showWindow(workspaceFolder: URL) {
        let key = workspaceFolder.standardizedFileURL.path
        if let existing = controllers[key] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let project = CollaborationProject(
            name: workspaceFolder.lastPathComponent,
            directoryURL: workspaceFolder
        )
        let creatorID = Host.current().localizedName ?? "macOS Device"
        let manager = CollaborationManager(project: project, creatorID: creatorID)
        let chat = CollaborationChatManager()
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 980, height: 640)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Collaboration — \(workspaceFolder.lastPathComponent)"
        window.minSize = NSSize(width: 720, height: 480)
        window.setFrameAutosaveName("SwiftCodeCollaborationWindow")
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(
            rootView: CollaborationMainView(manager: manager, chat: chat)
        )
        let controller = NSWindowController(window: window)
        controller.window?.delegate = self
        controllers[key] = controller
        window.makeKeyAndOrderFront(nil)
    }

    public func closeWindow(workspaceFolder: URL) {
        controllers[workspaceFolder.standardizedFileURL.path]?.close()
    }

    func controllerClosed(_ controller: NSWindowController) {
        guard let window = controller.window,
              let key = controllers.first(where: { $0.value.window === window })?.key else { return }
        controllers[key] = nil
    }
}

extension CollaborationWindowManager: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let controller = controllers.values.first(where: { $0.window === window }) else { return }
        controllerClosed(controller)
    }
}

extension WorkspaceWindowController {
    @objc public func showCollaboration(_ sender: Any?) {
        CollaborationWindowManager.shared.showWindow(workspaceFolder: workspaceFolder)
    }
}
