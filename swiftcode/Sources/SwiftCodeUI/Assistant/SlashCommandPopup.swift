import AppKit
import SwiftCodeAssistant
import SwiftCodeIDECore

/// The `/` slash-command popup (gap closure, specs/ide/
/// gap-closure-windows-artboards.md §1.4).
///
/// Legacy's `AssistComposerPopup` in `.metaCommand` mode: rows from
/// `searchCommands`, ↑↓ wraparound selection, Return commits, a
/// footer count line. This is the SwiftCode port as an `NSPopover`
/// anchored to the composer: it lists the filtered commands, shows
/// an argument field when the selected command takes one (Legacy's
/// argument prompt, inlined), and commits through the model's
/// existing intercept — effect commands are sent immediately,
/// anything else is left in the input for editing.
///
/// The popup only ever opens when Assist with Meta is the active
/// provider and `useMetaSlashCommands` is on (the composer patch
/// checks both before showing it); this controller trusts its
/// caller on that and only drives the list.
@MainActor
public final class SlashCommandPopupController: NSObject {
    /// The model whose slash-command catalog drives the list.
    public let model: CodingAssistantModel
    /// The composer text view the popover anchors to.
    public weak var anchorView: NSView?

    /// Called with the committed command text and whether to send
    /// it immediately (effect commands) or leave it in the input.
    public var onCommit: ((String, Bool) -> Void)?
    /// Called when the popup closes for any reason.
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

    /// The commands matching the query, in catalog order.
    public var filtered: [MetaSlashCommand] { state.filtered }

    private var state: SlashCommandPaletteState {
        get { content.state }
        set { content.state = newValue }
    }

    /// Opens the popup for `query` (the text after the `/`).
    /// Triggers the once-only terminal-skill capture, so skills
    /// join the list; typing refreshes it when the capture lands.
    public func show(query: String) {
        model.ensureSlashCommandsCaptured()
        self.query = query
        refresh()
        guard let anchorView else { return }
        if !popover.isShown {
            popover.show(relativeTo: anchorView.bounds, of: anchorView, preferredEdge: .maxY)
        }
    }

    /// Re-filters for a new query (called on every composer edit
    /// while the popup is open). A query with no matches keeps the
    /// popup open with the empty state — Legacy showed "No commands
    /// found" the same way.
    public func update(query: String) {
        self.query = query
        refresh()
    }

    public func hide() {
        popover.close()
    }

    /// Rebuilds the palette state from the model's live catalog
    /// (the capture may have added terminal skills since the popup
    /// opened) and reloads the table.
    public func refresh() {
        state = SlashCommandPaletteState(manager: model.metaSlashCommands, query: query)
        content.reload()
    }

    /// Offers a key event to the popup. Returns true when the popup
    /// consumed it (the composer must not also handle it).
    /// Up/Down move, Return commits, Escape dismisses.
    public func handleKeyDown(_ event: NSEvent) -> Bool {
        guard popover.isShown else { return false }
        // The argument field owns Return while focused; Escape
        // still dismisses from there.
        if content.argumentFieldIsFocused {
            if event.keyCode == 53 { hide(); return true }
            return false
        }
        switch event.keyCode {
        case 126: // Up
            state.moveUp()
            content.reload()
            return true
        case 125: // Down
            state.moveDown()
            content.reload()
            return true
        case 36, 76: // Return / keypad Enter
            commit()
            return true
        case 53: // Escape
            hide()
            return true
        default:
            return false
        }
    }

    /// Commits the selection: the full command text goes to
    /// `onCommit` with whether it should be sent immediately.
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

/// The popover's content: the command table, the argument field
/// (only when the selected command takes arguments), and the
/// footer count line.
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

    /// The argument the user typed, or nil when no argument field
    /// is shown (the command takes none).
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

    /// Shows the argument field when the selected command takes
    /// arguments, with the first argument's name/choices as the
    /// placeholder (Legacy's argument prompt, inlined).
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

    // MARK: - NSTableViewDataSource

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

    // MARK: - NSTableViewDelegate

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, state.filtered.indices.contains(row) else { return }
        // Keep the palette state's selection in step with clicks.
        while state.selectedIndex != row {
            if (state.selectedIndex ?? 0) < row { state.moveDown() } else { state.moveUp() }
        }
        updateArgumentField()
    }
}
