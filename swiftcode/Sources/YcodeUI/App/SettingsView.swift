import AppKit
import SwiftUI

struct SettingsItem: Identifiable, Hashable {
    let id: String
    let title: String
    let icon: String
    let iconBgColor: Color
    let category: String
    let sortOrder: Int
    let keywords: String
    let helpDoc: String

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: SettingsItem, rhs: SettingsItem) -> Bool {
        lhs.id == rhs.id
    }
}

@Observable
@MainActor
public final class SettingsCoordinator {
    public var selectedPaneId: String = "general"
    public var searchText: String = ""
    public var favorites: [String] = []
    public var recents: [String] = []
    public var showInspector: Bool = true
    public var isFullScreen: Bool = false

    private static let favoritesKey = "com.swiftcode.settings.favorites"
    private static let recentsKey = "com.swiftcode.settings.recents"

    public init() {
        loadFavoritesAndRecents()
    }

    public func loadFavoritesAndRecents() {
        favorites = UserDefaults.standard.stringArray(forKey: Self.favoritesKey) ?? []
        recents = UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? []
    }

    public func toggleFavorite(id: String) {
        if favorites.contains(id) {
            favorites.removeAll { $0 == id }
        } else {
            favorites.append(id)
        }
        UserDefaults.standard.set(favorites, forKey: Self.favoritesKey)
    }

    public func appendToRecents(id: String) {
        recents.removeAll { $0 == id }
        recents.insert(id, at: 0)
        recents = Array(recents.prefix(5))
        UserDefaults.standard.set(recents, forKey: Self.recentsKey)
    }
}

@MainActor
public final class SettingsWindowManager: NSObject, NSWindowDelegate {
    public static let shared = SettingsWindowManager()
    private var windowControllers: [SettingsWindowController] = []

    public func showSettings() {
        let wc = SettingsWindowController()
        wc.window?.delegate = self
        if let window = wc.window {
            window.isReleasedWhenClosed = false
            let mainWindow = NSApp.mainWindow ?? NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0 != window && !($0 is NSPanel) })
            if let main = mainWindow {
                let mainFrame = main.frame
                let originX = mainFrame.origin.x + (mainFrame.width - window.frame.width) / 2.0
                let originY = mainFrame.origin.y + (mainFrame.height - window.frame.height) / 2.0
                window.setFrame(NSRect(x: originX, y: originY, width: window.frame.width, height: window.frame.height), display: true)
                window.order(.above, relativeTo: main.windowNumber)
            }
            windowControllers.append(wc)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    public var isSettingsOpen: Bool {
        return windowControllers.contains { $0.window?.isVisible ?? false }
    }

    @discardableResult
    public func focusIfVisible() -> Bool {
        if let active = windowControllers.first(where: { $0.window?.isVisible ?? false })?.window {
            let mainWindow = NSApp.mainWindow ?? NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible && $0 != active && !($0 is NSPanel) })
            if let main = mainWindow {
                active.order(.above, relativeTo: main.windowNumber)
            }
            active.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return true
        }
        return false
    }

    public func closeSettings() {
        let controllers = windowControllers
        windowControllers.removeAll()
        for wc in controllers {
            wc.window?.close()
        }
    }

    public func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow,
           let wc = windowControllers.first(where: { $0.window == window }) {
            windowControllers.removeAll { $0 == wc }
        }
    }
}

@MainActor
public struct DebugSettingsView: View {
    @State private var coordinator = SettingsCoordinator()

    public init() {}

    public var body: some View {
        SettingsMainWrapper(coordinator: coordinator)
    }
}

public final class SettingsSplitViewController: NSSplitViewController {
    public let coordinator: SettingsCoordinator

    private var sidebarItem: NSSplitViewItem?
    private var mainItem: NSSplitViewItem?

