import AppKit
import SwiftUI

@MainActor
public final class IPABuildWindowManager: NSObject {
    public static let shared = IPABuildWindowManager()
    private var controller: IPABuildWindowController?

    public func showWindow() {
        if let existing = controller {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = IPABuildWindowController()
        self.controller = controller
        controller.window?.delegate = self
        controller.window?.makeKeyAndOrderFront(nil)
    }
}

extension IPABuildWindowManager: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === controller?.window {
            controller = nil
        }
    }
}

@MainActor
public final class IPABuildWindowController: NSWindowController {
    public static let shared = IPABuildWindowController()

    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "IPA Packaging & Distribution"
        window.center()
        window.setFrameAutosaveName("SwiftCodeIPABuildWindow")
        window.contentView = NSHostingView(rootView: IPABuildView())
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public func show() {
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }
}
