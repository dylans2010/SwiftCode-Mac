import SwiftUI

struct DatabaseImportExportView: View {
    @EnvironmentObject var connManager: DatabaseConnectionManager
    @State private var csvContent = "id,name,email\n1,Alex,alex@example.com\n2,Emma,emma@example.com"
    @State private var targetTable = ""
    @State private var message = ""
    @State private var tables: [DatabaseTable] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Import CSV Section
                GroupBox("Import CSV Data") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Target Table", selection: $targetTable) {
                            ForEach(tables) { t in
                                Text(t.name).tag(t.name)
                            }
                        }

                        Text("Paste CSV Data below:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $csvContent)
                            .font(.system(.body, design: .monospaced))
                            .frame(height: 120)
                            .border(Color.secondary.opacity(0.2))

                        Button("Execute Import") {
                            importCSV()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(targetTable.isEmpty || csvContent.isEmpty)
                    }
                    .padding(8)
                }

                // Export Section
                GroupBox("Export Data") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Select a table to dump schema & rows in CSV, JSON, or SQL format.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Button("Export Schema SQL") {
                                exportSQL()
                            }
                            Button("Export Active Rows JSON") {
                                exportJSON()
                            }
                        }
                    }
                    .padding(8)
                }

                if !message.isEmpty {
                    GroupBox("Console Logs") {
                        ScrollView {
                            Text(message)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 150)
                    }
                }
            }
            .padding()
        }
        .onAppear {
            loadTables()
        }
    }

    private func loadTables() {
        guard let conn = connManager.activeConnection, conn.provider == .sqlite, let path = conn.sqliteFilePath else { return }
        Task {
            if let t = try? DatabaseManager.shared.fetchSQLiteTables(filePath: path) {
                tables = t
                targetTable = t.first?.name ?? ""
            }
        }
    }

    private func importCSV() {
        guard let conn = connManager.activeConnection, conn.provider == .sqlite, let path = conn.sqliteFilePath else { return }
        let (columns, rows) = DatabaseImportManager.shared.parseCSV(content: csvContent)

        var successCount = 0
        Task {
            for row in rows {
                let colNames = columns.joined(separator: ", ")
                let values = columns.map { col in
                    if let val = row[col] {
                        return "'\(val)'"
                    }
                    return "NULL"
                }.joined(separator: ", ")

                let sql = "INSERT INTO \(targetTable) (\(colNames)) VALUES (\(values));"
                do {
                    _ = try DatabaseManager.shared.executeSQLiteQuery(filePath: path, sql: sql)
                    successCount += 1
                } catch {
                    message = "Error inserting row: \(error.localizedDescription)"
                }
            }
            message = "Successfully imported \(successCount) records into '\(targetTable)' table."
        }
    }

    private func exportSQL() {
        guard let conn = connManager.activeConnection else { return }
        let sql = DatabaseExportManager.shared.exportSQLSchema(tables: tables, provider: conn.provider)
        message = "SQL SCHEMA DUMP:\n\n\(sql)"
    }

    private func exportJSON() {
        guard let conn = connManager.activeConnection, conn.provider == .sqlite, let path = conn.sqliteFilePath else { return }
        guard !targetTable.isEmpty else { return }

        Task {
            do {
                let sql = "SELECT * FROM \(targetTable) LIMIT 200;"
                let rows = try DatabaseManager.shared.executeSQLiteQuery(filePath: path, sql: sql)
                let json = try DatabaseExportManager.shared.exportToJSON(rows: rows)
                message = "TABLE DATA JSON DUMP (\(targetTable)):\n\n\(json)"
            } catch {
                message = "Export failed: \(error.localizedDescription)"
            }
        }
    }
}
