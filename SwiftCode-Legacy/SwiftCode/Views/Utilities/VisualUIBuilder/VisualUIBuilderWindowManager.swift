import AppKit
import SwiftUI

@MainActor
public final class VisualUIBuilderWindowManager: NSObject, NSWindowDelegate {
    public static let shared = VisualUIBuilderWindowManager()
    private var windowController: VisualUIBuilderWindowController?

    public func showWindow() {
        if let existing = windowController {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let wc = VisualUIBuilderWindowController()
        wc.window?.delegate = self
        self.windowController = wc
        wc.window?.makeKeyAndOrderFront(nil)
    }

    public func closeWindow() {
        windowController?.close()
        windowController = nil
    }

    public func windowWillClose(_ notification: Notification) {
        windowController = nil
    }
}
