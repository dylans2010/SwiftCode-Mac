import AppKit
import SwiftCodeMCP
import SwiftCodePreviews

/// The Artboards window (gap closure, specs/ide/
/// gap-closure-windows-artboards.md §12): the visual UI builder
/// for the workspace's artboards.
///
/// The model is the gap-closure Artboards format: 57 component
/// types in a tree (`ArtboardComponentNode`), one
/// `ArtboardDocument` per workspace persisted by `ArtboardStore`
/// to Application Support `SwiftCode/Artboards/` as a
/// `.swiftcode-artboard` file — never inside the workspace. The
/// window lists the artboards, edits the active artboard's
/// component tree (add / delete / duplicate / lock / hide /
/// properties), edits the artboard's device/appearance/source,
/// and renders the active artboard's custom SwiftUI source
/// on demand through `PreviewRenderRunner`.
///
/// There is no live preview session: rendering is on demand only
/// (the Render Preview button), off the main thread, and an
/// artboard with no custom SwiftUI source says so instead of
/// rendering nothing. Every mutation saves immediately and tells
/// the MCP host to reload from the store, so the `artboard_*`
/// tools see the window's edits.
///
/// The controller's document operations are plain methods, so
/// tests drive them without showing the window.
@MainActor
public final class ArtboardWindowController: NSWindowController {
    /// Device frames the picker offers. The frame is a free
    /// string in the record; these are just the common ones.
    public static let deviceFrames = [
        "iPhone 16 Pro", "iPhone 16", "iPhone SE",
        "iPad Pro", "iPad", "Apple Watch",
    ]

    public let workspaceFolder: URL
    private let host: SwiftCodeMCPHost?

    /// The workspace's document. Setting it saves.
    public var document: ArtboardDocument {
        didSet { saveDocument() }
    }

    /// The active artboard, if any.
    public var activeArtboard: ArtboardRecord? {
        guard let id = document.activeArtboardID else { return nil }
        return document.artboards.first { $0.id == id }
    }

    /// The selected component node's id, if any.
    public private(set) var selectedNodeID: UUID?

    /// The last-rendered preview image, if any (tests).
    public private(set) var previewImage: NSImage?

    /// The current status text (tests).
    public private(set) var statusText = ""

    private let artboardTable = NSTableView()
    private let componentOutline = NSOutlineView()
    private let nameField = NSTextField()
    private let devicePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let appearancePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    private let portraitButton = NSButton(checkboxWithTitle: "Portrait", target: nil, action: nil)
    private let nodeNameField = NSTextField()
    private let nodeTypeLabel = NSTextField(labelWithString: "")
    private let nodeLockedButton = NSButton(checkboxWithTitle: "Locked", target: nil, action: nil)
    private let nodeHiddenButton = NSButton(checkboxWithTitle: "Hidden", target: nil, action: nil)
    private let propertiesView = NSTextView()
    private let sourceView = NSTextView()
    private let previewImageView = NSImageView()
    private let statusLabel = NSTextField(labelWithString: "")

    public init(workspaceFolder: URL, host: SwiftCodeMCPHost? = nil) {
        self.workspaceFolder = workspaceFolder
        self.host = host
        self.document = ArtboardStore.load(forWorkspace: workspaceFolder) ?? ArtboardDocument()
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 980, height: 620)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Artboards — \(workspaceFolder.lastPathComponent)"
        super.init(window: window)
        window.delegate = self
        buildContent()
        reloadAll()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Document operations

    /// Mutates the document through a copy and reassigns it, so
    /// `document`'s didSet saves. (Mutating `document.artboards`
    /// in place would not trigger didSet — the save would silently
    /// not happen.)
    private func mutateDocument(_ update: (inout ArtboardDocument) -> Void) {
        var copy = document
        update(&copy)
        document = copy
    }

    /// Adds an artboard (with Legacy's default root) and makes it
    /// active. Returns it.
    @discardableResult
    public func addArtboard(name: String, deviceFrame: String = "iPhone 16 Pro") -> ArtboardRecord {
        let record = ArtboardRecord(
            name: name, deviceFrame: deviceFrame,
            rootNode: ArtboardRecord.defaultRoot(name: name))
        mutateDocument { doc in
            doc.artboards.append(record)
            doc.activeArtboardID = record.id
        }
        selectedNodeID = record.rootNode.id
        reloadAll()
        return record
    }

