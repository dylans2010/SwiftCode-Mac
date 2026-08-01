import SwiftUI

struct DatabaseTemplatesView: View {
    @EnvironmentObject var connManager: DatabaseConnectionManager
    @StateObject private var templateManager = DatabaseTemplateManager.shared
    @State private var searchQuery = ""
    @State private var alertMessage = ""
    @State private var showingAlert = false

    // Panel tab selection
    @State private var selectedTab = 0 // 0 = Layout Templates, 1 = Seed Data Generator

    // Seed Generator states
    @State private var tablesList: [DatabaseTable] = []
    @State private var selectedSeedTable = ""
    @State private var rowsCountToGenerate = 25
    @State private var isGeneratingSeeds = false
    @State private var generationLog = ""

    var filteredTemplates: [DatabaseTemplate] {
        if searchQuery.isEmpty { return templateManager.templates }
        return templateManager.templates.filter {
            $0.name.localizedCaseInsensitiveContains(searchQuery) ||
            $0.description.localizedCaseInsensitiveContains(searchQuery)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Mode Selectors
            Picker("", selection: $selectedTab) {
                Text("Database Structural Templates").tag(0)
                Text("Synthetic Seed Data Generator").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(14)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if selectedTab == 0 {
                // Templates Grid List
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search structural templates...", text: $searchQuery)
                            .textFieldStyle(.plain)
                    }
                    .padding()
                    .background(Color.secondary.opacity(0.06))

                    Divider()

                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220))], spacing: 16) {
                            ForEach(filteredTemplates) { template in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Image(systemName: "square.stack.3d.up.fill")
                                            .foregroundColor(.blue)
                                        Text(template.name)
                                            .font(.headline)
                                        Spacer()
                                        Button(action: { templateManager.toggleFavorite(template) }) {
                                            Image(systemName: template.isFavorite ? "star.fill" : "star")
                                                .foregroundColor(.yellow)
                                        }
                                        .buttonStyle(.plain)
                                    }

                                    Text(template.description)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(3)
                                        .frame(height: 42, alignment: .top)

                                    HStack {
                                        ForEach(template.tags, id: \.self) { tag in
                                            Text(tag)
                                                .font(.system(size: 8))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.blue.opacity(0.12), in: Capsule())
                                        }
                                    }

                                    Button("Apply Template Schema") {
                                        applyTemplate(template)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                                .padding()
                                .background(Color.secondary.opacity(0.08))
                                .cornerRadius(8)
                            }
                        }
                        .padding()
                    }
                }
            } else {
                // Seed Data Generator View
                seedGeneratorPane()
            }
        }
        .onAppear {
            loadTablesList()
        }
        .onChange(of: connManager.activeConnection) {
            loadTablesList()
        }
        .alert("Schema Status", isPresented: $showingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Seed Data Generator UI Pane
    @ViewBuilder
    private func seedGeneratorPane() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Image(systemName: "cube.fill")
                        .font(.title2)
                        .foregroundColor(.green)
                    Text("Synthetic Seed Data Generator")
                        .font(.title2.bold())
                }

                Text("Instantly generate high-fidelity synthetic mock records based on active target table constraints, identifying names, contact emails, currency amounts, UUIDs, and timestamps automatically.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                GroupBox("Generation Setup") {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 24) {
                            Picker("Target Table:", selection: $selectedSeedTable) {
                                if tablesList.isEmpty {
                                    Text("No tables discovered").tag("")
                                } else {
                                    ForEach(tablesList) { t in
                                        Text(t.name).tag(t.name)
                                    }
                                }
                            }
                            .frame(width: 250)

                            Picker("Rows count:", selection: $rowsCountToGenerate) {
                                Text("5 records").tag(5)
                                Text("25 records").tag(25)
                                Text("100 records").tag(100)
                                Text("500 records").tag(500)
                            }
                            .frame(width: 180)
                        }

                        Button(action: generateSeedData) {
                            if isGeneratingSeeds {
                                HStack {
                                    ProgressView().scaleEffect(0.6)
                                    Text("Inserting Records...")
                                }
                            } else {
                                Label("Generate & Seed Dataset", systemImage: "bolt.fill")
                                    .foregroundColor(.white)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .disabled(isGeneratingSeeds || selectedSeedTable.isEmpty)
                    }
                    .padding(8)
                }

                if !generationLog.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Seed Database Logs:")
                            .font(.subheadline.bold())
                        ScrollView {
                            Text(generationLog)
                                .font(.system(.body, design: .monospaced))
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.15))
                                .cornerRadius(8)
                        }
                        .frame(height: 220)
                    }
                }
            }
            .padding(20)
        }
    }

    // MARK: - Logic Operations
    private func loadTablesList() {
        guard let conn = connManager.activeConnection, conn.provider == .sqlite, let path = conn.sqliteFilePath else { return }
        Task {
            if let t = try? DatabaseManager.shared.fetchSQLiteTables(filePath: path) {
                tablesList = t
                selectedSeedTable = t.first?.name ?? ""
            }
        }
    }

    private func applyTemplate(_ template: DatabaseTemplate) {
        guard let conn = connManager.activeConnection else {
            alertMessage = "No active database connection selected. Please activate a connection first."
            showingAlert = true
            return
        }

        Task {
            var appliedCount = 0
            var errorOccurred = false
            var lastErrorMessage = ""

            for table in template.tables {
                do {
                    try await DatabaseSchemaManager.shared.createTable(connection: conn, table: table)
                    appliedCount += 1
                } catch {
                    errorOccurred = true
                    lastErrorMessage = error.localizedDescription
                }
            }

            await MainActor.run {
                if errorOccurred {
                    alertMessage = "Successfully applied \(appliedCount) tables. Error applying remaining: \(lastErrorMessage)"
                } else {
                    alertMessage = "Successfully applied \(appliedCount) tables from template '\(template.name)' to connection '\(conn.name)'!"
                }
                showingAlert = true
                loadTablesList()
            }
        }
    }

    private func generateSeedData() {
        guard let conn = connManager.activeConnection, conn.provider == .sqlite, let path = conn.sqliteFilePath else { return }
        guard let targetTableObj = tablesList.first(where: { $0.name == selectedSeedTable }) else { return }

        isGeneratingSeeds = true
        generationLog = "Analyzing schema columns in '\(selectedSeedTable)'...\n"

        Task {
            let names = ["Alice Smith", "Bob Jones", "Charlie Brown", "Diana Prince", "Evan Wright", "Fiona Gallagher", "George Clark", "Hannah Abbott"]
            let domains = ["example.com", "swiftcode.org", "apple.dev", "icloud.com"]
            let products = ["Laptop Pro", "Developer Keyboard", "USB-C Hub", "UltraWide Screen", "Trackpad", "Ergonomic Mouse"]
            let statuses = ["active", "pending", "inactive", "completed", "cancelled"]

            var inserted = 0
            var errors = 0

            for index in 1...rowsCountToGenerate {
                let columnsList = targetTableObj.columns.filter { !$0.isPrimaryKey || !$0.isAutoIncrement }
                let colNames = columnsList.map { $0.name }.joined(separator: ", ")

                let colValues = columnsList.map { col -> String in
                    let lowerName = col.name.lowercased()
                    let colType = col.type.lowercased()

                    if lowerName.contains("email") {
                        let safeName = names.randomElement()!.replacingOccurrences(of: " ", with: "").lowercased()
                        return "'\(safeName)\(index)@\(domains.randomElement()!)'"
                    } else if lowerName.contains("name") {
                        if lowerName.contains("product") {
                            return "'\(products.randomElement()!)'"
                        }
                        return "'\(names.randomElement()!)'"
                    } else if lowerName.contains("uuid") {
                        return "'\(UUID().uuidString)'"
                    } else if lowerName.contains("status") {
                        return "'\(statuses.randomElement()!)'"
                    } else if colType.contains("int") {
                        return "\(Int.random(in: 1...10000))"
                    } else if colType.contains("real") || colType.contains("double") || colType.contains("float") {
                        return "\(Double.random(in: 9.99...1499.99))"
                    } else if colType.contains("date") || colType.contains("time") {
                        return "CURRENT_TIMESTAMP"
                    } else if colType.contains("bool") {
                        return "\(Int.random(in: 0...1))"
                    } else {
                        return "'Mock \(col.name) Value \(index)'"
                    }
                }.joined(separator: ", ")

                let sql = "INSERT INTO \(selectedSeedTable) (\(colNames)) VALUES (\(colValues));"
                do {
                    _ = try DatabaseManager.shared.executeSQLiteQuery(filePath: path, sql: sql)
                    inserted += 1
                } catch {
                    errors += 1
                    generationLog += "Error executing insert: \(error.localizedDescription) (SQL: \(sql))\n"
                }
            }

            await MainActor.run {
                isGeneratingSeeds = false
                generationLog = "Successfully inserted \(inserted) synthetic mock records into '\(selectedSeedTable)'!\nInsertion Errors: \(errors)\n" + generationLog
                alertMessage = "Successfully seeded \(inserted) mock records into '\(selectedSeedTable)'!"
                showingAlert = true
                loadTablesList()
            }
        }
    }
}
