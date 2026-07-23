import SwiftUI

struct SnippetsLibraryView: View {
    @State private var snippets: [CodeSnippet] = CodeSnippetStore.load()
    @State private var selectedCategory: SnippetCategory = .swiftUIViews
    @State private var searchQuery = ""
    @State private var languageFilter = "All"
    @State private var draft = CodeSnippet.empty
    @State private var showCreateSheet = false
    @State private var selectedSnippet: CodeSnippet? = nil

    let languages = ["All", "Swift", "Objective-C", "Shell", "Markdown", "JSON"]

    private var filtered: [CodeSnippet] {
        var list = snippets

        // Category filter
        list = list.filter { $0.category == selectedCategory }

        // Search filter
        if !searchQuery.isEmpty {
            list = list.filter {
                $0.title.localizedCaseInsensitiveContains(searchQuery) ||
                $0.code.localizedCaseInsensitiveContains(searchQuery)
            }
        }

        // Language filter
        if languageFilter != "All" {
            list = list.filter { $0.language.localizedCaseInsensitiveContains(languageFilter) }
        }

        return list
    }

    var body: some View {
        NavigationStack {
            HSplitView {
                // Left Pane: Snippets Directory
                VStack(spacing: 0) {
                    VStack(spacing: 8) {
                        // Search bar
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundStyle(.secondary)
                            TextField("Search snippets...", text: $searchQuery)
                                .textFieldStyle(.plain)
                        }
                        .padding(6)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

                        // Category Picker
                        Picker("Category", selection: $selectedCategory) {
                            ForEach(SnippetCategory.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.menu)

                        // Language Filter & Actions
                        HStack {
                            Picker("Language", selection: $languageFilter) {
                                ForEach(languages, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 145)

                            Spacer()

                            Button {
                                prepareCreate()
                            } label: {
                                Label("Add", systemImage: "plus")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(12)

                    Divider()

                    // List of Snippets
                    if filtered.isEmpty {
                        ContentUnavailableView("No Snippets", systemImage: "curlybraces")
                            .frame(maxHeight: .infinity)
                    } else {
                        List(filtered, selection: $selectedSnippet) { snippet in
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(snippet.title).bold()
                                        if snippet.isPinned {
                                            Image(systemName: "pin.fill")
                                                .font(.caption2)
                                                .foregroundStyle(.orange)
                                        }
                                    }
                                    Text(snippet.language)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if snippet.isFavorite {
                                    Image(systemName: "star.fill")
                                        .foregroundStyle(.yellow)
                                }
                            }
                            .tag(snippet)
                        }
                    }
                }
                .frame(minWidth: 260, idealWidth: 280, maxWidth: 350)

                // Right Pane: Detail & Preview
                Group {
                    if let snippet = selectedSnippet {
                        snippetDetailsPanel(snippet)
                    } else {
                        ContentUnavailableView(
                            "Select a Snippet",
                            systemImage: "curlybraces",
                            description: Text("Choose a code template from the directory to review, copy, export, or insert directly into the active editor.")
                        )
                    }
                }
                .frame(minWidth: 350)
            }
            .navigationTitle("Snippets Library")
            .sheet(isPresented: $showCreateSheet) {
                createSnippetSheet
            }
        }
    }

    // MARK: - Details Panel

    private func snippetDetailsPanel(_ snippet: CodeSnippet) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(snippet.title)
                            .font(.title2.bold())
                        Text("Category: \(snippet.category.rawValue) | Language: \(snippet.language)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()

                    Button("Insert Into Editor") {
                        insertIntoEditor(snippet.code)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                }

                Divider()

                // Code Codebox Block with highlight simulation
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Source Code Template Preview")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Copy Code") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(snippet.code, forType: .string)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        ScrollView {
                            Text(snippet.code)
                                .font(.system(.body, design: .monospaced))
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.12))
                                .cornerRadius(6)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 300)
                    }
                    .padding(6)
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Actions Area
                HStack(spacing: 8) {
                    Button(snippet.isFavorite ? "Unfavorite" : "Favorite") {
                        toggleFavorite(snippet)
                    }
                    .buttonStyle(.bordered)

                    Button(snippet.isPinned ? "Unpin" : "Pin Snippet") {
                        togglePinned(snippet)
                    }
                    .buttonStyle(.bordered)

                    Button("Duplicate") {
                        duplicateSnippet(snippet)
                    }
                    .buttonStyle(.bordered)

                    Button("Export Snippet") {
                        exportSnippet(snippet)
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        deleteSnippet(snippet)
                    } label: {
                        Text("Delete")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(20)
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Create Snippet Sheet

    private var createSnippetSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Create New Snippet")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    showCreateSheet = false
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Snippet Title").bold()
                            TextField("Enter title (e.g. JSON Post Fetch)", text: $draft.title)
                                .textFieldStyle(.roundedBorder)

                            Text("Category").bold()
                            Picker("Category", selection: $selectedCategory) {
                                ForEach(SnippetCategory.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.menu)

                            Text("Programming Language").bold()
                            TextField("Swift, Shell, Objective-C, etc.", text: $draft.language)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Code Template Content").bold()
                            TextField("Write or paste code templates here...", text: $draft.code, axis: .vertical)
                                .textFieldStyle(.roundedBorder)
                                .frame(height: 150)
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    Button("Save Snippet") {
                        saveSnippet()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.title.isEmpty || draft.code.isEmpty)
                }
                .padding()
            }
        }
        .frame(width: 500, height: 460)
    }

    // MARK: - Operations Helpers

    private func prepareCreate() {
        draft = .empty
        draft.language = "Swift"
        showCreateSheet = true
    }

    private func saveSnippet() {
        draft.category = selectedCategory
        snippets.append(draft)
        CodeSnippetStore.save(snippets)
        selectedSnippet = draft
        showCreateSheet = false
        draft = .empty
    }

    private func toggleFavorite(_ snippet: CodeSnippet) {
        if let idx = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[idx].isFavorite.toggle()
            CodeSnippetStore.save(snippets)
            selectedSnippet = snippets[idx]
        }
    }

    private func togglePinned(_ snippet: CodeSnippet) {
        if let idx = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[idx].isPinned.toggle()
            CodeSnippetStore.save(snippets)
            selectedSnippet = snippets[idx]
        }
    }

    private func duplicateSnippet(_ snippet: CodeSnippet) {
        let copy = CodeSnippet(
            id: UUID(),
            title: "\(snippet.title) Copy",
            code: snippet.code,
            category: snippet.category,
            language: snippet.language,
            isFavorite: snippet.isFavorite,
            isPinned: snippet.isPinned
        )
        snippets.append(copy)
        CodeSnippetStore.save(snippets)
        selectedSnippet = copy
    }

    private func exportSnippet(_ snippet: CodeSnippet) {
        if let data = try? JSONEncoder().encode(snippet),
           let str = String(data: data, encoding: .utf8) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(str, forType: .string)
        }
    }

    private func deleteSnippet(_ snippet: CodeSnippet) {
        snippets.removeAll { $0.id == snippet.id }
        CodeSnippetStore.save(snippets)
        selectedSnippet = nil
    }

    private func insertIntoEditor(_ code: String) {
        ProjectSessionStore.shared.activeFileContent += "\n\n" + code
    }
}

