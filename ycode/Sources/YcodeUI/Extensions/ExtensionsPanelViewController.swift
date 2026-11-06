import AppKit
import YcodeIDECore
#if canImport(YcodeExtensions)
import YcodeExtensions
#endif

/// The Extensions panel (spec `extensions-platform.md` §1.2, §3–§8):
/// the editor toolbar's Extensions button opens this popover. It lists
/// installed extensions only — there is no remote marketplace UI (no
/// reachable remote endpoint was found; Open VSX search/install is a
/// later slice) — with enable/disable, the selected extension's
/// permissions/capabilities (from the host's grant store), and a
/// diagnostics view (host status, Node availability, recent errors).
///
/// The panel talks to the host through `ExtensionsPanelDataSource`,
/// not to `ExtensionManager` directly: the host target is built in
/// parallel by Slice B, so the adapter behind
/// `#if canImport(YcodeExtensions)` is the only place that names the
/// spec §10 API, and the panel keeps working (honestly reporting the
/// host as unavailable) until that target is wired in.

/// One installed extension as the panel shows it.
public struct ExtensionPanelRow: Sendable, Equatable {
    public var id: String
    public var displayName: String
    public var version: String
    public var kind: String
    public var state: String
    public var isEnabled: Bool
    public var description: String
    public var commands: [String]
    public var grantedCapabilities: [String]
    public var lastError: String?

    public init(id: String, displayName: String, version: String, kind: String, state: String, isEnabled: Bool,
                description: String, commands: [String] = [], grantedCapabilities: [String] = [], lastError: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.version = version
        self.kind = kind
        self.state = state
        self.isEnabled = isEnabled
        self.description = description
        self.commands = commands
        self.grantedCapabilities = grantedCapabilities
        self.lastError = lastError
    }
}

/// The diagnostics view's data: host status, Node availability (a real
/// check — spec §4.2 discovery), and recent error lines.
public struct ExtensionsDiagnostics: Sendable, Equatable {
    public var hostAvailable: Bool
    public var hostStatus: String
    public var nodePath: String?
    public var nodeAvailable: Bool { nodePath != nil }
    public var recentErrors: [String]

    public init(hostAvailable: Bool, hostStatus: String, nodePath: String? = nil, recentErrors: [String] = []) {
        self.hostAvailable = hostAvailable
        self.hostStatus = hostStatus
        self.nodePath = nodePath
        self.recentErrors = recentErrors
    }
}

/// What the panel needs from the extensions host. One seam, so the
/// panel never invents host state: every row, grant, and diagnostic
/// line comes from here.
public protocol ExtensionsPanelDataSource: Sendable {
    func installedExtensions() async -> [ExtensionPanelRow]
    func setEnabled(_ id: String, enabled: Bool) async throws
    func diagnostics() async -> ExtensionsDiagnostics
}

/// Node.js discovery (spec §4.2), minus the settings path — the
/// configured path lives in the host's settings, which only the host
/// knows. Well-known paths first, then a `PATH` lookup. A real check:
/// the returned path is an executable file, or nil.
public enum ExtensionsNodeAvailability {
    public static func locate() -> String? {
        let fm = FileManager.default
        for path in ["/opt/homebrew/bin/node", "/usr/local/bin/node", "/usr/bin/node"] where fm.isExecutableFile(atPath: path) {
            return path
        }
        guard let pathEnv = ProcessInfo.processInfo.environment["PATH"] else { return nil }
        for dir in pathEnv.split(separator: ":") {
            let candidate = String(dir) + "/node"
            if fm.isExecutableFile(atPath: candidate) { return candidate }
        }
        return nil
    }
}

/// The data source while the `YcodeExtensions` host target is not wired
/// into the build: no rows, no enable/disable, and a diagnostics view
/// that says so — with a real Node check, since that needs no host.
@MainActor
public final class UnavailableExtensionsDataSource: ExtensionsPanelDataSource {
    public init() {}

    public func installedExtensions() async -> [ExtensionPanelRow] { [] }

    public func setEnabled(_ id: String, enabled: Bool) async throws {
        throw NSError(domain: "YcodeExtensionsPanel", code: 0,
                      userInfo: [NSLocalizedDescriptionKey:
                        "The Extensions v2 host (YcodeExtensions) is not wired into this build yet, so '\(id)' cannot be \(enabled ? "enabled" : "disabled")."])
    }

    public func diagnostics() async -> ExtensionsDiagnostics {
        ExtensionsDiagnostics(hostAvailable: false,
                              hostStatus: "The Extensions v2 host is not available in this build yet — extensions cannot be listed, activated, or executed.",
                              nodePath: ExtensionsNodeAvailability.locate())
    }
}

