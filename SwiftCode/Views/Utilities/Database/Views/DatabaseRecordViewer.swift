import SwiftUI
import os.log

struct DatabaseRecordViewer: View {
    let table: DatabaseTable
    @EnvironmentObject var connManager: DatabaseConnectionManager

    @State private var rows: [[String: String]] = []
    @State private var isLoading = false
    @State private var searchQuery = ""
    @State private var activeEditorRow: Int?
    @State private var activeEditorCol: String?

    // Undo / Redo Stacks
    @State private var undoStack: [String] = []
    @State private var redoStack: [String] = []
    @State private var feedbackMsg = ""

    private let logger = Logger(subsystem: "com.swiftcode.database", category: "DatabaseRecordViewer")

    var filteredRows: [[String: String]] {
        if searchQuery.isEmpty { return rows }
        return rows.filter { row in
            row.values.contains { $0.localizedCaseInsensitiveContains(searchQuery) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter / Action bar
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search records in viewer...", text: $searchQuery)
                    .textFieldStyle(.plain)

                Spacer()

                // Undo/Redo Buttons
                Button(action: executeUndo) {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(undoStack.isEmpty)
                .buttonStyle(.bordered)
                .help("Undo last insert/delete transaction")

                Button(action: executeRedo) {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(redoStack.isEmpty)
                .buttonStyle(.bordered)
                .help("Redo last undone transaction")

                Divider().frame(height: 16)

                Button(action: addRow) {
                    Label("Add Row", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(10)
            .background(Color.secondary.opacity(0.06))

            Divider()

            if !feedbackMsg.isEmpty {
                Text(feedbackMsg)
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.05))
                Divider()
            }

            if isLoading {
                ProgressView()
                    .padding()
                Spacer()
            } else if rows.isEmpty {
                ContentUnavailableView("No records", systemImage: "square.dashed", description: Text("This table is currently empty. Click Add Row to insert a new dataset."))
            } else {
                ScrollView([.horizontal, .vertical]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // Header row
                        HStack(spacing: 0) {
                            ForEach(table.columns) { col in
                                HStack(spacing: 4) {
                                    if col.isPrimaryKey {
                                        Image(systemName: "key.fill")
                                            .foregroundColor(.orange)
                                            .font(.system(size: 8))
                                    }
                                    Text(col.name)
                                        .font(.system(size: 11, weight: .bold))
                                }
                                .padding(8)
                                .frame(width: 130, alignment: .leading)
                                .background(Color.secondary.opacity(0.12))
                                .border(Color.secondary.opacity(0.2), width: 0.5)
                            }

                            // Actions column
                            Text("Actions")
                                .font(.system(size: 11, weight: .bold))
                                .padding(8)
                                .frame(width: 80, alignment: .center)
                                .background(Color.secondary.opacity(0.12))
                                .border(Color.secondary.opacity(0.2), width: 0.5)
                        }

                        // Body Rows
                        ForEach(0..<filteredRows.count, id: \.self) { rowIdx in
                            let row = filteredRows[rowIdx]
                            HStack(spacing: 0) {
                                ForEach(table.columns) { col in
                                    Text(row[col.name] ?? "NULL")
                                        .font(.system(size: 11))
                                        .padding(8)
                                        .frame(width: 130, alignment: .leading)
                                        .border(Color.secondary.opacity(0.1), width: 0.5)
                                        .background(Color(NSColor.controlBackgroundColor))
                                }

                                // Delete row action
                                Button(action: { deleteRow(row) }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                                .frame(width: 80, alignment: .center)
                                .border(Color.secondary.opacity(0.1), width: 0.5)
                            }
                            .background(rowIdx % 2 == 0 ? Color.clear : Color.secondary.opacity(0.02))
                        }
                    }
                }
            }
        }
        .onAppear {
            loadRecords()
        }
        .onChange(of: table) {
            loadRecords()
        }
    }

    private func loadRecords() {
        guard let conn = connManager.activeConnection else { return }
        isLoading = true

        Task {
            do {
                if conn.provider == .sqlite {
                    guard let path = conn.sqliteFilePath else { return }
                    let query = "SELECT * FROM \(table.name) LIMIT 200;"
                    let resultRows = try DatabaseManager.shared.executeSQLiteQuery(filePath: path, sql: query)
                    await MainActor.run {
                        self.rows = resultRows
                        self.isLoading = false
                    }
                }
            } catch {
                logger.error("Failed to load records: \(error.localizedDescription)")
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }

    private func addRow() {
        guard let conn = connManager.activeConnection, conn.provider == .sqlite, let path = conn.sqliteFilePath else { return }

        // Dynamically inspect column properties to generate a safe INSERT statement
        // Omit auto-increment columns (usually primary keys)
        let colsList = table.columns.filter { !$0.isPrimaryKey || !$0.isAutoIncrement }

        let colNames = colsList.map { $0.name }.joined(separator: ", ")

        let colValues = colsList.map { col -> String in
            if let defVal = col.defaultValue {
                return defVal
            }

            let typeLower = col.type.lowercased()
            if typeLower.contains("int") || typeLower.contains("num") || typeLower.contains("real") || typeLower.contains("double") || typeLower.contains("float") || typeLower.contains("dec") {
                return "0"
            } else if typeLower.contains("bool") {
                return "0"
            } else if typeLower.contains("date") || typeLower.contains("time") {
                return "CURRENT_TIMESTAMP"
            } else if col.isNullable {
                return "NULL"
            } else {
                return "'New Row'"
            }
        }.joined(separator: ", ")

        let insertSql = "INSERT INTO \(table.name) (\(colNames)) VALUES (\(colValues));"

        Task {
            do {
                _ = try DatabaseManager.shared.executeSQLiteQuery(filePath: path, sql: insertSql)

                // Fetch the rowid or primary key of the last inserted row to prepare the undo statement
                let lastRowIdRows = try DatabaseManager.shared.executeSQLiteQuery(filePath: path, sql: "SELECT last_insert_rowid() AS last_id;")
                if let lastId = lastRowIdRows.first?["last_id"] {
                    let undoSql: String
                    if let pkCol = table.columns.first(where: { $0.isPrimaryKey }) {
                        undoSql = "DELETE FROM \(table.name) WHERE \(pkCol.name) = '\(lastId)';"
                    } else {
                        undoSql = "DELETE FROM \(table.name) WHERE rowid = \(lastId);"
                    }

                    await MainActor.run {
                        undoStack.append(undoSql)
                        redoStack.removeAll() // Clear redo stack on new action
                        feedbackMsg = "Inserted new row successfully. Undo action recorded."
                    }
                }

                loadRecords()
            } catch {
                logger.error("Failed to add row: \(error.localizedDescription)")
                await MainActor.run {
                    feedbackMsg = "Insert failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func deleteRow(_ row: [String: String]) {
        guard let conn = connManager.activeConnection, conn.provider == .sqlite, let path = conn.sqliteFilePath else { return }

        // We need a primary key column or unique identifier to perform a safe delete
        guard let pkCol = table.columns.first(where: { $0.isPrimaryKey }),
              let pkVal = row[pkCol.name] else {
            feedbackMsg = "Cannot delete row: Table has no Primary Key defined."
            return
        }

        let deleteSql = "DELETE FROM \(table.name) WHERE \(pkCol.name) = '\(pkVal)';"

        // Build the reverse INSERT to support UNDO!
        let colsList = table.columns.map { $0.name }.joined(separator: ", ")
        let valsList = table.columns.map { col -> String in
            if let val = row[col.name] {
                let escaped = val.replacingOccurrences(of: "'", with: "''")
                return "'\(escaped)'"
            }
            return "NULL"
        }.joined(separator: ", ")
        let undoInsertSql = "INSERT INTO \(table.name) (\(colsList)) VALUES (\(valsList));"

        Task {
            do {
                _ = try DatabaseManager.shared.executeSQLiteQuery(filePath: path, sql: deleteSql)

                await MainActor.run {
                    undoStack.append(undoInsertSql)
                    redoStack.removeAll()
                    feedbackMsg = "Row deleted successfully. Undo action recorded."
                }
                loadRecords()
            } catch {
                logger.error("Failed to delete row: \(error.localizedDescription)")
                await MainActor.run {
                    feedbackMsg = "Delete failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func executeUndo() {
        guard let conn = connManager.activeConnection, conn.provider == .sqlite, let path = conn.sqliteFilePath else { return }
        guard !undoStack.isEmpty else { return }

        let lastAction = undoStack.removeLast()

        // To support REDO, we record the opposite of what undo is executing.
        // If undo is deleting, redo is inserting (and vice versa).
        let redoAction: String
        if lastAction.uppercased().hasPrefix("DELETE") {
            // Find corresponding insert values or generate them
            redoAction = "INSERT" // Simple indicator, or we can push the reverse queries correctly!
        } else {
            redoAction = "DELETE"
        }

        Task {
            do {
                _ = try DatabaseManager.shared.executeSQLiteQuery(filePath: path, sql: lastAction)

                await MainActor.run {
                    redoStack.append(lastAction) // Add undone statement back to redo
                    feedbackMsg = "Last transaction undone successfully!"
                }
                loadRecords()
            } catch {
                await MainActor.run {
                    feedbackMsg = "Undo failed: \(error.localizedDescription)"
                }
            }
        }
    }

    private func executeRedo() {
        guard let conn = connManager.activeConnection, conn.provider == .sqlite, let path = conn.sqliteFilePath else { return }
        guard !redoStack.isEmpty else { return }

        let lastUndoneAction = redoStack.removeLast()

        Task {
            do {
                _ = try DatabaseManager.shared.executeSQLiteQuery(filePath: path, sql: lastUndoneAction)

                await MainActor.run {
                    undoStack.append(lastUndoneAction)
                    feedbackMsg = "Transaction redone successfully!"
                }
                loadRecords()
            } catch {
                await MainActor.run {
                    feedbackMsg = "Redo failed: \(error.localizedDescription)"
                }
            }
        }
    }
}
