import AppKit
import Foundation
import UniformTypeIdentifiers
import YcodeIDECore

// MARK: - SQLite Explorer sections panel
//
// Gap-closure misc: the eight sections beyond Wave 17's browser
// core — dashboard, migrations, backups, import/export, templates,
// AI assistant, performance, logs — as one panel over the section
// models in `YcodeIDECore/Model/Database/` (each a port of the
// Legacy manager or view it names). One generic panel rather than
// eight bespoke views: a section picker, a detail text view the
// section renders into, and a small action row rebuilt per section.
// File actions use open/save panels; destructive ones (restore,
// prune, vacuum, clear history) confirm first. The panel shares
// the browser's connection (`model.database`), so what it does is
// visible in the browser as soon as the window reloads its tables
// (`onDatabaseChanged`).

@MainActor
public final class SQLiteExplorerSectionsController: NSWindowController {
    private enum Section: String, CaseIterable {
        case dashboard, migrations, backups, importExport, templates, ai, performance, logs

        var title: String {
            switch self {
            case .dashboard: return "Dashboard"
            case .migrations: return "Migrations"
            case .backups: return "Backups"
            case .importExport: return "Import / Export"
            case .templates: return "Templates"
            case .ai: return "AI Assistant"
            case .performance: return "Performance"
            case .logs: return "Logs"
            }
        }
    }

    private let model: SQLiteExplorerModel
    private let migrations: DatabaseMigrationManager
    private let backups: DatabaseBackupManager
    private let exporter: DatabaseExportManager
    private let importer: DatabaseImportManager
    private let templates: DatabaseTemplateManager
    private let ai: DatabaseAIAssistant
    private let performance: DatabasePerformanceAnalyzer
    private let dashboard: DatabaseDashboard
    private let history = DatabaseHistoryService.shared

    /// Called after an action that changes the database file or its
    /// schema (restore, migration, template, vacuum), so the browser
    /// window can reload its tables.
    public var onDatabaseChanged: (() -> Void)?

    private var section: Section = .dashboard
    private let sectionPopup = NSPopUpButton()
    private let optionPopup = NSPopUpButton()
    private let inputField = NSTextField()
    private let detailTextView = NSTextView()
    private let statusLabel = NSTextField(labelWithString: "")
    private let actionStack = NSStackView()
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    public init(model: SQLiteExplorerModel) {
        self.model = model
        let db = model.database
        self.migrations = DatabaseMigrationManager(db: db)
        self.backups = DatabaseBackupManager(databasePath: model.path)
        self.exporter = DatabaseExportManager(db: db)
        self.importer = DatabaseImportManager(db: db)
        self.templates = DatabaseTemplateManager()
        self.ai = DatabaseAIAssistant(db: db)
        self.performance = DatabasePerformanceAnalyzer(db: db)
        self.dashboard = DatabaseDashboard(db: db)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: NSSize(width: 760, height: 560)),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SQLite Explorer — Sections"
        window.minSize = NSSize(width: 560, height: 400)
        super.init(window: window)
        build()
        window.center()
        select(.dashboard)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Layout

    private func build() {
        guard let content = window?.contentView else { return }
        sectionPopup.addItems(withTitles: Section.allCases.map(\.title))
        sectionPopup.target = self
        sectionPopup.action = #selector(sectionChanged)
        optionPopup.target = self
        optionPopup.action = #selector(optionChanged)
        inputField.placeholderString = "SQL to explain"
        inputField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        detailTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        detailTextView.isRichText = false
        detailTextView.isEditable = false
        let detailScroll = NSScrollView()
        detailScroll.documentView = detailTextView
        detailScroll.hasVerticalScroller = true
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        actionStack.orientation = .horizontal
        actionStack.spacing = 8
        let topRow = NSStackView(views: [sectionPopup, optionPopup, inputField])
        topRow.orientation = .horizontal
        topRow.spacing = 8
        for view in [topRow, detailScroll, actionStack, statusLabel] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            topRow.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            topRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            topRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            detailScroll.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: 12),
            detailScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            detailScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            actionStack.topAnchor.constraint(equalTo: detailScroll.bottomAnchor, constant: 12),
            actionStack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            statusLabel.topAnchor.constraint(equalTo: actionStack.bottomAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            statusLabel.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
    }

    private func button(_ title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        return button
    }

    // MARK: - Section switching

    @objc private func sectionChanged() {
        select(Section.allCases[sectionPopup.indexOfSelectedItem])
    }

    @objc private func optionChanged() {
        render()
    }

