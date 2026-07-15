import SwiftUI
import AppKit

// MARK: - Settings Item Definition

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

// MARK: - Settings Coordinator

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

// MARK: - Native Settings Window Manager

@MainActor
public final class SettingsWindowManager: NSObject, NSWindowDelegate {
    public static let shared = SettingsWindowManager()
    private var windowControllers: [SettingsWindowController] = []

    public func showSettings() {
        // Support multiple settings windows
        let wc = SettingsWindowController()
        wc.window?.delegate = self
        windowControllers.append(wc)
        wc.window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - NSWindowDelegate
    public func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow,
           let wc = windowControllers.first(where: { $0.window == window }) {
            windowControllers.removeAll { $0 == wc }
        }
    }
}

// MARK: - Native Settings Window Controller

@MainActor
public final class SettingsWindowController: NSWindowController {
    public let coordinator = SettingsCoordinator()

    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 150, y: 150, width: 1050, height: 750),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Preferences"
        window.minSize = NSSize(width: 850, height: 600)
        window.setFrameAutosaveName("SettingsMainWindow")
        window.collectionBehavior = [.fullScreenPrimary, .managed]

        super.init(window: window)

        let splitVC = SettingsSplitViewController(coordinator: coordinator)
        window.contentViewController = splitVC

        setupToolbar(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupToolbar(window: NSWindow) {
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
    }
}

extension SettingsWindowController: NSToolbarDelegate {
    public func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)

        switch itemIdentifier {
        case .toggleSidebar:
            item.label = "Toggle Sidebar"
            item.paletteLabel = "Toggle Sidebar"
            item.toolTip = "Toggle Settings Categories Sidebar"
            item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(toggleSidebarAction(_:))

        case .toggleInspector:
            item.label = "Toggle Inspector"
            item.paletteLabel = "Toggle Inspector"
            item.toolTip = "Toggle Settings Help Inspector"
            item.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(toggleInspectorAction(_:))

        default:
            return nil
        }
        return item
    }

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, .toggleInspector]
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.toggleSidebar, .sidebarTrackingSeparator, .toggleInspector, .flexibleSpace, .space]
    }
}

extension SettingsWindowController {
    @objc private func toggleSidebarAction(_ sender: Any?) {
        if let splitVC = contentViewController as? SettingsSplitViewController {
            splitVC.toggleSidebar(sender)
        }
    }

    @objc private func toggleInspectorAction(_ sender: Any?) {
        withAnimation {
            coordinator.showInspector.toggle()
        }
        if let splitVC = contentViewController as? SettingsSplitViewController {
            splitVC.updateSplitItems(animate: true)
        }
    }
}

// MARK: - Native Settings Split View Controller

public final class SettingsSplitViewController: NSSplitViewController {
    public let coordinator: SettingsCoordinator

    private var sidebarItem: NSSplitViewItem?
    private var mainItem: NSSplitViewItem?
    private var inspectorItem: NSSplitViewItem?

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

        // 1. Sidebar Panel (Pure AppKit View Controller)
        let sidebarVC = SettingsSidebarViewController(coordinator: coordinator)
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        sidebarItem.minimumThickness = 240
        sidebarItem.maximumThickness = 320
        sidebarItem.holdingPriority = .defaultLow + 10
        self.sidebarItem = sidebarItem
        addSplitViewItem(sidebarItem)

        // 2. Main Preferences View (SwiftUI Wrapper)
        let mainView = SettingsMainWrapper(coordinator: coordinator)
            .environmentObject(AppSettings.shared)
            .environment(ThemeViewModel())
        let mainVC = NSHostingController(rootView: mainView)
        mainVC.sizingOptions = []
        mainVC.view.autoresizingMask = [.width, .height]
        let mainItem = NSSplitViewItem(viewController: mainVC)
        mainItem.minimumThickness = 500
        mainItem.holdingPriority = .defaultLow - 10
        self.mainItem = mainItem
        addSplitViewItem(mainItem)

