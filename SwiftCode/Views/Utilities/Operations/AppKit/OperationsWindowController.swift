import AppKit
import SwiftUI

@MainActor
public final class OperationsWindowManager: NSObject, NSWindowDelegate {
    public static let shared = OperationsWindowManager()
    private var windowController: OperationsWindowController?

    public func showWindow() {
        if let existing = windowController {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let wc = OperationsWindowController()
        wc.window?.delegate = self
        self.windowController = wc
        wc.window?.makeKeyAndOrderFront(nil)
    }

    public func closeWindow() {
        windowController?.close()
        windowController = nil
    }

    // MARK: - NSWindowDelegate
    public func windowWillClose(_ notification: Notification) {
        windowController = nil
    }
}

@MainActor
public final class OperationsWindowController: NSWindowController {

    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 80, y: 80, width: 1280, height: 850),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Operations Workspace"
        window.minSize = NSSize(width: 1024, height: 700)
        window.setFrameAutosaveName("OperationsMainWindow")
        window.collectionBehavior = [.fullScreenPrimary, .managed]

        super.init(window: window)

        let splitVC = OperationsSplitViewController()
        window.contentViewController = splitVC

        setupToolbar(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupToolbar(window: NSWindow) {
        let toolbar = NSToolbar(identifier: "OperationsToolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
    }
}

extension OperationsWindowController: NSToolbarDelegate {
    public func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)

        switch itemIdentifier {
        case .toggleSidebar:
            item.label = "Toggle Sidebar"
            item.paletteLabel = "Toggle Sidebar"
            item.toolTip = "Toggle the workspace sidebar"
            item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(toggleSidebarAction(_:))

        case .toggleInspector:
            item.label = "Toggle Inspector"
            item.paletteLabel = "Toggle Inspector"
            item.toolTip = "Toggle the right inspector panel"
            item.image = NSImage(systemSymbolName: "sidebar.right", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(toggleInspectorAction(_:))

        case .refreshWorkspace:
            item.label = "Rescan"
            item.paletteLabel = "Rescan"
            item.toolTip = "Force refresh diagnostics and storage metrics"
            item.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(refreshWorkspaceAction(_:))

        default:
            return nil
        }
        return item
    }

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, .refreshWorkspace, .flexibleSpace, .toggleInspector]
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.toggleSidebar, .toggleInspector, .refreshWorkspace, .flexibleSpace, .space]
    }
}

extension NSToolbarItem.Identifier {
    public static let toggleSidebar = NSToolbarItem.Identifier("toggleSidebar")
    public static let toggleInspector = NSToolbarItem.Identifier("toggleInspector")
    public static let refreshWorkspace = NSToolbarItem.Identifier("refreshWorkspace")
}

extension OperationsWindowController {
    @objc private func toggleSidebarAction(_ sender: Any?) {
        if let splitVC = contentViewController as? OperationsSplitViewController {
            splitVC.toggleSidebar()
        }
    }

    @objc private func toggleInspectorAction(_ sender: Any?) {
        if let splitVC = contentViewController as? OperationsSplitViewController {
            splitVC.toggleInspector()
        }
    }

    @objc private func refreshWorkspaceAction(_ sender: Any?) {
        NotificationCenter.default.post(name: NSNotification.Name("OperationsForceRefresh"), object: nil)
    }
}

// MARK: - Native Split View Controller
@MainActor
public class OperationsSplitViewController: NSSplitViewController {
    private var sidebarItem: NSSplitViewItem?
    private var mainItem: NSSplitViewItem?
    private var inspectorItem: NSSplitViewItem?

    override public func viewDidLoad() {
        super.viewDidLoad()
        setupSplitView()
    }

    private func setupSplitView() {
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autoresizingMask = [.width, .height]

        // Sidebar Panel
        let sidebarVC = NSHostingController(rootView: OperationsSidebarView())
        sidebarVC.sizingOptions = []
        sidebarVC.view.autoresizingMask = [.width, .height]
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        sidebarItem.minimumThickness = 220
        sidebarItem.maximumThickness = 320
        sidebarItem.holdingPriority = .defaultLow + 10
        self.sidebarItem = sidebarItem
        addSplitViewItem(sidebarItem)

        // Main Workspace Panel
        let mainVC = NSHostingController(rootView: OperationsWorkspaceView())
        mainVC.sizingOptions = []
        mainVC.view.autoresizingMask = [.width, .height]
        let mainItem = NSSplitViewItem(viewController: mainVC)
        mainItem.minimumThickness = 650
        mainItem.holdingPriority = .defaultLow - 10
        self.mainItem = mainItem
        addSplitViewItem(mainItem)

        // Inspector Panel (starts collapsed)
        let inspectorVC = NSHostingController(rootView: SCInspectorView())
        inspectorVC.sizingOptions = []
        inspectorVC.view.autoresizingMask = [.width, .height]
        let inspectorItem = NSSplitViewItem(viewController: inspectorVC)
        inspectorItem.minimumThickness = 240
        inspectorItem.maximumThickness = 350
        inspectorItem.isCollapsed = true
        inspectorItem.holdingPriority = .defaultLow + 20
        self.inspectorItem = inspectorItem
        addSplitViewItem(inspectorItem)
    }

    public func toggleSidebar() {
        if let sidebar = sidebarItem {
            sidebar.isCollapsed.toggle()
            OperationsCoordinator.shared.isSidebarCollapsed = sidebar.isCollapsed
        }
    }

    public func toggleInspector() {
        if let inspector = inspectorItem {
            inspector.isCollapsed.toggle()
            OperationsCoordinator.shared.showInspector = !inspector.isCollapsed
        }
    }
}
