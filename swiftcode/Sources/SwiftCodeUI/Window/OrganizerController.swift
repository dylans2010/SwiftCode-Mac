import AppKit
import SwiftCodeIDECore

@MainActor
public final class OrganizerController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSMenuItemValidation {
    public let archivesDirectory: URL
    public private(set) var state = OrganizerState()
    public var groups: [(app: String, archives: [ArchiveEntry])] { state.groups }
    public var rows: [OrganizerState.Row] { state.rows }
    public var selected: ArchiveEntry? { state.selected }
    public private(set) var lastExport: (status: Int32, output: String)?
    let table = NSTableView()
    let sidebarTable = NSTableView()
    let emptyTitle = NSTextField(labelWithString: "")
    let emptyMessage = NSTextField(labelWithString: "")
    var emptyView: NSView?
    var archivesViews: [NSView] = []
    public var page: String { state.page }
    public var pageSection: String { state.section }

    public func showPage(_ page: String, section: String) {
        _ = view
        state.showPage(page, section: section)
        refreshPage()
    }

    private func refreshPage() {
        let has = state.showsArchives
        archivesViews.forEach { $0.isHidden = !has }
        emptyView?.isHidden = has
        let e = state.emptyState
        emptyTitle.stringValue = e.title
        emptyMessage.stringValue = e.message
        view.window?.title = page
        pageTitle.stringValue = page
        backButton.isEnabled = canGoBack
        forwardButton.isEnabled = canGoForward
        if let i = state.sidebarRow, sidebarTable.selectedRow != i {
            sidebarTable.selectRowIndexes([i], byExtendingSelection: false)
        }
    }

    public var history: [(section: String, page: String)] { state.history }
    public var historyIndex: Int { state.historyIndex }
    public let backButton = NSButton()
    public let forwardButton = NSButton()
    public let bellButton = NSButton()
    let pageTitle = NSTextField(labelWithString: "Archives")
    public var notificationsShown: Bool { state.notificationsShown }
    private var notificationsPopover: NSPopover?
    public static let noNotificationsText = OrganizerState.noNotificationsText

    public var canGoBack: Bool { state.canGoBack }
    public var canGoForward: Bool { state.canGoForward }

    @objc public func goBack() { moveInHistory(-1) }
    @objc public func goForward() { moveInHistory(1) }

    private func moveInHistory(_ step: Int) {
        _ = view
        if state.moveInHistory(step) { refreshPage() }
    }

