import AppKit
import Foundation
import Testing
@testable import SwiftCodeIDECore
import SwiftCodeProject
@testable import SwiftCodeUI

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
        #expect(item.visibilityPriority == .high)
    }

    @Test func toggleExtensionsPanelCreatesThePanel() throws {
        let wc = try window()
        defer { wc.window?.close() }
        #expect(wc.extensionsPanel == nil)
        wc.toggleExtensionsPanel(nil)
        _ = try #require(wc.extensionsPanel)
    }

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
        c.table.selectRowIndexes([1], byExtendingSelection: false)
        c.tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification))
        #expect(c.nameLabel.stringValue == "Second")
        #expect(c.stateLabel.stringValue.contains("Crashed once."))
        #expect(c.enableCheckbox.state == .off)
        #expect(c.capabilitiesText.string == "none")
        #expect(c.commandsText.string == "No commands.")
        await c.viewModel.setEnabledSelected(true)
        #expect(stub.setEnabledCalls.contains { $0 == ("pub.second", true) })
        #expect(c.viewModel.selectedRow?.isEnabled == true)
    }

    @Test func nodeAvailabilityIsCoherent() {
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
#if canImport(SwiftCodeExtensions)
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
