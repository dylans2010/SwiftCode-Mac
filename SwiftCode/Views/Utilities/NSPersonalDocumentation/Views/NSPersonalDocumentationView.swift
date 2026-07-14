// ====================================================================
// NS PERSONAL DOCUMENTATION - MAIN ENTRY POINT (RECONSTRUCTED WORKSPACE)
// ====================================================================
// Reconstructed around AppKit's NSSplitViewController and NSSplitViewItem,
// featuring a native NSWindowController, NSToolbar, NSOutlineView, NSScrollView,
// and NSStackView/NSGridView. It provides a fluid, unconstrained multi-column
// desktop workspace that behaves exactly like Xcode or Finder.
// ====================================================================

import SwiftUI
import AppKit

// MARK: - Native Window Manager
@MainActor
public final class PersonalDocWindowManager: NSObject, NSWindowDelegate {
    public static let shared = PersonalDocWindowManager()
    private var windowController: PersonalDocWindowController?

    public func showWindow(for project: Project) {
        if let existing = windowController {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        do {
            let coord = try PersonalDocumentationCoordinator(projectID: project.id, projectURL: project.directoryURL)
            let wc = PersonalDocWindowController(coordinator: coord)
            wc.window?.delegate = self
            self.windowController = wc
            wc.window?.makeKeyAndOrderFront(nil)
        } catch {
            LoggingTool.error("Failed to initialize Personal Documentation coordinator: \(error.localizedDescription)")
        }
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

// MARK: - Native Window Controller
@MainActor
public class PersonalDocWindowController: NSWindowController {
    public let coordinator: PersonalDocumentationCoordinator

    public init(coordinator: PersonalDocumentationCoordinator) {
        self.coordinator = coordinator

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Personal Documentation Workspace"
        window.minSize = NSSize(width: 1200, height: 800)
        window.setFrameAutosaveName("PersonalDocumentationMainWindow")

        super.init(window: window)

        let splitVC = PersonalDocSplitViewController(coordinator: coordinator)
        window.contentViewController = splitVC

        setupToolbar(window: window)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupToolbar(window: NSWindow) {
        let toolbar = NSToolbar(identifier: "PersonalDocToolbar")
        toolbar.delegate = self
        toolbar.allowsUserCustomization = true
        toolbar.autosavesConfiguration = true
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
    }
}

extension PersonalDocWindowController: NSToolbarDelegate {
    public func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        let item = NSToolbarItem(itemIdentifier: itemIdentifier)

        switch itemIdentifier {
        case .toggleSidebar:
            item.label = "Toggle Sidebar"
            item.paletteLabel = "Toggle Sidebar"
            item.toolTip = "Toggle the left sidebar"
            item.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(toggleSidebarAction(_:))

        case .commandPalette:
            item.label = "Command Palette"
            item.paletteLabel = "Command Palette"
            item.toolTip = "Open Command Palette Quick Search"
            item.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(openCommandPaletteAction(_:))

        case .newDocument:
            let button = NSButton(image: NSImage(systemSymbolName: "doc.badge.plus", accessibilityDescription: nil) ?? NSImage(), target: self, action: #selector(newDocumentAction(_:)))
            button.bezelStyle = .texturedRounded
            button.isBordered = true
            item.label = "New Document"
            item.paletteLabel = "New Document"
            item.toolTip = "Create a new document choosing its category"
            item.view = button

        case .duplicateDocument:
            item.label = "Duplicate"
            item.paletteLabel = "Duplicate"
            item.toolTip = "Duplicate current document"
            item.image = NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(duplicateDocumentAction(_:))

        case .deleteDocument:
            item.label = "Delete"
            item.paletteLabel = "Delete"
            item.toolTip = "Delete current document"
            item.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
            item.target = self
            item.action = #selector(deleteDocumentAction(_:))

        default:
            return nil
        }
        return item
    }

    public func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.toggleSidebar, .sidebarTrackingSeparator, .flexibleSpace, .flexibleSpace, .commandPalette, .newDocument, .duplicateDocument, .deleteDocument]
    }

    public func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        return [.toggleSidebar, .sidebarTrackingSeparator, .commandPalette, .newDocument, .duplicateDocument, .deleteDocument, .flexibleSpace, .space]
    }
}

extension NSToolbarItem.Identifier {
    public static let commandPalette = NSToolbarItem.Identifier("commandPalette")
    public static let newDocument = NSToolbarItem.Identifier("newDocument")
    public static let duplicateDocument = NSToolbarItem.Identifier("duplicateDocument")
    public static let deleteDocument = NSToolbarItem.Identifier("deleteDocument")
}

extension PersonalDocWindowController {
    @objc private func toggleSidebarAction(_ sender: Any?) {
        if let splitVC = contentViewController as? PersonalDocSplitViewController {
            splitVC.toggleSidebar(sender)
        }
    }

