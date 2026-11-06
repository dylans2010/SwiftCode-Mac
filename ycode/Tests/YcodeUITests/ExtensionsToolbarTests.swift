import AppKit
import Foundation
import Testing
@testable import YcodeIDECore
import YcodeProject
@testable import YcodeUI

/// The Extensions toolbar entry point + panel (Wave 11 Slice C).
///
/// Spec: `extensions-platform.md` §1.2 (Extensions on the editor
/// toolbar beside Assist, not in the workspace sidebar), §3–§8 (what
/// the panel shows). The toolbar tests pin the entry point's place in
/// the default set; the panel tests drive
/// `ExtensionsPanelViewController` against a stub data source (the
/// real host target is Slice B's — see the `#if canImport` split in
/// the panel file).
@MainActor
@Suite(.serialized) struct ExtensionsToolbarTests {
    func window() throws -> WorkspaceWindowController {
        _ = NSApplication.shared
        let model = try WorkspaceModel(url: try WindowSnapshotTests().samplePackage())
        return WorkspaceWindowController(session: WorkspaceSession(model: model), loadDestinations: false,
                                         startLanguageService: false, openFirstFile: false)
    }

    @Test func extensionsButtonSitsBesideEditorModes() throws {
        let wc = try window()
        defer { wc.window?.close() }
        let ids = wc.toolbarDefaultItemIdentifiers(NSToolbar()).map(\.rawValue)
        let modes = try #require(ids.firstIndex(of: "editorModes"))
        #expect(ids[modes + 1] == "extensions", "\(ids)")
        let item = try #require(wc.toolbar(NSToolbar(), itemForItemIdentifier: .init("extensions"),
                                           willBeInsertedIntoToolbar: false))
        #expect(item.label == "Extensions" && item.toolTip == "Extensions")
        #expect(item.action == NSSelectorFromString("toggleExtensionsPanel:"))
        #expect(item.isBordered)
        // The toolbar-fit steps only allow the editor-mode group in the
        // overflow, so this button stays visible while the modes group
        // goes into the "»" menu.
        #expect(item.visibilityPriority == .high)
    }

    @Test func toggleExtensionsPanelCreatesThePanel() throws {
        let wc = try window()
        defer { wc.window?.close() }
        #expect(wc.extensionsPanel == nil)
        wc.toggleExtensionsPanel(nil)
        // The panel controller is created on toggle (the popover itself
        // needs a visible window, so it is not shown in tests).
        _ = try #require(wc.extensionsPanel)
    }

    // MARK: - Panel against a stub data source

    @MainActor
    final class StubExtensionsDataSource: ExtensionsPanelDataSource {
        var rows: [ExtensionPanelRow]
        var diagnosticsValue: ExtensionsDiagnostics
        var setEnabledCalls: [(String, Bool)] = []

        init(rows: [ExtensionPanelRow], diagnostics: ExtensionsDiagnostics) {
            self.rows = rows
            self.diagnosticsValue = diagnostics
        }

        func installedExtensions() async -> [ExtensionPanelRow] { rows }
        func setEnabled(_ id: String, enabled: Bool) async throws {
            setEnabledCalls.append((id, enabled))
            if let i = rows.firstIndex(where: { $0.id == id }) { rows[i].isEnabled = enabled }
        }
        func diagnostics() async -> ExtensionsDiagnostics { diagnosticsValue }
    }

    static func stubRows() -> [ExtensionPanelRow] {
        [ExtensionPanelRow(id: "pub.first", displayName: "First", version: "1.2.0", kind: "VS Code",
                           state: "Enabled", isEnabled: true, description: "The first.",
                           commands: ["first.run (Run First)"], grantedCapabilities: ["Read workspace files"]),
         ExtensionPanelRow(id: "pub.second", displayName: "Second", version: "0.1.0", kind: "SwiftCode Native",
                           state: "Disabled", isEnabled: false, description: "The second.",
                           commands: [], grantedCapabilities: [], lastError: "Crashed once.")
        ]
    }

    @Test func panelListsRowsAndShowsSelectedDetail() async {
        let stub = StubExtensionsDataSource(rows: Self.stubRows(),
                                            diagnostics: ExtensionsDiagnostics(hostAvailable: true, hostStatus: "Extensions host available.",
                                                                             nodePath: "/usr/local/bin/node",
                                                                             recentErrors: ["[2026-11-06T00:00:00Z] [error] pub.first: boom"]))
        let c = ExtensionsPanelViewController(dataSource: stub)
        _ = c.view
        await c.viewModel.load()
        c.refreshAll()
        #expect(c.numberOfRows(in: c.table) == 2)
        #expect(c.nameLabel.stringValue == "First")
        #expect(c.idLabel.stringValue.contains("pub.first") && c.idLabel.stringValue.contains("v1.2.0"))
        #expect(c.stateLabel.stringValue.contains("Enabled"))
        #expect(c.enableCheckbox.state == .on && c.enableCheckbox.isEnabled)
        #expect(c.capabilitiesText.string.contains("Read workspace files"))
        #expect(c.commandsText.string.contains("first.run"))
        #expect(c.diagnosticsText.string.contains("Node.js found at /usr/local/bin/node"))
        #expect(c.diagnosticsText.string.contains("boom"))
        // Selecting the second row swaps the detail (and shows its error).
        c.table.selectRowIndexes([1], byExtendingSelection: false)
        c.tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification))
        #expect(c.nameLabel.stringValue == "Second")
        #expect(c.stateLabel.stringValue.contains("Crashed once."))
        #expect(c.enableCheckbox.state == .off)
        #expect(c.capabilitiesText.string == "none")
        #expect(c.commandsText.string == "No commands.")
        // Toggling goes through the data source and reloads from it.
        await c.viewModel.setEnabledSelected(true)
        #expect(stub.setEnabledCalls.contains { $0 == ("pub.second", true) })
        #expect(c.viewModel.selectedRow?.isEnabled == true)
    }

    @Test func nodeAvailabilityIsCoherent() {
        // A real check (spec §4.2): the reported path is an executable
        // file when one is reported at all.
        let found = ExtensionsNodeAvailability.locate()
        if let path = found {
            #expect(FileManager.default.isExecutableFile(atPath: path))
        }
        let d = UnavailableExtensionsDataSource()
        _ = d
    }

    @Test func panelWithoutHostReportsItHonestly() async {
        let c = ExtensionsPanelViewController()
        _ = c.view
        await c.viewModel.load()
        c.refreshAll()
#if canImport(YcodeExtensions)
        // The host is wired in: the panel loads from the real manager.
        #expect(c.viewModel.diagnostics?.hostAvailable == true)
#else
        #expect(c.viewModel.rows.isEmpty)
        #expect(c.viewModel.diagnostics?.hostAvailable == false)
        #expect(c.statusLabel.stringValue.contains("not available"))
        #expect(c.nameLabel.stringValue == "No extensions installed.")
        #expect(!c.enableCheckbox.isEnabled)
        #expect(c.diagnosticsText.string.contains("Node.js"))
#endif
    }
}
