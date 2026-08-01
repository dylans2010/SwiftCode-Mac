import SwiftUI

struct DatabaseAIPromptItem: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var prompt: String
    var category: String // "Architect", "Generator", "Optimizer"
    var isFavorite: Bool
    var isRecent: Bool
}

struct DatabaseAIHistoryItem: Identifiable, Codable, Hashable {
    let id: UUID
    var promptText: String
    var generatedOutput: String
    var timestamp: Date
}

struct DatabaseAIView: View {
    @State private var prompt = "Create a database architecture for a messaging app."
    @State private var response = ""
    @State private var isGenerating = false
    @State private var copiedText = false
    @State private var promptSearchText = ""

    // Prompt Library & History States
    @State private var promptLibrary: [DatabaseAIPromptItem] = []
    @State private var taskHistory: [DatabaseAIHistoryItem] = []
    @State private var currentOutputCategory = "Schema" // "Schema", "Model", "SQL"

    var filteredPromptLibrary: [DatabaseAIPromptItem] {
        if promptSearchText.isEmpty { return promptLibrary }
        return promptLibrary.filter {
            $0.title.localizedCaseInsensitiveContains(promptSearchText) ||
            $0.prompt.localizedCaseInsensitiveContains(promptSearchText)
        }
    }

    var body: some View {
        HSplitView {
            // Left Workspace: Prompt Libraries, Search & History
            VStack(alignment: .leading, spacing: 14) {
                Text("AI Prompt Library")
                    .font(.headline)
                    .padding(.horizontal, 16)
                    .padding(.top, 14)

                // Search Box
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search preset prompts...", text: $promptSearchText)
                        .textFieldStyle(.plain)
                }
                .padding(8)
                .background(Color.secondary.opacity(0.08))
                .cornerRadius(8)
                .padding(.horizontal, 16)

                Divider()

                List {
                    Section(header: Text("FAVORITE PROMPTS").font(.system(size: 9, weight: .bold))) {
                        let favorites = filteredPromptLibrary.filter { $0.isFavorite }
                        if favorites.isEmpty {
                            Text("No favorite prompts bookmarked")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(favorites) { item in
                                promptLibraryRow(item)
                            }
                        }
                    }

                    Section(header: Text("SCHEMA ARCHITECTS").font(.system(size: 9, weight: .bold))) {
                        let schemaPresets = filteredPromptLibrary.filter { $0.category == "Architect" && !$0.isFavorite }
                        ForEach(schemaPresets) { item in
                            promptLibraryRow(item)
                        }
                    }

                    Section(header: Text("SWIFT MODEL GENERATORS").font(.system(size: 9, weight: .bold))) {
                        let genPresets = filteredPromptLibrary.filter { $0.category == "Generator" && !$0.isFavorite }
                        ForEach(genPresets) { item in
                            promptLibraryRow(item)
                        }
                    }

                    Section(header: Text("PERFORMANCE OPTIMIZERS").font(.system(size: 9, weight: .bold))) {
                        let optPresets = filteredPromptLibrary.filter { $0.category == "Optimizer" && !$0.isFavorite }
                        ForEach(optPresets) { item in
                            promptLibraryRow(item)
                        }
                    }

                    Section(header: Text("CONVERSATION HISTORY").font(.system(size: 9, weight: .bold))) {
                        if taskHistory.isEmpty {
                            Text("No recent queries executed")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(taskHistory) { hist in
                                Button {
                                    prompt = hist.promptText
                                    response = hist.generatedOutput
                                } label: {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(hist.promptText)
                                            .font(.caption.bold())
                                            .lineLimit(1)
                                        Text(hist.timestamp, style: .time)
                                            .font(.system(size: 8))
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.vertical, 4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 260, idealWidth: 280, maxWidth: 320)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Right Workspace: Interactive Studio
            VStack(spacing: 0) {
                // Command Header Bar
                HStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.purple)
                        .font(.title3)

                    Text("AI Database Architect Studio")
                        .font(.headline)

                    Spacer()

                    Picker("Classification:", selection: $currentOutputCategory) {
                        Text("Architecture Schema").tag("Schema")
                        Text("Model Layer").tag("Model")
                        Text("SQL Optimizer").tag("SQL")
                    }
                    .pickerStyle(.menu)
                    .frame(width: 180)
                }
                .padding(14)
                .background(Color.secondary.opacity(0.04))

                Divider()

                // Response Canvas
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if isGenerating {
                            VStack(spacing: 16) {
                                ProgressView()
                                    .controlSize(.large)
                                Text("Database Co-Pilot is assembling indexes and compiling tables...")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.top, 100)
                        } else if !response.isEmpty {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    Label("AI Technical Specification", systemImage: "doc.text.fill")
                                        .font(.subheadline.bold())
                                        .foregroundColor(.purple)

                                    Spacer()

                                    Button(action: copyToClipboard) {
                                        Label(copiedText ? "Copied" : "Copy Specification", systemImage: copiedText ? "checkmark" : "doc.on.doc")
                                    }
                                    .buttonStyle(.bordered)
                                }

                                Divider()

                                Text(response)
                                    .font(.system(.body, design: .monospaced))
                                    .lineSpacing(6)
                                    .padding()
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.black.opacity(0.15))
                                    .cornerRadius(10)
                                    .textSelection(.enabled)
                            }
                            .padding(20)
                        } else {
                            ContentUnavailableView("Ask AI Co-Pilot", systemImage: "sparkles", description: Text("Choose a template from the sidebar or input a custom database task. Senior AI will compile structured schemas, SwiftData model files, or optimize your slow queries instantly."))
                                .padding(.top, 100)
                        }
                    }
                }
                .background(Color(NSColor.controlBackgroundColor))

