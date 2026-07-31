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

    var body: some View {
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
    }

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