    /// Deletes an artboard. The active id moves to the first
    /// remaining artboard, if any.
    public func deleteArtboard(id: UUID) {
        mutateDocument { doc in
            doc.artboards.removeAll { $0.id == id }
            if doc.activeArtboardID == id {
                doc.activeArtboardID = doc.artboards.first?.id
            }
        }
        selectedNodeID = activeArtboard?.rootNode.id
        reloadAll()
    }

    /// Makes an artboard active.
    public func selectArtboard(id: UUID) {
        guard document.artboards.contains(where: { $0.id == id }) else { return }
        mutateDocument { doc in doc.activeArtboardID = id }
        selectedNodeID = activeArtboard?.rootNode.id
        reloadAll()
    }

    /// Adds a component of `type` under the selected container
    /// node (or the root when nothing suitable is selected).
    /// Returns the new node, or nil when there is no artboard.
    @discardableResult
    public func addComponent(type: ArtboardComponentType, name: String? = nil) -> ArtboardComponentNode? {
        guard var artboard = activeArtboard else { return nil }
        let parentID: UUID
        if let selected = selectedNodeID,
           let selectedNode = artboard.rootNode.node(id: selected),
           selectedNode.type.isContainer {
            parentID = selected
        } else {
            parentID = artboard.rootNode.id
        }
        let node = ArtboardComponentNode(type: type, name: name ?? type.rawValue)
        artboard.rootNode = artboard.rootNode.addChild(node, to: parentID)
        replaceArtboard(artboard)
        selectedNodeID = node.id
        reloadAll()
        return node
    }

    /// Deletes a component. The root node cannot be deleted.
    public func deleteComponent(id: UUID) {
        guard var artboard = activeArtboard, id != artboard.rootNode.id else { return }
        artboard.rootNode = artboard.rootNode.removeNode(id: id)
        replaceArtboard(artboard)
        selectedNodeID = artboard.rootNode.id
        reloadAll()
    }

    /// Duplicates a component (the copy gets a fresh id) as a
    /// sibling after the original.
    @discardableResult
    public func duplicateComponent(id: UUID) -> ArtboardComponentNode? {
        guard var artboard = activeArtboard, id != artboard.rootNode.id,
              let original = artboard.rootNode.node(id: id) else { return nil }
        let copy = original.duplicated()
        artboard.rootNode = insertSibling(copy, after: id, in: artboard.rootNode)
        replaceArtboard(artboard)
        selectedNodeID = copy.id
        reloadAll()
        return copy
    }

    /// Updates one component node in place.
    public func updateComponent(id: UUID, _ update: (inout ArtboardComponentNode) -> Void) {
        guard var artboard = activeArtboard else { return }
        artboard.rootNode = artboard.rootNode.updateNode(id: id, update)
        replaceArtboard(artboard)
        reloadAll()
    }

    /// Updates the active artboard's own fields.
    public func updateArtboard(_ update: (inout ArtboardRecord) -> Void) {
        guard var artboard = activeArtboard else { return }
        update(&artboard)
        replaceArtboard(artboard)
        reloadAll()
    }

    /// Reloads the document from the store (discarding unsaved
    /// window edits).
    public func reload() {
        document = ArtboardStore.load(forWorkspace: workspaceFolder) ?? ArtboardDocument()
        selectedNodeID = activeArtboard?.rootNode.id
        reloadAll()
    }

    /// Saves the document to the store and tells the MCP host to
    /// reload from it. Returns false (with the status set) when
    /// the save fails.
    @discardableResult
    public func saveDocument() -> Bool {
        do {
            try ArtboardStore.save(document, forWorkspace: workspaceFolder)
            host?.reloadArtboardsFromStore(workspaceFolder: workspaceFolder)
            return true
        } catch {
            setStatus("Could not save artboards: \(error.localizedDescription)")
            return false
        }
    }

    private func replaceArtboard(_ artboard: ArtboardRecord) {
        mutateDocument { doc in
            guard let index = doc.artboards.firstIndex(where: { $0.id == artboard.id }) else { return }
            doc.artboards[index] = artboard
        }
    }

    /// Inserts `node` as a sibling after `id` in the tree.
    private func insertSibling(_ node: ArtboardComponentNode, after id: UUID, in root: ArtboardComponentNode) -> ArtboardComponentNode {
        var root = root
        if let index = root.children.firstIndex(where: { $0.id == id }) {
            root.children.insert(node, at: index + 1)
            return root
        }
        root.children = root.children.map { insertSibling(node, after: id, in: $0) }
        return root
    }

    // MARK: - Preview rendering

