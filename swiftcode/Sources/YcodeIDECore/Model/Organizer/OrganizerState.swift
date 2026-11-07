import Foundation

public struct OrganizerState: Sendable {
    public struct Row: Equatable, Sendable {
        public var title: String
        public var archive: ArchiveEntry?
    }

    public struct Column: Equatable, Sendable {
        public var id: String
        public var title: String
        public var width: Double
    }

    public static let columns: [Column] = [
        Column(id: "name", title: "Name", width: 118), Column(id: "created", title: "Creation Date", width: 170),
        Column(id: "version", title: "Version", width: 70), Column(id: "status", title: "Status", width: 74),
    ]

    public private(set) var groups: [(app: String, archives: [ArchiveEntry])] = []
    public private(set) var rows: [Row] = []
    public private(set) var selectedApp: String?
    public private(set) var selected: ArchiveEntry?
    public private(set) var page = "Archives"
    public private(set) var section = "Products"
    public private(set) var history: [(section: String, page: String)] = []
    public private(set) var historyIndex = -1
    public var notificationsShown = false
    public static let noNotificationsText = "No Notifications"
    public static let distributeTitle = "Distribute App…"
    #if os(macOS)
    public static let showInFilesTitle = "Show in Finder"
    #else
    public static let showInFilesTitle = "Show in Files"
    #endif

    public init() { showPage(page, section: section) }

    public mutating func load(_ archives: [ArchiveEntry], exported: Set<String> = []) {
        groups = Organizer.grouped(archives).map { g in
            var g = g
            for i in g.archives.indices where exported.contains(g.archives[i].url.standardizedFileURL.path) { g.archives[i].status = "Exported" }
            return g
        }
        if let a = selectedApp, !groups.contains(where: { $0.app == a }) { selectedApp = nil }
        if selectedApp == nil { selectedApp = groups.first?.app }
        rebuildRows()
        if let s = selected { selected = rows.first { $0.archive?.url == s.url }?.archive }
    }

    private mutating func rebuildRows() {
        rows = groups.filter { $0.app == selectedApp }.flatMap { g in [Row(title: g.app)] + g.archives.map { Row(title: $0.name, archive: $0) } }
    }

    public var appPickerTitles: [String] { groups.isEmpty ? ["No App"] : groups.map(\.app) }

    public mutating func chooseApp(_ app: String) {
        guard groups.contains(where: { $0.app == app }) else { return }
        selectedApp = app
        if selected.map({ $0.appName != app }) ?? false { selected = nil }
        rebuildRows()
    }

    public var selectedRow: Int? {
        guard let s = selected else { return nil }
        return rows.firstIndex { $0.archive?.url == s.url }
    }

    public mutating func selectRow(_ row: Int?) {
        selected = row.flatMap { rows.indices.contains($0) ? rows[$0].archive : nil }
    }

    @discardableResult
    public mutating func select(archiveAt url: URL) -> Int? {
        let path = url.standardizedFileURL.path
        if let app = groups.first(where: { $0.archives.contains { $0.url.standardizedFileURL.path == path } })?.app, app != selectedApp {
            selectedApp = app
            rebuildRows()
        }
        guard let i = rows.firstIndex(where: { $0.archive?.url.standardizedFileURL.path == path }) else { return nil }
        selected = rows[i].archive
        return i
    }

    public mutating func markExported(_ url: URL) {
        let path = url.standardizedFileURL.path
        func same(_ a: ArchiveEntry?) -> Bool { a?.url.standardizedFileURL.path == path }
        for g in groups.indices {
            for i in groups[g].archives.indices where same(groups[g].archives[i]) { groups[g].archives[i].status = "Exported" }
        }
        for i in rows.indices where same(rows[i].archive) { rows[i].archive?.status = "Exported" }
        if same(selected) { selected?.status = "Exported" }
    }

    nonisolated(unsafe) public static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    public static func dateText(_ date: Date?) -> String { date.map(dateFormatter.string(from:)) ?? "" }

    public static func cellText(_ a: ArchiveEntry, column: String) -> String {
        switch column {
        case "name": a.name
        case "created": dateText(a.created)
        case "version": a.versionText
        default: a.status
        }
    }

    public var detailRows: [(String, String)] {
        guard let a = selected else { return [("No Selection", "")] }
        return [("Name", a.name), ("Creation Date", Self.dateText(a.created)),
                ("Version", a.versionText), ("Identifier", a.bundleIdentifier ?? ""), ("Type", a.hasApplication ? "macOS App Archive" : "Generic Archive"),
                ("Architectures", a.architectures.joined(separator: ", ")), ("Status", a.status), ("Comment", a.comment.isEmpty ? "No Description" : a.comment)]
    }

    public var canDistribute: Bool { selected?.hasApplication == true }

    public var showsArchives: Bool { OrganizerSidebar.hasData(section: section) }

    public var emptyState: (title: String, message: String) {
        let version = selected?.versionText ?? groups.first(where: { $0.app == selectedApp })?.archives.first?.versionText ?? "1.0"
        return OrganizerSidebar.emptyState(page: page, version: version.isEmpty ? "1.0" : version)
    }

    public mutating func showPage(_ page: String, section: String) {
        if !(history.indices.contains(historyIndex) && history[historyIndex] == (section, page)) {
            if historyIndex + 1 < history.count { history.removeSubrange((historyIndex + 1)...) }
            history.append((section, page))
            historyIndex = history.count - 1
        }
        self.page = page
        self.section = section
    }

    public var canGoBack: Bool { historyIndex > 0 }
    public var canGoForward: Bool { historyIndex < history.count - 1 }

    @discardableResult
    public mutating func moveInHistory(_ step: Int) -> Bool {
        let i = historyIndex + step
        guard history.indices.contains(i) else { return false }
        historyIndex = i
        page = history[i].page
        section = history[i].section
        return true
    }

    public var sidebarRow: Int? { OrganizerSidebar.rows.firstIndex { $0.section == section && $0.page == page } }
}
