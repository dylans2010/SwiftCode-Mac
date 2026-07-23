import SwiftUI

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

struct SnippetsLibraryView: View {
    @State private var snippets: [CodeSnippet] = CodeSnippetStore.load()
    @State private var selectedCategory: SnippetCategory = .swiftUIViews
    @State private var searchQuery = ""
    @State private var languageFilter = "All"
    @State private var draft = CodeSnippet.empty
    @State private var showCreateSheet = false
    @State private var selectedSnippet: CodeSnippet? = nil
    @Environment(\.dismiss) private var dismiss

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
            ScrollView {
                VStack(spacing: 24) {
                    // Header Card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("Snippets Library Hub", systemImage: "curlybraces")
                                    .font(.headline)
                                    .foregroundColor(.orange)
                                Spacer()
                            }
                            Text("Store, tag, categorize, and quickly insert code snippet templates directly into your active editors.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Filter & Create panel
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Filters & Actions")
                                .font(.subheadline.bold())
                                .foregroundColor(.blue)

                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundStyle(.secondary)
                                TextField("Search snippets...", text: $searchQuery)
                                    .textFieldStyle(.plain)
                            }
                            .padding(6)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

                            Picker("Category", selection: $selectedCategory) {
                                ForEach(SnippetCategory.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)

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
                                    Label("Add Snippet", systemImage: "plus")
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Snippets list/select GroupBox
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Snippets Directory")
                                .font(.subheadline.bold())
                                .foregroundColor(.green)

                            let list = filtered
                            if list.isEmpty {
                                Text("No snippets match the criteria.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 8)
                            } else {
                                ForEach(list) { snippet in
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

                                        HStack(spacing: 8) {
                                            Button("Select") {
                                                selectedSnippet = snippet
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)

                                            Button {
                                                toggleFavorite(snippet)
                                            } label: {
                                                Image(systemName: snippet.isFavorite ? "star.fill" : "star")
                                                    .foregroundStyle(snippet.isFavorite ? .yellow : .secondary)
                                            }
                                            .buttonStyle(.plain)

                                            Button {
                                                togglePinned(snippet)
                                            } label: {
                                                Image(systemName: snippet.isPinned ? "pin.fill" : "pin")
                                                    .foregroundStyle(snippet.isPinned ? .orange : .secondary)
                                            }
                                            .buttonStyle(.plain)

                                            Button(role: .destructive) {
                                                deleteSnippet(snippet)
                                            } label: {
                                                Image(systemName: "trash")
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                    }
                                    .padding(8)
                                    .background(selectedSnippet?.id == snippet.id ? Color.accentColor.opacity(0.1) : Color.clear)
                                    .cornerRadius(6)

                                    if snippet.id != list.last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Details Panel of selected snippet
                    if let snippet = selectedSnippet ?? filtered.first {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(snippet.title)
                                            .font(.title3.bold())
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
                                    .controlSize(.small)
                                }

                                Divider()

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
                                    .frame(maxHeight: 250)
                                }

                                Divider()

                                HStack(spacing: 8) {
                                    Button("Duplicate") {
                                        duplicateSnippet(snippet)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Button("Export") {
                                        exportSnippet(snippet)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                            .padding(8)
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                    }
                }
                .padding(24)
            }
            .background(Color(NSColor.windowBackgroundColor))
            .navigationTitle("Snippets Library")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                createSnippetSheet
            }
        }
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
            if selectedSnippet?.id == snippet.id {
                selectedSnippet = snippets[idx]
            }
        }
    }

    private func togglePinned(_ snippet: CodeSnippet) {
        if let idx = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[idx].isPinned.toggle()
            CodeSnippetStore.save(snippets)
            if selectedSnippet?.id == snippet.id {
                selectedSnippet = snippets[idx]
            }
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
        if selectedSnippet?.id == snippet.id {
            selectedSnippet = nil
        }
    }

    private func insertIntoEditor(_ code: String) {
        ProjectSessionStore.shared.activeFileContent += "\n\n" + code
    }
}
