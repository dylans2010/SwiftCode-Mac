import SwiftUI

struct DatabaseIndexesView: View {
    @EnvironmentObject var connManager: DatabaseConnectionManager
    @State private var indexes: [DatabaseIndex] = []
    @State private var selectedTable = ""
    @State private var indexName = ""
    @State private var columnName = ""
    @State private var tables: [DatabaseTable] = []

    var body: some View {
        VStack(spacing: 0) {
            // Index Creation Form
            GroupBox("Add New Index") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Picker("Table", selection: $selectedTable) {
                            ForEach(tables) { t in
                                Text(t.name).tag(t.name)
                            }
                        }

                        if let tbl = tables.first(where: { $0.name == selectedTable }) {
                            Picker("Column", selection: $columnName) {
                                ForEach(tbl.columns) { c in
                                    Text(c.name).tag(c.name)
                                }
                            }
                        }
                    }

                    HStack {
                        TextField("Index Name", text: $indexName)
                        Button("Create Index") {
                            createIndex()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(8)
            }
            .padding()

            Divider()

            // Indexes list
            List(indexes) { idx in
                HStack {
                    Image(systemName: "bolt.fill")
                        .foregroundColor(.orange)
                    VStack(alignment: .leading) {
                        Text(idx.name)
                            .font(.headline)
                        Text("Columns: \(idx.columns.joined(separator: ", ")) | Type: \(idx.type)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .onAppear {
            loadTablesAndIndexes()
        }
    }

    private func loadTablesAndIndexes() {
        guard let conn = connManager.activeConnection, conn.provider == .sqlite, let path = conn.sqliteFilePath else { return }
        Task {
            do {
                tables = try DatabaseManager.shared.fetchSQLiteTables(filePath: path)
                if let first = tables.first {
                    selectedTable = first.name
                    if let col = first.columns.first {
                        columnName = col.name
                    }
                }

                // Query sqlite_master to fetch indexes
                let sql = "SELECT name, tbl_name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%';"
                let rows = try DatabaseManager.shared.executeSQLiteQuery(filePath: path, sql: sql)
                self.indexes = rows.map { row in
                    DatabaseIndex(name: row["name"] ?? "", columns: [row["tbl_name"] ?? ""])
                }
            } catch {
                print("Failed to load: \(error.localizedDescription)")
            }
        }
    }

    private func createIndex() {
        guard !indexName.isEmpty && !selectedTable.isEmpty && !columnName.isEmpty else { return }
        guard let conn = connManager.activeConnection, conn.provider == .sqlite, let path = conn.sqliteFilePath else { return }

        let sql = "CREATE INDEX IF NOT EXISTS \(indexName) ON \(selectedTable)(\(columnName));"

        Task {
            do {
                _ = try DatabaseManager.shared.executeSQLiteQuery(filePath: path, sql: sql)
                loadTablesAndIndexes()
                indexName = ""
            } catch {
                print("Error creating index: \(error.localizedDescription)")
            }
        }
    }
}