        // 3. Right Inspector Help Panel (SwiftUI Wrapper)
        let inspectorView = SettingsInspectorWrapper(coordinator: coordinator)
        let inspectorVC = NSHostingController(rootView: inspectorView)
        inspectorVC.sizingOptions = []
        inspectorVC.view.autoresizingMask = [.width, .height]
        let inspectorItem = NSSplitViewItem(viewController: inspectorVC)
        inspectorItem.minimumThickness = 260
        inspectorItem.maximumThickness = 320
        inspectorItem.holdingPriority = .defaultLow + 20
        self.inspectorItem = inspectorItem
        addSplitViewItem(inspectorItem)

        updateSplitItems(animate: false)
    }

    public func updateSplitItems(animate: Bool) {
        if let inspector = inspectorItem {
            if animate {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.2
                    inspector.isCollapsed = !coordinator.showInspector
                }
            } else {
                inspector.isCollapsed = !coordinator.showInspector
            }
        }
    }
}

// MARK: - Native Settings Sidebar View Controller

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

        let searchContainer = NSView()
        searchContainer.translatesAutoresizingMaskIntoConstraints = false
        visualEffectView.addSubview(searchContainer)

        let searchField = NSSearchField()
        searchField.placeholderString = "Search settings..."
        searchField.delegate = self
        searchField.bezelStyle = .roundedBezel
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchContainer.addSubview(searchField)

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
            searchContainer.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            searchContainer.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
            searchContainer.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            searchContainer.heightAnchor.constraint(equalToConstant: 44),

            searchField.leadingAnchor.constraint(equalTo: searchContainer.leadingAnchor, constant: 14),
            searchField.trailingAnchor.constraint(equalTo: searchContainer.trailingAnchor, constant: -14),
            searchField.centerYAnchor.constraint(equalTo: searchContainer.centerYAnchor),

            scroll.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: searchContainer.bottomAnchor),
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

    private func rebuildNodes() {
        nodes = buildSettingsSidebarNodes(coordinator: coordinator)
        outlineView?.reloadData()
        expandAllGroups()
    }

    // MARK: - NSOutlineViewDataSource

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

    // MARK: - NSOutlineViewDelegate

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
            if let color = node.color {
                cell?.iconBackground.fillColor = color
            } else {
                cell?.iconBackground.fillColor = .controlAccentColor
            }

            // Right Click Context menu to toggle Favorites
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

extension SettingsSidebarViewController: NSSearchFieldDelegate {
    public func controlTextDidChange(_ obj: Notification) {
        guard let searchField = obj.object as? NSSearchField else { return }
        coordinator.searchText = searchField.stringValue
        rebuildNodes()
    }
}

// MARK: - AppKit Settings Sidebar Node & Cell View

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

final class SettingsSidebarCellView: NSTableCellView {
    let iconBackground = NSBox()
    let iconView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        iconBackground.translatesAutoresizingMaskIntoConstraints = false
        iconBackground.boxType = .custom
        iconBackground.cornerRadius = 6
        iconBackground.borderWidth = 0
        addSubview(iconBackground)

        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.contentTintColor = .white
        iconBackground.addSubview(iconView)

        let text = NSTextField(labelWithString: "")
        text.translatesAutoresizingMaskIntoConstraints = false
        text.font = .systemFont(ofSize: 13)
        text.textColor = .labelColor
        addSubview(text)
        self.textField = text