#if canImport(YcodeExtensions)
/// The data source against the real host (spec §10.6): the manager is
/// the single source of truth; the panel keeps no install-state copy.
@MainActor
public final class YcodeExtensionsDataSource: ExtensionsPanelDataSource {
    public init() {}

    public func installedExtensions() async -> [ExtensionPanelRow] {
        let manager = ExtensionManager.shared
        await manager.ensureReady()
        manager.refreshInstalled()
        return manager.installed.map { installed in
            var commands: [String] = []
            if let contribution = manager.contributions[installed.id] {
                commands = contribution.commands.map { "\($0.command) (\($0.title))" }
            } else if installed.metadata.kind == .native,
                      let manifest = NativePluginRegistry.shared.manifests.first(where: { $0.metadata.id == installed.id }) {
                commands = manifest.commands.map { "\($0.command) (\($0.title))" }
            } else if installed.metadata.kind == .vscode {
                let manifestURL = URL(fileURLWithPath: installed.installPath)
                    .appendingPathComponent("extension/package.json")
                if let manifest = try? VSCodeManifestParser.parseFile(at: manifestURL) {
                    commands = manifest.contributesCommands.map { "\($0.command) (\($0.title))" }
                }
            }
            return ExtensionPanelRow(id: installed.id, displayName: installed.metadata.displayName,
                                     version: installed.metadata.version, kind: installed.metadata.kind.displayName,
                                     state: installed.state.displayName, isEnabled: installed.isEnabled,
                                     description: installed.metadata.description, commands: commands,
                                     grantedCapabilities: manager.permissions.grantedCapabilities(for: installed.id).map(\.displayName),
                                     lastError: installed.lastError)
        }
    }

    public func setEnabled(_ id: String, enabled: Bool) async throws {
        let manager = ExtensionManager.shared
        await manager.ensureReady()
        guard manager.installed.contains(where: { $0.id == id }) else {
            throw YcodeExtensionError.notInstalled(id)
        }
        manager.setEnabled(extensionId: id, enabled: enabled)
        manager.refreshInstalled()
    }

    public func diagnostics() async -> ExtensionsDiagnostics {
        let manager = ExtensionManager.shared
        await manager.ensureReady()
        let running = manager.installed.filter { $0.state == .running }.count
        let node = manager.hostManager.nodeExecutable(settings: manager.settings)?.path
            ?? ExtensionsNodeAvailability.locate()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let recent = DiagnosticsService.shared.allEntries()
            .filter { $0.level == .error }.suffix(20)
            .map { "[\(formatter.string(from: $0.timestamp))] [\($0.level.rawValue)] \($0.extensionId.map { "\($0): " } ?? "")\($0.message)" }
        return ExtensionsDiagnostics(hostAvailable: true,
                                     hostStatus: "Extensions host available — \(manager.installed.count) installed, \(running) running.",
                                     nodePath: node, recentErrors: Array(recent))
    }
}
#endif

/// The panel's state: rows + selection + diagnostics from the data
/// source, nothing cached from anywhere else.
@MainActor
public final class ExtensionsPanelViewModel {
    public let dataSource: ExtensionsPanelDataSource
    public private(set) var rows: [ExtensionPanelRow] = []
    public private(set) var diagnostics: ExtensionsDiagnostics?
    public private(set) var selectedID: String?
    public private(set) var errorMessage: String?

    public init(dataSource: ExtensionsPanelDataSource) {
        self.dataSource = dataSource
    }

    public var selectedRow: ExtensionPanelRow? { rows.first { $0.id == selectedID } }

    public func load() async {
        errorMessage = nil
        rows = await dataSource.installedExtensions()
        diagnostics = await dataSource.diagnostics()
        if selectedID == nil || !rows.contains(where: { $0.id == selectedID }) {
            selectedID = rows.first?.id
        }
    }

    public func select(id: String?) { selectedID = id }

