import AppKit
import Foundation
import UniformTypeIdentifiers
import SwiftCodeIDECore

@MainActor
public final class SQLiteExplorerWindowManager: NSObject {
    public static let shared = SQLiteExplorerWindowManager()
    private var windowController: SQLiteExplorerWindowController?

    private override init() {}

    public func showWindow() {
        if let existing = windowController {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }
        Self.runOpenPanel(from: NSApp.keyWindow ?? NSApp.mainWindow) { [weak self] url in
            guard let self, let url else { return }
            do {
                let model = try SQLiteExplorerModel(path: url.path)
                let controller = SQLiteExplorerWindowController(model: model)
                self.windowController = controller
                controller.window?.delegate = self
                controller.window?.makeKeyAndOrderFront(nil)
            } catch {
                NSApp.presentError(error)
            }
        }
    }

    public func closeWindow() {
        windowController?.close()
        windowController = nil
    }

    static func runOpenPanel(from window: NSWindow?, completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Open SQLite Database"
        panel.allowedContentTypes = ["sqlite", "sqlite3", "db", "db3"].compactMap { UTType(filenameExtension: $0) }
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let window {
            panel.beginSheetModal(for: window) { response in
                completion(response == .OK ? panel.url : nil)
            }
        } else {
            completion(panel.runModal() == .OK ? panel.url : nil)
        }
    }
}

extension SQLiteExplorerWindowManager: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        windowController = nil
    }
}

