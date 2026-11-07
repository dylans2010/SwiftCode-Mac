import AppKit
import SwiftUI

@MainActor
public final class VisualUIBuilderWindowManager: NSObject, NSWindowDelegate, NSToolbarDelegate {
    public static let shared = VisualUIBuilderWindowManager()
    private var window: NSWindow?
    private var splitViewController: VisualUIBuilderSplitViewController?

    public func showWindow() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Visual UI Builder Workspace"
        window.minSize = NSSize(width: 1000, height: 700)
        window.setFrameAutosaveName("VisualUIBuilderMainWindow")
        window.collectionBehavior = [.fullScreenPrimary, .managed]
        window.delegate = self

        let splitVC = VisualUIBuilderSplitViewController()
        window.contentViewController = splitVC
        self.splitViewController = splitVC

        let toolbar = NSToolbar(identifier: "VisualUIBuilderToolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar

        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    public func closeWindow() {
        window?.close()
        window = nil
        splitViewController = nil
    }

    public func windowWillClose(_ notification: Notification) {
        window = nil
        splitViewController = nil
    }

    public func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)

        switch itemIdentifier {
        case .toggleSidebar:
            item.label = "Toggle Left Sidebar"
            item.paletteLabel = "Toggle Left Sidebar"
            item.toolTip = "Toggle Component Library Sidebar"
            item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(toggleLeftSidebarAction(_:))
            return item

        case .toggleInspector:
            item.label = "Toggle Right Inspector"
            item.paletteLabel = "Toggle Right Inspector"
            item.toolTip = "Toggle Properties Inspector"
            item.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(toggleRightInspectorAction(_:))
            return item

        default:
            return nil
        }
    }

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, .toggleInspector]
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, .toggleInspector, .space]
    }

    @objc private func toggleLeftSidebarAction(_ sender: Any?) {
        splitViewController?.toggleLeftSidebar(sender)
    }

    @objc private func toggleRightInspectorAction(_ sender: Any?) {
        splitViewController?.toggleRightInspector(sender)
    }
}
