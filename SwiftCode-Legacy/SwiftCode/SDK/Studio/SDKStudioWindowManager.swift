import AppKit
import SwiftUI

@MainActor
public final class SDKStudioWindowManager: NSObject, ObservableObject, NSWindowDelegate {
    public static let shared = SDKStudioWindowManager()

    private static let lastSectionKey = "com.swiftcode.sdk.studio.lastSection"
    private static let studioIsOpenKey = "com.swiftcode.sdk.studio.isOpen"

    @Published public private(set) var currentSection: SDKStudioSection = .projects

    private var studioWindow: NSWindow?

    public var isStudioOpen: Bool {
        studioWindow != nil
    }

    private override init() {
        if let raw = UserDefaults.standard.string(forKey: Self.lastSectionKey),
           let section = SDKStudioSection(rawValue: raw) {
            self.currentSection = section
        } else {
            self.currentSection = .projects
        }
        super.init()
    }

    public func updateSection(_ section: SDKStudioSection) {
        currentSection = section
        UserDefaults.standard.set(section.rawValue, forKey: Self.lastSectionKey)
        UserDefaults.standard.synchronize()
    }

    public func openStudio() {
        openStudio(section: currentSection)
    }

    public func openStudio(section: SDKStudioSection) {
        updateSection(section)
        UserDefaults.standard.set(true, forKey: Self.studioIsOpenKey)
        UserDefaults.standard.synchronize()

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

    public func closeStudio() {
        studioWindow?.close()
        studioWindow = nil
        UserDefaults.standard.set(false, forKey: Self.studioIsOpenKey)
        UserDefaults.standard.synchronize()
    }

    public func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === studioWindow {
            studioWindow = nil
            UserDefaults.standard.set(false, forKey: Self.studioIsOpenKey)
            UserDefaults.standard.synchronize()
        }
    }
}