    @objc private func openCommandPaletteAction(_ sender: Any?) {
        NotificationCenter.default.post(name: NSNotification.Name("ShowPersonalDocCommandPalette"), object: nil)
    }

    @objc private func newDocumentAction(_ sender: Any?) {
        guard let button = sender as? NSButton else { return }
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 260, height: 480)

        let popoverView = DocumentCreationPopoverView(coordinator: coordinator) { [weak popover] in
            popover?.performClose(nil)
        }
        let hostingController = NSHostingController(rootView: popoverView)
        popover.contentViewController = hostingController

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    @objc private func duplicateDocumentAction(_ sender: Any?) {
        NotificationCenter.default.post(name: NSNotification.Name("PersonalDocDuplicateDocument"), object: nil)
    }

    @objc private func deleteDocumentAction(_ sender: Any?) {
        NotificationCenter.default.post(name: NSNotification.Name("PersonalDocDeleteDocument"), object: nil)
    }
}

// MARK: - Native Split View Controller
public class PersonalDocSplitViewController: NSSplitViewController {
    public let coordinator: PersonalDocumentationCoordinator

    private var sidebarItem: NSSplitViewItem?
    private var mainItem: NSSplitViewItem?

    public init(coordinator: PersonalDocumentationCoordinator) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        setupSplitView()
        setupNotifications()
    }

    private func setupSplitView() {
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        // Panel 1: Sidebar (Pure AppKit Controller)
        let sidebarVC = PersonalDocSidebarViewController(coordinator: coordinator)
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        sidebarItem.minimumThickness = 240
        sidebarItem.maximumThickness = 240
        sidebarItem.holdingPriority = .defaultLow
        self.sidebarItem = sidebarItem
        addSplitViewItem(sidebarItem)

        // Panel 2: Main Workspace / Editor (SwiftUI Main Wrapper)
        let mainView = PersonalDocMainWrapper(coord: coordinator)
        let mainVC = NSHostingController(rootView: mainView)
        mainVC.sizingOptions = []
        let mainItem = NSSplitViewItem(viewController: mainVC)
        mainItem.minimumThickness = 600
        mainItem.holdingPriority = .defaultHigh
        self.mainItem = mainItem
        addSplitViewItem(mainItem)

        updateSplitItems(animate: false)
    }

    public func updateSplitItems(animate: Bool) {
        // Omit collapsible middle pane or inspector in the modernized two-region desktop layout
    }