    /// Renders the active artboard's custom SwiftUI source on
    /// demand, off the main thread. An artboard with no source
    /// says so instead of rendering nothing.
    public func renderPreview() {
        guard let artboard = activeArtboard else {
            setStatus("No artboard is selected.")
            return
        }
        guard let source = artboard.customSwiftUISource?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              !source.isEmpty else {
            setStatus("“\(artboard.name)” has no custom SwiftUI source — add source to render a preview.")
            return
        }
        setStatus("Rendering “\(artboard.name)”…")
        let folder = workspaceFolder
        let artboardID = artboard.id
        let artboardName = artboard.name
        Task.detached {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("swiftcode-artboard-render-\(UUID().uuidString)")
            let sourceFile = tempDir.appendingPathComponent("\(artboardName).swift")
            let output = ArtboardStore.previewRenderCacheDirectory()
                .appendingPathComponent("\(artboardID.uuidString).png")
            defer { try? FileManager.default.removeItem(at: tempDir) }
            do {
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                try source.write(to: sourceFile, atomically: true, encoding: .utf8)
            } catch {
                await MainActor.run { self.setStatus("Could not stage the preview source: \(error.localizedDescription)") }
                return
            }
            let result = PreviewRenderRunner.render(
                file: sourceFile.path, name: nil, output: output.path, starts: [folder])
            await MainActor.run {
                switch result {
                case .success(let url):
                    self.previewImage = NSImage(contentsOf: url)
                    self.previewImageView.image = self.previewImage
                    self.setStatus("Rendered “\(artboardName)” to \(url.lastPathComponent).")
                case .failure(let failure):
                    self.previewImage = nil
                    self.previewImageView.image = nil
                    self.setStatus("Preview failed: \(failure.description)")
                }
            }
        }
    }

    // MARK: - Status

    private func setStatus(_ text: String) {
        statusText = text
        statusLabel.stringValue = text
    }

    // MARK: - UI

