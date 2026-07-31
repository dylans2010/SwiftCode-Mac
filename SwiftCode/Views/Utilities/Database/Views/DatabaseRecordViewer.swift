import SwiftUI

struct DatabaseRecordViewer: View {
    let table: DatabaseTable
    @EnvironmentObject var connManager: DatabaseConnectionManager

    @State private var rows: [[String: String]] = []
    @State private var isLoading = false
    @State private var searchQuery = ""
    @State private var activeEditorRow: Int?
    @State private var activeEditorCol: String?

    var filteredRows: [[String: String]] {
        if searchQuery.isEmpty { return rows }
        return rows.filter { row in
            row.values.contains { $0.localizedCaseInsensitiveContains(searchQuery) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Filter / Action bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search records...", text: $searchQuery)
                    .textFieldStyle(.plain)

                Spacer()

                Button(action: addRow) {
                    Label("Add Row", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            .padding(10)
            .background(Color.secondary.opacity(0.06))

            Divider()

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
                                Text(col.name)
                                    .font(.system(size: 11, weight: .bold))
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
                    self.rows = try DatabaseManager.shared.executeSQLiteQuery(filePath: path, sql: query)
                }
            } catch {
                print("Failed to load records: \(error.localizedDescription)")
            }
            isLoading = false
        }
    }

    private func addRow() {
        guard let conn = connManager.activeConnection, conn.provider == .sqlite, let path = conn.sqliteFilePath else { return }
        // Simple insert of default row
        let colsList = table.columns.filter { !$0.isPrimaryKey || !$0.isAutoIncrement }.map { $0.name }
        let placeHolders = colsList.map { _ in "NULL" }.joined(separator: ", ")
        let sql = "INSERT INTO \(table.name) (\(colsList.joined(separator: ", "))) VALUES (\(placeHolders));"

        Task {
            do {
                _ = try DatabaseManager.shared.executeSQLiteQuery(filePath: path, sql: sql)
                loadRecords()
            } catch {
                print("Failed to add row: \(error.localizedDescription)")
            }
        }
    }

    private func deleteRow(_ row: [String: String]) {
        guard let conn = connManager.activeConnection, conn.provider == .sqlite, let path = conn.sqliteFilePath else { return }

        // Find primary key column to safely delete
        guard let pkCol = table.columns.first(where: { $0.isPrimaryKey }),
              let pkVal = row[pkCol.name] else { return }

        let sql = "DELETE FROM \(table.name) WHERE \(pkCol.name) = '\(pkVal)';"

        Task {
            do {
                _ = try DatabaseManager.shared.executeSQLiteQuery(filePath: path, sql: sql)
                loadRecords()
            } catch {
                print("Failed to delete row: \(error.localizedDescription)")
            }
        }
    }
}
