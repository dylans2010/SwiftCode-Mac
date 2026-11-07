import AppKit
import Foundation
import SwiftUI

@MainActor
enum SDKActiveProjectResolver {
    static func resolve() throws -> Project {
        if let active = ProjectSessionStore.shared.activeProject {
            return active
        }
        if let first = ProjectSessionStore.shared.projects.first {
            return first
        }
        throw SDKError(
            code: .projectNotOpen,
            message: "No project is open in SwiftCode.",
            suggestion: "Open a project in SwiftCode and try again."
        )
    }
}

@MainActor
final class SDKHostedWindow<Content: View>: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(
        rootView: Content,
        title: String,
        size: NSSize,
        autosaveName: String,
        minSize: NSSize? = nil
    ) {
        if let window {
            window.contentViewController = NSHostingController(rootView: rootView)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        if let minSize { window.minSize = minSize }
        window.setFrameAutosaveName(autosaveName)
        window.collectionBehavior = [.fullScreenPrimary, .managed]
        window.center()
        window.contentViewController = NSHostingController(rootView: rootView)
        window.delegate = self

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window?.close()
        window = nil
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
