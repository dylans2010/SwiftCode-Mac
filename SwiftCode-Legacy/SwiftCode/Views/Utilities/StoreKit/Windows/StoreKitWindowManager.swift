import AppKit
import SwiftUI

@MainActor
public final class StoreKitWindowManager: NSObject, NSWindowDelegate {
    public static let shared = StoreKitWindowManager()

    private var windowControllers: [StoreKitWindowController] = []

    private override init() {
        super.init()
    }

    public func showWindow(for fileURL: URL? = nil) {
        // If a window for this file is already open, focus it
        if let fileURL = fileURL,
           let existing = windowControllers.first(where: { $0.associatedURL == fileURL }) {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let wc = StoreKitWindowController(fileURL: fileURL)
        wc.window?.delegate = self
        windowControllers.append(wc)
        wc.window?.makeKeyAndOrderFront(nil)
    }

    public func closeAllWindows() {
        for wc in windowControllers {
            wc.close()
        }
        windowControllers.removeAll()
    }

    // MARK: - NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow,
           let wc = window.windowController as? StoreKitWindowController {
            windowControllers.removeAll { $0 === wc }
        }
    }
}
