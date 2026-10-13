import AppKit
import SwiftUI

// MARK: - SDKStudioWindowManager
//
// Singleton window manager for SwiftCode Studio (spec §13.3). Mirrors the
// established project pattern (`VisualUIBuilderWindowManager`,
// `DatabaseExplorerWindowManager`, `StoreKitWindowManager`): a shared
// instance owns one window at a time, `windowWillClose` clears the
// reference so a subsequent open creates a fresh window.
//
// The window hosts `SDKStudioView` through `NSHostingController`.
// Callers should use `openStudio(section:)` to deep-link into a section;
// the remembered section is published via `currentSection` for toolbar or
// menu integration by the app layer.

@MainActor
public final class SDKStudioWindowManager: NSObject, ObservableObject, NSWindowDelegate {
    public static let shared = SDKStudioWindowManager()

    /// The section the Studio last opened on; restored on a bare `openStudio()`.
    @Published public private(set) var currentSection: SDKStudioSection = .projects

    private var studioWindow: NSWindow?

    private override init() {
        super.init()
    }

    /// Opens Studio on the last-visited section (or Projects on first launch).
    public func openStudio() {
        openStudio(section: currentSection)
    }

    /// Opens Studio, focusing the given section. If Studio is already open,
    /// its content is re-hosted on the new section and the window is raised.
    public func openStudio(section: SDKStudioSection) {
        currentSection = section

        if let studioWindow {
            studioWindow.contentViewController = NSHostingController(
                rootView: SDKStudioView(initialSection: section)
            )
            studioWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = "SwiftCode Studio"
        window.minSize = NSSize(width: 900, height: 600)
        window.setFrameAutosaveName("SwiftCodeStudioWindow")
        window.collectionBehavior = [.fullScreenPrimary, .managed]
        window.center()

        // A window-level toolbar lets NavigationSplitView render its native
        // sidebar toggle; no Studio-specific items are defined here.
        let toolbar = NSToolbar(identifier: "SwiftCodeStudioToolbar")
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar

        window.contentViewController = NSHostingController(
            rootView: SDKStudioView(initialSection: section)
        )
        window.delegate = self

        studioWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Closes Studio if it is open.
    public func closeStudio() {
        studioWindow?.close()
        studioWindow = nil
    }

    // MARK: - NSWindowDelegate

    public func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === studioWindow {
            studioWindow = nil
        }
    }
}