        NSLayoutConstraint.activate([
            iconBackground.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            iconBackground.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconBackground.widthAnchor.constraint(equalToConstant: 22),
            iconBackground.heightAnchor.constraint(equalToConstant: 22),

            iconView.centerXAnchor.constraint(equalTo: iconBackground.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconBackground.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 12),
            iconView.heightAnchor.constraint(equalToConstant: 12),

            text.leadingAnchor.constraint(equalTo: iconBackground.trailingAnchor, constant: 8),
            text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            text.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

// MARK: - Central Settings Registry list

private let settingsRegistryList: [SettingsItem] = [
    SettingsItem(
        id: "general",
        title: "General",
        icon: "gearshape.fill",
        iconBgColor: .gray,
        category: "System",
        sortOrder: 10,
        keywords: "general interface background appearance font behavior launch startup log path executable editor",
        helpDoc: "Configure general editor preferences, custom startup options, logging levels, and terminal shell behaviors."
    ),
    SettingsItem(
        id: "themes",
        title: "Themes",
        icon: "paintbrush.fill",
        iconBgColor: .pink,
        category: "System",
        sortOrder: 15,
        keywords: "themes colors styles customization dark light visual custom editor fonts highlight darkpro nord gruvbox",
        helpDoc: "Select and modify code-coloring themes, visual parameters, font sizes, font families, and custom text styles."
    ),
    SettingsItem(
        id: "ai_assist",
        title: "AI & Assist",
        icon: "sparkles",
        iconBgColor: .purple,
        category: "A.I. & Tools",
        sortOrder: 20,
        keywords: "ai assist smart complete chat model code suggestion intelligence openrouter local key API suggestions",
        helpDoc: "Setup A.I. routing modes, OpenRouter developer API keys, default completion models, and customize the prompt engineer parameters."
    ),
    SettingsItem(
        id: "offline_models",
        title: "Offline Models",
        icon: "externaldrive.fill",
        iconBgColor: .blue,
        category: "A.I. & Tools",
        sortOrder: 30,
        keywords: "offline models local coreml download storage model weight install local model manager",
        helpDoc: "Download, manage, and cache on-device local models for private, zero-latency secure codebase reasoning."
    ),
    SettingsItem(
        id: "templates",
        title: "Project Templates",
        icon: "doc.badge.plus",
        iconBgColor: .teal,
        category: "A.I. & Tools",
        sortOrder: 40,
        keywords: "templates project custom scaffold boilerplates ios app macos framework library structure boilerplate",
        helpDoc: "Build and organize custom project scaffolds, code boilerplates, target architectures, and standard workspace structures."
    ),
    SettingsItem(
        id: "plugins",
        title: "Plugin Manager",
        icon: "cpu",
        iconBgColor: .orange,
        category: "A.I. & Tools",
        sortOrder: 50,
        keywords: "plugins custom tools automate script capability action plugin manifest code manager interop",
        helpDoc: "Automate development pipelines with custom capability plugins, build scripts, action manifests, and platform extensions."
    ),
    SettingsItem(
        id: "extensions",
        title: "Extensions",
        icon: "puzzlepiece.extension.fill",
        iconBgColor: .indigo,
        category: "Extension & Updates",
        sortOrder: 60,
        keywords: "extensions language linter formatter kotlin python rust typescript spm formatter linting tools capability market",
        helpDoc: "Install and manage language-specific linters, code formatters, and tooling extensions for Python, Go, Rust, and TypeScript."
    ),
    SettingsItem(
        id: "updates",
        title: "Updates",
        icon: "arrow.triangle.2.circlepath.circle.fill",
        iconBgColor: .green,
        category: "Extension & Updates",
        sortOrder: 70,
        keywords: "updates version release check upgrade changelog download system latest news improvements bugfix",
        helpDoc: "Check for updates, view system changelogs, review release notes, and install the latest IDE engine optimizations."
    ),
    SettingsItem(
        id: "credits",
        title: "Credits",
        icon: "person.2.fill",
        iconBgColor: .cyan,
        category: "About",
        sortOrder: 80,
        keywords: "credits licenses developers thirdparty apple swift library contributors team community about",
        helpDoc: "Review licenses for integrated open-source libraries, developer credits, contributors, and legal information."
    )
]

@MainActor
func buildSettingsSidebarNodes(coordinator: SettingsCoordinator) -> [SettingsSidebarNode] {
    var nodes: [SettingsSidebarNode] = []

    let filteredRegistry = settingsRegistryList.filter { item in
        if coordinator.searchText.isEmpty { return true }
        return item.title.localizedCaseInsensitiveContains(coordinator.searchText) ||
               item.keywords.localizedCaseInsensitiveContains(coordinator.searchText) ||
               item.category.localizedCaseInsensitiveContains(coordinator.searchText)
    }

    // 1. Favorites Group (if non-empty and not searching)
    if !coordinator.favorites.isEmpty && coordinator.searchText.isEmpty {
        let favGroup = SettingsSidebarNode(title: "FAVORITES", isGroup: true)
        favGroup.children = coordinator.favorites.compactMap { favId in
            settingsRegistryList.first { $0.id == favId }
        }.map { item in
            SettingsSidebarNode(id: item.id, title: item.title, icon: item.icon, color: NSColor(item.iconBgColor))
        }
        nodes.append(favGroup)
    }

    // 2. Recents Group (if non-empty and not searching)
    if !coordinator.recents.isEmpty && coordinator.searchText.isEmpty {
        let recentGroup = SettingsSidebarNode(title: "RECENTS", isGroup: true)
        recentGroup.children = coordinator.recents.compactMap { rId in
            settingsRegistryList.first { $0.id == rId }
        }.map { item in
            SettingsSidebarNode(id: item.id, title: item.title, icon: item.icon, color: NSColor(item.iconBgColor))
        }
        nodes.append(recentGroup)
    }

    // 3. Category Categorized Groups
    let categories = ["System", "A.I. & Tools", "Extension & Updates", "About"]
    for category in categories {
        let itemsInCategory = filteredRegistry.filter { $0.category == category }
            .sorted { $0.sortOrder < $1.sortOrder }

        if !itemsInCategory.isEmpty {
            let catGroup = SettingsSidebarNode(title: category.uppercased(), isGroup: true)
            catGroup.children = itemsInCategory.map { item in
                SettingsSidebarNode(id: item.id, title: item.title, icon: item.icon, color: NSColor(item.iconBgColor))
            }
            nodes.append(catGroup)
        }
    }

    return nodes
}

// MARK: - Settings Main View Wrapper (SwiftUI)

struct SettingsMainWrapper: View {
    let coordinator: SettingsCoordinator
    @EnvironmentObject private var settings: AppSettings
    @Environment(ThemeViewModel.self) var themeVM

    var body: some View {
        if let currentItem = settingsRegistryList.first(where: { $0.id == coordinator.selectedPaneId }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header
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

                        // Toggle Favorite Button
                        Button {
                            coordinator.toggleFavorite(id: currentItem.id)
                        } label: {
                            Image(systemName: coordinator.favorites.contains(currentItem.id) ? "star.fill" : "star")
                                .foregroundStyle(coordinator.favorites.contains(currentItem.id) ? Color.yellow : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Toggle Favorite")
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)

                    Divider()
                        .padding(.horizontal, 24)

                    // Destination View Loader
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
        case "ai_assist":
            AssistSettingsView()
        case "offline_models":
            OfflineModelsView()
        case "templates":
            ProjectTemplateView()
        case "plugins":
            PluginManagerView()
        case "extensions":
            ExtensionsView()
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

// MARK: - Settings Help Inspector View Wrapper (SwiftUI)

struct SettingsInspectorWrapper: View {
    let coordinator: SettingsCoordinator

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Settings Help")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Divider()

                if let currentItem = settingsRegistryList.first(where: { $0.id == coordinator.selectedPaneId }) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(currentItem.title, systemImage: currentItem.icon)
                            .font(.subheadline.bold())
                            .foregroundStyle(currentItem.iconBgColor)

                        Text(currentItem.helpDoc)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)

                        Divider()

                        Text("Keywords")
                            .font(.caption.bold())
                            .foregroundStyle(.tertiary)

                        FlowLayout(currentItem.keywords.components(separatedBy: " ").filter { !$0.isEmpty }, spacing: 6) { kw in
                            Text(rtrim(kw))
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.12))
                                .cornerRadius(6)
                        }
                    }
                } else {
                    Text("Select a preferences category to view detail diagnostics and context documentation here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(16)
        }
        .background(Color(NSColor.windowBackgroundColor))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func rtrim(_ kw: String) -> String {
        kw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// Simple FlowLayout Helper for Keyword Badges
struct FlowLayout: View {
    let spacing: CGFloat
    let items: [AnyView]

    init<Data: RandomAccessCollection, Content: View>(
        _ data: Data,
        spacing: CGFloat = 8,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.spacing = spacing
        self.items = data.map { AnyView(content($0)) }
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: spacing) {
            ForEach(0..<items.count, id: \.self) { index in
                items[index]
            }
        }
    }
}

// MARK: - NewSettingsView (SwiftUI Sheet Shorthand Fallback)

public struct NewSettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "gearshape.2.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)

            Text("System Preferences")
                .font(.title2.bold())

            Text("Preferences can be loaded inside a dedicated native macOS split-screen settings window.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            HStack(spacing: 12) {
                Button("Open Native Settings Window") {
                    SettingsWindowManager.shared.showSettings()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
        .padding(40)
        .frame(width: 500, height: 350)
        .onAppear {
            SettingsWindowManager.shared.showSettings()
            dismiss()
        }
    }
}
