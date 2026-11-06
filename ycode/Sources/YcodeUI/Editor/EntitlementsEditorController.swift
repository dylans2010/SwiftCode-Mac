import AppKit
import YcodeIDECore

/// The `.entitlements` editor for the AppKit IDE: the capability catalog
/// as a table (name, key, on/off checkbox), the selected capability's
/// payload editor below it, and the validation findings at the bottom.
/// Every edit goes through `EntitlementsEditorModel` and is written back
/// as a sorted XML plist. The Linux IDE renders the same model with
/// `EntitlementsEditorView` (ycode-ide).
@MainActor
public final class EntitlementsEditorController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {
    public let url: URL
    public let model: EntitlementsEditorModel
    private let table = NSTableView()
    private let searchField = NSSearchField()
    private let sectionPopup = NSPopUpButton()
    private let statusLabel = NSTextField(labelWithString: "")
    private let issuesView = NSTextView()

    public init(url: URL) throws {
        self.url = url
        model = try EntitlementsEditorModel(url: url)
        super.init(nibName: nil, bundle: nil)
    }

    /// An in-memory editor (tests).
    public init(model: EntitlementsEditorModel, url: URL) {
        self.url = url
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - View

    public override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 560))

        searchField.delegate = self
        searchField.placeholderString = "Search capabilities"
        sectionPopup.addItems(withTitles: ["All Capabilities"] + EntitlementCapabilitySection.allCases
            .filter { $0 != .all && $0 != .other }.map(\.fullTitle))
        sectionPopup.target = self
        sectionPopup.action = #selector(sectionChosen)
        let toolbar = NSStackView(views: [searchField, sectionPopup])
        toolbar.spacing = 8
        searchField.widthAnchor.constraint(equalToConstant: 260).isActive = true

        for (id, title, width) in [("on", "", 28.0), ("name", "Capability", 240.0), ("key", "Entitlement Key", 340.0)] {
            let column = NSTableColumn(identifier: .init(id))
            column.title = title
            column.width = width
            table.addTableColumn(column)
        }
        table.dataSource = self
        table.delegate = self
        table.usesAlternatingRowBackgroundColors = true
        table.rowSizeStyle = .small
        table.headerView = NSTableHeaderView()
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true

        issuesView.isEditable = false
        issuesView.font = .systemFont(ofSize: 11)
        let issuesScroll = NSScrollView()
        issuesScroll.documentView = issuesView
        issuesScroll.hasVerticalScroller = true

        let saveButton = NSButton(title: "Save", target: self, action: #selector(saveClicked))
        let revertButton = NSButton(title: "Revert", target: self, action: #selector(revertClicked))
        let validateButton = NSButton(title: "Validate", target: self, action: #selector(validateClicked))
        for b in [saveButton, revertButton, validateButton] { b.bezelStyle = .rounded }
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        let buttons = NSStackView(views: [saveButton, revertButton, validateButton, statusLabel])
        buttons.spacing = 8

        for v in [toolbar, scroll, issuesScroll, buttons] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(v)
        }
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: root.topAnchor, constant: 8),
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.heightAnchor.constraint(equalTo: root.heightAnchor, multiplier: 0.6),
            issuesScroll.topAnchor.constraint(equalTo: scroll.bottomAnchor, constant: 6),
            issuesScroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            issuesScroll.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            issuesScroll.bottomAnchor.constraint(equalTo: buttons.topAnchor, constant: -6),
            buttons.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 8),
            buttons.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            buttons.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),
            buttons.heightAnchor.constraint(equalToConstant: 28),
        ])
        view = root
        reload()
    }

    func reload() {
        table.reloadData()
        refreshIssues()
        statusLabel.stringValue = "\(model.entitlements.count) active — \(model.sandboxIsOn ? "Sandbox on" : "Sandbox off")"
    }

    /// Writes the file as a sorted XML plist.
    func commit() {
        do { try model.save() } catch { presentError(error) }
        reload()
    }

    // MARK: - Table

    private var visibleDefinitions: [CapabilityDefinition] {
        EntitlementCapabilityCatalog.definitions(in: model.selectedSection)
            .filter { model.capabilityMatchesSearch($0) }
    }

    public func numberOfRows(in tableView: NSTableView) -> Int { visibleDefinitions.count }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard visibleDefinitions.indices.contains(row) else { return nil }
        let def = visibleDefinitions[row]
        switch tableColumn?.identifier.rawValue {
        case "on":
            let check = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleClicked(_:)))
            check.state = model.isCapabilityOn(def) ? .on : .off
            check.tag = row
            check.toolTip = def.requiresSpecialApproval ? "Requires a special entitlement request to Apple." : nil
            return check
        case "key":
            let f = NSTextField(labelWithString: def.rawKey)
            f.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            f.textColor = .secondaryLabelColor
            return f
        default:
            let f = NSTextField(labelWithString: def.name)
            f.font = .systemFont(ofSize: 12)
            return f
        }
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        guard table.selectedRow >= 0, visibleDefinitions.indices.contains(table.selectedRow) else { return }
        model.selectedKey = visibleDefinitions[table.selectedRow].rawKey
    }

    @objc private func toggleClicked(_ sender: NSButton) {
        guard visibleDefinitions.indices.contains(sender.tag) else { return }
        let def = visibleDefinitions[sender.tag]
        model.setCapability(def, on: sender.state == .on)
        commit()
    }

    @objc private func sectionChosen() {
        let title = sectionPopup.titleOfSelectedItem ?? "All Capabilities"
        model.selectedSection = EntitlementCapabilitySection.allCases.first { $0.fullTitle == title } ?? .all
        reload()
    }

    public func controlTextDidChange(_ obj: Notification) {
        model.searchText = searchField.stringValue
        reload()
    }

    // MARK: - Actions (also used by tests)

    @objc private func saveClicked() { commit() }

    @objc private func revertClicked() {
        do { try model.revert() } catch { presentError(error) }
        reload()
    }

    @objc private func validateClicked() { refreshIssues() }

    private func refreshIssues() {
        let issues = model.validate()
        if issues.isEmpty {
            issuesView.string = "All capabilities are valid."
        } else {
            issuesView.string = issues.map { issue in
                "\(issue.severity.rawValue.uppercased()) \(issue.rawKey): \(issue.message)"
            }.joined(separator: "\n")
        }
        statusLabel.stringValue = "\(model.entitlements.count) active — \(issues.filter { $0.severity == .error }.count) errors, \(issues.filter { $0.severity == .warning }.count) warnings"
    }

    /// Applies one of Legacy's four capability presets.
    public func applyPreset(_ preset: EntitlementsPreset) {
        model.applyPreset(preset)
        commit()
    }

    /// The raw XML text of the current dictionary (Copy Raw XML).
    public var xmlText: String { model.xmlText() }
}
