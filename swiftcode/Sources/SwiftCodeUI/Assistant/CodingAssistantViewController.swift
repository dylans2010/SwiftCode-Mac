import AppKit
import SwiftCodeAssistant
import SwiftCodeIDECore

@MainActor
public final class CodingAssistantViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate, NSMenuDelegate {
    public let model: CodingAssistantModel
    public var onReviewProposal: ((ChangeProposal, ConversationMessage, UUID) -> Void)? {
        didSet { conversationView.onReviewProposal = onReviewProposal }
    }
    public var onOpenSettings: (() -> Void)? { didSet { conversationView.onOpenSettings = onOpenSettings } }
    public var attachmentSource: (() -> (file: Attachment?, selection: Attachment?))? {
        didSet { conversationView.attachmentSource = attachmentSource }
    }

    public let newConversationButton = NSComboButton()
    public let newGroupButton = NSButton(title: "New Group", target: nil, action: nil)
    public let list = NSOutlineView()
    public private(set) lazy var conversationView = ConversationView(model: model)
    public private(set) var newConversationMenuPresentations = 0
    private var items: [Item] = []
    private var collapsedGroups: Set<UUID> = []
    private var archiveExpanded = false
    private var reloading = false
    static let dragType = NSPasteboard.PasteboardType("dev.swiftcode.conversation")

    public static let newConversationSize = NSSize(width: 146, height: 27)
    public static let newGroupSize = NSSize(width: 115, height: 27)
    public static let headerSpacing: CGFloat = 8
    static let capsuleOutset = (newConversation: CGFloat(2), newGroup: CGFloat(1.5))
    static let capsuleGap: CGFloat = 7
    let newConversationGlass = GlassBars.capsule()
    let newGroupGlass = GlassBars.capsule()
    public var headerCapsules: [NSView] { GlassBars.enabled ? [newConversationGlass, newGroupGlass] : [] }