    private func hasMiddleList(_ kind: ModuleKind) -> Bool {
        switch kind {
        case .dashboard, .smartCollections, .knowledgeGraph, .timeline, .analytics, .intelligence:
            return false
        default:
            return true
        }
    }

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleNewDocument(_:)),
            name: NSNotification.Name("PersonalDocNewDocument"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDuplicateDocument(_:)),
            name: NSNotification.Name("PersonalDocDuplicateDocument"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeleteDocument(_:)),
            name: NSNotification.Name("PersonalDocDeleteDocument"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAddLinkTriggered(_:)),
            name: NSNotification.Name("PersonalDocAddLinkTriggered"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleShowCommandPalette(_:)),
            name: NSNotification.Name("ShowPersonalDocCommandPalette"),
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSelectionChanged(_:)),
            name: NSNotification.Name("PersonalDocSelectionChanged"),
            object: nil
        )
    }

    @objc private func handleSelectionChanged(_ notification: Notification) {
        updateSplitItems(animate: true)
    }

    @objc private func handleNewDocument(_ notification: Notification) {
        let kind = coordinator.selectedModuleKind ?? .personalDocumentation
        let state = coordinator.state(for: kind)
        do {
            if let newDoc = try? coordinator.documents.createDocument(title: "Untitled Document", kind: kind) {
                state.selectedDocumentID = newDoc.id
                updateSplitItems(animate: true)
            }
        }
    }

    @objc private func handleDuplicateDocument(_ notification: Notification) {
        let kind = coordinator.selectedModuleKind ?? .personalDocumentation
        let state = coordinator.state(for: kind)
        guard let id = state.selectedDocumentID,
              let doc = try? coordinator.documents.fetchDocument(id: id) else { return }
        do {
            let duplicate = Document(
                projectID: doc.projectID,
                archetype: doc.archetype,
                moduleKind: doc.moduleKind,
                title: "\(doc.title) Copy",
                markdownSource: doc.markdownSource,
                attachments: doc.attachments,
                tags: doc.tags,
                createdAt: Date(),
                updatedAt: Date(),
                pinned: doc.pinned,
                archived: doc.archived
            )
            duplicate.status = doc.status
            duplicate.priority = doc.priority
            duplicate.severity = doc.severity
            duplicate.reproSteps = doc.reproSteps
            duplicate.stackTrace = doc.stackTrace
            duplicate.targetQuarter = doc.targetQuarter
            duplicate.dependencyIDs = doc.dependencyIDs

            coordinator.storage.context.insert(duplicate)
            try coordinator.storage.context.save()

            state.selectedDocumentID = duplicate.id
            updateSplitItems(animate: true)
        } catch {
            LoggingTool.error("Failed to duplicate document: \(error.localizedDescription)")
        }
    }

    @objc private func handleDeleteDocument(_ notification: Notification) {
        let kind = coordinator.selectedModuleKind ?? .personalDocumentation
        let state = coordinator.state(for: kind)
        guard let id = state.selectedDocumentID,
              let doc = try? coordinator.documents.fetchDocument(id: id) else { return }

        let alert = NSAlert()
        alert.messageText = "Delete Document"
        alert.informativeText = "Are you sure you want to delete this document? This action cannot be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        if let window = self.view.window {
            alert.beginSheetModal(for: window) { [weak self] response in
                if response == .alertFirstButtonReturn {
                    try? self?.coordinator.documents.deleteDocument(doc)
                    state.selectedDocumentID = nil
                    self?.updateSplitItems(animate: true)
                }
            }
        } else {
            if alert.runModal() == .alertFirstButtonReturn {
                try? coordinator.documents.deleteDocument(doc)
                state.selectedDocumentID = nil
                updateSplitItems(animate: true)
            }
        }
    }

    @objc private func handleAddLinkTriggered(_ notification: Notification) {
        guard let id = coordinator.selectedDocumentID,
              let doc = try? coordinator.documents.fetchDocument(id: id) else { return }

        let alert = NSAlert()
        alert.messageText = "Link to Project Resource"
        alert.informativeText = "Enter the resource name (e.g. main.swift, SHA hash, milestone name):"
        alert.addButton(withTitle: "Link")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        input.placeholderString = "Resource name"
        alert.accessoryView = input

        if let window = self.view.window {
            alert.beginSheetModal(for: window) { [weak self] response in
                if response == .alertFirstButtonReturn {
                    let text = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        try? self?.coordinator.relationships.addLink(
                            sourceID: doc.id,
                            targetType: "Project Resource",
                            targetIdentifier: UUID().uuidString,
                            targetName: text
                        )
                    }
                }
            }
        }
    }

    @objc private func handleShowCommandPalette(_ notification: Notification) {
        let paletteView = PersonalDocCommandPalette(coordinator: coordinator) { [weak self] in
            self?.dismissCommandPalette()
        }
        let hostingVC = NSHostingController(rootView: paletteView)
        hostingVC.view.frame = NSRect(x: 0, y: 0, width: 500, height: 400)
        self.presentAsSheet(hostingVC)
    }

    private func dismissCommandPalette() {
        if let first = presentedViewControllers?.first {
            dismiss(first)
        }
    }
}

// MARK: - Native Sidebar View Controller
public class PersonalDocSidebarViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    public let coordinator: PersonalDocumentationCoordinator
    private var scrollView: NSScrollView?
    private var outlineView: NSOutlineView?
    private let nodes: [SidebarNode]

    public init(coordinator: PersonalDocumentationCoordinator) {
        self.coordinator = coordinator
        self.nodes = buildSidebarNodes()
        super.init(nibName: nil, bundle: nil)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func loadView() {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .sidebar
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]
        self.scrollView = scroll

        let outline = NSOutlineView()
        outline.autoresizingMask = [.width]
        outline.headerView = nil
        outline.selectionHighlightStyle = .sourceList
        outline.style = .sourceList
        outline.floatsGroupRows = false
        self.outlineView = outline

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SidebarColumn"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column

        outline.dataSource = self
        outline.delegate = self

        scroll.documentView = outline
        visualEffectView.addSubview(scroll)

        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor)
        ])

        self.view = visualEffectView
    }

    override public func viewDidLoad() {
        super.viewDidLoad()
        setupContextMenu()
        setupDragAndDrop()

        if let outline = outlineView {
            for group in nodes {
                outline.expandItem(group)
            }
        }
    }

    private func setupContextMenu() {
        let menu = NSMenu(title: "Sidebar Context Menu")
        menu.addItem(NSMenuItem(title: "New Document", action: #selector(contextNewDocument(_:)), keyEquivalent: "n"))
        menu.addItem(NSMenuItem(title: "Toggle Section", action: #selector(contextToggleSection(_:)), keyEquivalent: ""))
        if let outline = outlineView {
            outline.menu = menu
        }
    }

    private func setupDragAndDrop() {
        if let outline = outlineView {
            outline.registerForDraggedTypes([.string])
        }
    }

    @objc private func contextNewDocument(_ sender: Any?) {
        NotificationCenter.default.post(name: NSNotification.Name("PersonalDocNewDocument"), object: nil)
    }

    @objc private func contextToggleSection(_ sender: Any?) {
        guard let outline = outlineView else { return }
        let clickedRow = outline.clickedRow
        guard clickedRow >= 0 else { return }
        if let item = outline.item(atRow: clickedRow) {
            if outline.isItemExpanded(item) {
                outline.collapseItem(item)
            } else {
                outline.expandItem(item)
            }
        }
    }

    // MARK: - NSOutlineViewDataSource

    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil {
            return nodes.count
        }
        if let node = item as? SidebarNode {
            return node.children.count
        }
        return 0
    }

    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil {
            return nodes[index]
        }
        guard let node = item as? SidebarNode else { return SidebarNode(title: "") }
        return node.children[index]
    }

    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let node = item as? SidebarNode {
            return node.isGroup
        }
        return false
    }

    // MARK: - NSOutlineViewDelegate

    public func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        if let node = item as? SidebarNode {
            return node.isGroup
        }
        return false
    }

    public func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        if let node = item as? SidebarNode {
            return !node.isGroup
        }
        return true
    }

    public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? SidebarNode else { return nil }

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
            var cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? SidebarCellView
            if cell == nil {
                cell = SidebarCellView(frame: .zero)
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
                cell?.iconView.contentTintColor = color
            } else {
                cell?.iconView.contentTintColor = .controlAccentColor
            }

            return cell
        }
    }

    public func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let outline = outlineView else { return }
        let selectedRow = outline.selectedRow
        if selectedRow >= 0, let node = outline.item(atRow: selectedRow) as? SidebarNode, let kind = node.kind {
            coordinator.selectedModuleKind = kind
        }
    }

    // MARK: - Drag & Drop

    public func outlineView(_ outlineView: NSOutlineView, pasteboardWriterForItem item: Any) -> NSPasteboardWriting? {
        guard let node = item as? SidebarNode, !node.isGroup else { return nil }
        return node.title as NSString
    }

    public func outlineView(_ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?, proposedChildIndex index: Int) -> NSDragOperation {
        return .generic
    }

    public func outlineView(_ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?, childIndex index: Int) -> Bool {
        return true
    }
}

