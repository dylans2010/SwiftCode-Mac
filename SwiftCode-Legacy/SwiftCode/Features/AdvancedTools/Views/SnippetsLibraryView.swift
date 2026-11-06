import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Model

private struct LibraryCodeSnippet: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var code: String
    var category: LibrarySnippetCategory
    var language: String
    var tags: [String]
    var usageCount: Int
    var isFavorite: Bool = false
    var isPinned: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, title, code, category, language, tags, usageCount, isFavorite, isPinned
    }

    init(
        id: UUID = UUID(),
        title: String,
        code: String,
        category: LibrarySnippetCategory,
        language: String,
        tags: [String] = [],
        usageCount: Int = 0,
        isFavorite: Bool = false,
        isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.code = code
        self.category = category
        self.language = language
        self.tags = tags
        self.usageCount = usageCount
        self.isFavorite = isFavorite
        self.isPinned = isPinned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        code = try container.decode(String.self, forKey: .code)
        category = try container.decode(LibrarySnippetCategory.self, forKey: .category)
        language = try container.decode(String.self, forKey: .language)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        usageCount = try container.decodeIfPresent(Int.self, forKey: .usageCount) ?? 0
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
    }

    static let empty = LibraryCodeSnippet(id: UUID(), title: "", code: "", category: .utilities, language: "Swift")
}

private enum LibrarySnippetCategory: String, CaseIterable, Identifiable, Codable {
    case swiftUIViews = "SwiftUI Views"
    case networking = "Networking"
    case asyncTasks = "Async Tasks"
    case dataModels = "Data Models"
    case utilities = "Utilities"
    var id: String { rawValue }
}

private enum LibraryCodeSnippetStore {
    private static let key = "com.swiftcode.snippets"

    static func load() -> [LibraryCodeSnippet] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([LibraryCodeSnippet].self, from: data) else {
            return [
                LibraryCodeSnippet(id: UUID(), title: "Async Task MainActor wrapper", code: "Task {\n    await MainActor.run {\n        // Update UI state securely\n    }\n}", category: .asyncTasks, language: "Swift", tags: ["async", "mainactor"], isPinned: true),
                LibraryCodeSnippet(id: UUID(), title: "Custom SwiftUI Button Style", code: "struct ModernButtonStyle: ButtonStyle {\n    func makeBody(configuration: Configuration) -> some View {\n        configuration.label\n            .padding(.horizontal, 16)\n            .padding(.vertical, 8)\n            .background(Color.accentColor)\n            .cornerRadius(8)\n            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)\n    }\n}", category: .swiftUIViews, language: "Swift", tags: ["swiftui", "button"])
            ]
        }
        return decoded
    }

    static func save(_ snippets: [LibraryCodeSnippet]) {
        guard let data = try? JSONEncoder().encode(snippets) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

// MARK: - Export document

private struct SnippetsExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var payload: Data

    init(snippets: [LibraryCodeSnippet]) {
        payload = (try? JSONEncoder().encode(snippets)) ?? Data()
    }

    init(configuration: ReadConfiguration) throws {
        payload = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: payload)
    }
}

// MARK: - View

struct SnippetsLibraryView: View {
    @State private var snippets: [LibraryCodeSnippet] = LibraryCodeSnippetStore.load()
    @State private var selectedCategory: LibrarySnippetCategory = .swiftUIViews
    @State private var searchQuery = ""
    @State private var languageFilter = "All"
    @State private var selectedTags: Set<String> = []
    @State private var favoritesOnly = false

    @State private var draft = LibraryCodeSnippet.empty
    @State private var draftTags = ""
    @State private var draftIsFavorite = false
    @State private var draftIsPinned = false
    @State private var showEditSheet = false
    @State private var isCreatingNew = true

    @State private var selectedSnippet: LibraryCodeSnippet? = nil
    @State private var snippetPendingDelete: LibraryCodeSnippet? = nil

    @State private var isImporting = false
    @State private var exportDocument: SnippetsExportDocument? = nil
    @State private var isExporting = false
    @State private var importError = false

    @Environment(\.dismiss) private var dismiss