@MainActor
public final class SQLiteExplorerWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    public static let size = NSSize(width: 1100, height: 700)
    public static let pageSize = 100

    private var model: SQLiteExplorerModel

    private let openButton = NSButton(title: "Open…", target: nil, action: nil)
    private let sectionsButton = NSButton(title: "Sections…", target: nil, action: nil)
    private let pathLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let schemaLabel = NSTextField(labelWithString: "")
    private let tablesTable = NSTableView()
    private let gridTable = NSTableView()
    private let prevButton = NSButton(title: "‹ Previous", target: nil, action: nil)
    private let nextButton = NSButton(title: "Next ›", target: nil, action: nil)
    private let pageLabel = NSTextField(labelWithString: "")
    private let sqlTextView = NSTextView()
    private let runButton = NSButton(title: "Run", target: nil, action: nil)
    private let resultLabel = NSTextField(labelWithString: "")

    private var tables: [SQLiteExplorerTable] = []
    private var currentTable: String?
    private var currentResult = SQLiteExplorerResult(columns: [], rows: [])
    private var currentPage = 0
    private var totalRows = 0
    private var showingSQLResult = false
    private var sectionsController: SQLiteExplorerSectionsController?

    public init(model: SQLiteExplorerModel) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "SQLite Explorer — \(URL(fileURLWithPath: model.path).lastPathComponent)"
        window.minSize = NSSize(width: 800, height: 500)
        window.setFrameAutosaveName("SwiftCodeSQLiteExplorerWindow")
        window.isReleasedWhenClosed = false
        super.init(window: window)
        build()
        window.center()
        reloadTables()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func build() {
        guard let content = window?.contentView else { return }
        openButton.target = self
        openButton.action = #selector(openClicked)
        sectionsButton.target = self
        sectionsButton.action = #selector(sectionsClicked)
        pathLabel.stringValue = model.path
        pathLabel.font = .systemFont(ofSize: 12)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        schemaLabel.font = .systemFont(ofSize: 12)
        schemaLabel.textColor = .secondaryLabelColor

        let topRow = NSStackView(views: [openButton, sectionsButton, pathLabel])
        topRow.orientation = .horizontal
        topRow.spacing = 8

        let tablesColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
        tablesTable.addTableColumn(tablesColumn)
        tablesTable.headerView = nil
        tablesTable.rowHeight = 22
        tablesTable.dataSource = self
        tablesTable.delegate = self
        let tablesScroll = NSScrollView()
        tablesScroll.documentView = tablesTable
        tablesScroll.hasVerticalScroller = true

        gridTable.rowHeight = 20
        gridTable.dataSource = self
        gridTable.delegate = self
        gridTable.usesAlternatingRowBackgroundColors = true
        let gridScroll = NSScrollView()
        gridScroll.documentView = gridTable
        gridScroll.hasVerticalScroller = true
        gridScroll.hasHorizontalScroller = true

        prevButton.target = self
        prevButton.action = #selector(prevClicked)
        nextButton.target = self
        nextButton.action = #selector(nextClicked)
        let pagerRow = NSStackView(views: [prevButton, nextButton, pageLabel])
        pagerRow.orientation = .horizontal
        pagerRow.spacing = 8

        sqlTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        sqlTextView.isRichText = false
        let sqlScroll = NSScrollView()
        sqlScroll.documentView = sqlTextView
        sqlScroll.hasVerticalScroller = true

        runButton.target = self
        runButton.action = #selector(runClicked)
        runButton.keyEquivalent = "\r"
        let runRow = NSStackView(views: [runButton, resultLabel])
        runRow.orientation = .horizontal
        runRow.spacing = 8

        let sqlLabel = NSTextField(labelWithString: "SQL")
        sqlLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        let gridSep = NSBox()
        gridSep.boxType = .separator
        gridSep.heightAnchor.constraint(equalToConstant: 1).isActive = true

        let rightStack = NSStackView(views: [schemaLabel, gridScroll, pagerRow, gridSep, sqlLabel, sqlScroll, runRow])
        rightStack.orientation = .vertical
        rightStack.spacing = 8
        rightStack.setHuggingPriority(.defaultLow, for: .vertical)
        gridScroll.setContentHuggingPriority(.defaultLow, for: .vertical)
        gridScroll.heightAnchor.constraint(greaterThanOrEqualToConstant: 200).isActive = true
        sqlScroll.heightAnchor.constraint(equalToConstant: 110).isActive = true

        let sep = NSBox()
        sep.boxType = .separator

        for view in [topRow, statusLabel, tablesScroll, sep, rightStack] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(view)
        }
        NSLayoutConstraint.activate([
            topRow.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            topRow.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            topRow.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            statusLabel.topAnchor.constraint(equalTo: topRow.bottomAnchor, constant: 8),
            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),

            tablesScroll.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            tablesScroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            tablesScroll.widthAnchor.constraint(equalToConstant: 220),
            tablesScroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),

            sep.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            sep.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
            sep.leadingAnchor.constraint(equalTo: tablesScroll.trailingAnchor, constant: 4),
            sep.widthAnchor.constraint(equalToConstant: 1),

            rightStack.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 8),
            rightStack.leadingAnchor.constraint(equalTo: sep.trailingAnchor, constant: 4),
            rightStack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            rightStack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
    }

    public func reloadTables() {
        do {
            tables = try model.tables()
            tablesTable.reloadData()
            if tables.isEmpty {
                statusLabel.stringValue = "No tables or views in this database."
                currentTable = nil
                show(result: SQLiteExplorerResult(columns: [], rows: []), sql: false)
            } else {
                statusLabel.stringValue = "\(tables.count) table(s) and view(s)."
                tablesTable.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            }
        } catch {
            statusLabel.stringValue = error.localizedDescription
        }
    }

    private func loadPage(_ page: Int) {
        guard let table = currentTable else { return }
        do {
            totalRows = try model.rowCount(of: table)
            let maxPage = max(0, (totalRows - 1) / Self.pageSize)
            currentPage = min(max(0, page), maxPage)
            let result = try model.rows(of: table, limit: Self.pageSize, offset: currentPage * Self.pageSize)
            show(result: result, sql: false)
            let first = totalRows == 0 ? 0 : currentPage * Self.pageSize + 1
            let last = min(totalRows, (currentPage + 1) * Self.pageSize)
            pageLabel.stringValue = "Rows \(first)–\(last) of \(totalRows)"
            prevButton.isEnabled = currentPage > 0
            nextButton.isEnabled = currentPage < maxPage
        } catch {
            statusLabel.stringValue = error.localizedDescription
        }
    }

    private func loadSchema(for table: String) {
        do {
            let columns = try model.columns(of: table)
            schemaLabel.stringValue = columns.map {
                "\($0.name) \($0.type)\($0.primaryKey ? " (PK)" : "")\($0.notNull ? " NOT NULL" : "")"
            }.joined(separator: "  ·  ")
        } catch {
            schemaLabel.stringValue = error.localizedDescription
        }
    }

    private func show(result: SQLiteExplorerResult, sql: Bool) {
        showingSQLResult = sql
        currentResult = result
        for column in gridTable.tableColumns {
            gridTable.removeTableColumn(column)
        }
        for (index, name) in result.columns.enumerated() {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("\(index)"))
            column.title = name
            column.minWidth = 60
            column.width = 140
            gridTable.addTableColumn(column)
        }
        gridTable.reloadData()
        prevButton.isEnabled = !sql && currentPage > 0
        nextButton.isEnabled = false
        if !sql { loadPageButtonState() }
    }

    private func loadPageButtonState() {
        let maxPage = max(0, (totalRows - 1) / Self.pageSize)
        prevButton.isEnabled = currentPage > 0
        nextButton.isEnabled = currentPage < maxPage
    }

    @objc func openClicked() {
        SQLiteExplorerWindowManager.runOpenPanel(from: window) { [weak self] url in
            guard let self, let url else { return }
            do {
                let newModel = try SQLiteExplorerModel(path: url.path)
                self.model = newModel
                self.window?.title = "SQLite Explorer — \(url.lastPathComponent)"
                self.pathLabel.stringValue = newModel.path
                self.currentTable = nil
                self.currentPage = 0
                self.reloadTables()
            } catch {
                NSApp.presentError(error)
            }
        }
    }

    @objc func prevClicked() { loadPage(currentPage - 1) }
    @objc func nextClicked() { loadPage(currentPage + 1) }

    @objc func runClicked() {
        let sql = sqlTextView.string
        let started = Date()
        do {
            let result = try model.run(sql: sql)
            DatabaseHistoryService.shared.record(
                sql: sql, executionTimeMs: Date().timeIntervalSince(started) * 1000,
                rowsAffected: result.columns.isEmpty ? 0 : result.rows.count, status: "SUCCESS")
            show(result: result, sql: true)
            resultLabel.stringValue = result.message ?? ""
            if result.columns.isEmpty {
                pageLabel.stringValue = ""
            } else {
                pageLabel.stringValue = "\(result.rows.count) row(s)"
            }
        } catch {
            DatabaseHistoryService.shared.record(
                sql: sql, executionTimeMs: Date().timeIntervalSince(started) * 1000,
                rowsAffected: 0, status: "ERROR", errorMessage: error.localizedDescription)
            resultLabel.stringValue = error.localizedDescription
        }
    }

    @objc func sectionsClicked() {
        if let sectionsController {
            sectionsController.window?.makeKeyAndOrderFront(nil)
            return
        }
        let controller = SQLiteExplorerSectionsController(model: model)
        controller.onDatabaseChanged = { [weak self] in
            self?.reloadTables()
            if self?.currentTable != nil { self?.loadPage(0) }
        }
        sectionsController = controller
        controller.window?.makeKeyAndOrderFront(nil)
    }

    public func numberOfRows(in tableView: NSTableView) -> Int {
        if tableView === tablesTable { return tables.count }
        return currentResult.rows.count
    }

    public func tableView(_ tableView: NSTableView, viewFor column: NSTableColumn?, row: Int) -> NSView? {
        if tableView === tablesTable {
            guard row < tables.count else { return nil }
            let table = tables[row]
            let field = NSTextField(labelWithString: table.kind == .view ? "\(table.name) (view)" : table.name)
            field.font = .systemFont(ofSize: 12)
            return field
        }
        guard row < currentResult.rows.count,
              let column,
              let index = Int(column.identifier.rawValue),
              index < currentResult.rows[row].count else { return nil }
        let field = NSTextField(labelWithString: currentResult.rows[row][index])
        field.font = .systemFont(ofSize: 12)
        field.lineBreakMode = .byTruncatingTail
        return field
    }

    public func tableViewSelectionDidChange(_ notification: Notification) {
        guard let tableView = notification.object as? NSTableView, tableView === tablesTable else { return }
        let row = tablesTable.selectedRow
        guard row >= 0, row < tables.count else { return }
        currentTable = tables[row].name
        currentPage = 0
        loadSchema(for: tables[row].name)
        loadPage(0)
    }
}
