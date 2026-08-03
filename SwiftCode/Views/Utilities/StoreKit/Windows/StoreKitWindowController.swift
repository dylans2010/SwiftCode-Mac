import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
public final class StoreKitWindowController: NSWindowController {

    public let associatedURL: URL?
    public let session: StoreKitWorkspaceSession

    public init(fileURL: URL? = nil) {
        self.associatedURL = fileURL
        self.session = StoreKitWorkspaceSession(fileURL: fileURL)

        let window = NSWindow(
            contentRect: NSRect(x: 150, y: 150, width: 1250, height: 850),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "StoreKit Workspace - Xcode Grade Editor"
        window.minSize = NSSize(width: 1050, height: 750)

        // Remember position using a unique autosave name per file or a general autosave name
        if let fileURL = fileURL {
            window.title = "StoreKit - \(fileURL.lastPathComponent)"
            window.setFrameAutosaveName("StoreKitWorkspace_\(fileURL.lastPathComponent)")
        } else {
            window.setFrameAutosaveName("StoreKitWorkspace_Default")
        }

        window.collectionBehavior = [.fullScreenPrimary, .managed]

        super.init(window: window)

        let splitVC = StoreKitSplitViewController(session: session)
        window.contentViewController = splitVC

        setupToolbar(window: window)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupToolbar(window: NSWindow) {
        let toolbar = NSToolbar(identifier: "StoreKitWorkspaceToolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
    }

    // Overriding standard responder chain to handle native macOS undo/redo shortcuts
    @objc public func undo(_ sender: Any?) {
        session.undo()
    }

    @objc public func redo(_ sender: Any?) {
        session.redo()
    }
}

extension NSToolbarItem.Identifier {
    static let storekitToggleSidebar = NSToolbarItem.Identifier("com.swiftcode.storekit.toggleSidebar")
    static let storekitToggleInspector = NSToolbarItem.Identifier("com.swiftcode.storekit.toggleInspector")
    static let storekitUndo = NSToolbarItem.Identifier("com.swiftcode.storekit.undo")
    static let storekitRedo = NSToolbarItem.Identifier("com.swiftcode.storekit.redo")
    static let storekitSave = NSToolbarItem.Identifier("com.swiftcode.storekit.save")
    static let storekitOpen = NSToolbarItem.Identifier("com.swiftcode.storekit.open")
}

extension StoreKitWindowController: NSToolbarDelegate {
    public func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)

        switch itemIdentifier {
        case .storekitToggleSidebar:
            item.label = "Toggle Left Sidebar"
            item.paletteLabel = "Toggle Left Sidebar"
            item.toolTip = "Toggle Sidebar Panel"
            item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(toggleLeftSidebarAction(_:))
            return item

        case .storekitToggleInspector:
            item.label = "Toggle Right Inspector"
            item.paletteLabel = "Toggle Right Inspector"
            item.toolTip = "Toggle Inspector Panel"
            item.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(toggleRightInspectorAction(_:))
            return item

        case .storekitUndo:
            item.label = "Undo"
            item.paletteLabel = "Undo"
            item.toolTip = "Undo last action"
            item.image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(undo(_:))
            return item

        case .storekitRedo:
            item.label = "Redo"
            item.paletteLabel = "Redo"
            item.toolTip = "Redo last undone action"
            item.image = NSImage(systemSymbolName: "arrow.uturn.forward", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(redo(_:))
            return item

        case .storekitSave:
            item.label = "Save"
            item.paletteLabel = "Save"
            item.toolTip = "Save StoreKit configuration to disk"
            item.image = NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(saveAction(_:))
            return item

        case .storekitOpen:
            item.label = "Open"
            item.paletteLabel = "Open"
            item.toolTip = "Open standard .storekit file from disk"
            item.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(openAction(_:))
            return item

        default:
            return nil
        }
    }

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.storekitToggleSidebar, .sidebarTrackingSeparator, .storekitOpen, .storekitSave, .flexibleSpace, .storekitUndo, .storekitRedo, .flexibleSpace, .storekitToggleInspector]
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.storekitToggleSidebar, .sidebarTrackingSeparator, .storekitOpen, .storekitSave, .storekitUndo, .storekitRedo, .flexibleSpace, .storekitToggleInspector, .space]
    }
}

extension StoreKitWindowController {
    @objc private func toggleLeftSidebarAction(_ sender: Any?) {
        if let splitVC = contentViewController as? StoreKitSplitViewController {
            splitVC.toggleLeftSidebar(sender)
        }
    }

    @objc private func toggleRightInspectorAction(_ sender: Any?) {
        if let splitVC = contentViewController as? StoreKitSplitViewController {
            splitVC.toggleRightInspector(sender)
        }
    }

    @objc private func saveAction(_ sender: Any?) {
        session.saveDocument()
    }

    @objc private func openAction(_ sender: Any?) {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json, UTType(filenameExtension: "storekit")!]
        openPanel.title = "Open StoreKit Configuration"
        openPanel.allowsMultipleSelection = false
        if openPanel.runModal() == .OK, let selectedURL = openPanel.url {
            session.loadDocument(from: selectedURL)
        }
    }
}
