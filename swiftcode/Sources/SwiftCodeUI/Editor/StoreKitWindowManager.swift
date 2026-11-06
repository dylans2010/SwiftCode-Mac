// Ported from Legacy `SwiftCode/Views/Utilities/StoreKit/Windows/StoreKitWindowManager.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged only — not yet merged into swiftcode/Sources. See staging-wire/missing/DISPOSITIONS.md.
// Verbatim. BLOCKED reference: StoreKitWindowController (Legacy
// `Views/Utilities/StoreKit/Windows/StoreKitWindowController.swift`, PARTIAL,
// another scope) — the manager creates/focuses/closes one per file URL.
// NOTE the tension for the coordinator: the destination's StoreKitEditorModel
// header says the standalone StoreKit window chrome "is not reproduced" (the
// editor is embedded in the workspace window). This manager is staged whole per
// the no-omissions directive; if the controller is deliberately not reproduced,
// the coordinator must decide whether this manager is wired (e.g. by hosting
// StoreKitEditorController in a plain NSWindow) or dropped with cause —
// do not silently drop it here.
// Wiring: showWindow(for:) is the entry point for opening a .storekit file in
// its own window; closeAllWindows() on app/session teardown.

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
