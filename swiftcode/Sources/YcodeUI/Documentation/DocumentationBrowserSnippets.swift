import AppKit
import SwiftUI

struct DocumentationSnippetLibraryView: View {
    @State private var snippets: [LibraryCodeSnippet] = LibraryCodeSnippetStore.load()
    @State private var searchText = ""
    @State private var selectedCategory: LibrarySnippetCategory?
    @State private var selectedID: UUID?
    @State private var draft = LibraryCodeSnippet.empty
    @State private var draftTags = ""
    @State private var showingDeleteConfirmation = false

    private var filtered: [LibraryCodeSnippet] {
        snippets
            .filter { selectedCategory == nil || $0.category == selectedCategory }
            .filter {
                searchText.isEmpty
                || $0.title.localizedCaseInsensitiveContains(searchText)
                || $0.code.localizedCaseInsensitiveContains(searchText)
                || $0.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
            }
            .sorted {
                if $0.isPinned != $1.isPinned { return $0.isPinned }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    var body: some View {
        HSplitView {
            listPane
            editorPane
        }
        .onChange(of: selectedID) { _, newValue in
            if let id = newValue, let found = snippets.first(where: { $0.id == id }) {
                draft = found
                draftTags = found.tags.joined(separator: ", ")
            }
        }
    }

    private var listPane: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search snippets", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                Button {
                    startNewSnippet()
                } label: {
                    Label("New", systemImage: "plus")
                }
            }
            .padding(8)
            Picker("Category", selection: $selectedCategory) {
                Text("All Categories").tag(nil as LibrarySnippetCategory?)
                ForEach(LibrarySnippetCategory.allCases) { category in
                    Text(category.rawValue).tag(category as LibrarySnippetCategory?)
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
            List(filtered, selection: $selectedID) { snippet in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(snippet.title).font(.headline).lineLimit(1)
                        if snippet.isPinned {
                            Image(systemName: "pin.fill").foregroundStyle(.secondary)
                        }
                        if snippet.isFavorite {
                            Image(systemName: "star.fill").foregroundStyle(.yellow)
                        }
                    }
                    Text("\(snippet.category.rawValue) · \(snippet.language)")
                        .font(.caption).foregroundStyle(.secondary)
                    if !snippet.tags.isEmpty {
                        Text(snippet.tags.joined(separator: ", "))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                .tag(snippet.id)
            }
            .listStyle(.sidebar)
        }
        .frame(minWidth: 220, idealWidth: 280)
    }

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Title", text: $draft.title)
                    .textFieldStyle(.roundedBorder)
                Picker("Category", selection: $draft.category) {
                    ForEach(LibrarySnippetCategory.allCases) { category in
                        Text(category.rawValue).tag(category)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)
            }
            HStack {
                TextField("Language", text: $draft.language)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
                TextField("Tags (comma-separated)", text: $draftTags)
                    .textFieldStyle(.roundedBorder)
            }
            TextEditor(text: $draft.code)
                .font(.system(.body, design: .monospaced))
                .border(Color.secondary.opacity(0.3))
            HStack {
                Toggle("Favorite", isOn: $draft.isFavorite)
                Toggle("Pinned", isOn: $draft.isPinned)
                Spacer()
                Button("Copy Code") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(draft.code, forType: .string)
                }
                .disabled(draft.code.isEmpty)
                Button("Delete", role: .destructive) {
                    showingDeleteConfirmation = true
                }
                .disabled(selectedID == nil)
                Button("Save") { saveDraft() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.title.isEmpty || draft.code.isEmpty)
            }
        }
        .padding()
        .frame(minWidth: 320)
        .alert("Delete this snippet?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) { deleteSelected() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func startNewSnippet() {
        selectedID = nil
        draft = .empty
        draftTags = ""
    }

    private func saveDraft() {
        let tags = draftTags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if let id = selectedID, let at = snippets.firstIndex(where: { $0.id == id }) {
            snippets[at] = LibraryCodeSnippet(
                id: id, title: draft.title, code: draft.code, category: draft.category,
                language: draft.language, tags: tags,
                usageCount: snippets[at].usageCount,
                isFavorite: draft.isFavorite, isPinned: draft.isPinned)
        } else {
            let created = LibraryCodeSnippet(
                title: draft.title, code: draft.code, category: draft.category,
                language: draft.language, tags: tags,
                isFavorite: draft.isFavorite, isPinned: draft.isPinned)
            snippets.append(created)
            selectedID = created.id
        }
        LibraryCodeSnippetStore.save(snippets)
    }

    private func deleteSelected() {
        guard let id = selectedID else { return }
        snippets.removeAll { $0.id == id }
        LibraryCodeSnippetStore.save(snippets)
        selectedID = nil
        draft = .empty
        draftTags = ""
    }
}
