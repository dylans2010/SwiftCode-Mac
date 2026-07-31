import SwiftUI

struct DatabaseTablesView: View {
    @EnvironmentObject var connManager: DatabaseConnectionManager
    @Binding var selectedTable: DatabaseTable?
    @State private var tables: [DatabaseTable] = []
    @State private var isLoading = false
    @State private var showingCreateForm = false

    var body: some View {
        VStack(spacing: 0) {
            // Table selector bar
            HStack {
                Text("Tables & Views")
                    .font(.headline)

                Spacer()

                Button {
                    showingCreateForm = true
                } label: {
                    Label("Add Table", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            .padding(12)
            .background(Color.secondary.opacity(0.05))

            Divider()

            HStack(spacing: 0) {
                // Table Names Sidebar List
                VStack(spacing: 0) {
                    if isLoading {
                        ProgressView()
                            .padding()
                    } else {
                        List(tables, selection: $selectedTable) { table in
                            NavigationLink(value: table) {
                                HStack {
                                    Image(systemName: table.isView ? "eye.fill" : "tablecells")
                                        .foregroundColor(table.isView ? .purple : .blue)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(table.name)
                                            .font(.subheadline.bold())
                                        Text("\(table.recordCount) records")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(width: 200)

                Divider()

                // Record Spreadsheet Viewer
                if let table = selectedTable {
                    DatabaseRecordViewer(table: table)
                } else {
                    ContentUnavailableView("Select a table", systemImage: "tablecells", description: Text("Choose a database table to view and edit its records."))
                }
            }
        }
        .onAppear {
            loadTables()
        }
        .onChange(of: connManager.activeConnection) {
            selectedTable = nil
            loadTables()
        }
        .sheet(isPresented: $showingCreateForm) {
            DatabaseTableEditor(onSave: {
                loadTables()
                showingCreateForm = false
            })
            .frame(width: 600, height: 500)
        }
    }

    private func loadTables() {
        guard let conn = connManager.activeConnection else { return }
        isLoading = true

        Task {
            do {
                if conn.provider == .sqlite {
                    if let path = conn.sqliteFilePath {
                        tables = try DatabaseManager.shared.fetchSQLiteTables(filePath: path)
                    }
                } else if conn.provider == .supabase {
                    tables = try await SupabaseService.shared.fetchTables(connection: conn)
                }
            } catch {
                print("Failed to load tables: \(error.localizedDescription)")
            }
            isLoading = false
        }
    }
}