    public init(coordinator: SettingsCoordinator) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        setupSplitView()
    }

    override public func viewDidAppear() {
        super.viewDidAppear()
        if let window = view.window {
            NotificationCenter.default.addObserver(self, selector: #selector(windowDidEnterFullScreen(_:)), name: NSWindow.didEnterFullScreenNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(windowDidExitFullScreen(_:)), name: NSWindow.didExitFullScreenNotification, object: window)
        }
    }

    override public func viewWillDisappear() {
        super.viewWillDisappear()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didEnterFullScreenNotification, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSWindow.didExitFullScreenNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func windowDidEnterFullScreen(_ notification: Notification) {
        coordinator.isFullScreen = true
        splitView.needsLayout = true
    }

    @objc private func windowDidExitFullScreen(_ notification: Notification) {
        coordinator.isFullScreen = false
        splitView.needsLayout = true
    }

    private func setupSplitView() {
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.autoresizingMask = [.width, .height]

        let sidebarVC = SettingsSidebarViewController(coordinator: coordinator)
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        sidebarItem.minimumThickness = 240
        sidebarItem.maximumThickness = 320
        sidebarItem.holdingPriority = .defaultLow + 10
        self.sidebarItem = sidebarItem
        addSplitViewItem(sidebarItem)

        let mainView = SettingsMainWrapper(coordinator: coordinator)
            .environmentObject(AppSettings.shared)
            .environment(ThemeViewModel())
        let mainVC = NSHostingController(rootView: StylingBootstrap.configureEnvironment(mainView))
        mainVC.sizingOptions = []
        mainVC.view.autoresizingMask = [.width, .height]
        let mainItem = NSSplitViewItem(viewController: mainVC)
        mainItem.minimumThickness = 500
        mainItem.holdingPriority = .defaultLow - 10
        self.mainItem = mainItem
        addSplitViewItem(mainItem)
    }
}

public final class SettingsSidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    public let coordinator: SettingsCoordinator
    private var scrollView: NSScrollView?
    private var outlineView: NSOutlineView?
    private var nodes: [SettingsSidebarNode] = []

    public init(coordinator: SettingsCoordinator) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
        rebuildNodes()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func loadView() {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .sidebar
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active
        visualEffectView.autoresizingMask = [.width, .height]

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]
        scroll.translatesAutoresizingMaskIntoConstraints = false
        self.scrollView = scroll

        let outline = NSOutlineView()
        outline.autoresizingMask = [.width]
        outline.headerView = nil
        outline.selectionHighlightStyle = .sourceList
        outline.style = .sourceList
        outline.floatsGroupRows = false
        outline.rowSizeStyle = .custom
        outline.indentationPerLevel = 14
        self.outlineView = outline

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SettingsSidebarColumn"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column

        outline.dataSource = self
        outline.delegate = self

        scroll.documentView = outline
        visualEffectView.addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: visualEffectView.topAnchor, constant: 40),
            scroll.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor)
        ])

        self.view = visualEffectView
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        expandAllGroups()
    }

    private func expandAllGroups() {
        if let outline = outlineView {
            for group in nodes {
                outline.expandItem(group)
            }
        }
    }

    func rebuildNodes() {
        nodes = buildSettingsSidebarNodes(coordinator: coordinator)
        outlineView?.reloadData()
        expandAllGroups()
    }

    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return nodes.count
        }
        if let node = item as? SettingsSidebarNode {
            return node.children.count
        }
        return 0
    }

    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return nodes[index]
        }
        guard let node = item as? SettingsSidebarNode else { return SettingsSidebarNode(title: "") }
        return node.children[index]
    }

    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let node = item as? SettingsSidebarNode {
            return node.isGroup
        }
        return false
    }

    public func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        if let node = item as? SettingsSidebarNode {
            return node.isGroup
        }
        return false
    }

    public func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        if let node = item as? SettingsSidebarNode {
            return !node.isGroup
        }
        return true
    }

    public func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        if let node = item as? SettingsSidebarNode, node.isGroup {
            return 26
        }
        return 32
    }

    public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? SettingsSidebarNode else { return nil }

        if node.isGroup {
            let identifier = NSUserInterfaceItemIdentifier("HeaderView")
            var textField = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTextField
            if textField == nil {
                textField = NSTextField(labelWithString: node.title)
                textField?.identifier = identifier
                textField?.font = .systemFont(ofSize: 11, weight: .bold)
                textField?.textColor = .headerTextColor
            } else {
                textField?.stringValue = node.title
            }
            return textField
        } else {
            let identifier = NSUserInterfaceItemIdentifier("SidebarCell")
            var cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? SettingsSidebarCellView
            if cell == nil {
                cell = SettingsSidebarCellView(frame: .zero)
                cell?.identifier = identifier
            }

            cell?.textField?.stringValue = node.title
            if let iconName = node.icon {
                if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
                    cell?.iconView.image = image
                } else {
                    cell?.iconView.image = nil
                }
            } else {
                cell?.iconView.image = nil
            }
            cell?.iconBackground.fillColor = .clear
            cell?.iconBackground.isTransparent = true
            cell?.iconView.contentTintColor = .systemOrange

            let menu = NSMenu()
            let favItem = NSMenuItem(title: coordinator.favorites.contains(node.id) ? "Remove from Favorites" : "Add to Favorites", action: #selector(toggleFavoriteAction(_:)), keyEquivalent: "")
            favItem.representedObject = node
            menu.addItem(favItem)
            cell?.menu = menu

            return cell
        }
    }

    @objc private func toggleFavoriteAction(_ sender: NSMenuItem) {
        if let node = sender.representedObject as? SettingsSidebarNode {
            coordinator.toggleFavorite(id: node.id)
            rebuildNodes()
        }
    }

    public func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let outline = outlineView else { return }
        let selectedRow = outline.selectedRow
        if selectedRow >= 0, let node = outline.item(atRow: selectedRow) as? SettingsSidebarNode, !node.isGroup {
            coordinator.selectedPaneId = node.id
            coordinator.appendToRecents(id: node.id)
            rebuildNodes()
        }
    }
}