    @objc public func toggleNotifications() {
        state.notificationsShown.toggle()
        if notificationsShown, view.window?.isVisible == true {
            let vc = NSViewController()
            let l = NSTextField(labelWithString: Self.noNotificationsText)
            l.textColor = .secondaryLabelColor
            let box = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 80))
            l.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(l)
            l.centerXAnchor.constraint(equalTo: box.centerXAnchor).isActive = true
            l.centerYAnchor.constraint(equalTo: box.centerYAnchor).isActive = true
            vc.view = box
            let pop = NSPopover()
            pop.contentViewController = vc
            pop.behavior = .transient
            pop.show(relativeTo: bellButton.bounds, of: bellButton, preferredEdge: .maxY)
            notificationsPopover = pop
        } else {
            notificationsPopover?.close()
            notificationsPopover = nil
        }
    }

    public static let toolbarItems: [NSToolbarItem.Identifier] = [
        .init("organizer.back"), .init("organizer.forward"), .init("organizer.title"), .flexibleSpace, .init("organizer.bell"),
    ]

    public private(set) lazy var toolbar: NSToolbar = {
        for (b, sym, desc, sel) in [(backButton, "chevron.left", "Back", #selector(goBack)), (forwardButton, "chevron.right", "Forward", #selector(goForward)),
                                    (bellButton, "bell", "Notifications", #selector(toggleNotifications))] {
            b.image = NSImage(systemSymbolName: sym, accessibilityDescription: desc)
            b.bezelStyle = .texturedRounded
            b.isBordered = false
            b.target = self
            b.action = sel
            b.toolTip = desc
        }
        pageTitle.font = .boldSystemFont(ofSize: 13)
        let t = NSToolbar(identifier: "OrganizerToolbar")
        t.delegate = toolbarDelegate
        t.displayMode = .iconOnly
        t.allowsUserCustomization = false
        return t
    }()

    private lazy var toolbarDelegate = OrganizerToolbarDelegate(owner: self)

    func toolbarView(for id: NSToolbarItem.Identifier) -> NSView? {
        switch id.rawValue {
        case "organizer.back": return backButton
        case "organizer.forward": return forwardButton
        case "organizer.title": return pageTitle
        case "organizer.bell": return bellButton
        default: return nil
        }
    }

    public override func viewDidLayout() {
        super.viewDidLayout()
        table.sizeToFit()
    }

    public override func viewWillAppear() {
        super.viewWillAppear()
        installToolbar()
    }

    public func installToolbar() {
        guard let w = view.window, w.toolbar !== toolbar else { return }
        w.toolbar = toolbar
        w.toolbarStyle = .unified
    }

    let details = NSStackView()
    let distributeButton = NSButton(title: OrganizerState.distributeTitle, target: nil, action: nil)

    public init(archivesDirectory: URL = Organizer.defaultArchivesDirectory) {
        self.archivesDirectory = archivesDirectory
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public override func loadView() {
        let root = PanelBackgroundView(frame: NSRect(x: 0, y: 0, width: 900, height: 520))
        appPicker.target = self
        appPicker.action = #selector(appPicked(_:))
        let sideCol = NSTableColumn(identifier: .init("side"))
        sidebarTable.addTableColumn(sideCol)
        sidebarTable.headerView = nil
        sidebarTable.dataSource = self
        sidebarTable.delegate = self
        sidebarTable.style = .sourceList
        let sideScroll = NSScrollView()
        sideScroll.documentView = sidebarTable
        let sidebar = NSStackView(views: [appPicker, sideScroll])
        sidebar.orientation = .vertical
        sidebar.alignment = .leading
        emptyTitle.font = .boldSystemFont(ofSize: 17)
        emptyMessage.textColor = .secondaryLabelColor
        let empty = NSStackView(views: [emptyTitle, emptyMessage])
        empty.orientation = .vertical
        emptyView = empty
        for col in OrganizerState.columns {
            let c = NSTableColumn(identifier: .init(col.id))
            c.title = col.title
            c.width = col.width
            table.addTableColumn(c)
        }
        table.dataSource = self
        table.delegate = self
        table.menu = rowMenu
        table.rowSizeStyle = .small
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.usesAlternatingRowBackgroundColors = true
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        details.orientation = .vertical
        details.alignment = .leading
        details.spacing = 6
        distributeButton.target = self
        distributeButton.action = #selector(distributeClicked)
        distributeButton.bezelStyle = .rounded
        let side = NSStackView(views: [details, distributeButton])
        side.orientation = .vertical
        side.alignment = .leading
        side.spacing = 14
        side.edgeInsets = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        archivesViews = [scroll, side]
        _ = toolbar
        for v in [sidebar, scroll, side, empty] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        NSLayoutConstraint.activate([
            sidebar.topAnchor.constraint(equalTo: root.topAnchor, constant: 10), sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor), sidebar.widthAnchor.constraint(equalToConstant: 180),
            sideScroll.widthAnchor.constraint(equalTo: sidebar.widthAnchor),
            scroll.topAnchor.constraint(equalTo: root.topAnchor), scroll.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: 8),
            empty.centerXAnchor.constraint(equalTo: scroll.centerXAnchor, constant: 125), empty.centerYAnchor.constraint(equalTo: root.centerYAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor), scroll.trailingAnchor.constraint(equalTo: side.leadingAnchor),
            side.topAnchor.constraint(equalTo: root.topAnchor), side.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            side.widthAnchor.constraint(equalToConstant: 250),
        ])
        view = root
        reload()
        showPage("Archives", section: "Products")
    }

    static var exportedPaths: Set<String> = []

    public let appPicker = NSPopUpButton(frame: .zero, pullsDown: false)
    public var selectedApp: String? { state.selectedApp }

    public var appPickerTitles: [String] { state.appPickerTitles }

    public func chooseApp(_ app: String) {
        state.chooseApp(app)
        reload()
    }

    @objc func appPicked(_ p: NSPopUpButton) { if let t = p.titleOfSelectedItem { chooseApp(t) } }

    func refreshAppPicker() {
        let titles = appPickerTitles
        if appPicker.itemTitles != titles {
            appPicker.removeAllItems()
            appPicker.addItems(withTitles: titles)
        }
        appPicker.isEnabled = !groups.isEmpty
        if let a = selectedApp { appPicker.selectItem(withTitle: a) } else { appPicker.selectItem(at: 0) }
    }

    public func reload() {
        state.load(Organizer.archives(in: archivesDirectory), exported: Self.exportedPaths)
        refreshAppPicker()
        guard isViewLoaded else { return }
        table.reloadData()
        if let i = state.selectedRow { table.selectRowIndexes([i], byExtendingSelection: false) }
        showDetails()
    }

    public func select(archiveAt url: URL) {
        _ = view
        reload()
        state.select(archiveAt: url)
        refreshAppPicker()
        table.reloadData()
        if let i = state.selectedRow { table.selectRowIndexes([i], byExtendingSelection: false) }
        showDetails()
    }

    public var detailRows: [(String, String)] { state.detailRows }

    func showDetails() {
        details.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for (l, v) in detailRows {
            let label = NSTextField(labelWithString: l)
            label.font = .boldSystemFont(ofSize: 11)
            let value = NSTextField(wrappingLabelWithString: v)
            value.font = .systemFont(ofSize: 11)
            value.preferredMaxLayoutWidth = 220
            details.addArrangedSubview(label)
            if !v.isEmpty { details.addArrangedSubview(value) }
        }
        distributeButton.isEnabled = state.canDistribute
    }

    @discardableResult
    public func distribute(to folder: URL) -> URL? {
        guard let a = selected, a.hasApplication else { return nil }
        let result = Organizer.exportCopy(a.url, to: folder)
        lastExport = result
        guard result.status == 0 else { return nil }
        Self.exportedPaths.insert(a.url.standardizedFileURL.path)
        state.markExported(a.url)
        showDetails()
        table.reloadData()
        return folder.appendingPathComponent(a.appName + ".app")
    }

    private lazy var rowMenu: NSMenu = {
        let m = NSMenu()
        let item = NSMenuItem(title: OrganizerState.showInFilesTitle, action: #selector(showClickedInFinder), keyEquivalent: "")
        item.target = self
        m.addItem(item)
        return m
    }()

    @discardableResult
    public func showInFinder(row: Int? = nil) -> URL? {
        let r = row ?? state.selectedRow
        guard let r, rows.indices.contains(r), let a = rows[r].archive else { return nil }
        if view.window?.isVisible == true { NSWorkspace.shared.activateFileViewerSelecting([a.url]) }
        return a.url
    }

    @objc private func showClickedInFinder() { showInFinder(row: table.clickedRow >= 0 ? table.clickedRow : nil) }

    public func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard item.action == #selector(showClickedInFinder) else { return true }
        let r = table.clickedRow >= 0 ? table.clickedRow : (state.selectedRow ?? -1)
        return rows.indices.contains(r) && rows[r].archive != nil
    }

    @objc private func distributeClicked() {
        guard view.window?.isVisible == true, let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = "Choose where to copy the app (Copy App: mac-application)."
        panel.beginSheetModal(for: window) { [weak self] r in
            if r == .OK, let url = panel.url { self?.distribute(to: url) }
        }
    }

    public func numberOfRows(in t: NSTableView) -> Int { t === sidebarTable ? OrganizerSidebar.rows.count : rows.count }
    public func tableView(_ t: NSTableView, isGroupRow row: Int) -> Bool {
        t === sidebarTable ? OrganizerSidebar.rows[row].page == nil : rows[row].archive == nil
    }
    public func tableView(_ t: NSTableView, shouldSelectRow row: Int) -> Bool {
        t === sidebarTable ? OrganizerSidebar.rows[row].page != nil : rows[row].archive != nil
    }

    public func tableViewSelectionDidChange(_ n: Notification) {
        if (n.object as? NSTableView) === sidebarTable {
            let i = sidebarTable.selectedRow
            if i >= 0, let p = OrganizerSidebar.rows[i].page { showPage(p, section: OrganizerSidebar.rows[i].section) }
            return
        }
        let r = table.selectedRow
        state.selectRow(r >= 0 ? r : nil)
        showDetails()
    }

    public func tableView(_ t: NSTableView, viewFor c: NSTableColumn?, row: Int) -> NSView? {
        if t === sidebarTable {
            let s = OrganizerSidebar.rows[row]
            let l = NSTextField(labelWithString: s.page ?? s.section)
            if s.page == nil { l.font = .boldSystemFont(ofSize: 11); l.textColor = .secondaryLabelColor }
            return l
        }
        let r = rows[row]
        guard let a = r.archive else {
            let l = NSTextField(labelWithString: r.title)
            l.font = .boldSystemFont(ofSize: 12)
            return l
        }
        let cell = NSTextField(labelWithString: OrganizerState.cellText(a, column: c?.identifier.rawValue ?? "status"))
        cell.lineBreakMode = .byTruncatingTail
        return cell
    }
}

@MainActor
final class OrganizerToolbarDelegate: NSObject, NSToolbarDelegate {
    weak var owner: OrganizerController?
    init(owner: OrganizerController) { self.owner = owner }
    func toolbarDefaultItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] { OrganizerController.toolbarItems }
    func toolbarAllowedItemIdentifiers(_ t: NSToolbar) -> [NSToolbarItem.Identifier] { OrganizerController.toolbarItems }
    func toolbar(_ t: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar f: Bool) -> NSToolbarItem? {
        guard let v = owner?.toolbarView(for: id) else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.view = v
        item.label = (v as? NSButton)?.toolTip ?? ""
        if id.rawValue == "organizer.back" || id.rawValue == "organizer.forward" { item.isNavigational = true }
        return item
    }
}