// MARK: - Extended Model

private struct CodeSnippet: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var code: String
    var category: SnippetCategory
    var language: String
    var isFavorite: Bool = false
    var isPinned: Bool = false

    static let empty = CodeSnippet(id: UUID(), title: "", code: "", category: .utilities, language: "Swift")
}

private enum SnippetCategory: String, CaseIterable, Identifiable, Codable {
    case swiftUIViews = "SwiftUI Views"
    case networking = "Networking"
    case asyncTasks = "Async Tasks"
    case dataModels = "Data Models"
    case utilities = "Utilities"
    var id: String { rawValue }
}

private enum CodeSnippetStore {
    private static let key = "com.swiftcode.snippets"

    static func load() -> [CodeSnippet] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([CodeSnippet].self, from: data) else {
            // Default Templates fallback
            return [
                CodeSnippet(id: UUID(), title: "Async Task MainActor wrapper", code: "Task {\n    await MainActor.run {\n        // Update UI state securely\n    }\n}", category: .asyncTasks, language: "Swift", isPinned: true),
                CodeSnippet(id: UUID(), title: "Custom SwiftUI Button Style", code: "struct ModernButtonStyle: ButtonStyle {\n    func makeBody(configuration: Configuration) -> some View {\n        configuration.label\n            .padding(.horizontal, 16)\n            .padding(.vertical, 8)\n            .background(Color.accentColor)\n            .cornerRadius(8)\n            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)\n    }\n}", category: .swiftUIViews, language: "Swift", isPinned: false)
            ]
        }
        return decoded
    }

    static func save(_ snippets: [CodeSnippet]) {
        guard let data = try? JSONEncoder().encode(snippets) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
