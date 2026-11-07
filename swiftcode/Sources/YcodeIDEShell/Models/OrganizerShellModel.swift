import Foundation
import Observation
import YcodeIDECore

@MainActor
@Observable
public final class OrganizerShellModel {
    public var archivesDirectory: URL
    public private(set) var state = OrganizerState()
    @ObservationIgnored public var revealInFiles: (URL) -> Void = { _ in }
    public private(set) var lastRevealed: URL?

    public init(archivesDirectory: URL = Organizer.defaultArchivesDirectory) {
        self.archivesDirectory = archivesDirectory
    }

    public func reload() {
        state.load(Organizer.archives(in: archivesDirectory))
    }

    public func select(archiveAt url: URL) {
        reload()
        state.select(archiveAt: url)
    }

    public func selectRow(_ row: Int?) { state.selectRow(row) }

    public func chooseApp(_ app: String) { state.chooseApp(app) }

    public func showPage(_ page: String, section: String) {
        state.notificationsShown = false
        state.showPage(page, section: section)
    }

    public func goBack() { state.moveInHistory(-1) }
    public func goForward() { state.moveInHistory(1) }

    public func toggleNotifications() { state.notificationsShown.toggle() }
    public func hideNotifications() { state.notificationsShown = false }

    public var canDistribute: Bool { false }

    @discardableResult
    public func showInFiles(row: Int? = nil) -> URL? {
        let r = row ?? state.selectedRow
        guard let r, state.rows.indices.contains(r), let a = state.rows[r].archive else { return nil }
        lastRevealed = a.url
        revealInFiles(a.url)
        return a.url
    }
}