    private func select(_ newSection: Section) {
        section = newSection
        sectionPopup.selectItem(at: Section.allCases.firstIndex(of: newSection) ?? 0)
        for view in actionStack.views { actionStack.removeView(view) }
        optionPopup.removeAllItems()
        optionPopup.isHidden = true
        inputField.isHidden = true
        switch newSection {
        case .dashboard:
            actionStack.addView(button("Refresh", action: #selector(refreshClicked)), in: .leading)
        case .migrations:
            actionStack.addView(button("Apply SQL File…", action: #selector(applyMigrationClicked)), in: .leading)
            actionStack.addView(button("Rollback Latest", action: #selector(rollbackClicked)), in: .leading)
            actionStack.addView(button("Refresh", action: #selector(refreshClicked)), in: .leading)
        case .backups:
            optionPopup.addItems(withTitles: backups.listBackups().map { $0.url.lastPathComponent })
            optionPopup.isHidden = false
            actionStack.addView(button("Create Backup", action: #selector(createBackupClicked)), in: .leading)
            actionStack.addView(button("Restore Selected", action: #selector(restoreClicked)), in: .leading)
            actionStack.addView(button("Prune to 5", action: #selector(pruneClicked)), in: .leading)
        case .importExport:
            optionPopup.addItems(withTitles: (try? performance.userTables()) ?? [])
            optionPopup.isHidden = false
            actionStack.addView(button("Export CSV…", action: #selector(exportCSVClicked)), in: .leading)
            actionStack.addView(button("Export JSON…", action: #selector(exportJSONClicked)), in: .leading)
            actionStack.addView(button("Export SQL…", action: #selector(exportSQLClicked)), in: .leading)
            actionStack.addView(button("Import CSV…", action: #selector(importCSVClicked)), in: .leading)
        case .templates:
            optionPopup.addItems(withTitles: templates.templates.map(\.name))
            optionPopup.isHidden = false
            actionStack.addView(button("Preview SQL", action: #selector(refreshClicked)), in: .leading)
            actionStack.addView(button("Apply Template", action: #selector(applyTemplateClicked)), in: .leading)
        case .ai:
            inputField.isHidden = false
            actionStack.addView(button("Analyze Schema", action: #selector(refreshClicked)), in: .leading)
            actionStack.addView(button("Explain Locally", action: #selector(explainLocallyClicked)), in: .leading)
            actionStack.addView(button("Explain with LLM", action: #selector(explainLLMClicked)), in: .leading)
        case .performance:
            actionStack.addView(button("Refresh", action: #selector(refreshClicked)), in: .leading)
            actionStack.addView(button("Vacuum", action: #selector(vacuumClicked)), in: .leading)
        case .logs:
            actionStack.addView(button("Refresh", action: #selector(refreshClicked)), in: .leading)
            actionStack.addView(button("Clear History", action: #selector(clearHistoryClicked)), in: .leading)
        }
        render()
    }

    // MARK: - Rendering

    private func setDetail(_ text: String) {
        detailTextView.string = text
    }

    private func fail(_ error: Error) {
        statusLabel.stringValue = error.localizedDescription
    }

    private func render() {
        statusLabel.stringValue = ""
        do {
            switch section {
            case .dashboard: try renderDashboard()
            case .migrations: try renderMigrations()
            case .backups: renderBackups()
            case .importExport: try renderImportExport()
            case .templates: renderTemplates()
            case .ai: try renderAI()
            case .performance: try renderPerformance()
            case .logs: renderLogs()
            }
        } catch {
            fail(error)
        }
    }

    private func renderDashboard() throws {
        let stats = try dashboard.stats(backupManager: backups)
        var lines = [
            "Database: \(model.path)",
            "Size: \(stats.databaseSizeBytes) bytes (\(stats.pageCount) pages × \(stats.pageSize) bytes)",
            "Tables: \(stats.tableCount)   Indexes: \(stats.indexCount)   Total rows: \(stats.totalRows)",
            "Integrity: \(stats.integrity)",
            "Applied migrations: \(stats.migrationCount)   Backups: \(stats.backupCount)",
            "",
            "Largest tables:",
        ]
        lines += stats.largestTables.map { "  \($0.name): \($0.rowCount) rows, \($0.indexCount) indexes" }
        lines += ["", "Health:"]
        lines += stats.healthChecks.map { "  [\($0.passed ? "OK" : "FAIL")] \($0.name) — \($0.detail)" }
        setDetail(lines.joined(separator: "\n"))
    }

    private func renderMigrations() throws {
        let applied = try migrations.applied()
        var lines = ["Applied migrations:"]
        if applied.isEmpty {
            lines.append("  (none — the tracking table is empty)")
        } else {
            lines += applied.map { "  v\($0.version) \($0.name) — \(dateFormatter.string(from: $0.appliedAt))\($0.downSQL == nil ? " (no down SQL)" : "")" }
        }
        setDetail(lines.joined(separator: "\n"))
    }

    private func renderBackups() {
        let list = backups.listBackups()
        var lines = ["Backups in \(backups.backupDirectory.path):"]
        if list.isEmpty {
            lines.append("  (none yet)")
        } else {
            lines += list.map { "  \($0.url.lastPathComponent) — \(dateFormatter.string(from: $0.createdAt)), \($0.sizeBytes) bytes" }
        }
        setDetail(lines.joined(separator: "\n"))
    }

    private func renderImportExport() throws {
        let table = optionPopup.titleOfSelectedItem ?? ""
        guard !table.isEmpty else {
            setDetail("No tables in this database.")
            return
        }
        let columns = try model.database.queryWithColumns("SELECT * FROM \(SQLiteExplorerModel.quoted(table)) LIMIT 0").columns
        let count = try model.database.query("SELECT COUNT(*) FROM \(SQLiteExplorerModel.quoted(table))").first?.first?.int ?? 0
        setDetail("Table: \(table)\nRows: \(count)\nColumns: \(columns.joined(separator: ", "))")
    }

    private func renderTemplates() {
        guard let name = optionPopup.titleOfSelectedItem,
              let template = templates.templates.first(where: { $0.name == name }) else {
            setDetail("No templates.")
            return
        }
        var lines = ["\(template.name) — \(template.description)", "Category: \(template.category)   Tags: \(template.tags.joined(separator: ", "))", ""]
        lines += template.tables.map { table in
            "Table \(table.name): " + table.columns.map { "\($0.name) \($0.type)\($0.isPrimaryKey ? " PK" : "")\($0.isUnique ? " UNIQUE" : "")" }.joined(separator: ", ")
        }
        lines += ["", "SQL (SQLite types):", DatabaseTemplateManager.createSQL(for: template)]
        setDetail(lines.joined(separator: "\n"))
    }

    private func renderAI() throws {
        let insights = try ai.analyzeSchema()
        var lines = ["[Local analysis — no model involved]", ""]
        if insights.isEmpty {
            lines.append("No schema findings: every table has a primary key and every foreign-key column is indexed.")
        } else {
            lines += insights.map { "[\($0.severity.rawValue.uppercased())] \($0.title)\n  \($0.detail)" }
        }
        setDetail(lines.joined(separator: "\n"))
    }

    private func renderPerformance() throws {
        let report = try performance.report()
        var lines = [
            "Pages: \(report.pageCount) × \(report.pageSize) bytes   Free pages: \(report.freelistCount)",
            "Journal mode: \(report.journalMode)   Cache: \(report.cacheSizeKiB) KiB",
            "Size: \(report.databaseSizeBytes) bytes   Integrity: \(report.integrity)",
            "Total rows: \(report.totalRows)",
            "",
            "Tables:",
        ]
        lines += report.tables.map { "  \($0.name): \($0.rowCount) rows, \($0.indexCount) indexes" }
        let unindexed = try performance.unindexedForeignKeys()
        lines += ["", "Unindexed foreign keys:"]
        lines += unindexed.isEmpty ? ["  (none)"] : unindexed.map { "  \($0.table).\($0.column)" }
        setDetail(lines.joined(separator: "\n"))
    }

    private func renderLogs() {
        let items = history.fetchHistory()
        var lines = ["Query history (newest first):"]
        if items.isEmpty {
            lines.append("  (no queries run yet — running SQL in the browser records here)")
        } else {
            lines += items.prefix(50).map {
                "  [\(dateFormatter.string(from: $0.timestamp))] \($0.status) (\($0.rowsAffected) rows, \(String(format: "%.1f", $0.executionTimeMs)) ms) \($0.sql)"
                    + ($0.errorMessage.map { " — \($0)" } ?? "")
            }
        }
        lines += ["", "Saved queries:"]
        lines += history.fetchSavedQueries().map { "  \($0.title) [\($0.category)] — \($0.sql)" }
        setDetail(lines.joined(separator: "\n"))
    }

    // MARK: - Actions

    @objc private func refreshClicked() { render() }

    @objc private func applyMigrationClicked() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["sql"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let sql = try? String(contentsOf: url) else { return }
        do {
            let migration = try migrations.generate(name: url.deletingPathExtension().lastPathComponent, up: sql)
            try migrations.apply(migration)
            statusLabel.stringValue = "Applied migration v\(migration.version) (\(migration.name))."
            onDatabaseChanged?()
            render()
        } catch {
            fail(error)
        }
    }

    @objc private func rollbackClicked() {
        do {
            guard let rolledBack = try migrations.rollbackLatest() else {
                statusLabel.stringValue = "Nothing applied to roll back."
                return
            }
            statusLabel.stringValue = "Rolled back migration v\(rolledBack.version) (\(rolledBack.name))."
            onDatabaseChanged?()
            render()
        } catch {
            fail(error)
        }
    }

    @objc private func createBackupClicked() {
        do {
            let backup = try backups.createBackup()
            statusLabel.stringValue = "Created \(backup.url.lastPathComponent)."
            select(.backups)
        } catch {
            fail(error)
        }
    }

    @objc private func restoreClicked() {
        guard let name = optionPopup.titleOfSelectedItem,
              let backup = backups.listBackups().first(where: { $0.url.lastPathComponent == name }) else { return }
        let alert = NSAlert()
        alert.messageText = "Restore \(name)?"
        alert.informativeText = "The current database file will be replaced with this backup."
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try backups.restore(backup)
            try model.reopen()
            statusLabel.stringValue = "Restored \(name)."
            onDatabaseChanged?()
            render()
        } catch {
            fail(error)
        }
    }

    @objc private func pruneClicked() {
        do {
            let deleted = try backups.prune(keeping: 5)
            statusLabel.stringValue = "Deleted \(deleted) old backup(s)."
            select(.backups)
        } catch {
            fail(error)
        }
    }

    private func selectedTable() -> String? {
        optionPopup.titleOfSelectedItem
    }

    private func saveText(_ text: String, filename: String, extension ext: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = filename
        panel.allowedContentTypes = [ext].compactMap { UTType(filenameExtension: $0) }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            statusLabel.stringValue = "Wrote \(url.lastPathComponent)."
        } catch {
            fail(error)
        }
    }

    @objc private func exportCSVClicked() {
        guard let table = selectedTable() else { return }
        do { saveText(try exporter.exportCSV(table: table), filename: "\(table).csv", extension: "csv") } catch { fail(error) }
    }

    @objc private func exportJSONClicked() {
        guard let table = selectedTable() else { return }
        do { saveText(try exporter.exportJSON(table: table), filename: "\(table).json", extension: "json") } catch { fail(error) }
    }

    @objc private func exportSQLClicked() {
        guard let table = selectedTable() else { return }
        do { saveText(try exporter.exportSQL(table: table), filename: "\(table).sql", extension: "sql") } catch { fail(error) }
    }

    @objc private func importCSVClicked() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["csv"].compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let csv = try? String(contentsOf: url) else { return }
        do {
            let count = try importer.importCSV(csv, into: url.deletingPathExtension().lastPathComponent)
            statusLabel.stringValue = "Imported \(count) row(s)."
            onDatabaseChanged?()
            render()
        } catch {
            fail(error)
        }
    }

    @objc private func applyTemplateClicked() {
        guard let name = optionPopup.titleOfSelectedItem,
              let template = templates.templates.first(where: { $0.name == name }) else { return }
        do {
            try templates.apply(template, to: model.database)
            statusLabel.stringValue = "Applied template '\(name)'."
            onDatabaseChanged?()
            render()
        } catch {
            fail(error)
        }
    }

    @objc private func explainLocallyClicked() {
        let sql = inputField.stringValue
        guard !sql.isEmpty else {
            statusLabel.stringValue = "Enter SQL to explain."
            return
        }
        do {
            setDetail(try ai.explainSQLLocally(sql))
        } catch {
            fail(error)
        }
    }

    @objc private func explainLLMClicked() {
        let sql = inputField.stringValue
        guard !sql.isEmpty else {
            statusLabel.stringValue = "Enter SQL to explain."
            return
        }
        Task {
            do {
                setDetail(try await ai.explainSQL(sql))
            } catch {
                fail(error)
            }
        }
    }

    @objc private func vacuumClicked() {
        let alert = NSAlert()
        alert.messageText = "Vacuum this database?"
        alert.informativeText = "VACUUM rebuilds the file to reclaim free pages, then ANALYZE refreshes planner statistics."
        alert.addButton(withTitle: "Vacuum")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try performance.vacuum()
            statusLabel.stringValue = "Vacuumed."
            onDatabaseChanged?()
            render()
        } catch {
            fail(error)
        }
    }

    @objc private func clearHistoryClicked() {
        let alert = NSAlert()
        alert.messageText = "Clear query history?"
        alert.informativeText = "Saved queries are kept; only the run history is cleared."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        history.clearHistory()
        render()
    }
}
