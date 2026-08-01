import SwiftUI

struct DatabaseTablesView: View {
    @EnvironmentObject var connManager: DatabaseConnectionManager
    @Binding var selectedTable: DatabaseTable?
    @State private var tables: [DatabaseTable] = []
    @State private var isLoading = false
    @State private var showingCreateForm = false

    // Switch between Spreadsheet and Triggers/Views Manager
    @State private var selectedMode = 0 // 0 = Data Spreadsheet, 1 = Trigger & View Manager

    // Triggers and Views states
    @State private var dbTriggers: [[String: String]] = []
    @State private var dbViews: [[String: String]] = []
    @State private var selectedTrigger: [String: String]?
    @State private var selectedView: [String: String]?
    @State private var newObjectType = "View" // View, Trigger
    @State private var newObjectName = "v_users_active"
    @State private var newObjectSQL = "CREATE VIEW v_users_active AS\nSELECT * FROM users WHERE status = 'active';"
    @State private var showCreateObjectSheet = false
    @State private var objectError = ""

    var body: some View {
        VStack(spacing: 0) {
            // Table selector bar
            HStack(spacing: 16) {
                Text("Tables & Views")
                    .font(.headline)

                Picker("", selection: $selectedMode) {
                    Text("Data Spreadsheet").tag(0)
                    Text("Triggers & Views").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 280)

                Spacer()

                if selectedMode == 0 {
                    Button {
                        showingCreateForm = true
                    } label: {
                        Label("Add Table", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        showCreateObjectSheet = true
                    } label: {
                        Label("Create Trigger/View", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(12)
            .background(Color.secondary.opacity(0.05))

            Divider()

            if selectedMode == 0 {
                // Spreadsheet mode
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
            } else {
                // Trigger & View Manager
                triggerAndViewManagerPane()
            }
        }
        .onAppear {
            loadTables()
            loadTriggersAndViews()
        }
        .onChange(of: connManager.activeConnection) {
            selectedTable = nil
            loadTables()
            loadTriggersAndViews()
        }
        .sheet(isPresented: $showingCreateForm) {
            DatabaseTableEditor(onSave: {
                loadTables()
                showingCreateForm = false
            })
            .frame(width: 600, height: 500)
        }
        .sheet(isPresented: $showCreateObjectSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Create New Trigger or View")
                    .font(.headline)

                Picker("Object Type", selection: $newObjectType) {
                    Text("SQL View").tag("View")
                    Text("Database Trigger").tag("Trigger")
                }
                .pickerStyle(.segmented)
                .onChange(of: newObjectType) { _, newValue in
                    if newValue == "View" {
                        newObjectName = "v_users_active"
                        newObjectSQL = "CREATE VIEW v_users_active AS\nSELECT * FROM users WHERE status = 'active';"
                    } else {
                        newObjectName = "tr_audit_users"
                        newObjectSQL = "CREATE TRIGGER tr_audit_users AFTER INSERT ON users\nBEGIN\n  -- Insert auditing actions here\nEND;"
                    }
                }

                Form {
                    TextField("Name", text: $newObjectName)
                }
                .formStyle(.grouped)

                Text("Definition SQL:")
                    .font(.subheadline.bold())
                TextEditor(text: $newObjectSQL)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 160)
                    .border(Color.secondary.opacity(0.2))

                if !objectError.isEmpty {
                    Text(objectError)
                        .foregroundColor(.red)
                        .font(.caption)
                }

                HStack {
                    Button("Cancel") { showCreateObjectSheet = false; objectError = "" }
                        .buttonStyle(.bordered)

                    Spacer()

                    Button("Create Object") {
                        executeCreateObject()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(width: 500, height: 480)
        }
    }

    // MARK: - Trigger & View Manager UI Pane
    @ViewBuilder
    private func triggerAndViewManagerPane() -> some View {
        HSplitView {
            // Left list of triggers & views
            VStack(alignment: .leading, spacing: 0) {
                Text("SQL VIEWS")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                if dbViews.isEmpty {
                    Text("No custom views defined")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(12)
                } else {
                    List(dbViews, id: \.self, selection: Binding(
                        get: { selectedView },
                        set: { selectedView = $0; selectedTrigger = nil }
                    )) { viewItem in
                        HStack {
                            Image(systemName: "eye.fill")
                                .foregroundColor(.purple)
                            Text(viewItem["name"] ?? "")
                                .font(.subheadline)
                        }
                        .tag(viewItem)
                    }
                    .frame(height: 180)
                }

                Divider()

                Text("DATABASE TRIGGERS")
                    .font(.caption2.bold())
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                if dbTriggers.isEmpty {
                    Text("No triggers defined")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(12)
                } else {
                    List(dbTriggers, id: \.self, selection: Binding(
                        get: { selectedTrigger },
                        set: { selectedTrigger = $0; selectedView = nil }
                    )) { trigItem in
                        HStack {
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading) {
                                Text(trigItem["name"] ?? "")
                                    .font(.subheadline.bold())
                                Text("on: " + (trigItem["tbl_name"] ?? ""))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .tag(trigItem)
                    }
                    .frame(height: 180)
                }
                Spacer()
            }
            .frame(width: 250)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Detail / Code viewer
            VStack(spacing: 0) {
                if let view = selectedView {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("SQL VIEW: \(view["name"] ?? "")", systemImage: "eye")
                                .font(.headline)
                            Spacer()
                            Button("Drop View", role: .destructive) {
                                executeDropObject(type: "VIEW", name: view["name"] ?? "")
                            }
                            .buttonStyle(.bordered)
                        }

                        Divider()

                        Text("Definition SQL:")
                            .font(.subheadline.bold())
                        ScrollView {
                            Text(view["sql"] ?? "No SQL defined.")
                                .font(.system(.body, design: .monospaced))
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.15))
                                .cornerRadius(8)
                        }
                    }
                    .padding(16)
                } else if let trig = selectedTrigger {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("TRIGGER: \(trig["name"] ?? "")", systemImage: "bolt")
                                .font(.headline)
                            Spacer()
                            Button("Drop Trigger", role: .destructive) {
                                executeDropObject(type: "TRIGGER", name: trig["name"] ?? "")
                            }
                            .buttonStyle(.bordered)
                        }

                        Divider()

                        Text("On Table: **\(trig["tbl_name"] ?? "")**")

                        Text("Definition SQL:")
                            .font(.subheadline.bold())
                        ScrollView {
                            Text(trig["sql"] ?? "No SQL defined.")
                                .font(.system(.body, design: .monospaced))
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.15))
                                .cornerRadius(8)
                        }
                    }
                    .padding(16)
                } else {
                    ContentUnavailableView("Select Object", systemImage: "bolt.eye", description: Text("Choose an existing SQL View or database Trigger to inspect definition code or perform maintenance."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private func loadTriggersAndViews() {
        guard let conn = connManager.activeConnection, conn.provider == .sqlite, let path = conn.sqliteFilePath else { return }

        Task {
            do {
                let viewSql = "SELECT name, sql FROM sqlite_master WHERE type='view';"
                dbViews = try DatabaseManager.shared.executeSQLiteQuery(filePath: path, sql: viewSql)

                let trigSql = "SELECT name, tbl_name, sql FROM sqlite_master WHERE type='trigger';"
                dbTriggers = try DatabaseManager.shared.executeSQLiteQuery(filePath: path, sql: trigSql)
            } catch {
                print("Failed to load triggers/views: \(error.localizedDescription)")
            }
        }
    }

    private func executeCreateObject() {
        guard let conn = connManager.activeConnection, conn.provider == .sqlite, let path = conn.sqliteFilePath else { return }

        Task {
            do {
                _ = try DatabaseManager.shared.executeSQLiteQuery(filePath: path, sql: newObjectSQL)
                await MainActor.run {
                    showCreateObjectSheet = false
                    objectError = ""
                    loadTriggersAndViews()
                    loadTables()
                }
            } catch {
                await MainActor.run {
                    objectError = error.localizedDescription
                }
            }
        }
    }

    private func executeDropObject(type: String, name: String) {
        guard let conn = connManager.activeConnection, conn.provider == .sqlite, let path = conn.sqliteFilePath else { return }

        Task {
            do {
                let dropSql = "DROP \(type) IF EXISTS \(name);"
                _ = try DatabaseManager.shared.executeSQLiteQuery(filePath: path, sql: dropSql)
                await MainActor.run {
                    selectedView = nil
                    selectedTrigger = nil
                    loadTriggersAndViews()
                    loadTables()
                }
            } catch {
                print("Drop object error: \(error.localizedDescription)")
            }
        }
    }
}
