import AppKit
import SwiftUI
import SwiftCodeCloud

/// Row Level Security policy editor for PostgreSQL / Supabase.
///
/// Ported from Legacy's
/// `Views/Utilities/Database/Views/DatabasePermissionsView.swift`,
/// rebuilt so the controls do something real.
///
/// Legacy's toggles and role list were purely presentational: the
/// switches changed no state anywhere and the roles were a fixed
/// list. This port keeps the two switches and the three roles, but
/// wires the switches to the real DDL they describe, generated for
/// the table picked from the active connection:
///
/// - "Enforce RLS" on generates `ALTER TABLE … ENABLE ROW LEVEL
///   SECURITY`; off generates `DISABLE`.
/// - "Restrict anonymous access" on generates `REVOKE SELECT,
///   INSERT, UPDATE, DELETE … FROM anon`; off generates the
///   matching `GRANT`.
///
/// The SQL is shown for review and copy. It is not executed here:
/// the destination's `SupabaseService.executeSQL` fails honestly
/// (PostgREST exposes no SQL-execution endpoint and Legacy
/// configured no RPC for one), so running it would only report a
/// failure — the SQL belongs in the Supabase SQL editor or `psql`.
/// SQLite connections show that RLS is a PostgreSQL feature and
/// does not apply, instead of generating meaningless DDL.
///
/// The three roles are Supabase's built-in roles — fixed by the
/// platform on every project, not rows fetched from this database
/// — and are labelled as such; effective access still depends on
/// the project's policies.
@MainActor
struct DatabasePermissionsView: View {
    @EnvironmentObject var connManager: DatabaseConnectionManager

    @State private var useRowLevelSecurity = true
    @State private var restrictAnonymousAccess = true
    @State private var tables: [DatabaseTable] = []
    @State private var selectedTable = ""
    @State private var loadMessage = ""
    @State private var copied = false

    /// The DDL the two switches describe for the selected table.
    /// Empty for SQLite, where RLS does not exist.
    private var generatedSQL: String {
        guard let conn = connManager.activeConnection, conn.provider != .sqlite,
              !selectedTable.isEmpty else { return "" }
        let table = SQLiteExplorerModel.quoted(selectedTable)
        var lines: [String] = []
        lines.append("ALTER TABLE \(table) \(useRowLevelSecurity ? "ENABLE" : "DISABLE") ROW LEVEL SECURITY;")
        if restrictAnonymousAccess {
            lines.append("REVOKE SELECT, INSERT, UPDATE, DELETE ON \(table) FROM anon;")
        } else {
            lines.append("GRANT SELECT, INSERT, UPDATE, DELETE ON \(table) TO anon;")
        }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        Form {
            Section("Access Controls & Policies") {
                Toggle("Enforce PostgreSQL Row Level Security (RLS)", isOn: $useRowLevelSecurity)
                Toggle("Restrict anonymous reading/writing", isOn: $restrictAnonymousAccess)

                if let conn = connManager.activeConnection, conn.provider != .sqlite {
                    Picker("Table", selection: $selectedTable) {
                        ForEach(tables) { table in
                            Text(table.name).tag(table.name)
                        }
                    }
                }
            }

            if let conn = connManager.activeConnection, conn.provider == .sqlite {
                Section {
                    Text("Row Level Security is a PostgreSQL / Supabase feature and does not apply to this SQLite connection.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else if !generatedSQL.isEmpty {
                Section("Generated Policy SQL") {
                    Text(generatedSQL)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    HStack {
                        Button(copied ? "Copied" : "Copy SQL") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(generatedSQL, forType: .string)
                            copied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copied = false }
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                        Text("Run in the Supabase SQL editor or psql — this app has no SQL-execution endpoint for remote providers.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else if !loadMessage.isEmpty {
                Section {
                    Text(loadMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Authenticated Roles") {
                Text("Supabase built-in roles — fixed by the platform on every project, not fetched from this database. Effective access depends on the project's policies.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                List {
                    HStack {
                        Text("authenticated")
                        Spacer()
                        Text("READ / WRITE")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    HStack {
                        Text("anon")
                        Spacer()
                        Text("READ ONLY")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    HStack {
                        Text("service_role")
                        Spacer()
                        Text("BYPASS ALL")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                .frame(height: 120)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            loadTables()
        }
        .onChange(of: connManager.activeConnection) { _, _ in
            loadTables()
        }
    }

    private func loadTables() {
        guard let conn = connManager.activeConnection, conn.provider != .sqlite else {
            tables = []
            selectedTable = ""
            return
        }
        Task { @MainActor in
            do {
                if conn.provider == .supabase {
                    tables = try await SupabaseService().fetchTables(connection: conn)
                } else {
                    // PostgreSQL / MySQL / MariaDB: no driver in
                    // this package, so no table list can be fetched.
                    // The toggles still generate real DDL, but there
                    // is no table to target it at.
                    tables = []
                    loadMessage = "No driver for \(conn.provider.rawValue): table names cannot be listed, so no policy SQL can be targeted. Connect a Supabase project to pick a table."
                    return
                }
                selectedTable = tables.first?.name ?? ""
                loadMessage = tables.isEmpty ? "No tables on this connection." : ""
            } catch {
                tables = []
                loadMessage = error.localizedDescription
            }
        }
    }
}
