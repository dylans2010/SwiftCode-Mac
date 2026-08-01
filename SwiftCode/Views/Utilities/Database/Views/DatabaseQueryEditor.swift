import SwiftUI

struct DatabaseQueryEditor: View {
    @EnvironmentObject var connManager: DatabaseConnectionManager
    @State private var query = "SELECT * FROM sqlite_master WHERE type='table';"
    @State private var queryResult: [[String: String]] = []
    @State private var columns: [String] = []
    @State private var executionStats = ""
    @State private var errorMessage = ""
    @State private var isExecuting = false
    @State private var explainOutput = ""

    // AI co-pilot states
    @State private var aiInput = ""
    @State private var aiResponse = ""
    @State private var isGeneratingAI = false

    // Tabs / Panel selectors
    @State private var selectedEditorTab = 0 // 0 = Editor, 1 = History, 2 = Saved & Favorites

    // Save Query Dialog states
    @State private var saveTitle = ""
    @State private var saveCategory = "General"
    @State private var saveTags = "Utility"
    @State private var showSaveSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Upper Editor Navigation / Tab switcher
            HStack {
                Picker("", selection: $selectedEditorTab) {
                    Text("SQL Console").tag(0)
                    Text("Query History").tag(1)
                    Text("Saved Queries & Favorites").tag(2)
                }
                .pickerStyle(.segmented)
                .frame(width: 400)

                Spacer()

                if selectedEditorTab == 0 {
                    Button(action: { showSaveSheet = true }) {
                        Label("Save Script", systemImage: "bookmark")
                    }
                    .buttonStyle(.bordered)
                    .disabled(query.isEmpty)
                }
            }
            .padding(10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if selectedEditorTab == 0 {
                // Main Console Editor View
                VStack(spacing: 0) {
                    // Editor Toolbar
                    HStack {
                        Button(action: runQuery) {
                            Label("Run SQL", systemImage: "play.fill")
                                .foregroundColor(.green)
                        }
                        .disabled(isExecuting)

                        Button(action: runExplain) {
                            Label("Explain Plan", systemImage: "questionmark.circle")
                        }
                        .disabled(isExecuting)

                        Spacer()

                        Button(action: askAICopilot) {
                            Label("AI Optimize", systemImage: "sparkles")
                                .foregroundColor(.purple)
                        }
                        .disabled(query.isEmpty)
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.08))

                    Divider()

                    // SQL Text Editor & AI Panel Split
                    HStack(spacing: 0) {
                        VStack(spacing: 0) {
                            TextEditor(text: $query)
                                .font(.system(.body, design: .monospaced))
                                .frame(height: 180)
                                .padding(4)
                                .background(Color(NSColor.controlBackgroundColor))

                            Divider()

                            // Stats / Errors Panel
                            if !errorMessage.isEmpty {
                                Text(errorMessage)
                                    .foregroundColor(.red)
                                    .font(.caption)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.red.opacity(0.1))
                            } else if !executionStats.isEmpty {
                                Text(executionStats)
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.secondary.opacity(0.05))
                            }

                            Divider()

                            // Results spreadsheet Viewer
                            if !queryResult.isEmpty {
                                ScrollView([.horizontal, .vertical]) {
                                    LazyVStack(alignment: .leading, spacing: 0) {
                                        // Header row
                                        HStack(spacing: 0) {
                                            ForEach(columns, id: \.self) { col in
                                                Text(col)
                                                    .font(.system(size: 11, weight: .bold))
                                                    .padding(6)
                                                    .frame(width: 120, alignment: .leading)
                                                    .background(Color.secondary.opacity(0.15))
                                                    .border(Color.secondary.opacity(0.2), width: 0.5)
                                            }
                                        }

                                        // Records rows
                                        ForEach(0..<queryResult.count, id: \.self) { rowIdx in
                                            let row = queryResult[rowIdx]
                                            HStack(spacing: 0) {
                                                ForEach(columns, id: \.self) { col in
                                                    Text(row[col] ?? "NULL")
                                                        .font(.system(size: 11))
                                                        .padding(6)
                                                        .frame(width: 120, alignment: .leading)
                                                        .border(Color.secondary.opacity(0.1), width: 0.5)
                                                }
                                            }
                                            .background(rowIdx % 2 == 0 ? Color.clear : Color.secondary.opacity(0.03))
                                        }
                                    }
                                }
                            } else if !explainOutput.isEmpty {
                                ScrollView {
                                    Text(explainOutput)
                                        .font(.system(.body, design: .monospaced))
                                        .padding()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            } else {
                                ContentUnavailableView("No query results", systemImage: "terminal", description: Text("Run an SQL statement to view and inspect records details."))
                            }
                        }

                        // AI Co-pilot Suggestions Sidebar panel
                        if !aiResponse.isEmpty || isGeneratingAI {
                            Divider()

                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Image(systemName: "sparkles")
                                        .foregroundColor(.purple)
                                    Text("AI SQL Assistant")
                                        .font(.headline)
                                    Spacer()
                                    Button(action: { aiResponse = "" }) {
                                        Image(systemName: "xmark")
                                    }
                                    .buttonStyle(.plain)
                                }

                                if isGeneratingAI {
                                    ProgressView("Optimizing query...")
                                        .padding()
                                } else {
                                    ScrollView {
                                        Text(aiResponse)
                                            .font(.caption)
                                            .padding()
                                            .background(Color.purple.opacity(0.08))
                                            .cornerRadius(6)
                                    }
                                }
                            }
                            .frame(width: 250)
                            .padding()
                            .background(Color.secondary.opacity(0.04))
                        }
                    }
                }
            } else if selectedEditorTab == 1 {
                // SQL Query History view
                queryHistoryPane()
            } else {
                // Saved & Bookmarked Queries
                savedQueriesPane()
            }
        }
        .sheet(isPresented: $showSaveSheet) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Save Active SQL Script")
                    .font(.headline)

                Form {
                    TextField("Script Title", text: $saveTitle)
                    TextField("Category", text: $saveCategory)
                    TextField("Tags (comma separated)", text: $saveTags)
                }
                .formStyle(.grouped)

                HStack {
                    Button("Cancel") { showSaveSheet = false }
                        .buttonStyle(.bordered)
                    Spacer()
                    Button("Save Snippet") {
                        let tagsList = saveTags.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
                        DatabaseHistoryService.shared.saveQuery(title: saveTitle, sql: query, category: saveCategory, tags: tagsList)
                        showSaveSheet = false
                        selectedEditorTab = 2
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(saveTitle.isEmpty)
                }
            }
            .padding()
            .frame(width: 400, height: 260)
        }
    }

    // MARK: - Query History Pane
    @ViewBuilder
    private func queryHistoryPane() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Executed Queries Log")
                        .font(.headline)
                    Text("Double click or select a record to restore raw SQL to the compiler console.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button("Purge Logs", role: .destructive) {
                    DatabaseHistoryService.shared.clearHistory()
                }
                .buttonStyle(.bordered)
            }
            .padding(14)
            .background(Color.secondary.opacity(0.04))

            Divider()

            let historyList = DatabaseHistoryService.shared.fetchHistory()
            if historyList.isEmpty {
                ContentUnavailableView("No Executed History", systemImage: "clock", description: Text("Executed SQL statements will be logged here with timers and execution status."))
            } else {
                List(historyList) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            ZStack {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(item.status == "SUCCESS" ? Color.green.opacity(0.12) : Color.red.opacity(0.12))
                                    .frame(width: 64, height: 18)
                                Text(item.status)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(item.status == "SUCCESS" ? .green : .red)
                            }

                            Text("Duration: \(String(format: "%.2f", item.executionTimeMs)) ms")
                                .font(.caption2.monospaced())
                                .foregroundColor(.secondary)

                            Spacer()

                            Text(item.timestamp, style: .time)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }

                        Text(item.sql)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(2)
                            .padding(8)
                            .background(Color.black.opacity(0.15))
                            .cornerRadius(4)

                        if let err = item.errorMessage {
                            Text("Error message: \(err)")
                                .font(.caption2)
                                .foregroundColor(.red)
                        }

                        HStack {
                            Button("Copy to Console") {
                                query = item.sql
                                selectedEditorTab = 0
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("Rerun Query") {
                                query = item.sql
                                selectedEditorTab = 0
                                runQuery()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: - Saved Queries Pane
    @ViewBuilder
    private func savedQueriesPane() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Saved Queries & Favorites Library")
                        .font(.headline)
                    Text("Instant-access collection of frequently executed procedures, migration statements, or schema audits.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(14)
            .background(Color.secondary.opacity(0.04))

            Divider()

            let savedList = DatabaseHistoryService.shared.fetchSavedQueries()
            if savedList.isEmpty {
                ContentUnavailableView("Library Empty", systemImage: "star", description: Text("Save queries using 'Save Script' button inside raw SQL Console."))
            } else {
                List(savedList) { item in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(item.title)
                                .font(.headline)

                            if item.isFavorite {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                            }

                            Spacer()

                            Text(item.category)
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.15), in: Capsule())
                        }

                        Text(item.sql)
                            .font(.system(.body, design: .monospaced))
                            .padding(8)
                            .background(Color.black.opacity(0.15))
                            .cornerRadius(4)

                        HStack {
                            ForEach(item.tags, id: \.self) { tag in
                                Text("#" + tag)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }

                        HStack {
                            Button("Open in Console") {
                                query = item.sql
                                selectedEditorTab = 0
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button(item.isFavorite ? "Unfavorite" : "Favorite") {
                                DatabaseHistoryService.shared.toggleSavedQueryFavorite(id: item.id)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Spacer()

                            Button("Delete", role: .destructive) {
                                DatabaseHistoryService.shared.deleteSavedQuery(id: item.id)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.red)
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: - Handlers & Actions
    private func runQuery() {
        guard let conn = connManager.activeConnection else { return }
        isExecuting = true
        errorMessage = ""
        explainOutput = ""

        let startTime = Date()

        Task {
            do {
                if conn.provider == .sqlite {
                    guard let path = conn.sqliteFilePath else { return }
                    let rows = try DatabaseManager.shared.executeSQLiteQuery(filePath: path, sql: query)
                    if let first = rows.first {
                        self.columns = Array(first.keys).sorted()
                    }
                    self.queryResult = rows

                    let duration = Date().timeIntervalSince(startTime) * 1000
                    executionStats = "Success: \(rows.count) rows returned in \(String(format: "%.2f", duration)) ms."

                    DatabaseHistoryService.shared.addHistoryItem(QueryHistoryItem(
                        sql: query,
                        executionTimeMs: duration,
                        rowsAffected: rows.count,
                        status: "SUCCESS"
                    ))
                } else if conn.provider == .supabase {
                    let log = try await SupabaseService.shared.executeSQL(connection: conn, sql: query)
                    executionStats = log
                    queryResult = []

                    let duration = Date().timeIntervalSince(startTime) * 1000
                    DatabaseHistoryService.shared.addHistoryItem(QueryHistoryItem(
                        sql: query,
                        executionTimeMs: duration,
                        rowsAffected: 0,
                        status: "SUCCESS"
                    ))
                }
            } catch {
                errorMessage = error.localizedDescription
                DatabaseHistoryService.shared.addHistoryItem(QueryHistoryItem(
                    sql: query,
                    executionTimeMs: 0,
                    rowsAffected: 0,
                    status: "ERROR",
                    errorMessage: error.localizedDescription
                ))
            }
            isExecuting = false
        }
    }

    private func runExplain() {
        guard let conn = connManager.activeConnection, conn.provider == .sqlite, let path = conn.sqliteFilePath else { return }
        isExecuting = true
        errorMessage = ""
        queryResult = []

        Task {
            do {
                let explainSql = "EXPLAIN QUERY PLAN " + query
                let rows = try DatabaseManager.shared.executeSQLiteQuery(filePath: path, sql: explainSql)
                var output = ""
                for row in rows {
                    output += (row["detail"] ?? "") + "\n"
                }
                explainOutput = output.isEmpty ? "No explain details returned." : output
            } catch {
                errorMessage = error.localizedDescription
            }
            isExecuting = false
        }
    }

    private func askAICopilot() {
        isGeneratingAI = true
        aiResponse = "Generating..."

        Task {
            do {
                aiResponse = try await DatabaseAIService.shared.explainSQL(sql: query)
            } catch {
                aiResponse = "Error: \(error.localizedDescription)"
            }
            isGeneratingAI = false
        }
    }
}