// MARK: - Native Inspector View Controller
public class PersonalDocInspectorViewController: NSViewController {
    public let coordinator: PersonalDocumentationCoordinator
    private var selectedDocumentID: UUID?

    private var scrollView: NSScrollView?
    private var mainStackView: NSStackView?

    public init(coordinator: PersonalDocumentationCoordinator) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]
        self.scrollView = scroll

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.translatesAutoresizingMaskIntoConstraints = false
        self.mainStackView = stack

        scroll.documentView = stack
        container.addSubview(scroll)

        scroll.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: container.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])

        self.view = container
    }

    public func setSelectedDocumentID(_ id: UUID?) {
        self.selectedDocumentID = id
        reloadData()
    }

    public func reloadData() {
        guard let mainStack = mainStackView else { return }

        for subview in mainStack.views {
            mainStack.removeView(subview)
            subview.removeFromSuperview()
        }

        guard let id = selectedDocumentID,
              let doc = try? coordinator.documents.fetchDocument(id: id) else {
            let emptyLabel = NSTextField(labelWithString: "Select a document to view relationships & version history.")
            emptyLabel.textColor = .secondaryLabelColor
            emptyLabel.font = .systemFont(ofSize: 13)
            emptyLabel.alignment = .center
            if let cell = emptyLabel.cell as? NSTextFieldCell {
                cell.wraps = true
                cell.lineBreakMode = .byWordWrapping
            }
            mainStack.addView(emptyLabel, in: .top)
            return
        }

        let titleLabel = NSTextField(labelWithString: "Inspector: \(doc.title)")
        titleLabel.font = .boldSystemFont(ofSize: 14)
        titleLabel.textColor = .labelColor
        if let cell = titleLabel.cell as? NSTextFieldCell {
            cell.lineBreakMode = .byTruncatingTail
        }
        mainStack.addView(titleLabel, in: .top)

        let divider = NSBox()
        divider.boxType = .separator
        mainStack.addView(divider, in: .top)

        let relHeader = NSTextField(labelWithString: "Document Relationships")
        relHeader.font = .boldSystemFont(ofSize: 12)
        relHeader.textColor = .secondaryLabelColor
        mainStack.addView(relHeader, in: .top)

        let relationships = (try? coordinator.relationships.fetchRelationships(for: doc.id)) ?? []
        if relationships.isEmpty {
            let noneLabel = NSTextField(labelWithString: "No connected resources. Link this document to Swift files, commits, bugs, or milestones.")
            noneLabel.font = .systemFont(ofSize: 11)
            noneLabel.textColor = .secondaryLabelColor
            if let cell = noneLabel.cell as? NSTextFieldCell {
                cell.wraps = true
                cell.lineBreakMode = .byWordWrapping
            }
            mainStack.addView(noneLabel, in: .top)
        } else {
            for rel in relationships {
                let icon = NSImageView(image: NSImage(systemSymbolName: "link", accessibilityDescription: nil) ?? NSImage())
                icon.contentTintColor = .systemBlue
                icon.widthAnchor.constraint(equalToConstant: 16).isActive = true
                icon.heightAnchor.constraint(equalToConstant: 16).isActive = true

                let itemTitle = NSTextField(labelWithString: rel.targetName)
                itemTitle.font = .boldSystemFont(ofSize: 11)
                itemTitle.textColor = .labelColor
                if let cell = itemTitle.cell as? NSTextFieldCell {
                    cell.lineBreakMode = .byTruncatingTail
                }

                let itemType = NSTextField(labelWithString: rel.targetType)
                itemType.font = .systemFont(ofSize: 9)
                itemType.textColor = .secondaryLabelColor

                let textStack = NSStackView(views: [itemTitle, itemType])
                textStack.orientation = .vertical
                textStack.alignment = .leading
                textStack.spacing = 2

                let deleteBtn = NSButton(image: NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: "Remove Link") ?? NSImage(), target: self, action: #selector(deleteRelationship(_:)))
                deleteBtn.isBordered = false
                deleteBtn.identifier = NSUserInterfaceItemIdentifier(rel.id.uuidString)

                let rowView = NSView()
                rowView.addSubview(icon)
                rowView.addSubview(textStack)
                rowView.addSubview(deleteBtn)

                icon.translatesAutoresizingMaskIntoConstraints = false
                textStack.translatesAutoresizingMaskIntoConstraints = false
                deleteBtn.translatesAutoresizingMaskIntoConstraints = false

                NSLayoutConstraint.activate([
                    icon.leadingAnchor.constraint(equalTo: rowView.leadingAnchor, constant: 4),
                    icon.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),

                    textStack.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
                    textStack.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),

                    deleteBtn.trailingAnchor.constraint(equalTo: rowView.trailingAnchor, constant: -4),
                    deleteBtn.centerYAnchor.constraint(equalTo: rowView.centerYAnchor),
                    deleteBtn.leadingAnchor.constraint(greaterThanOrEqualTo: textStack.trailingAnchor, constant: 8)
                ])

                rowView.heightAnchor.constraint(equalToConstant: 36).isActive = true

                let cardBox = NSBox()
                cardBox.boxType = .custom
                cardBox.borderWidth = 1
                cardBox.borderColor = NSColor.separatorColor
                cardBox.fillColor = NSColor.controlBackgroundColor
                cardBox.cornerRadius = 6
                cardBox.contentView = rowView

                mainStack.addView(cardBox, in: .top)
            }
        }

        let addLinkBtn = NSButton(title: "Link to Project Resource", target: self, action: #selector(addLinkAction(_:)))
        addLinkBtn.bezelStyle = .rounded
        mainStack.addView(addLinkBtn, in: .top)

        let divider2 = NSBox()
        divider2.boxType = .separator
        mainStack.addView(divider2, in: .top)

        let verHeader = NSTextField(labelWithString: "Document Versioning")
        verHeader.font = .boldSystemFont(ofSize: 12)
        verHeader.textColor = .secondaryLabelColor
        mainStack.addView(verHeader, in: .top)

        let saveVerBtn = NSButton(title: "Save Revision Point", target: self, action: #selector(saveRevisionAction(_:)))
        saveVerBtn.bezelStyle = .rounded
        mainStack.addView(saveVerBtn, in: .top)

        let versions = (try? coordinator.versionHistory.fetchVersions(for: doc.id)) ?? []
        if versions.isEmpty {
            let noneLabel = NSTextField(labelWithString: "No previous snapshots. Snapshots provide historical restoration points.")
            noneLabel.font = .systemFont(ofSize: 11)
            noneLabel.textColor = .secondaryLabelColor
            if let cell = noneLabel.cell as? NSTextFieldCell {
                cell.wraps = true
                cell.lineBreakMode = .byWordWrapping
            }
            mainStack.addView(noneLabel, in: .top)
        } else {
            for ver in versions {
                let formatter = DateFormatter()
                formatter.timeStyle = .short
                let timeStr = formatter.string(from: ver.timestamp)

                let rowBtn = NSButton(title: "Snapshot (\(timeStr))", target: self, action: #selector(restoreVersionAction(_:)))
                rowBtn.bezelStyle = .regularSquare
                rowBtn.image = NSImage(systemSymbolName: "clock.arrow.trianglehead.counterclockwise.rotate.90", accessibilityDescription: nil)
                rowBtn.imagePosition = .imageLeft
                rowBtn.alignment = .left
                rowBtn.identifier = NSUserInterfaceItemIdentifier(ver.id.uuidString)

                mainStack.addView(rowBtn, in: .top)
            }
        }
    }

    @objc private func deleteRelationship(_ sender: NSButton) {
        guard let idStr = sender.identifier?.rawValue,
              let relUUID = UUID(uuidString: idStr),
              let docID = selectedDocumentID else { return }

        if let rel = try? coordinator.relationships.fetchRelationships(for: docID).first(where: { $0.id == relUUID }) {
            try? coordinator.relationships.removeLink(rel)
            reloadData()
        }
    }

    @objc private func addLinkAction(_ sender: Any?) {
        NotificationCenter.default.post(name: NSNotification.Name("PersonalDocAddLinkTriggered"), object: nil)
    }

    @objc private func saveRevisionAction(_ sender: Any?) {
        guard let id = selectedDocumentID,
              let doc = try? coordinator.documents.fetchDocument(id: id) else { return }
        try? coordinator.versionHistory.recordSnapshot(for: doc)
        reloadData()
    }

    @objc private func restoreVersionAction(_ sender: NSButton) {
        guard let idStr = sender.identifier?.rawValue,
              let verUUID = UUID(uuidString: idStr),
              let id = selectedDocumentID,
              let doc = try? coordinator.documents.fetchDocument(id: id),
              let versions = try? coordinator.versionHistory.fetchVersions(for: doc.id),
              let ver = versions.first(where: { $0.id == verUUID }) else { return }

        let alert = NSAlert()
        alert.messageText = "Restore Snapshot"
        alert.informativeText = "Are you sure you want to restore the document to this historical snapshot?"
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")

        if let window = self.view.window {
            alert.beginSheetModal(for: window) { [weak self] response in
                if response == .alertFirstButtonReturn {
                    doc.markdownSource = ver.markdownSnapshot
                    doc.title = ver.titleSnapshot
                    try? self?.coordinator.documents.updateDocument(doc)
                    self?.reloadData()
                    NotificationCenter.default.post(name: NSNotification.Name("PersonalDocDocumentRestored"), object: nil)
                }
            }
        }
    }
}

// MARK: - AppKit-backed Native Search Field
struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = "Search..."

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.placeholderString = placeholder
        searchField.delegate = context.coordinator
        searchField.bezelStyle = .roundedBezel
        return searchField
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: NativeSearchField

        init(_ parent: NativeSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let searchField = obj.object as? NSSearchField else { return }
            parent.text = searchField.stringValue
        }
    }
}