    let languages = ["All", "Swift", "Objective-C", "Shell", "Markdown", "JSON"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    headerCard
                    filterCard
                    snippetsCard
                    detailCard
                }
                .padding(24)
            }
            .background(Color(NSColor.windowBackgroundColor))
            .navigationTitle("Snippets library")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack {
                        Button {
                            isImporting = true
                        } label: {
                            Label("Import", systemImage: "square.and.arrow.down")
                        }
                        Button {
                            exportDocument = SnippetsExportDocument(snippets: snippets)
                            isExporting = true
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        .disabled(snippets.isEmpty)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showEditSheet) {
                editSnippetSheet
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
                switch result {
                case .success(let url):
                    importSnippets(from: url)
                case .failure:
                    importError = true
                }
            }
            .fileExporter(
                isPresented: $isExporting,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "code-snippets.json"
            ) { _ in }
            .confirmationDialog(
                "Delete snippet",
                isPresented: Binding(
                    get: { snippetPendingDelete != nil },
                    set: { if !$0 { snippetPendingDelete = nil } }
                ),
                presenting: snippetPendingDelete
            ) { snippet in
                Button("Delete", role: .destructive) {
                    deleteSnippet(snippet)
                    snippetPendingDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    snippetPendingDelete = nil
                }
            } message: { snippet in
                Text("Delete the snippet \"\(snippet.title)\"? This can't be undone.")
            }
            .alert("Couldn't import snippets", isPresented: $importError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("The selected file doesn't contain valid snippet JSON.")
            }
        }
    }

    // MARK: - Filtering

    private var allTags: [String] {
        Array(Set(snippets.flatMap { $0.tags })).sorted()
    }

    private var filtered: [LibraryCodeSnippet] {
        var list = snippets

        list = list.filter { $0.category == selectedCategory }

        if !searchQuery.isEmpty {
            let query = searchQuery
            list = list.filter {
                $0.title.localizedCaseInsensitiveContains(query) ||
                $0.code.localizedCaseInsensitiveContains(query) ||
                $0.tags.contains { $0.localizedCaseInsensitiveContains(query) }
            }
        }

        if languageFilter != "All" {
            list = list.filter { $0.language.localizedCaseInsensitiveContains(languageFilter) }
        }

        if !selectedTags.isEmpty {
            list = list.filter { snippet in
                !selectedTags.isDisjoint(with: Set(snippet.tags))
            }
        }

        if favoritesOnly {
            list = list.filter { $0.isFavorite }
        }

        list.sort {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }

        return list
    }

    // MARK: - Cards

    private var headerCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Label("Snippets library", systemImage: "curlybraces")
                    .font(.headline)
                Text("Store, tag, and categorize code snippet templates, then copy or insert them into your active editors.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(nil)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }

    private var filterCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Text("Filters and actions")
                    .font(.subheadline.bold())

                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search snippets", text: $searchQuery)
                        .textFieldStyle(.plain)
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

                Picker("Category", selection: $selectedCategory) {
                    ForEach(LibrarySnippetCategory.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if !allTags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(allTags, id: \.self) { tag in
                                let isSelected = selectedTags.contains(tag)
                                Button {
                                    if isSelected {
                                        selectedTags.remove(tag)
                                    } else {
                                        selectedTags.insert(tag)
                                    }
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "tag")
                                            .font(.caption2)
                                        Text(tag)
                                            .font(.caption)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(
                                        isSelected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08),
                                        in: Capsule()
                                    )
                                    .foregroundStyle(isSelected ? .primary : .secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                HStack {
                    Picker("Language", selection: $languageFilter) {
                        ForEach(languages, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 145)

                    Toggle("Favorites only", isOn: $favoritesOnly)
                        .toggleStyle(.checkbox)
                        .font(.caption)

                    Spacer()

                    Button {
                        prepareCreate()
                    } label: {
                        Label("Add snippet", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(8)
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }

    private var snippetsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Snippets")
                        .font(.subheadline.bold())
                    Spacer()
                    Text("\(filtered.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if snippets.isEmpty {
                    ContentUnavailableView {
                        Label("No snippets yet", systemImage: "curlybraces")
                    } description: {
                        Text("Save reusable code templates here so you can copy or insert them later.")
                    } actions: {
                        Button("Add snippet") {
                            prepareCreate()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else if filtered.isEmpty {
                    Text("No snippets match these filters.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 8) {
                        ForEach(filtered) { snippet in
                            snippetRow(snippet)

                            if snippet.id != filtered.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(8)
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }

    private func snippetRow(_ snippet: LibraryCodeSnippet) -> some View {
        let isSelected = selectedSnippet?.id == snippet.id

        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if snippet.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if snippet.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text(snippet.title)
                        .bold()
                        .lineLimit(nil)
                }

                HStack(spacing: 6) {
                    Text(snippet.language)
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                        .foregroundStyle(.secondary)

                    if !snippet.tags.isEmpty {
                        Text(snippet.tags.prefix(3).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Text(usageText(for: snippet))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 8) {
                Button("Copy") {
                    copySnippet(snippet)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    prepareEdit(snippet)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Edit")

                Button {
                    duplicateSnippet(snippet)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Duplicate")

                Button {
                    toggleFavorite(snippet)
                } label: {
                    Image(systemName: snippet.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Toggle favorite")

                Button {
                    togglePinned(snippet)
                } label: {
                    Image(systemName: snippet.isPinned ? "pin.fill" : "pin")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Pin to top")

                Button(role: .destructive) {
                    snippetPendingDelete = snippet
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Delete")
            }
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
        .cornerRadius(6)
        .contentShape(Rectangle())
        .onTapGesture {
            selectedSnippet = snippet
        }
    }

    @ViewBuilder
    private var detailCard: some View {
        if let snippet = currentSnippet {
            GroupBox {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(snippet.title)
                                .font(.title3.bold())
                                .lineLimit(nil)
                            HStack(spacing: 6) {
                                Text(snippet.language)
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.secondary.opacity(0.12), in: Capsule())
                                    .foregroundStyle(.secondary)
                                Text(snippet.category.rawValue)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(usageText(for: snippet))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Insert into editor") {
                            insertIntoEditor(snippet)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }

                    if !snippet.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(snippet.tags, id: \.self) { tag in
                                    Text(tag)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(Color.secondary.opacity(0.08), in: Capsule())
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Code preview")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Copy code") {
                                copySnippet(snippet)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }

                        ScrollView([.horizontal, .vertical], showsIndicators: true) {
                            Text(snippet.code)
                                .font(.system(.body, design: .monospaced))
                                .fixedSize(horizontal: true, vertical: false)
                                .padding(12)
                                .textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 120, maxHeight: 280)
                        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    }

                    Divider()

                    HStack(spacing: 8) {
                        Button {
                            prepareEdit(snippet)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            duplicateSnippet(snippet)
                        } label: {
                            Label("Duplicate", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button {
                            exportSnippet(snippet)
                        } label: {
                            Label("Copy JSON", systemImage: "doc.on.clipboard")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Spacer()

                        Button(role: .destructive) {
                            snippetPendingDelete = snippet
                        } label: {
                            Label("Delete", systemImage: "trash")
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

    private var currentSnippet: LibraryCodeSnippet? {
        if let selected = selectedSnippet,
           let fresh = snippets.first(where: { $0.id == selected.id }) {
            return fresh
        }
        return selectedSnippet ?? filtered.first
    }

    private func usageText(for snippet: LibraryCodeSnippet) -> String {
        snippet.usageCount == 1 ? "Used 1 time" : "Used \(snippet.usageCount) times"
    }

    // MARK: - Create / edit sheet

    private var editSnippetSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isCreatingNew ? "Add snippet" : "Edit snippet")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    showEditSheet = false
                }
                .buttonStyle(.bordered)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Title").bold()
                            TextField("Title (e.g. JSON post fetch)", text: $draft.title)
                                .textFieldStyle(.roundedBorder)

                            Text("Category").bold()
                            Picker("Category", selection: $draft.category) {
                                ForEach(LibrarySnippetCategory.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.menu)

                            Text("Language").bold()
                            TextField("Swift, Shell, Objective-C, etc.", text: $draft.language)
                                .textFieldStyle(.roundedBorder)

                            Text("Tags").bold()
                            TextField("Comma-separated tags (e.g. async, networking)", text: $draftTags)
                                .textFieldStyle(.roundedBorder)

                            HStack {
                                Toggle("Favorite", isOn: $draftIsFavorite)
                                Toggle("Pinned", isOn: $draftIsPinned)
                            }
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Code").bold()
                            TextEditor(text: $draft.code)
                                .font(.system(.body, design: .monospaced))
                                .frame(minHeight: 140)
                                .padding(4)
                                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .padding(8)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    Button("Save snippet") {
                        saveSnippet()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty || draft.code.isEmpty)
                }
                .padding()
            }
        }
        .frame(minWidth: 500, minHeight: 480)
    }

    // MARK: - Operations

    private func prepareCreate() {
        draft = .empty
        draft.language = "Swift"
        draft.category = selectedCategory
        draftTags = ""
        draftIsFavorite = false
        draftIsPinned = false
        isCreatingNew = true
        showEditSheet = true
    }

    private func prepareEdit(_ snippet: LibraryCodeSnippet) {
        draft = snippet
        draftTags = snippet.tags.joined(separator: ", ")
        draftIsFavorite = snippet.isFavorite
        draftIsPinned = snippet.isPinned
        isCreatingNew = false
        showEditSheet = true
    }

    private func parsedTags() -> [String] {
        draftTags
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func saveSnippet() {
        var saved = draft
        saved.title = draft.title.trimmingCharacters(in: .whitespaces)
        saved.tags = parsedTags()
        saved.isFavorite = draftIsFavorite
        saved.isPinned = draftIsPinned

        if isCreatingNew {
            snippets.append(saved)
        } else if let idx = snippets.firstIndex(where: { $0.id == saved.id }) {
            // Preserve the usage count from the stored copy in case the draft is stale.
            saved.usageCount = max(saved.usageCount, snippets[idx].usageCount)
            snippets[idx] = saved
        }
        LibraryCodeSnippetStore.save(snippets)
        selectedSnippet = saved
        showEditSheet = false
        draft = .empty
    }

    private func updateSnippet(_ snippet: LibraryCodeSnippet) {
        if let idx = snippets.firstIndex(where: { $0.id == snippet.id }) {
            snippets[idx] = snippet
            LibraryCodeSnippetStore.save(snippets)
            if selectedSnippet?.id == snippet.id {
                selectedSnippet = snippet
            }
        }
    }

    private func toggleFavorite(_ snippet: LibraryCodeSnippet) {
        var updated = snippet
        updated.isFavorite.toggle()
        updateSnippet(updated)
    }

    private func togglePinned(_ snippet: LibraryCodeSnippet) {
        var updated = snippet
        updated.isPinned.toggle()
        updateSnippet(updated)
    }

    private func duplicateSnippet(_ snippet: LibraryCodeSnippet) {
        let copy = LibraryCodeSnippet(
            title: "\(snippet.title) copy",
            code: snippet.code,
            category: snippet.category,
            language: snippet.language,
            tags: snippet.tags,
            isFavorite: snippet.isFavorite,
            isPinned: snippet.isPinned
        )
        snippets.append(copy)
        LibraryCodeSnippetStore.save(snippets)
        selectedSnippet = copy
    }

    private func copySnippet(_ snippet: LibraryCodeSnippet) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snippet.code, forType: .string)
        var updated = snippet
        updated.usageCount += 1
        updateSnippet(updated)
    }

    private func exportSnippet(_ snippet: LibraryCodeSnippet) {
        if let data = try? JSONEncoder().encode(snippet),
           let str = String(data: data, encoding: .utf8) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(str, forType: .string)
        }
    }

    private func deleteSnippet(_ snippet: LibraryCodeSnippet) {
        snippets.removeAll { $0.id == snippet.id }
        LibraryCodeSnippetStore.save(snippets)
        if selectedSnippet?.id == snippet.id {
            selectedSnippet = nil
        }
    }

    private func insertIntoEditor(_ snippet: LibraryCodeSnippet) {
        ProjectSessionStore.shared.activeFileContent += "\n\n" + snippet.code
        var updated = snippet
        updated.usageCount += 1
        updateSnippet(updated)
    }

    // MARK: - Import / export

    private func importSnippets(from url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess { url.stopAccessingSecurityScopedResource() }
        }
        guard let data = try? Data(contentsOf: url) else {
            importError = true
            return
        }
        importSnippets(from: data)
    }

    private func importSnippets(from data: Data) {
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode([LibraryCodeSnippet].self, from: data) {
            mergeImportedSnippets(decoded)
        } else if let single = try? decoder.decode(LibraryCodeSnippet.self, from: data) {
            mergeImportedSnippets([single])
        } else {
            importError = true
        }
    }

    private func mergeImportedSnippets(_ imported: [LibraryCodeSnippet]) {
        for snippet in imported {
            if let idx = snippets.firstIndex(where: { $0.id == snippet.id }) {
                snippets[idx] = snippet
            } else {
                snippets.append(snippet)
            }
        }
        LibraryCodeSnippetStore.save(snippets)
    }
}
