import SwiftUI

struct DatabaseImportExportView: View {
    @EnvironmentObject var connManager: DatabaseConnectionManager
    @State private var selectedTab = 0 // 0 = Import, 1 = Export

    // Import states
    @State private var importFormat = "CSV" // CSV, JSON
    @State private var importText = "id,name,email\n1,Alex,alex@example.com\n2,Emma,emma@example.com"
    @State private var targetTable = ""
    @State private var tables: [DatabaseTable] = []
    @State private var parsedColumns: [String] = []
    @State private var parsedRows: [[String: String]] = []
    @State private var validationLog = ""
    @State private var importMessage = ""
    @State private var isImporting = false

    // Export states
    @State private var exportTable = ""
    @State private var exportFormat = "JSON" // JSON, CSV, SQL DDL, SQL Inserts, XML, Markdown
    @State private var csvDelimiter = ","
    @State private var customFileName = "export_data"
    @State private var exportLog = ""
    @State private var isExporting = false
    @State private var exportProgress: Double = 0.0

    var body: some View {
        VStack(spacing: 0) {
            // Mode Selector
            Picker("Action", selection: $selectedTab) {
                Text("Data Import Center").tag(0)
                Text("Data Export Center").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(14)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if selectedTab == 0 {
                        // Data Import Center
                        importCenterPane()
                    } else {
                        // Data Export Center
                        exportCenterPane()
                    }
                }
                .padding(20)
            }
        }
        .onAppear {
            loadTables()
        }
        .onChange(of: connManager.activeConnection) {
            loadTables()
        }
    }

    // MARK: - Import Center Pane
    @ViewBuilder
    private func importCenterPane() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "square.and.arrow.down.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                Text("Database Import Center")
                    .font(.title2.bold())
            }

            Text("Ingest high-density spreadsheets, webhooks payloads, or static mock files directly into your active SQLite tables. Parses structure schema validations automatically.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 16) {
                Picker("Target Table", selection: $targetTable) {
                    ForEach(tables) { t in
                        Text(t.name).tag(t.name)
                    }
                }
                .frame(width: 250)

                Picker("Source Format", selection: $importFormat) {
                    Text("CSV Spreadsheet").tag("CSV")
                    Text("JSON Payload").tag("JSON")
                }
                .frame(width: 250)

                Button("Auto-Detect Schema") {
                    parseAndPreview()
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Source Data Editor:")
                    .font(.subheadline.bold())
                TextEditor(text: $importText)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 140)
                    .padding(4)
                    .border(Color.secondary.opacity(0.2))
                    .cornerRadius(4)
            }

            HStack {
                Button(action: parseAndPreview) {
                    Label("Parse & Validate Data", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)

                Spacer()

                if !parsedRows.isEmpty {
                    Button(action: executeImport) {
                        if isImporting {
                            ProgressView().scaleEffect(0.6).padding(.horizontal, 8)
                        } else {
                            Label("Commit Import (\(parsedRows.count) Rows)", systemImage: "play.fill")
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(isImporting || targetTable.isEmpty)
                }
            }

            // Preview parsed grid
            if !parsedRows.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Parsed Records Preview (Top 5 rows)")
                        .font(.subheadline.bold())
                        .foregroundColor(.blue)

                    ScrollView(.horizontal) {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 0) {
                                ForEach(parsedColumns, id: \.self) { col in
                                    Text(col)
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(6)
                                        .frame(width: 110, alignment: .leading)
                                        .background(Color.secondary.opacity(0.15))
                                        .border(Color.secondary.opacity(0.2), width: 0.5)
                                }
                            }

                            ForEach(0..<min(5, parsedRows.count), id: \.self) { idx in
                                let row = parsedRows[idx]
                                HStack(spacing: 0) {
                                    ForEach(parsedColumns, id: \.self) { col in
                                        Text(row[col] ?? "NULL")
                                            .font(.system(size: 10))
                                            .padding(6)
                                            .frame(width: 110, alignment: .leading)
                                            .border(Color.secondary.opacity(0.1), width: 0.5)
                                    }
                                }
                                .background(idx % 2 == 0 ? Color.clear : Color.secondary.opacity(0.02))
                            }
                        }
                    }
                    .border(Color.secondary.opacity(0.2))
                    .cornerRadius(6)
                }
            }

            if !validationLog.isEmpty {
                GroupBox("Schema Integrity & Validation Scores") {
                    Text(validationLog)
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.orange)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !importMessage.isEmpty {
                GroupBox("Import Execution Terminal Logs") {
                    ScrollView {
                        Text(importMessage)
                            .font(.system(.body, design: .monospaced))
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 100)
                }
            }
        }
    }

    // MARK: - Export Center Pane
    @ViewBuilder
    private func exportCenterPane() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "square.and.arrow.up.fill")
                    .font(.title2)
                    .foregroundColor(.purple)
                Text("Database Export Center")
                    .font(.title2.bold())
            }

            Text("Compile clean SQL scripts, compressed JSON configurations, structured CSV files, or raw XML datasets from active database table partitions asynchronously.")
                .font(.caption)
                .foregroundColor(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                GridRow {
                    Text("Select Table:")
                        .font(.subheadline.bold())
                    Picker("", selection: $exportTable) {
                        ForEach(tables) { t in
                            Text(t.name).tag(t.name)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 250)
                }

                GridRow {
                    Text("Target Format:")
                        .font(.subheadline.bold())
                    Picker("", selection: $exportFormat) {
                        Text("JSON Array Dump").tag("JSON")
                        Text("CSV Spreadsheet").tag("CSV")
                        Text("SQL Schema DDL").tag("SQL DDL")
                        Text("SQL Inserts Script").tag("SQL Inserts")
                        Text("XML Document").tag("XML")
                        Text("Markdown Dataset Table").tag("Markdown")
                    }
                    .labelsHidden()
                    .frame(width: 250)
                }

                if exportFormat == "CSV" {
                    GridRow {
                        Text("CSV Delimiter:")
                            .font(.subheadline.bold())
                        Picker("", selection: $csvDelimiter) {
                            Text("Comma ( , )").tag(",")
                            Text("Semicolon ( ; )").tag(";")
                            Text("Tab Space").tag("\t")
                        }
                        .labelsHidden()
                        .frame(width: 250)
                    }
                }

                GridRow {
                    Text("Filename prefix:")
                        .font(.subheadline.bold())
                    TextField("Enter filename...", text: $customFileName)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 250)
                }
            }

            Button(action: executeExport) {
                if isExporting {
                    HStack {
                        ProgressView().scaleEffect(0.6)
                        Text("Compressing & Exporting...")
                    }
                } else {
                    Label("Execute Asynchronous Export", systemImage: "shippingbox.fill")
                        .foregroundColor(.white)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .disabled(isExporting || exportTable.isEmpty)

            if isExporting {
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: exportProgress, total: 1.0)
                        .tint(.purple)
                    Text("Export process queue is parsing rows: \(Int(exportProgress * 100))% complete")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if !exportLog.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Compiled Output Preview:")
                        .font(.subheadline.bold())
                    ScrollView {
                        Text(exportLog)
                            .font(.system(.body, design: .monospaced))
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.black.opacity(0.15))
                            .cornerRadius(8)
                            .textSelection(.enabled)
                    }
                    .frame(height: 250)
                }
            }
        }
    }

    // MARK: - Logic Operations
    private func loadTables() {
        guard let conn = connManager.activeConnection, conn.provider == .sqlite, let path = conn.sqliteFilePath else { return }
        Task {
            if let t = try? DatabaseManager.shared.fetchSQLiteTables(filePath: path) {
                tables = t
                targetTable = t.first?.name ?? ""
                exportTable = t.first?.name ?? ""
            }
        }
    }

    private func parseAndPreview() {
        parsedColumns = []
        parsedRows = []
        validationLog = ""
        importMessage = ""

        let trimmed = importText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if importFormat == "CSV" {
            let (cols, rows) = DatabaseImportManager.shared.parseCSV(content: trimmed)
            parsedColumns = cols
            parsedRows = rows
        } else {
            // JSON parsing
            guard let data = trimmed.data(using: .utf8),
                  let jsonArray = try? JSONSerialization.jsonObject(with: data, options: []) as? [[String: Any]] else {
                validationLog = "Error: Invalid JSON payload format. Must be an array of flat objects."
                return
            }

            guard let first = jsonArray.first else {
                validationLog = "Error: JSON Array payload is empty."
                return
            }

            parsedColumns = first.keys.sorted()
            var rowsList: [[String: String]] = []
            for obj in jsonArray {
                var rowDict: [String: String] = [:]
                for col in parsedColumns {
                    if let val = obj[col] {
                        rowDict[col] = String(describing: val)
                    }
                }
                rowsList.append(rowDict)
            }
            parsedRows = rowsList
        }

        // Match against targetTable schema column names & constraints
        if let currentTable = tables.first(where: { $0.name == targetTable }) {
            var issues: [String] = []
            let targetCols = Set(currentTable.columns.map { $0.name })

            for col in parsedColumns {
                if !targetCols.contains(col) {
                    issues.append("⚠️ Column '\(col)' in imported dataset does not exist in database table '\(targetTable)'. It will be ignored.")
                }
            }

            for col in currentTable.columns {
                if !col.isNullable && !col.isAutoIncrement && col.defaultValue == nil && !parsedColumns.contains(col.name) {
                    issues.append("🚨 Missing required non-nullable column '\(col.name)' in source dataset! The insert might fail.")
                }
            }

            if issues.isEmpty {
                validationLog = "✅ All \(parsedColumns.count) parsed columns perfectly match database schema configuration. Clean insert."
            } else {
                validationLog = issues.joined(separator: "\n")
            }
        }
    }

    private func executeImport() {
        guard let conn = connManager.activeConnection, conn.provider == .sqlite, let path = conn.sqliteFilePath else { return }
        guard !targetTable.isEmpty && !parsedRows.isEmpty else { return }

        isImporting = true
        importMessage = ""

        Task {
            var inserted = 0
            var errors = 0

            // Build statements
            for row in parsedRows {
                let columnsList = parsedColumns.filter { col in
                    if let tableObj = tables.first(where: { $0.name == targetTable }) {
                        return tableObj.columns.contains { $0.name == col }
                    }
                    return true
                }

                let colNames = columnsList.joined(separator: ", ")
                let colValues = columnsList.map { col -> String in
                    if let val = row[col] {
                        let escaped = val.replacingOccurrences(of: "'", with: "''")
                        return "'\(escaped)'"
                    }
                    return "NULL"
                }.joined(separator: ", ")

                let sql = "INSERT INTO \(targetTable) (\(colNames)) VALUES (\(colValues));"
                do {
                    _ = try DatabaseManager.shared.executeSQLiteQuery(filePath: path, sql: sql)
                    inserted += 1
                } catch {
                    errors += 1
                    importMessage += "Error: \(error.localizedDescription) on SQL: \(sql)\n"
                }
            }

            isImporting = false
            importMessage = "Commit Completed!\nRows inserted successfully: \(inserted)\nRow insertion errors: \(errors)\n" + importMessage
            loadTables()
        }
    }

    private func executeExport() {
        guard let conn = connManager.activeConnection, conn.provider == .sqlite, let path = conn.sqliteFilePath else { return }
        guard let targetTableObj = tables.first(where: { $0.name == exportTable }) else { return }

        isExporting = true
        exportProgress = 0.0
        exportLog = ""

        Task {
            do {
                try await Task.sleep(nanoseconds: 300_000_000)
                await MainActor.run { exportProgress = 0.3 }

                let query = "SELECT * FROM \(exportTable);"
                let rows = try DatabaseManager.shared.executeSQLiteQuery(filePath: path, sql: query)

                try await Task.sleep(nanoseconds: 300_000_000)
                await MainActor.run { exportProgress = 0.7 }

                var out = ""
                switch exportFormat {
                case "JSON":
                    if let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted]),
                       let str = String(data: data, encoding: .utf8) {
                        out = str
                    }
                case "CSV":
                    let headers = targetTableObj.columns.map { $0.name }.joined(separator: csvDelimiter)
                    out = headers + "\n"
                    for row in rows {
                        let line = targetTableObj.columns.map { col -> String in
                            let val = row[col.name] ?? ""
                            if val.contains(csvDelimiter) || val.contains("\n") || val.contains("\"") {
                                let escaped = val.replacingOccurrences(of: "\"", with: "\"\"")
                                return "\"\(escaped)\""
                            }
                            return val
                        }.joined(separator: csvDelimiter)
                        out += line + "\n"
                    }
                case "SQL DDL":
                    out = DatabaseExportManager.shared.exportSQLSchema(tables: [targetTableObj], provider: conn.provider)
                case "SQL Inserts":
                    for row in rows {
                        let cols = targetTableObj.columns.map { $0.name }.joined(separator: ", ")
                        let vals = targetTableObj.columns.map { col -> String in
                            if let val = row[col.name] {
                                let escaped = val.replacingOccurrences(of: "'", with: "''")
                                return "'\(escaped)'"
                            }
                            return "NULL"
                        }.joined(separator: ", ")
                        out += "INSERT INTO \(exportTable) (\(cols)) VALUES (\(vals));\n"
                    }
                case "XML":
                    out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<dataset>\n"
                    for row in rows {
                        out += "  <record>\n"
                        for (key, val) in row {
                            out += "    <\(key)>\(val)</\(key)>\n"
                        }
                        out += "  </record>\n"
                    }
                    out += "</dataset>"
                case "Markdown":
                    let headers = targetTableObj.columns.map { $0.name }.joined(separator: " | ")
                    let divider = targetTableObj.columns.map { _ in "---" }.joined(separator: " | ")
                    out = "| \(headers) |\n| \(divider) |\n"
                    for row in rows {
                        let line = targetTableObj.columns.map { row[ $0.name ] ?? "" }.joined(separator: " | ")
                        out += "| \(line) |\n"
                    }
                default:
                    out = "Invalid Format"
                }

                try await Task.sleep(nanoseconds: 300_000_000)
                await MainActor.run {
                    exportProgress = 1.0
                    exportLog = out
                    isExporting = false
                }
            } catch {
                await MainActor.run {
                    exportLog = "Export error: \(error.localizedDescription)"
                    isExporting = false
                }
            }
        }
    }
}