    private func buildContent() {
        guard let contentView = window?.contentView else { return }
        // Left: artboard list.
        let artboardColumn = NSStackView()
        artboardColumn.orientation = .vertical
        artboardColumn.spacing = 6
        artboardColumn.addArrangedSubview(Self.sectionLabel("Artboards"))
        let artboardColumnView = NSTableColumn(identifier: .init("artboard"))
        artboardColumnView.width = 190
        artboardTable.addTableColumn(artboardColumnView)
        artboardTable.headerView = nil
        artboardTable.dataSource = self
        artboardTable.delegate = self
        artboardTable.target = self
        artboardTable.doubleAction = #selector(artboardDoubleClicked)
        let artboardScroll = NSScrollView()
        artboardScroll.documentView = artboardTable
        artboardScroll.hasVerticalScroller = true
        artboardScroll.borderType = .bezelBorder
        artboardColumn.addArrangedSubview(artboardScroll)
        let addArtboardButton = NSButton(title: "Add", target: self, action: #selector(addArtboardClicked))
        let deleteArtboardButton = NSButton(title: "Delete", target: self, action: #selector(deleteArtboardClicked))
        let artboardButtons = NSStackView(views: [addArtboardButton, deleteArtboardButton, NSView()])
        artboardButtons.orientation = .horizontal
        artboardButtons.spacing = 6
        artboardColumn.addArrangedSubview(artboardButtons)

        // Middle: component tree.
        let componentColumn = NSStackView()
        componentColumn.orientation = .vertical
        componentColumn.spacing = 6
        componentColumn.addArrangedSubview(Self.sectionLabel("Components"))
        let componentColumnView = NSTableColumn(identifier: .init("component"))
        componentColumnView.width = 300
        componentOutline.addTableColumn(componentColumnView)
        componentOutline.headerView = nil
        componentOutline.dataSource = self
        componentOutline.delegate = self
        let componentScroll = NSScrollView()
        componentScroll.documentView = componentOutline
        componentScroll.hasVerticalScroller = true
        componentScroll.borderType = .bezelBorder
        componentColumn.addArrangedSubview(componentScroll)
        let addComponentPopUp = NSPopUpButton(frame: .zero, pullsDown: false)
        addComponentPopUp.addItem(withTitle: "Add Component…")
        for type in ArtboardComponentType.allCases {
            addComponentPopUp.addItem(withTitle: type.rawValue)
        }
        addComponentPopUp.target = self
        addComponentPopUp.action = #selector(addComponentChosen(_:))
        let deleteComponentButton = NSButton(title: "Delete", target: self, action: #selector(deleteComponentClicked))
        let duplicateComponentButton = NSButton(title: "Duplicate", target: self, action: #selector(duplicateComponentClicked))
        let componentButtons = NSStackView(views: [addComponentPopUp, deleteComponentButton, duplicateComponentButton])
        componentButtons.orientation = .horizontal
        componentButtons.spacing = 6
        componentColumn.addArrangedSubview(componentButtons)

        // Right: inspector.
        let inspectorColumn = NSStackView()
        inspectorColumn.orientation = .vertical
        inspectorColumn.spacing = 6
        inspectorColumn.addArrangedSubview(Self.sectionLabel("Inspector"))
        devicePopUp.addItems(withTitles: Self.deviceFrames)
        devicePopUp.target = self
        devicePopUp.action = #selector(deviceChosen(_:))
        appearancePopUp.addItems(withTitles: ["System", "Light", "Dark"])
        appearancePopUp.target = self
        appearancePopUp.action = #selector(appearanceChosen(_:))
        portraitButton.target = self
        portraitButton.action = #selector(portraitClicked(_:))
        nodeLockedButton.target = self
        nodeLockedButton.action = #selector(nodeLockedClicked(_:))
        nodeHiddenButton.target = self
        nodeHiddenButton.action = #selector(nodeHiddenClicked(_:))
        nameField.delegate = self
        nodeNameField.delegate = self
        propertiesView.delegate = self
        sourceView.delegate = self
        propertiesView.isRichText = false
        propertiesView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        sourceView.isRichText = false
        sourceView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        let inspectorForm = NSStackView(views: [
            Self.fieldRow("Name:", nameField),
            Self.fieldRow("Device:", devicePopUp),
            Self.fieldRow("Appearance:", appearancePopUp),
            portraitButton,
            Self.sectionLabel("Selected Component"),
            nodeTypeLabel,
            Self.fieldRow("Name:", nodeNameField),
            nodeLockedButton,
            nodeHiddenButton,
            Self.sectionLabel("Properties (one \"key: value\" per line)"),
            Self.textScroll(propertiesView, height: 90),
            Self.sectionLabel("Custom SwiftUI Source"),
            Self.textScroll(sourceView, height: 120),
        ])
        inspectorForm.orientation = .vertical
        inspectorForm.spacing = 6
        inspectorForm.alignment = .leading
        let inspectorScroll = NSScrollView()
        inspectorScroll.documentView = inspectorForm
        inspectorScroll.hasVerticalScroller = true
        inspectorColumn.addArrangedSubview(inspectorScroll)

        // Main row.
        let mainRow = NSStackView(views: [artboardColumn, componentColumn, inspectorColumn])
        mainRow.orientation = .horizontal
        mainRow.spacing = 8
        mainRow.distribution = .fill
        artboardColumn.widthAnchor.constraint(equalToConstant: 200).isActive = true
        inspectorColumn.widthAnchor.constraint(equalToConstant: 280).isActive = true

        // Preview row: the last render + the render button.
        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.wantsLayer = true
        previewImageView.layer?.borderWidth = 1
        previewImageView.layer?.borderColor = NSColor.separatorColor.cgColor
        previewImageView.widthAnchor.constraint(equalToConstant: 320).isActive = true
        previewImageView.heightAnchor.constraint(equalToConstant: 180).isActive = true
        let renderButton = NSButton(title: "Render Preview", target: self, action: #selector(renderClicked))
        renderButton.bezelStyle = .rounded
        let renderHint = NSTextField(wrappingLabelWithString: "Renders the active artboard's custom SwiftUI source on demand. No live preview session — press Render Preview after editing the source.")
        renderHint.font = .systemFont(ofSize: 11)
        renderHint.textColor = .secondaryLabelColor
        let renderColumn = NSStackView(views: [renderButton, renderHint])
        renderColumn.orientation = .vertical
        renderColumn.spacing = 6
        renderColumn.alignment = .leading
        let previewRow = NSStackView(views: [previewImageView, renderColumn])
        previewRow.orientation = .horizontal
        previewRow.spacing = 8
        previewRow.alignment = .top

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        let root = NSStackView(views: [mainRow, previewRow, statusLabel])
        root.orientation = .vertical
        root.spacing = 8
        root.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: contentView.topAnchor),
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            mainRow.heightAnchor.constraint(greaterThanOrEqualToConstant: 320),
        ])
    }

    private static func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .boldSystemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        return label
    }

    private static func fieldRow(_ title: String, _ control: NSView) -> NSStackView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11)
        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.spacing = 6
        row.alignment = .firstBaseline
        return row
    }

    private static func textScroll(_ textView: NSTextView, height: CGFloat) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
        return scroll
    }

    // MARK: - Refresh

    private func reloadAll() {
        artboardTable.reloadData()
        componentOutline.reloadData()
        if let active = activeArtboard {
            componentOutline.expandItem(active.rootNode.id)
            if let selected = selectedNodeID {
                let row = componentOutline.row(forItem: selected as Any)
                if row >= 0 {
                    componentOutline.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                }
            }
        }
        refreshInspector()
    }

    private func refreshInspector() {
        guard let artboard = activeArtboard else {
            nameField.stringValue = ""
            devicePopUp.selectItem(at: 0)
            appearancePopUp.selectItem(at: 0)
            portraitButton.state = .off
            nodeTypeLabel.stringValue = "No artboard."
            nodeNameField.stringValue = ""
            propertiesView.string = ""
            sourceView.string = ""
            return
        }
        nameField.stringValue = artboard.name
        if let deviceIndex = Self.deviceFrames.firstIndex(of: artboard.deviceFrame) {
            devicePopUp.selectItem(at: deviceIndex)
        } else {
            devicePopUp.selectItem(at: 0)
        }
        appearancePopUp.selectItem(withTitle: artboard.appearance)
        portraitButton.state = artboard.isPortrait ? .on : .off
        if let selected = selectedNodeID, let node = artboard.rootNode.node(id: selected) {
            nodeTypeLabel.stringValue = node.type.rawValue
            nodeNameField.stringValue = node.name
            nodeLockedButton.state = node.isLocked ? .on : .off
            nodeHiddenButton.state = node.isHidden ? .on : .off
            propertiesView.string = node.properties
                .sorted { $0.key < $1.key }
                .map { "\($0.key): \($0.value)" }
                .joined(separator: "\n")
        } else {
            nodeTypeLabel.stringValue = "No component selected."
            nodeNameField.stringValue = ""
            nodeLockedButton.state = .off
            nodeHiddenButton.state = .off
            propertiesView.string = ""
        }
        sourceView.string = artboard.customSwiftUISource ?? ""
    }

    // MARK: - Actions

    @objc private func addArtboardClicked() {
        addArtboard(name: "Artboard \(document.artboards.count + 1)")
    }

    @objc private func deleteArtboardClicked() {
        guard let active = activeArtboard else { return }
        deleteArtboard(id: active.id)
    }

    @objc private func artboardDoubleClicked() {
        // Double-click renames: focus the inspector's name field.
        window?.makeFirstResponder(nameField)
    }

    @objc private func addComponentChosen(_ sender: NSPopUpButton) {
        guard sender.indexOfSelectedItem > 0 else { return }
        let type = ArtboardComponentType.allCases[sender.indexOfSelectedItem - 1]
        addComponent(type: type)
        sender.selectItem(at: 0)
    }

    @objc private func deleteComponentClicked() {
        guard let selected = selectedNodeID else { return }
        deleteComponent(id: selected)
    }

    @objc private func duplicateComponentClicked() {
        guard let selected = selectedNodeID else { return }
        duplicateComponent(id: selected)
    }

    @objc private func deviceChosen(_ sender: NSPopUpButton) {
        guard let frame = sender.titleOfSelectedItem else { return }
        updateArtboard { $0.deviceFrame = frame }
    }

    @objc private func appearanceChosen(_ sender: NSPopUpButton) {
        guard let appearance = sender.titleOfSelectedItem else { return }
        updateArtboard { $0.appearance = appearance }
    }

    @objc private func portraitClicked(_ sender: NSButton) {
        updateArtboard { $0.isPortrait = sender.state == .on }
    }

    @objc private func nodeLockedClicked(_ sender: NSButton) {
        guard let selected = selectedNodeID else { return }
        updateComponent(id: selected) { $0.isLocked = sender.state == .on }
    }

    @objc private func nodeHiddenClicked(_ sender: NSButton) {
        guard let selected = selectedNodeID else { return }
        updateComponent(id: selected) { $0.isHidden = sender.state == .on }
    }

    @objc private func renderClicked() {
        renderPreview()
    }
}