public final class SettingsSidebarNode: NSObject {
    public let id: String
    public let title: String
    public let icon: String?
    public let color: NSColor?
    public let isGroup: Bool
    public var children: [SettingsSidebarNode] = []

    public init(id: String = UUID().uuidString, title: String, icon: String? = nil, color: NSColor? = nil, isGroup: Bool = false) {
        self.id = id
        self.title = title
        self.icon = icon
        self.color = color
        self.isGroup = isGroup
    }
}

struct SettingsMainWrapper: View {
    let coordinator: SettingsCoordinator
    @EnvironmentObject private var settings: AppSettings
    @Environment(ThemeViewModel.self) var themeVM

    var body: some View {
        if let currentItem = settingsRegistryList.first(where: { $0.id == coordinator.selectedPaneId }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(currentItem.iconBgColor)
                                .frame(width: 38, height: 38)
                            Image(systemName: currentItem.icon)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(currentItem.title)
                                .font(.title2.bold())
                            Text(currentItem.category)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button {
                            coordinator.toggleFavorite(id: currentItem.id)
                        } label: {
                            Image(systemName: coordinator.favorites.contains(currentItem.id) ? "star.fill" : "star")
                                .foregroundStyle(coordinator.favorites.contains(currentItem.id) ? Color.yellow : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Toggle Favorite")
                    }
                    .padding(16)
                    .liquidGlass(style: .standard, cornerRadius: 12)
                    .padding(.horizontal, 24)
                    .padding(.top, 24)

                    Divider()
                        .padding(.horizontal, 24)

                    destinationView(for: currentItem.id)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(NSColor.controlBackgroundColor))
        } else {
            ContentUnavailableView("Select a category", systemImage: "gearshape")
        }
    }

    @ViewBuilder
    private func destinationView(for id: String) -> some View {
        switch id {
        case "general":
            GeneralSettingsView()
                .environmentObject(settings)
        case "themes":
            ThemeManagementView()
                .environmentObject(settings)
        case "cloud":
            CloudManagementView()
        case "backups":
            BackupsView()
        case "connect_host":
            ConnectSettingsView()
        case "ai_assist":
            AssistSettingsView()
        case "composio":
            ComposioSettingsView()
        case "offline_models":
            OfflineModelsView()
        case "plugins":
            PluginManagerView()
        case "updates":
            UpdatesView()
        case "credits":
            CreditsView()
        default:
            GeneralSettingsView()
                .environmentObject(settings)
        }
    }
}