                Divider()

                // Prompt Input Box
                HStack(spacing: 12) {
                    TextField("Enter custom prompt instructions for the database...", text: $prompt)
                        .textFieldStyle(.roundedBorder)
                        .font(.body)
                        .onSubmit(generateArchitecture)

                    Button(action: generateArchitecture) {
                        Label("Run Co-Pilot", systemImage: "sparkles")
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .disabled(prompt.isEmpty || isGenerating)
                }
                .padding(14)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .onAppear {
            loadPromptLibrary()
            loadHistory()
        }
    }

    // MARK: - Row Builder
    @ViewBuilder
    private func promptLibraryRow(_ item: DatabaseAIPromptItem) -> some View {
        HStack {
            Button {
                prompt = item.prompt
                generateArchitecture()
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.caption.bold())
                        .foregroundColor(.primary)
                    Text(item.prompt)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                togglePromptFavorite(item)
            } label: {
                Image(systemName: item.isFavorite ? "star.fill" : "star")
                    .foregroundColor(.yellow)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Handlers & State Persistence
    private func generateArchitecture() {
        isGenerating = true
        response = ""
        copiedText = false

        Task {
            do {
                let contextPrompt = """
You are a senior database architect co-pilot.
Generate a structured technical document addressing this instruction:
\(prompt)
Use perfect formatting, clean markdown, and code blocks for tables or SQL.
"""
                let out = try await DatabaseAIService.shared.generateDatabaseArchitecture(prompt: contextPrompt)

                await MainActor.run {
                    response = out
                    // Save history item
                    let histItem = DatabaseAIHistoryItem(id: UUID(), promptText: prompt, generatedOutput: out, timestamp: Date())
                    taskHistory.insert(histItem, at: 0)
                    saveHistory()
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    response = "Generation Failed: \(error.localizedDescription)"
                    isGenerating = false
                }
            }
        }
    }

    private func copyToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(response, forType: .string)
        copiedText = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            copiedText = false
        }
    }

    private func loadPromptLibrary() {
        if let data = UserDefaults.standard.data(forKey: "com.swiftcode.database.aiPrompts"),
           let decoded = try? JSONDecoder().decode([DatabaseAIPromptItem].self, from: data) {
            promptLibrary = decoded
        } else {
            promptLibrary = [
                DatabaseAIPromptItem(id: UUID(), title: "User Auth Schema", prompt: "Design user authentication table with security session tokens, encryption, and status tracking.", category: "Architect", isFavorite: true, isRecent: false),
                DatabaseAIPromptItem(id: UUID(), title: "E-Commerce System", prompt: "Design e-commerce schema containing customers, product inventories, orders, and item checkout.", category: "Architect", isFavorite: false, isRecent: false),
                DatabaseAIPromptItem(id: UUID(), title: "Generate SwiftData Models", prompt: "Create swift models decorated with @Model mapped to user profile attributes.", category: "Generator", isFavorite: true, isRecent: false),
                DatabaseAIPromptItem(id: UUID(), title: "Codable JSON Wrapper", prompt: "Compile Codable swift structs mapping profiles databases columns.", category: "Generator", isFavorite: false, isRecent: false),
                DatabaseAIPromptItem(id: UUID(), title: "Database Index Builder", prompt: "Examine composite indices needed to optimize complex multi-table JOIN scripts.", category: "Optimizer", isFavorite: false, isRecent: false),
                DatabaseAIPromptItem(id: UUID(), title: "Analyze Normalization Form", prompt: "Evaluate third normal form (3NF) structures for enterprise inventory control systems.", category: "Optimizer", isFavorite: false, isRecent: false)
            ]
            savePromptLibrary()
        }
    }

    private func savePromptLibrary() {
        if let encoded = try? JSONEncoder().encode(promptLibrary) {
            UserDefaults.standard.set(encoded, forKey: "com.swiftcode.database.aiPrompts")
        }
    }

    private func togglePromptFavorite(_ item: DatabaseAIPromptItem) {
        if let idx = promptLibrary.firstIndex(where: { $0.id == item.id }) {
            promptLibrary[idx].isFavorite.toggle()
            savePromptLibrary()
        }
    }

    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: "com.swiftcode.database.aiHistory"),
           let decoded = try? JSONDecoder().decode([DatabaseAIHistoryItem].self, from: data) {
            taskHistory = decoded
        }
    }

    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(taskHistory) {
            UserDefaults.standard.set(encoded, forKey: "com.swiftcode.database.aiHistory")
        }
    }
}
