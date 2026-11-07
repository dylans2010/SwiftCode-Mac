import AppKit
import SwiftUI
import os.log
import SwiftCodeCloud

private struct RecordViewerUndoEntry {
    let undoSQL: String
    let redoSQL: String
}

@MainActor
struct DatabaseRecordViewer: View {
    let table: DatabaseTable
    @EnvironmentObject var connManager: DatabaseConnectionManager

    @State private var rows: [[String: String]] = []
    @State private var isLoading = false
    @State private var searchQuery = ""
    @State private var editingRow: DatabaseRecordViewerEditingRow?

    @State private var undoStack: [RecordViewerUndoEntry] = []
    @State private var redoStack: [RecordViewerUndoEntry] = []
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
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search records in viewer...", text: $searchQuery)
                    .textFieldStyle(.plain)

                Spacer()

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

                            Text("Actions")
                                .font(.system(size: 11, weight: .bold))
                                .padding(8)
                                .frame(width: 80, alignment: .center)
                                .background(Color.secondary.opacity(0.12))
                                .border(Color.secondary.opacity(0.2), width: 0.5)
                        }

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

                                Button(action: { deleteRow(row) }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                }
                                .buttonStyle(.plain)
                                .frame(width: 80, alignment: .center)
                                .border(Color.secondary.opacity(0.1), width: 0.5)
                            }
                            .background(rowIdx % 2 == 0 ? Color.clear : Color.secondary.opacity(0.02))
                            .onTapGesture(count: 2) {
                                editingRow = DatabaseRecordViewerEditingRow(values: row)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            loadRecords()
        }
        .onChange(of: table) { _, _ in
            loadRecords()
        }
        .sheet(item: $editingRow) { editing in
            DatabaseRecordEditor(table: table, rowData: editing.values) { newRow in
                saveEditedRow(original: editing.values, newRow: newRow)
            }
        }
    }

    private func loadRecords() {
        guard let conn = connManager.activeConnection, conn.provider == .sqlite else {
            rows = []
            return
        }
        isLoading = true

        Task { @MainActor in
            do {
                let explorer = try DatabaseViewSQLite.explorer(for: conn)
                let query = "SELECT * FROM \(SQLiteExplorerModel.quoted(table.name)) LIMIT 200;"
                rows = try DatabaseViewSQLite.runDictionaries(explorer, sql: query)
                isLoading = false
            } catch {
                logger.error("Failed to load records: \(error.localizedDescription)")
                isLoading = false
            }
        }
    }

    private func addRow() {
        guard let conn = connManager.activeConnection, conn.provider == .sqlite else { return }

        let colsList = table.columns.filter { !$0.isPrimaryKey || !$0.isAutoIncrement }

        let colNames = colsList.map { SQLiteExplorerModel.quoted($0.name) }.joined(separator: ", ")

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

        let insertSql = "INSERT INTO \(SQLiteExplorerModel.quoted(table.name)) (\(colNames)) VALUES (\(colValues));"

        Task { @MainActor in
            do {
                let explorer = try DatabaseViewSQLite.explorer(for: conn)
                _ = try explorer.run(sql: insertSql)

                let lastRowIdRows = try DatabaseViewSQLite.runDictionaries(explorer, sql: "SELECT last_insert_rowid() AS last_id;")
                if let lastId = lastRowIdRows.first?["last_id"] {
                    let undoSql: String
                    if let pkCol = table.columns.first(where: { $0.isPrimaryKey }) {
                        undoSql = "DELETE FROM \(SQLiteExplorerModel.quoted(table.name)) WHERE \(SQLiteExplorerModel.quoted(pkCol.name)) = \(DatabaseViewSQLite.sqlLiteral(lastId));"
                    } else {
                        undoSql = "DELETE FROM \(SQLiteExplorerModel.quoted(table.name)) WHERE rowid = \(lastId);"
                    }

                    undoStack.append(RecordViewerUndoEntry(undoSQL: undoSql, redoSQL: insertSql))
                    redoStack.removeAll()
                    feedbackMsg = "Inserted new row successfully. Undo action recorded."
                }

                loadRecords()
            } catch {
                logger.error("Failed to add row: \(error.localizedDescription)")
                feedbackMsg = "Insert failed: \(error.localizedDescription)"
            }
        }
    }

    private func deleteRow(_ row: [String: String]) {
        guard let conn = connManager.activeConnection, conn.provider == .sqlite else { return }

        guard let pkCol = table.columns.first(where: { $0.isPrimaryKey }),
              let pkVal = row[pkCol.name] else {
            feedbackMsg = "Cannot delete row: Table has no Primary Key defined."
            return
        }

        let deleteSql = "DELETE FROM \(SQLiteExplorerModel.quoted(table.name)) WHERE \(SQLiteExplorerModel.quoted(pkCol.name)) = \(DatabaseViewSQLite.sqlLiteral(pkVal));"

        let colsList = table.columns.map { SQLiteExplorerModel.quoted($0.name) }.joined(separator: ", ")
        let valsList = table.columns.map { col -> String in
            DatabaseViewSQLite.sqlLiteral(row[col.name])
        }.joined(separator: ", ")
        let undoInsertSql = "INSERT INTO \(SQLiteExplorerModel.quoted(table.name)) (\(colsList)) VALUES (\(valsList));"

        Task { @MainActor in
            do {
                let explorer = try DatabaseViewSQLite.explorer(for: conn)
                _ = try explorer.run(sql: deleteSql)

                undoStack.append(RecordViewerUndoEntry(undoSQL: undoInsertSql, redoSQL: deleteSql))
                redoStack.removeAll()
                feedbackMsg = "Row deleted successfully. Undo action recorded."
                loadRecords()
            } catch {
                logger.error("Failed to delete row: \(error.localizedDescription)")
                feedbackMsg = "Delete failed: \(error.localizedDescription)"
            }
        }
    }

    private func saveEditedRow(original: [String: String], newRow: [String: String]) {
        guard let conn = connManager.activeConnection, conn.provider == .sqlite else { return }
        guard let pkCol = table.columns.first(where: { $0.isPrimaryKey }),
              let pkVal = original[pkCol.name] else {
            feedbackMsg = "Cannot save row: Table has no Primary Key defined."
            return
        }
        let assignments = table.columns
            .filter { $0.name != pkCol.name }
            .map { col in
                "\(SQLiteExplorerModel.quoted(col.name)) = \(DatabaseViewSQLite.sqlLiteral(newRow[col.name]))"
            }
            .joined(separator: ", ")
        guard !assignments.isEmpty else { return }
        let updateSql = "UPDATE \(SQLiteExplorerModel.quoted(table.name)) SET \(assignments) "
            + "WHERE \(SQLiteExplorerModel.quoted(pkCol.name)) = \(DatabaseViewSQLite.sqlLiteral(pkVal));"

        Task { @MainActor in
            do {
                let explorer = try DatabaseViewSQLite.explorer(for: conn)
                _ = try explorer.run(sql: updateSql)
                feedbackMsg = "Row updated successfully."
                loadRecords()
            } catch {
                logger.error("Failed to update row: \(error.localizedDescription)")
                feedbackMsg = "Update failed: \(error.localizedDescription)"
            }
        }
    }

    private func executeUndo() {
        guard let conn = connManager.activeConnection, conn.provider == .sqlite else { return }
        guard !undoStack.isEmpty else { return }

        let entry = undoStack.removeLast()

        Task { @MainActor in
            do {
                let explorer = try DatabaseViewSQLite.explorer(for: conn)
                _ = try explorer.run(sql: entry.undoSQL)

                redoStack.append(entry)
                feedbackMsg = "Last transaction undone successfully!"
                loadRecords()
            } catch {
                feedbackMsg = "Undo failed: \(error.localizedDescription)"
            }
        }
    }

    private func executeRedo() {
        guard let conn = connManager.activeConnection, conn.provider == .sqlite else { return }
        guard !redoStack.isEmpty else { return }

        let entry = redoStack.removeLast()

        Task { @MainActor in
            do {
                let explorer = try DatabaseViewSQLite.explorer(for: conn)
                _ = try explorer.run(sql: entry.redoSQL)

                undoStack.append(entry)
                feedbackMsg = "Transaction redone successfully!"
                loadRecords()
            } catch {
                feedbackMsg = "Redo failed: \(error.localizedDescription)"
            }
        }
    }
}

private struct DatabaseRecordViewerEditingRow: Identifiable {
    let id = UUID()
    let values: [String: String]
}
