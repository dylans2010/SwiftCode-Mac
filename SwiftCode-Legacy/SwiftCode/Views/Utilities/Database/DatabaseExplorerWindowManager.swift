import AppKit
import SwiftUI

@MainActor
public final class DatabaseExplorerWindowManager: NSObject, NSWindowDelegate {
    public static let shared = DatabaseExplorerWindowManager()
    private var windowController: DatabaseExplorerWindowController?

    public func showWindow() {
        if let existing = windowController {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let wc = DatabaseExplorerWindowController()
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