    public init(model: CodingAssistantModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public override func loadView() {
        let root = NSView()
        newConversationButton.title = "New Conversation"
        newConversationButton.style = .split
        newConversationButton.target = self
        newConversationButton.action = #selector(newConversationClicked)
        newConversationButton.toolTip = "Start a conversation with the coding assistant"
        newConversationButton.setAccessibilityLabel("New Conversation")
        newGroupButton.bezelStyle = .rounded
        newGroupButton.target = self
        newGroupButton.action = #selector(newGroupClicked)
        newGroupButton.toolTip = "Add a group to the conversation list"
        let glass = GlassBars.enabled
        if glass { newGroupButton.isBordered = false }
        let header = NSStackView(views: [newConversationButton, newGroupButton])
        header.orientation = .horizontal
        header.spacing = glass ? Self.capsuleGap + Self.capsuleOutset.newConversation + Self.capsuleOutset.newGroup : Self.headerSpacing
        header.distribution = .gravityAreas
        for (b, size) in [(newConversationButton as NSView, Self.newConversationSize), (newGroupButton, Self.newGroupSize)] {
            b.translatesAutoresizingMaskIntoConstraints = false
            let w = b.widthAnchor.constraint(equalToConstant: size.width)
            w.priority = .defaultHigh
            w.isActive = true
            b.heightAnchor.constraint(equalToConstant: size.height).isActive = true
            b.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        let col = NSTableColumn(identifier: .init("title"))
        list.addTableColumn(col)
        list.outlineTableColumn = col
        list.headerView = nil
        list.style = .sourceList
        list.rowSizeStyle = .default
        list.dataSource = self
        list.delegate = self
        list.target = self
        list.doubleAction = #selector(renameClicked)
        list.setAccessibilityLabel("Conversations")
        list.registerForDraggedTypes([Self.dragType])
        let menu = NSMenu()
        menu.delegate = self
        list.menu = menu
        let listScroll = NSScrollView()
        listScroll.documentView = list
        listScroll.hasVerticalScroller = true
        listScroll.drawsBackground = false
        listScroll.autohidesScrollers = true

        let separator = NSBox()
        separator.boxType = .separator
        for v in [header, listScroll, separator, conversationView] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        if glass {
            for (g, b, o) in [(newConversationGlass, newConversationButton as NSView, Self.capsuleOutset.newConversation),
                              (newGroupGlass, newGroupButton, Self.capsuleOutset.newGroup)] {
                g.translatesAutoresizingMaskIntoConstraints = false
                root.addSubview(g, positioned: .below, relativeTo: header)
                NSLayoutConstraint.activate([
                    g.leadingAnchor.constraint(equalTo: b.leadingAnchor, constant: -o),
                    g.trailingAnchor.constraint(equalTo: b.trailingAnchor, constant: o),
                    g.centerYAnchor.constraint(equalTo: b.centerYAnchor),
                    g.heightAnchor.constraint(equalToConstant: GlassBars.height),
                ])
            }
        }
        let headerTop = glass ? GlassBars.topOffset + (GlassBars.height - Self.newConversationSize.height) / 2 : 6
        let headerSide = glass ? Self.capsuleGap + Self.capsuleOutset.newConversation : 8
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: headerTop),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: headerSide),
            header.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: glass ? -(Self.capsuleGap + Self.capsuleOutset.newGroup) : -8),
            listScroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: glass ? 6 + 1.5 : 6),
            listScroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            listScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            listScroll.heightAnchor.constraint(equalToConstant: 150),
            separator.topAnchor.constraint(equalTo: listScroll.bottomAnchor),
            separator.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            conversationView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            conversationView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            conversationView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            conversationView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        view = root
        model.observe(owner: self) { [weak self] change in self?.apply(change) }
        reloadNewConversationMenu()
        reloadList()
    }

    func apply(_ change: CodingAssistantModel.Change) {
        guard isViewLoaded else { return }
        switch change {
        case .list: reloadList()
        case .transcript(let id): reloadRow(id)
        case .status: reloadNewConversationMenu()
        }
    }

    public var providerPopUp: NSPopUpButton { conversationView.providerPopUp }
    public var statusLabel: NSTextField { conversationView.statusLabel }
    public var statusButtons: NSStackView { conversationView.statusButtons }
    public var statusText: String? { conversationView.statusText }
    public var transcript: NSStackView { conversationView.transcript }
    public var messageView: ComposerTextView { conversationView.messageView }
    public var sendButton: NSButton { conversationView.sendButton }
    public var attachButton: NSPopUpButton { conversationView.attachButton }
    public var planLabel: NSTextField { conversationView.planLabel }
    public var pendingAttachments: [Attachment] { conversationView.pendingAttachments }
    public var modelChoiceTitles: [String] { conversationView.modelChoiceTitles }
    public var messageViews: [MessageView] { conversationView.messageViews }
    @objc public func sendClicked() { conversationView.sendClicked() }
    public func attach(_ a: Attachment) { conversationView.attach(a) }
    public func focusMessageField() { view.window?.makeFirstResponder(conversationView.messageView) }

    func reloadNewConversationMenu() {
        newConversationButton.menu = NewConversationMenu.build(model, target: self, start: #selector(startWithProvider(_:)),
                                                               setUp: #selector(setUpProvider(_:)))
    }

    public var newConversationMenuTitles: [String] { NewConversationMenu.titles(newConversationButton.menu) }

    @objc public func newConversationClicked() {
        if !model.availability.isEmpty && !model.hasUsableBackend {
            presentNewConversationMenu()
            return
        }
        startConversation()
    }

    func presentNewConversationMenu() {
        newConversationMenuPresentations += 1
        guard view.window?.isVisible == true else { return }
        let menu = newConversationButton.menu
        let b = newConversationButton
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: b.isFlipped ? b.bounds.height + 4 : -4), in: b)
    }

    func startConversation() {
        model.newConversation()
        focusMessageField()
    }

    @objc func startWithProvider(_ item: NSMenuItem) {
        guard let kind = item.representedObject as? String, let k = ProviderKind(rawValue: kind) else { return }
        if k != model.providerKind { model.choose(k, model: nil) }
        startConversation()
    }

    @objc func setUpProvider(_ item: NSMenuItem) { onOpenSettings?() }

    @objc public func newGroupClicked() {
        let g = model.newGroup()
        if let row = items.firstIndex(where: { $0.kind == .group(g.id) }).map({ list.row(forItem: items[$0]) }), row >= 0 {
            list.selectRowIndexes([row], byExtendingSelection: false)
            list.scrollRowToVisible(row)
        }
        if view.window?.isVisible == true { renameGroup(g.id) }
    }

    public final class Item: NSObject {
        public enum Kind: Equatable { case group(UUID), archive, conversation(UUID) }
        let kind: Kind
        let title: String
        var children: [Item]
        let isActive: Bool
        init(_ kind: Kind, _ title: String, children: [Item] = [], isActive: Bool = false) {
            self.kind = kind
            self.title = title
            self.children = children
            self.isActive = isActive
        }
        var conversationID: UUID? { if case .conversation(let id) = kind { id } else { nil } }
        var isContainer: Bool { conversationID == nil }
    }

    func reloadList() {
        func row(_ c: Conversation) -> Item { Item(.conversation(c.id), c.title, isActive: c.isActive) }
        items = model.library.outline.map { node in
            switch node {
            case .group(let g, let cs): Item(.group(g.id), g.title, children: cs.map(row))
            case .conversation(let c): row(c)
            case .archive(let cs): Item(.archive, ConversationLibrary.archiveTitle, children: cs.map(row))
            }
        }
        reloading = true
        list.reloadData()
        for item in items where item.isContainer {
            let expand: Bool = switch item.kind {
            case .group(let id): !collapsedGroups.contains(id)
            case .archive: archiveExpanded || item.children.contains { $0.conversationID == model.selectedID && model.selectedID != nil }
            case .conversation: false
            }
            if expand { list.expandItem(item) } else { list.collapseItem(item) }
        }
        reloading = false
        if let id = model.selectedID, let item = self.item(for: id), list.row(forItem: item) >= 0 {
            list.selectRowIndexes([list.row(forItem: item)], byExtendingSelection: false)
        } else if list.selectedRow >= 0, (list.item(atRow: list.selectedRow) as? Item)?.conversationID != nil {
            list.deselectAll(nil)
        }
    }

    func item(for id: UUID) -> Item? {
        for i in items {
            if i.conversationID == id { return i }
            if let c = i.children.first(where: { $0.conversationID == id }) { return c }
        }
        return nil
    }

    func reloadRow(_ id: UUID) {
        guard let old = item(for: id), let c = model.conversation(id) else { return }
        if old.title != c.title || old.isActive != c.isActive { reloadList() }
    }

    public var listRows: [String] {
        (0..<list.numberOfRows).compactMap { r in
            (list.item(atRow: r) as? Item).map { String(repeating: "  ", count: list.level(forRow: r)) + $0.title }
        }
    }

    public var groupGlyphs: [String: String] {
        Dictionary(items.filter(\.isContainer).map { ($0.title, Self.glyph($0)) }, uniquingKeysWith: { a, _ in a })
    }

    static func glyph(_ item: Item) -> String {
        switch item.kind {
        case .group: "folder"
        case .archive: "archivebox"
        case .conversation: item.isActive ? "ellipsis.bubble" : "bubble.left"
        }
    }

    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? Item)?.children.count ?? items.count
    }

    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? Item)?.children[index] ?? items[index]
    }

    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? Item)?.isContainer ?? false
    }

    public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let item = item as? Item else { return nil }
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: item.title)
        label.lineBreakMode = .byTruncatingTail
        let icon = NSImageView(image: NSImage(systemSymbolName: Self.glyph(item),
                                              accessibilityDescription: item.isActive ? "Responding" : nil) ?? NSImage())
        let stack = NSStackView(views: [icon, label])
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(stack)
        cell.textField = label
        cell.imageView = icon
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: cell.trailingAnchor, constant: -4),
            stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    public func outlineViewSelectionDidChange(_ notification: Notification) {
        guard !reloading, let item = list.item(atRow: list.selectedRow) as? Item, let id = item.conversationID else { return }
        model.selectedID = id
    }

    public func outlineViewItemDidExpand(_ notification: Notification) { noteExpansion(notification, expanded: true) }
    public func outlineViewItemDidCollapse(_ notification: Notification) { noteExpansion(notification, expanded: false) }

    func noteExpansion(_ n: Notification, expanded: Bool) {
        guard !reloading, let item = n.userInfo?["NSObject"] as? Item else { return }
        switch item.kind {
        case .group(let id): if expanded { collapsedGroups.remove(id) } else { collapsedGroups.insert(id) }
        case .archive: archiveExpanded = expanded
        case .conversation: break
        }
    }

    public func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
        guard let id = (item as? Item)?.conversationID else { return nil }
        let p = NSPasteboardItem()
        p.setString(id.uuidString, forType: Self.dragType)
        return p
    }

    public func outlineView(_ outlineView: NSOutlineView, validateDrop info: any NSDraggingInfo, proposedItem item: Any?,
                            proposedChildIndex index: Int) -> NSDragOperation {
        guard info.draggingPasteboard.string(forType: Self.dragType) != nil else { return [] }
        let target = item as? Item
        if let t = target, !t.isContainer { return [] }
        outlineView.setDropItem(target, dropChildIndex: NSOutlineViewDropOnItemIndex)
        return .move
    }

    public func outlineView(_ outlineView: NSOutlineView, acceptDrop info: any NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        guard let s = info.draggingPasteboard.string(forType: Self.dragType), let id = UUID(uuidString: s) else { return false }
        drop(id, on: (item as? Item)?.kind)
        return true
    }

    public func drop(_ id: UUID, on target: Item.Kind?) {
        switch target {
        case .group(let g)?: model.move(id, toGroup: g)
        case .archive?: model.setArchived(id, true)
        case nil: model.move(id, toGroup: nil)
        case .conversation?: break
        }
    }

    var clickedItem: Item? {
        let row = list.clickedRow >= 0 ? list.clickedRow : list.selectedRow
        return row >= 0 ? list.item(atRow: row) as? Item : nil
    }

    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let item = clickedItem else { return }
        func add(_ title: String, _ action: Selector) {
            menu.addItem(withTitle: title, action: action, keyEquivalent: "").target = self
        }
        switch item.kind {
        case .group:
            add("Rename Group…", #selector(renameClicked))
            add("Delete Group", #selector(deleteClicked))
        case .archive:
            break
        case .conversation(let id):
            add("Rename Conversation…", #selector(renameClicked))
            let move = NSMenuItem(title: "Move to Group", action: nil, keyEquivalent: "")
            let sub = NSMenu()
            let current = model.conversation(id)
            for g in model.groups {
                let m = NSMenuItem(title: g.title, action: #selector(moveChosen(_:)), keyEquivalent: "")
                m.target = self
                m.representedObject = g.id.uuidString
                m.state = current?.groupID == g.id && current?.isArchived == false ? .on : .off
                sub.addItem(m)
            }
            if !model.groups.isEmpty { sub.addItem(.separator()) }
            let none = NSMenuItem(title: "No Group", action: #selector(moveChosen(_:)), keyEquivalent: "")
            none.target = self
            sub.addItem(none)
            move.submenu = sub
            menu.addItem(move)
            add(current?.isArchived == true ? "Move Out of Archive" : "Archive", #selector(archiveClicked))
            menu.addItem(.separator())
            add("Delete Conversation", #selector(deleteClicked))
        }
    }

    @objc func moveChosen(_ m: NSMenuItem) {
        guard let id = clickedItem?.conversationID else { return }
        model.move(id, toGroup: (m.representedObject as? String).flatMap(UUID.init(uuidString:)))
    }

    @objc func archiveClicked() {
        guard let id = clickedItem?.conversationID, let c = model.conversation(id) else { return }
        model.setArchived(id, !c.isArchived)
    }

    @objc func deleteClicked() {
        guard let item = clickedItem else { return }
        switch item.kind {
        case .group(let g): model.deleteGroup(g)
        case .conversation(let id): model.delete(id)
        case .archive: break
        }
    }

    @objc func renameClicked() {
        guard let item = clickedItem else { return }
        switch item.kind {
        case .group(let g): renameGroup(g)
        case .conversation(let id):
            ask("Rename Conversation", value: item.title) { [weak self] t in self?.model.rename(id, to: t) }
        case .archive: break
        }
    }

    func renameGroup(_ id: UUID) {
        guard let g = model.groups.first(where: { $0.id == id }) else { return }
        ask("Rename Group", value: g.title) { [weak self] t in self?.model.renameGroup(id, to: t) }
    }

    func ask(_ title: String, value: String, then: @escaping (String) -> Void) {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(string: value)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { r in
            if r == .alertFirstButtonReturn { then(field.stringValue) }
        }
    }
}

@MainActor
enum NewConversationMenu {
    static let heading = "Model Providers"
    static let setUp = "Set Up"

    static func build(_ model: CodingAssistantModel, target: AnyObject, start: Selector, setUp: Selector) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(NSMenuItem.sectionHeader(title: heading))
        for kind in ProviderKind.allCases {
            let item = NSMenuItem(title: kind.displayName, action: nil, keyEquivalent: "")
            item.representedObject = kind.rawValue
            item.target = target
            item.image = NSImage(systemSymbolName: kind.cliAgent != nil ? "terminal" : (kind.isLocalServer ? "desktopcomputer" : "cloud"),
                                 accessibilityDescription: nil)
            switch model.availability[kind] {
            case nil:
                item.isEnabled = false
                item.subtitle = "Checking…"
            case .ready?:
                item.action = start
                item.toolTip = "Start a conversation with \(kind.displayName)"
            case let a?:
                item.action = setUp
                item.subtitle = a.hint
                item.toolTip = a.hint
                item.attributedTitle = titleWithAction(kind.displayName, Self.setUp)
            }
            menu.addItem(item)
        }
        return menu
    }

    static func titleWithAction(_ title: String, _ action: String) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.tabStops = [NSTextTab(textAlignment: .right, location: 260)]
        let s = NSMutableAttributedString(string: title + "\t", attributes: [.font: NSFont.menuFont(ofSize: 0), .paragraphStyle: p])
        s.append(NSAttributedString(string: action, attributes: [.font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                                                                 .foregroundColor: NSColor.controlAccentColor, .paragraphStyle: p]))
        return s
    }

    static func titles(_ menu: NSMenu?) -> [String] {
        (menu?.items ?? []).map { item in
            if item.isSectionHeader { return "# " + item.title }
            let name = (item.representedObject as? String).flatMap(ProviderKind.init(rawValue:))?.displayName ?? item.title
            if item.subtitle == "Checking…" { return name + " — Checking…" }
            return item.attributedTitle != nil ? name + " — " + setUp : name
        }
    }
}