    /// Toggles the selected extension, then reloads so the row shows
    /// the host's state (never an optimistic local copy).
    public func setEnabledSelected(_ enabled: Bool) async {
        guard let row = selectedRow else { return }
        do {
            try await dataSource.setEnabled(row.id, enabled: enabled)
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The diagnostics view's text: host status, Node availability,
    /// then recent errors (or the honest empty line).
    public var diagnosticsText: String {
        guard let d = diagnostics else { return "" }
        var lines = [d.hostStatus,
                     d.nodeAvailable ? "Node.js found at \(d.nodePath!)." : "Node.js not found — VS Code extensions need Node.js 20 or later."]
        lines.append("")
        lines.append("Recent errors:")
        lines.append(contentsOf: d.recentErrors.isEmpty ? ["No diagnostics recorded."] : d.recentErrors)
        return lines.joined(separator: "\n")
    }
}

/// The Extensions popover's content: the installed list on the left,
/// the selected extension's detail (state, enable/disable, granted
/// capabilities, commands) and the diagnostics view on the right.
/// AppKit, in the style of `QuickActionsController` (programmatic
/// layout, anchor constraints, no redesign of the toolbar or settings).
@MainActor
public final class ExtensionsPanelViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    public static let size = NSSize(width: 620, height: 460)

    public let viewModel: ExtensionsPanelViewModel
    let table = NSTableView()
    let statusLabel = NSTextField(labelWithString: "")
    let nameLabel = NSTextField(labelWithString: "")
    let idLabel = NSTextField(labelWithString: "")
    let stateLabel = NSTextField(labelWithString: "")
    let enableCheckbox = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    let capabilitiesText = NSTextView()
    let commandsText = NSTextView()
    let diagnosticsText = NSTextView()
    let errorLabel = NSTextField(labelWithString: "")
    let refreshButton = NSButton(title: "Refresh", target: nil, action: nil)

    public static var defaultDataSource: ExtensionsPanelDataSource {
#if canImport(YcodeExtensions)
        YcodeExtensionsDataSource()
#else
        UnavailableExtensionsDataSource()
#endif
    }

    public init(dataSource: ExtensionsPanelDataSource = ExtensionsPanelViewController.defaultDataSource) {
        viewModel = ExtensionsPanelViewModel(dataSource: dataSource)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    public override func loadView() {
        let root = NSView(frame: NSRect(origin: .zero, size: Self.size))
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.maximumNumberOfLines = 2
        statusLabel.lineBreakMode = .byWordWrapping

        for (id, w) in [("name", 150.0), ("state", 80.0)] {
            let col = NSTableColumn(identifier: .init(id))
            col.width = w
            table.addTableColumn(col)
        }
        table.headerView = nil
        table.dataSource = self
        table.delegate = self
        table.style = .plain
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .boldSystemFont(ofSize: 13)
        idLabel.font = .systemFont(ofSize: 11)
        idLabel.textColor = .secondaryLabelColor
        stateLabel.font = .systemFont(ofSize: 11)
        enableCheckbox.target = self
        enableCheckbox.action = #selector(enableToggled(_:))
        // The detail column is laid out with explicit anchors (not a
        // stack view: a vertical stack would size the scroll views to
        // their fitting width, which collapses them).
        let capsLabel = Self.sectionLabel("Capabilities")
        let capsScroll = textScroll(capabilitiesText, height: 56)
        let cmdLabel = Self.sectionLabel("Commands")
        let cmdScroll = textScroll(commandsText, height: 56)
        let diagLabel = Self.sectionLabel("Diagnostics")
        let diagScroll = textScroll(diagnosticsText, height: nil)
        let detail = NSView()
        detail.translatesAutoresizingMaskIntoConstraints = false
        for v in [nameLabel, idLabel, stateLabel, enableCheckbox, capsLabel, capsScroll,
                  cmdLabel, cmdScroll, diagLabel, diagScroll] {
            v.translatesAutoresizingMaskIntoConstraints = false
            detail.addSubview(v)
        }

        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        errorLabel.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.target = self
        refreshButton.action = #selector(refreshClicked(_:))
        refreshButton.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(statusLabel)
        root.addSubview(scroll)
        root.addSubview(detail)
        root.addSubview(refreshButton)
        root.addSubview(errorLabel)
        NSLayoutConstraint.activate([
            statusLabel.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            scroll.widthAnchor.constraint(equalToConstant: 230),
            scroll.bottomAnchor.constraint(equalTo: refreshButton.topAnchor, constant: -8),
            detail.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            detail.leadingAnchor.constraint(equalTo: scroll.trailingAnchor, constant: 12),
            detail.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            detail.bottomAnchor.constraint(equalTo: refreshButton.topAnchor, constant: -8),
            refreshButton.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            refreshButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -12),
            errorLabel.leadingAnchor.constraint(equalTo: refreshButton.trailingAnchor, constant: 8),
            errorLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            errorLabel.centerYAnchor.constraint(equalTo: refreshButton.centerYAnchor),
        ])
        NSLayoutConstraint.activate([
            nameLabel.topAnchor.constraint(equalTo: detail.topAnchor),
            nameLabel.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
            idLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 2),
            idLabel.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            idLabel.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
            stateLabel.topAnchor.constraint(equalTo: idLabel.bottomAnchor, constant: 2),
            stateLabel.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            stateLabel.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
            enableCheckbox.topAnchor.constraint(equalTo: stateLabel.bottomAnchor, constant: 4),
            enableCheckbox.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            capsLabel.topAnchor.constraint(equalTo: enableCheckbox.bottomAnchor, constant: 8),
            capsLabel.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            capsLabel.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
            capsScroll.topAnchor.constraint(equalTo: capsLabel.bottomAnchor, constant: 2),
            capsScroll.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            capsScroll.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
            cmdLabel.topAnchor.constraint(equalTo: capsScroll.bottomAnchor, constant: 6),
            cmdLabel.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            cmdLabel.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
            cmdScroll.topAnchor.constraint(equalTo: cmdLabel.bottomAnchor, constant: 2),
            cmdScroll.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            cmdScroll.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
            diagLabel.topAnchor.constraint(equalTo: cmdScroll.bottomAnchor, constant: 6),
            diagLabel.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            diagLabel.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
            diagScroll.topAnchor.constraint(equalTo: diagLabel.bottomAnchor, constant: 2),
            diagScroll.leadingAnchor.constraint(equalTo: detail.leadingAnchor),
            diagScroll.trailingAnchor.constraint(equalTo: detail.trailingAnchor),
            diagScroll.bottomAnchor.constraint(equalTo: detail.bottomAnchor),
        ])
        view = root
        Task { await viewModel.load(); refreshAll() }
    }

