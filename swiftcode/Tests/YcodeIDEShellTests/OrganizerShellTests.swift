import Foundation
import Testing
@testable import YcodeIDECore
@testable import YcodeIDEShell

@MainActor
struct OrganizerShellTests {
    let t0 = Date(timeIntervalSince1970: 1_793_000_000)

    @Test func windowMenuOpensTheOrganizer() throws {
        #expect(ShellCommand.organizer.menu == "Window")
        #expect(ShellCommand.organizer.title(in: nil) == "Organizer")
        #expect(ShellCommand.organizer.shortcut?.text == "⌥⇧⌘O")

        let suite = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-shell-organizer-\(UUID().uuidString)").path
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let app = ShellAppModel(recentProjects: RecentProjects(defaults: defaults), engine: { ScriptedEngine(lines: [], issues: []) })
        let f = try ArchiveFixtures()
        defer { f.remove() }
        try f.make("Greeter 1", app: "Greeter", created: t0)
        app.organizer.archivesDirectory = f.root
        var opened: [String] = []
        app.openWindow = { opened.append($0) }
        #expect(app.workspace == nil && app.isEnabled(.organizer))
        app.perform(.organizer)
        #expect(opened == [ShellAppModel.organizerWindowID])
        #expect(app.organizer.state.rows.map(\.title) == ["Greeter", "Greeter 1"])
    }

    @Test func modelListsSelectsAndShowsInFiles() throws {
        let f = try ArchiveFixtures()
        defer { f.remove() }
        let a = try f.make("Greeter 1", app: "Greeter", created: t0)
        let m = OrganizerShellModel(archivesDirectory: f.root)
        var revealed: [URL] = []
        m.revealInFiles = { revealed.append($0) }
        m.reload()
        #expect(m.showInFiles() == nil && revealed.isEmpty)
        m.selectRow(1)
        let path = a.standardizedFileURL.path
        #expect(m.state.selected?.url.standardizedFileURL.path == path)
        let shown = m.showInFiles()
        #expect(shown?.standardizedFileURL.path == path && revealed.map(\.standardizedFileURL.path) == [path] && m.lastRevealed == shown)
        #expect(m.showInFiles(row: 0) == nil)
        #expect(m.state.canDistribute && !m.canDistribute)

        let b = try f.make("Greeter 2", app: "Greeter", created: t0 + 60)
        m.select(archiveAt: b)
        #expect(m.state.rows.map(\.title) == ["Greeter", "Greeter 2", "Greeter 1"] && m.state.selectedRow == 1)

        m.toggleNotifications()
        #expect(m.state.notificationsShown)
        m.showPage("Overview", section: "Insights")
        #expect(!m.state.notificationsShown && m.state.page == "Overview")
        m.goBack()
        #expect(m.state.page == "Archives")
        m.goForward()
        #expect(m.state.page == "Overview")
    }
}
