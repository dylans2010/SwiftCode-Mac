import SwiftUI
import SwiftCodeCloud

/// Creates and lists indexes on the active SQLite connection.
///
/// Ported from Legacy's
/// `Views/Utilities/Database/Views/DatabaseIndexesView.swift`.
///
/// Changes over Legacy, all recorded here:
///
/// - SQLite execution goes through `SQLiteExplorerModel` (via
///   `DatabaseViewSQLite`), not Legacy's `DatabaseManager`.
/// - Legacy listed each index's columns as its owning table
///   (`columns: [tbl_name]`) — that was the table name, not the
///   indexed columns. This port reads the real column list with
///   `PRAGMA index_info`, and reads uniqueness from the index's
///   own `CREATE` statement in `sqlite_master`.
/// - Added a Unique toggle on the creation form (Legacy could only
///   create non-unique indexes) and a Drop button per index
///   (Legacy could not remove one). Identifiers are quoted;
///   Legacy interpolated them raw.
/// - The view is SQLite-only, as Legacy was: it loads nothing and
///   creates nothing while the active connection is not SQLite.
///   Remote providers have no index driver in this package, and
///   the form does not pretend otherwise.
/// - Legacy's `liquidGlass` group-box style is gone (SwiftCodeUI
///   has no such modifier); the default group-box style is used.
@MainActor
struct DatabaseIndexesView: View {
    @EnvironmentObject var connManager: DatabaseConnectionManager
    @State private var indexes: [DatabaseIndex] = []
    @State private var selectedTable = ""
    @State private var indexName = ""
    @State private var columnName = ""
    @State private var isUnique = false
    @State private var tables: [DatabaseTable] = []
    @State private var errorMessage = ""

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
                        Toggle("Unique", isOn: $isUnique)
                        Button("Create Index") {
                            createIndex()
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
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
                        HStack {
                            Text(idx.name)
                                .font(.headline)
                            if idx.isUnique {
                                Text("UNIQUE")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.orange.opacity(0.15), in: Capsule())
                            }
                        }
                        Text("Columns: \(idx.columns.joined(separator: ", ")) | Type: \(idx.type)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Drop", role: .destructive) {
                        dropIndex(idx)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear {
            loadTablesAndIndexes()
        }
        .onChange(of: connManager.activeConnection) { _, _ in
            loadTablesAndIndexes()
        }
    }

    private func loadTablesAndIndexes() {
        guard let conn = connManager.activeConnection, conn.provider == .sqlite else {
            tables = []
            indexes = []
            return
        }
        Task { @MainActor in
            do {
                let explorer = try DatabaseViewSQLite.explorer(for: conn)
                tables = try DatabaseViewSQLite.fetchTables(explorer)
                if let first = tables.first,
                   selectedTable.isEmpty || !tables.contains(where: { $0.name == selectedTable }) {
                    selectedTable = first.name
                    columnName = first.columns.first?.name ?? ""
                }

                // Indexes from sqlite_master, with real column lists.
                let rows = try DatabaseViewSQLite.runDictionaries(
                    explorer,
                    sql: "SELECT name, sql FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%';"
                )
                var loaded: [DatabaseIndex] = []
                for row in rows {
                    guard let name = row["name"] else { continue }
                    let info = try DatabaseViewSQLite.runDictionaries(
                        explorer,
                        sql: "PRAGMA index_info(\(SQLiteExplorerModel.quoted(name)));"
                    )
                    let columns = info.compactMap { $0["name"] }
                    let isUnique = (row["sql"] ?? "").localizedCaseInsensitiveContains("UNIQUE")
                    loaded.append(DatabaseIndex(name: name, columns: columns, isUnique: isUnique))
                }
                indexes = loaded
                errorMessage = ""
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func createIndex() {
        guard !indexName.isEmpty && !selectedTable.isEmpty && !columnName.isEmpty else { return }
        guard let conn = connManager.activeConnection, conn.provider == .sqlite else { return }

        let unique = isUnique ? "UNIQUE " : ""
        let sql = "CREATE \(unique)INDEX IF NOT EXISTS \(SQLiteExplorerModel.quoted(indexName)) "
            + "ON \(SQLiteExplorerModel.quoted(selectedTable))(\(SQLiteExplorerModel.quoted(columnName)));"

        Task { @MainActor in
            do {
                let explorer = try DatabaseViewSQLite.explorer(for: conn)
                _ = try explorer.run(sql: sql)
                loadTablesAndIndexes()
                indexName = ""
                errorMessage = ""
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func dropIndex(_ index: DatabaseIndex) {
        guard let conn = connManager.activeConnection, conn.provider == .sqlite else { return }
        Task { @MainActor in
            do {
                let explorer = try DatabaseViewSQLite.explorer(for: conn)
                _ = try explorer.run(sql: "DROP INDEX IF EXISTS \(SQLiteExplorerModel.quoted(index.name));")
                loadTablesAndIndexes()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