    static func sectionLabel(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .boldSystemFont(ofSize: 11)
        l.textColor = .secondaryLabelColor
        return l
    }

    func textScroll(_ textView: NSTextView, height: CGFloat?) -> NSScrollView {
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .systemFont(ofSize: 11)
        textView.backgroundColor = .clear
        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.hasVerticalScroller = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        if let height { scroll.heightAnchor.constraint(equalToConstant: height).isActive = true }
        return scroll
    }

    /// Reloads the table and detail from the view model (tests drive it).
    public func refreshAll() {
        table.reloadData()
        let rows = viewModel.rows
        if let selected = viewModel.selectedID,
           let index = rows.firstIndex(where: { $0.id == selected }) {
            table.selectRowIndexes([index], byExtendingSelection: false)
        }
        if let d = viewModel.diagnostics {
            statusLabel.stringValue = rows.isEmpty
                ? d.hostStatus
                : "\(rows.count) extension\(rows.count == 1 ? "" : "s") installed."
        }
        errorLabel.stringValue = viewModel.errorMessage ?? ""
        showSelected()
    }

    func showSelected() {
        guard let row = viewModel.selectedRow else {
            nameLabel.stringValue = viewModel.rows.isEmpty ? "No extensions installed." : "No extension selected."
            idLabel.stringValue = ""
            stateLabel.stringValue = ""
            enableCheckbox.isEnabled = false
            capabilitiesText.string = ""
            commandsText.string = ""
            diagnosticsText.string = viewModel.diagnosticsText
            return
        }
        nameLabel.stringValue = row.displayName
        idLabel.stringValue = "\(row.id) · v\(row.version) · \(row.kind)"
        stateLabel.stringValue = "State: \(row.state)" + (row.lastError.map { " — \($0)" } ?? "")
        enableCheckbox.state = row.isEnabled ? .on : .off
        enableCheckbox.isEnabled = viewModel.diagnostics?.hostAvailable == true
        capabilitiesText.string = row.grantedCapabilities.isEmpty ? "none" : row.grantedCapabilities.joined(separator: "\n")
        commandsText.string = row.commands.isEmpty ? "No commands." : row.commands.joined(separator: "\n")
        diagnosticsText.string = viewModel.diagnosticsText
    }

    @objc func refreshClicked(_ sender: Any?) {
        Task { await viewModel.load(); refreshAll() }
    }

    @objc func enableToggled(_ sender: Any?) {
        Task { await viewModel.setEnabledSelected(enableCheckbox.state == .on); refreshAll() }
    }

    // MARK: NSTableView

    public func numberOfRows(in tableView: NSTableView) -> Int { viewModel.rows.count }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let r = viewModel.rows[row]
        let text: String
        switch tableColumn?.identifier.rawValue {
        case "state": text = r.state
        default: text = r.displayName
        }
        let l = NSTextField(labelWithString: text)
        l.lineBreakMode = .byTruncatingTail
        if tableColumn?.identifier.rawValue == "state" { l.textColor = .secondaryLabelColor }
        return l
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        let row = table.selectedRow
        viewModel.select(id: viewModel.rows.indices.contains(row) ? viewModel.rows[row].id : nil)
        showSelected()
    }
}
