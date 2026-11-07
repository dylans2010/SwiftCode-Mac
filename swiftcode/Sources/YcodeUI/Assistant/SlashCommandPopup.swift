import AppKit
import YcodeAssistant
import YcodeIDECore

@MainActor
public final class SlashCommandPopupController: NSObject {
    public let model: CodingAssistantModel
    public weak var anchorView: NSView?

    public var onCommit: ((String, Bool) -> Void)?
    public var onDismiss: (() -> Void)?

    private let popover = NSPopover()
    private let content = SlashCommandPopupContent()
    private var query = ""

    public init(model: CodingAssistantModel, anchorView: NSView) {
        self.model = model
        self.anchorView = anchorView
        super.init()
        content.controller = self
        popover.contentViewController = content
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
    }

    public var isVisible: Bool { popover.isShown }

    public var filtered: [MetaSlashCommand] { state.filtered }

    private var state: SlashCommandPaletteState {
        get { content.state }
        set { content.state = newValue }
    }

    public func show(query: String) {
        model.ensureSlashCommandsCaptured()
        self.query = query
        refresh()
        guard let anchorView else { return }
        if !popover.isShown {
            popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .maxY)
        }
    }

    public func update(query: String) {
        self.query = query
        refresh()
    }

    public func hide() {
        popover.close()
    }

    public func refresh() {
        state = SlashCommandPaletteState(manager: model.metaSlashCommands, query: query)
        content.reload()
    }

    public func handleKeyDown(_ event: NSEvent) -> Bool {
        guard popover.isShown else { return false }
        if content.argumentFieldIsFocused {
            if event.keyCode == 53 { hide(); return true }
            return false
        }
        switch event.keyCode {
        case 126:
            state.moveUp()
            content.reload()
            return true
        case 125:
            state.moveDown()
            content.reload()
            return true
        case 36, 76:
            commit()
            return true
        case 53:
            hide()
            return true
        default:
            return false
        }
    }

    public func commit() {
        let argument = content.argumentValue
        guard let text = state.commitText(argument: argument) else { return }
        let send = state.shouldSendImmediately(argument: argument)
        hide()
        onCommit?(text, send)
    }
}

extension SlashCommandPopupController: NSPopoverDelegate {
    public func popoverDidClose(_ notification: Notification) {
        onDismiss?()
    }
}

@MainActor
final class SlashCommandPopupContent: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    weak var controller: SlashCommandPopupController?

    var state = SlashCommandPaletteState(manager: MetaSlashCommandManager(), query: "") {
        didSet { reload() }
    }

    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let argumentField = NSTextField()
    private let footerLabel = NSTextField(labelWithString: "")

    var argumentValue: String? {
        guard !argumentField.isHidden else { return nil }
        let value = argumentField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    var argumentFieldIsFocused: Bool {
        view.window?.firstResponder == argumentField.currentEditor()
    }

    override func loadView() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 6, bottom: 6, right: 6)

        let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("command"))
        nameColumn.title = "Command"
        nameColumn.width = 140
        let titleColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("description"))
        titleColumn.title = "Description"
        titleColumn.width = 320
        tableView.addTableColumn(nameColumn)
        tableView.addTableColumn(titleColumn)
        tableView.headerView = nil
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(rowDoubleClicked)
        tableView.rowHeight = 22
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(equalToConstant: 220).isActive = true
        stack.addArrangedSubview(scrollView)

        argumentField.isHidden = true
        argumentField.target = self
        argumentField.action = #selector(argumentCommitted)
        stack.addArrangedSubview(argumentField)

        footerLabel.font = .systemFont(ofSize: 11)
        footerLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(footerLabel)

        view = stack
        view.frame = NSRect(x: 0, y: 0, width: 480, height: 280)
    }

    func reload() {
        tableView.reloadData()
        if let selected = state.selectedIndex {
            tableView.selectRowIndexes(IndexSet(integer: selected), byExtendingSelection: false)
            tableView.scrollRowToVisible(selected)
        } else {
            tableView.deselectAll(nil)
        }
        let count = state.filtered.count
        footerLabel.stringValue = "\(count) command\(count == 1 ? "" : "s") · Navigate with ↑↓ and Return ↵"
        updateArgumentField()
    }

    private func updateArgumentField() {
        guard let command = state.selected, command.requiresArguments,
              let first = command.arguments.first else {
            argumentField.isHidden = true
            return
        }
        argumentField.isHidden = false
        switch first {
        case .options(let name, let choices, _):
            argumentField.placeholderString = "\(name) (\(choices.joined(separator: ", ")))"
        case .text(let name, let placeholder, _):
            argumentField.placeholderString = "\(name): \(placeholder)"
        }
    }

    @objc private func rowDoubleClicked() {
        controller?.commit()
    }

    @objc private func argumentCommitted() {
        controller?.commit()
    }

    func numberOfRows(in tableView: NSTableView) -> Int {
        state.filtered.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard state.filtered.indices.contains(row) else { return nil }
        let command = state.filtered[row]
        let cell = NSTableCellView()
        let field = NSTextField(labelWithString: tableColumn?.identifier.rawValue == "command"
            ? command.name : command.title)
        field.font = tableColumn?.identifier.rawValue == "command"
            ? .monospacedSystemFont(ofSize: 12, weight: .regular)
            : .systemFont(ofSize: 12)
        field.lineBreakMode = .byTruncatingTail
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

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, state.filtered.indices.contains(row) else { return }
        while state.selectedIndex != row {
            if (state.selectedIndex ?? 0) < row { state.moveDown() } else { state.moveUp() }
        }
        updateArgumentField()
    }
}