// MARK: - Native Split View Wrappers for HHostingController
struct PersonalDocMiddleWrapper: View {
    let coord: PersonalDocumentationCoordinator

    var body: some View {
        Group {
            if let kind = coord.selectedModuleKind, hasMiddleList(kind) {
                middleListView(for: kind, coord: coord)
            } else {
                Color.clear
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func hasMiddleList(_ kind: ModuleKind) -> Bool {
        switch kind {
        case .dashboard, .smartCollections, .knowledgeGraph, .timeline, .analytics, .intelligence:
            return false
        default:
            return true
        }
    }

    @ViewBuilder
    private func middleListView(for kind: ModuleKind, coord: PersonalDocumentationCoordinator) -> some View {
        @Bindable var coord = coord
        let state = coord.state(for: kind)
        @Bindable var stateBindable = state
        switch kind {
        case .projectWiki:
            WikiPageListView(coordinator: coord)
        case .whiteboards:
            WhiteboardListView(coordinator: coord)
        case .snippets:
            SnippetListView(coordinator: coord)
        case .snapshots:
            SnapshotListView(coordinator: coord)
        default:
            RecordListView(coordinator: coord, kind: kind, selectedDocumentID: $stateBindable.selectedDocumentID)
        }
    }
}

struct PersonalDocMainWrapper: View {
    let coord: PersonalDocumentationCoordinator

    var body: some View {
        mainWorkspaceView(for: coord.selectedModuleKind, coord: coord)
            .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private func mainWorkspaceView(for kind: ModuleKind?, coord: PersonalDocumentationCoordinator) -> some View {
        if let kind = kind {
            let state = coord.state(for: kind)
            switch kind {
            case .dashboard:
                DashboardView(coordinator: coord)
            case .projectWiki:
                RecordDetailView(coordinator: coord, documentID: nil)
            case .smartCollections:
                GlobalSearchView(coordinator: coord)
            case .knowledgeGraph:
                KnowledgeGraphView(coordinator: coord)
            case .timeline:
                ProjectTimelineView(coordinator: coord)
            case .analytics:
                AnalyticsView(coordinator: coord)
            case .intelligence:
                IntelligenceView(coordinator: coord)
            case .whiteboards:
                WhiteboardCanvasDetailView(coordinator: coord)
            case .snippets:
                SnippetDetailView(coordinator: coord)
            case .snapshots:
                SnapshotDetailView(coordinator: coord)

            // Specialized Workspace Editors Routing
            case .apiDocumentation:
                APIDocumentationEditor(coordinator: coord, documentID: state.selectedDocumentID)
            case .databaseDocumentation:
                DatabaseDocumentationEditor(coordinator: coord, documentID: state.selectedDocumentID)
            case .architectureDecisions:
                ArchitectureDocumentationEditor(coordinator: coord, documentID: state.selectedDocumentID)
            case .featurePlanning:
                FeaturePlanningEditor(coordinator: coord, documentID: state.selectedDocumentID)
            case .securityNotes:
                SecurityNotesEditor(coordinator: coord, documentID: state.selectedDocumentID)
            case .changelogBuilder:
                ChangelogEditor(coordinator: coord, documentID: state.selectedDocumentID)
            case .technicalSpecification:
                TechnicalSpecificationEditor(coordinator: coord, documentID: state.selectedDocumentID)
            case .uiUXPlanning:
                DesignDocumentEditor(coordinator: coord, documentID: state.selectedDocumentID)
            case .researchLibrary:
                ResearchNotesEditor(coordinator: coord, documentID: state.selectedDocumentID)
            case .meetingNotes:
                MeetingNotesEditor(coordinator: coord, documentID: state.selectedDocumentID)
            case .structuredRecord:
                StructuredRecordEditor(coordinator: coord, documentID: state.selectedDocumentID)
            case .freeformDocument:
                FreeformDocumentEditor(coordinator: coord, documentID: state.selectedDocumentID)
            case .releaseChecklist:
                ReleaseChecklistEditor(coordinator: coord, documentID: state.selectedDocumentID)
            case .userStory:
                UserStoryEditor(coordinator: coord, documentID: state.selectedDocumentID)
            case .testingNotes:
                TestingNotesEditor(coordinator: coord, documentID: state.selectedDocumentID)
            case .personalDocumentation:
                FreeformDocumentEditor(coordinator: coord, documentID: state.selectedDocumentID)

            default:
                if kind.archetype == .structured {
                    StructuredRecordEditor(coordinator: coord, documentID: state.selectedDocumentID)
                } else {
                    FreeformDocumentEditor(coordinator: coord, documentID: state.selectedDocumentID)
                }
            }
        } else {
            ContentUnavailableView {
                Label("Select an Item", systemImage: "doc.text")
            } description: {
                Text("Choose a category and document to get started.")
            }
        }
    }
}

// MARK: - SwiftUI View Container (Shorthand Sheet Fallback)
public struct NSPersonalDocumentationView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore

    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
            Text("Personal Documentation Workspace")
                .font(.title2.bold())
            Text("The workspace opens in a dedicated native macOS window with full multi-column split layout and Finder-style sidebar.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)

            Button("Open Workspace Window") {
                if let project = sessionStore.activeProject {
                    PersonalDocWindowManager.shared.showWindow(for: project)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
        .frame(width: 500, height: 400)
        .onAppear {
            if let project = sessionStore.activeProject {
                PersonalDocWindowManager.shared.showWindow(for: project)
            }
        }
    }
}

// MARK: - AppKit Sidebar Helpers & Nodes
public class SidebarNode: NSObject {
    public let title: String
    public let icon: String?
    public let color: NSColor?
    public let kind: ModuleKind?
    public let isGroup: Bool
    public var children: [SidebarNode] = []

    public init(title: String, icon: String? = nil, color: NSColor? = nil, kind: ModuleKind? = nil, isGroup: Bool = false) {
        self.title = title
        self.icon = icon
        self.color = color
        self.kind = kind
        self.isGroup = isGroup
    }
}

class SidebarCellView: NSTableCellView {
    let iconView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        let text = NSTextField(labelWithString: "")
        text.translatesAutoresizingMaskIntoConstraints = false
        text.font = .systemFont(ofSize: 13)
        text.textColor = .labelColor
        addSubview(text)
        self.textField = text

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            text.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            text.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

func buildSidebarNodes() -> [SidebarNode] {
    var nodes: [SidebarNode] = []

    // 1. Overview
    let overview = SidebarNode(title: "OVERVIEW", isGroup: true)
    overview.children = [
        SidebarNode(title: "Dashboard", icon: "square.grid.2x2.fill", color: .systemBlue, kind: .dashboard),
        SidebarNode(title: "Global Search", icon: "magnifyingglass", color: .systemTeal, kind: .smartCollections)
    ]
    nodes.append(overview)

    // 2. Productivity Ecosystem
    let eco = SidebarNode(title: "PRODUCTIVITY ECOSYSTEM", isGroup: true)
    eco.children = [
        SidebarNode(title: "Knowledge Graph", icon: ModuleKind.knowledgeGraph.icon, color: .systemPurple, kind: .knowledgeGraph),
        SidebarNode(title: "Project Timeline", icon: ModuleKind.timeline.icon, color: .systemBlue, kind: .timeline),
        SidebarNode(title: "Project Analytics", icon: ModuleKind.analytics.icon, color: .systemOrange, kind: .analytics),
        SidebarNode(title: "Project Intelligence", icon: ModuleKind.intelligence.icon, color: .systemPurple, kind: .intelligence),
        SidebarNode(title: "Advanced Whiteboards", icon: ModuleKind.whiteboards.icon, color: .systemBlue, kind: .whiteboards),
        SidebarNode(title: "Snippet Workspace", icon: ModuleKind.snippets.icon, color: .systemGreen, kind: .snippets),
        SidebarNode(title: "Project Snapshots", icon: ModuleKind.snapshots.icon, color: .systemOrange, kind: .snapshots)
    ]
    nodes.append(eco)

    // 3. Libraries - Freeform Documents
    let freeform = SidebarNode(title: "FREEFORM DOCUMENTS", isGroup: true)
    freeform.children = ModuleKind.allCases.filter { $0.archetype == .freeform }.map { kind in
        SidebarNode(title: kind.rawValue, icon: kind.icon, color: .systemBlue, kind: kind)
    }
    nodes.append(freeform)

    // 4. Libraries - Structured Records
    let structured = SidebarNode(title: "STRUCTURED RECORDS", isGroup: true)
    structured.children = ModuleKind.allCases.filter { $0.archetype == .structured }.map { kind in
        SidebarNode(title: kind.rawValue, icon: kind.icon, color: .systemOrange, kind: kind)
    }
    nodes.append(structured)

    // 5. Libraries - Generated & Wiki
    let generated = SidebarNode(title: "GENERATED & WIKI", isGroup: true)
    var genChildren = [SidebarNode(title: "Project Wiki", icon: "globe.americas.fill", color: .systemPurple, kind: .projectWiki)]
    genChildren.append(contentsOf: ModuleKind.allCases.filter {
        $0.archetype == .generated &&
        $0 != .dashboard &&
        $0 != .knowledgeGraph &&
        $0 != .timeline &&
        $0 != .analytics &&
        $0 != .intelligence &&
        $0 != .whiteboards &&
        $0 != .snippets &&
        $0 != .snapshots &&
        $0 != .projectWiki
    }.map { kind in
        SidebarNode(title: kind.rawValue, icon: kind.icon, color: .systemPurple, kind: kind)
    })
    generated.children = genChildren
    nodes.append(generated)

    return nodes
}

// MARK: - Modernized Document Type Selection Popover
struct DocumentCreationPopoverView: View {
    let coordinator: PersonalDocumentationCoordinator
    let onDismiss: () -> Void

    struct DocTypeItem {
        let name: String
        let kind: ModuleKind
        let icon: String
        let color: Color
    }

    private let items: [DocTypeItem] = [
        DocTypeItem(name: "API Documentation", kind: .apiDocumentation, icon: "network", color: .purple),
        DocTypeItem(name: "Database Documentation", kind: .databaseDocumentation, icon: "cylinder.split.1x2.fill", color: .orange),
        DocTypeItem(name: "Feature Planning", kind: .featurePlanning, icon: "slider.horizontal.3", color: .blue),
        DocTypeItem(name: "Security Notes", kind: .securityNotes, icon: "shield.fill", color: .red),
        DocTypeItem(name: "Architecture Record", kind: .architectureDecisions, icon: "gavel.fill", color: .purple),
        DocTypeItem(name: "Design Document", kind: .uiUXPlanning, icon: "paintpalette.fill", color: .green),
        DocTypeItem(name: "Technical Specification", kind: .technicalSpecification, icon: "doc.text.fill", color: .indigo),
        DocTypeItem(name: "Changelog", kind: .changelogBuilder, icon: "doc.text.below.ecg.fill", color: .orange),
        DocTypeItem(name: "Meeting Notes", kind: .meetingNotes, icon: "person.2.wave.2.fill", color: .cyan),
        DocTypeItem(name: "Research Notes", kind: .researchLibrary, icon: "archivebox.fill", color: .blue),
        DocTypeItem(name: "User Story", kind: .userStory, icon: "doc.text.image", color: .teal),
        DocTypeItem(name: "Testing Notes", kind: .testingNotes, icon: "checklist", color: .green),
        DocTypeItem(name: "Structured Record", kind: .structuredRecord, icon: "tablecells", color: .orange),
        DocTypeItem(name: "Freeform Document", kind: .freeformDocument, icon: "doc.text", color: .blue),
        DocTypeItem(name: "Release Checklist", kind: .releaseChecklist, icon: "shippingbox.fill", color: .orange)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                Text("Create New Entry")
                    .font(.headline)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                Divider()
                    .padding(.bottom, 4)

                ForEach(items, id: \.name) { item in
                    Button {
                        createNewDocument(of: item)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.icon)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(item.color)
                                .frame(width: 24, height: 24)
                                .background(item.color.opacity(0.12))
                                .cornerRadius(6)

                            Text(item.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.primary)

                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
        }
        .frame(width: 260, height: 480)
    }

    private func createNewDocument(of item: DocTypeItem) {
        do {
            let doc = try coordinator.documents.createDocument(title: "Untitled \(item.name)", kind: item.kind)
            coordinator.selectedModuleKind = item.kind
            let state = coordinator.state(for: item.kind)
            state.selectedDocumentID = doc.id
        } catch {
            // logging or ignore
        }
        onDismiss()
    }
}