// MARK: - NSTableView / NSOutlineView

extension ArtboardWindowController: NSTableViewDataSource, NSTableViewDelegate {
    public func numberOfRows(in tableView: NSTableView) -> Int {
        document.artboards.count
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard document.artboards.indices.contains(row) else { return nil }
        let artboard = document.artboards[row]
        let cell = NSTableCellView()
        let field = NSTextField(labelWithString: "\(artboard.name) — \(artboard.deviceFrame)")
        field.font = .systemFont(ofSize: 12)
        cell.textField = field
        cell.addSubview(field)
        field.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        let row = artboardTable.selectedRow
        guard document.artboards.indices.contains(row) else { return }
        selectArtboard(id: document.artboards[row].id)
    }
}

extension ArtboardWindowController: NSOutlineViewDataSource, NSOutlineViewDelegate {
    public func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let root = activeArtboard?.rootNode else { return 0 }
        if let id = item as? UUID, let node = root.node(id: id) {
            return node.children.count
        }
        return 1 // the root node itself
    }

    public func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let root = activeArtboard?.rootNode else { return UUID() }
        if let id = item as? UUID, let node = root.node(id: id) {
            return node.children[index].id
        }
        return root.id
    }

    public func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        guard let root = activeArtboard?.rootNode,
              let id = item as? UUID, let node = root.node(id: id) else { return false }
        return node.type.isContainer && !node.children.isEmpty
    }

    public func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let root = activeArtboard?.rootNode,
              let id = item as? UUID, let node = root.node(id: id) else { return nil }
        let cell = NSTableCellView()
        let suffix = node.isLocked ? " (locked)" : (node.isHidden ? " (hidden)" : "")
        let field = NSTextField(labelWithString: "\(node.name) — \(node.type.rawValue)\(suffix)")
        field.font = .systemFont(ofSize: 12)
        cell.textField = field
        cell.addSubview(field)
        field.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -4),
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
        ])
        return cell
    }

    public func outlineViewSelectionDidChange(_ notification: Notification) {
        let row = componentOutline.selectedRow
        guard row >= 0, let id = componentOutline.item(atRow: row) as? UUID else { return }
        selectedNodeID = id
        refreshInspector()
    }
}

