import AppKit
import SwiftUI

@MainActor
public class DatabaseExplorerWindowController: NSWindowController {

    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Database Explorer Workspace"
        window.minSize = NSSize(width: 1000, height: 700)
        window.setFrameAutosaveName("DatabaseExplorerMainWindow")
        window.collectionBehavior = [.fullScreenPrimary, .managed]

        super.init(window: window)

        let splitVC = DatabaseExplorerSplitViewController()
        window.contentViewController = splitVC

        setupToolbar(window: window)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupToolbar(window: NSWindow) {
        let toolbar = NSToolbar(identifier: "DatabaseExplorerToolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
    }
}

extension DatabaseExplorerWindowController: NSToolbarDelegate {
    public func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)

        switch itemIdentifier {
        case .toggleSidebar:
            item.label = "Toggle Left Sidebar"
            item.paletteLabel = "Toggle Left Sidebar"
            item.toolTip = "Toggle Database Sidebar"
            item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(toggleLeftSidebarAction(_:))
            return item

        case .toggleInspector:
            item.label = "Toggle Right Inspector"
            item.paletteLabel = "Toggle Right Inspector"
            item.toolTip = "Toggle Database Inspector"
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
}

extension DatabaseExplorerWindowController {
    @objc private func toggleLeftSidebarAction(_ sender: Any?) {
        if let splitVC = contentViewController as? DatabaseExplorerSplitViewController {
            splitVC.toggleLeftSidebar(sender)
        }
    }

    @objc private func toggleRightInspectorAction(_ sender: Any?) {
        if let splitVC = contentViewController as? DatabaseExplorerSplitViewController {
            splitVC.toggleRightInspector(sender)
        }
    }
}
