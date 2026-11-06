import SwiftUI
import SwiftCodeCloud

/// Creates a table on the active connection.
///
/// Ported from Legacy's
/// `Views/Utilities/Database/Views/DatabaseTableEditor.swift`.
///
/// Changes over Legacy, all recorded here:
///
/// - Creation runs through the staged `DatabaseSchemaManager`
///   (`shared.createTable(connection:table:)`), exactly as Legacy
///   did. That manager generates the real `CREATE TABLE` DDL
///   inline (`createTableSQL(table:provider:)`, ported from
///   Legacy's `DatabaseUtilities`) and executes it against SQLite
///   for real; for Supabase it goes through `SupabaseService`,
///   which fails honestly when no SQL RPC is configured; for
///   PostgreSQL / MySQL / MariaDB it fails honestly with
///   `.schemaModificationFailed` instead of Legacy's silent
///   no-op.
/// - The DDL that will run is previewed live below the form, from
///   the same `DatabaseSchemaManager.createTableSQL` the manager
///   itself uses, so the preview cannot drift from what executes.
/// - The column-type picker follows the active connection's
///   provider (SQLite / Postgres / MySQL type lists from
///   `DatabaseConstants`); Legacy always offered SQLite types.
/// - Validation still uses `DatabaseValidators.validateTableName`.
/// - Legacy's `liquidGlass` header is gone (SwiftCodeUI has no
///   such modifier); the header is a plain row on a subtle
///   background.
@MainActor
struct DatabaseTableEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var connManager: DatabaseConnectionManager
    var onSave: () -> Void

    @State private var tableName = ""
    @State private var comment = ""
    @State private var columns: [DatabaseColumn] = [
        DatabaseColumn(name: "id", type: "INTEGER", isPrimaryKey: true, isNullable: false, isAutoIncrement: true)
    ]
    @State private var errorMessage = ""

    private var availableTypes: [String] {
        switch connManager.activeConnection?.provider {
        case .postgresql, .supabase:
            return DatabaseConstants.standardPostgresTypes
        case .mysql, .mariadb:
            return DatabaseConstants.standardMySQLTypes
        default:
            return DatabaseConstants.standardSQLiteTypes
        }
    }

    /// The `CREATE TABLE` statement that saving will run, from the
    /// same generator the schema manager uses.
    private var createTablePreview: String {
        guard !tableName.isEmpty else { return "" }
        let table = DatabaseTable(
            name: tableName,
            columns: columns,
            comment: comment.isEmpty ? nil : comment
        )
        return DatabaseSchemaManager.createTableSQL(
            table: table,
            provider: connManager.activeConnection?.provider ?? .sqlite)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Create New Table")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.06))

            Form {
                Section("Table Metadata") {
                    TextField("Table Name", text: $tableName)
                    TextField("Comment", text: $comment)
                }

                Section("Columns") {
                    ForEach($columns) { $col in
                        HStack {
                            TextField("Name", text: $col.name)

                            Picker("", selection: $col.type) {
                                ForEach(availableTypes, id: \.self) { t in
                                    Text(t).tag(t)
                                }
                            }
                            .frame(width: 100)

                            Toggle("PK", isOn: $col.isPrimaryKey)
                            Toggle("Null", isOn: $col.isNullable)
                        }
                    }

                    Button(action: {
                        columns.append(DatabaseColumn(name: "col_\(columns.count)", type: "TEXT"))
                    }) {
                        Label("Add Column", systemImage: "plus")
                    }
                }

                if !createTablePreview.isEmpty {
                    Section("DDL Preview") {
                        Text(createTablePreview)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }
            }
            .formStyle(.grouped)

            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .padding()
            }

            Divider()

            HStack {
                Spacer()
                Button("Save Table") {
                    saveTable()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }

    private func saveTable() {
        let (isValid, message) = DatabaseValidators.validateTableName(tableName)
        guard isValid else {
            errorMessage = message
            return
        }

        guard let conn = connManager.activeConnection else {
            errorMessage = "No active database connection."
            return
        }

        let table = DatabaseTable(
            name: tableName,
            columns: columns,
            comment: comment.isEmpty ? nil : comment
        )

        Task {
            do {
                try await DatabaseSchemaManager.shared.createTable(connection: conn, table: table)
                onSave()
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