// MARK: - Text editing

extension ArtboardWindowController: NSTextFieldDelegate, NSTextViewDelegate {
    public func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        if field === nameField {
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { refreshInspector(); return }
            updateArtboard { $0.name = name }
        } else if field === nodeNameField {
            guard let selected = selectedNodeID else { return }
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { refreshInspector(); return }
            updateComponent(id: selected) { $0.name = name }
        }
    }

    public func textDidEndEditing(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        if textView === propertiesView {
            guard let selected = selectedNodeID else { return }
            var properties: [String: String] = [:]
            var dropped = 0
            for line in textView.string.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { continue }
                guard let colon = trimmed.firstIndex(of: ":") else { dropped += 1; continue }
                let key = trimmed[..<colon].trimmingCharacters(in: .whitespaces)
                let value = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty else { dropped += 1; continue }
                properties[String(key)] = String(value)
            }
            updateComponent(id: selected) { $0.properties = properties }
            if dropped > 0 {
                setStatus("\(dropped) propert\(dropped == 1 ? "y" : "ies") ignored (each line needs \"key: value\").")
            }
        } else if textView === sourceView {
            let source = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
            updateArtboard { $0.customSwiftUISource = source.isEmpty ? nil : textView.string }
        }
    }
}

extension ArtboardWindowController: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        saveDocument()
    }
}

/// One Artboards window per workspace (the same shape as the
/// deploy / CI / virtualization window managers): a second open
/// for the same workspace focuses the existing window.
@MainActor
public final class ArtboardWindowManager: NSObject {
    public static let shared = ArtboardWindowManager()

    private var controllers: [String: ArtboardWindowController] = [:]

    /// Shows the workspace's Artboards window (creating it the
    /// first time). `host` is the workspace window's MCP host, so
    /// window edits reach the `artboard_*` tools; nil opens the
    /// window standalone.
    public func showWindow(workspaceFolder: URL, host: SwiftCodeMCPHost? = nil) {
        let key = workspaceFolder.standardizedFileURL.path
        if let existing = controllers[key] {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = ArtboardWindowController(workspaceFolder: workspaceFolder, host: host)
        controllers[key] = controller
        if let window = controller.window {
            var token: NSObjectProtocol?
            token = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                if let token { NotificationCenter.default.removeObserver(token) }
                MainActor.assumeIsolated {
                    self?.controllers.removeValue(forKey: key)
                }
            }
        }
        controller.showWindow(nil)
    }
}
