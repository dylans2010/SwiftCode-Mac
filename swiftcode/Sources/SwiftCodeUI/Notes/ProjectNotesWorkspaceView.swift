import SwiftUI
import AppKit
import UniformTypeIdentifiers
import os
import SwiftCodeIDECore
import SwiftCodeAssistant

// MARK: - Project Notes workspace (Wave 19, slice C)
//
// Ported from Legacy
// `SwiftCode/Features/AdvancedTools/Views/ProjectNotesWorkspaceView.swift`
// (Dylan's own code, ported under MIT). The model and state already live in
// the destination (`SwiftCodeIDECore/Model/ProjectNotes.swift`:
// `ProjectNote`, `ProjectNotebook`, `NoteAttachment`, `NoteVersion`,
// `SavedSearch`, `ProjectNoteTemplates`, `ProjectNotesWorkspaceState`);
// this file is only the view, plus the window manager/controller at the
// end (Legacy kept them in the same file).
//
// Destination adaptations (behaviour preserved unless noted):
// * State: Legacy used `ProjectNotesWorkspaceState.shared`; the destination
//   state has no singleton, so the view owns
//   `@State private var state = ProjectNotesWorkspaceState()` (it loads its
//   JSON on init). The window manager is a singleton holding one window,
//   so there is one live state instance in practice.
// * Glass: Legacy's `.liquidGlass(...)` modifier has no destination
//   equivalent — SwiftCode draws no glass of its own making
//   (specs/ide/liquid-glass-swiftcode.md) and uses the system's materials
//   through public API. Glass surfaces here use `.thinMaterial` in a
//   rounded rectangle, the same treatment the destination's own SwiftUI
//   views use.
// * Legacy orange is gone: folder/pin/file accents that were `.orange`
//   are `.accentColor`. Other semantic sidebar colours are unchanged.
// * Editor: Legacy edited through `TextEditorRepresentable`, an NSTextView
//   wrapper around its code editor (SUPERSEDED in the destination by
//   `SourceEditorView`, which lives in the `swiftcode-ide` executable
//   target and is not importable from `SwiftCodeUI`). The notes editor
//   uses SwiftUI `TextEditor` instead — real editing, monospaced, word
//   wrap on; the code-editor features (syntax highlighting, search
//   highlight) are not carried over. See specs/ide/wave19-views.md.
// * AI Copilot tab: Legacy streamed through its own `LLMService` with a
//   hardcoded model fallback; the destination state deliberately carries
//   no AI fields (AI lives in the Assistant). The tab runs one-shot
//   completions through the destination's real provider dispatch
//   (`LLMToolCompletionService`, gap-closure LLM wiring) and fails honestly
//   — the error names the provider and what is missing. Legacy streamed
//   tokens live; this tab shows a progress view and then the full reply.
//   No model is ever hardcoded and nothing is generated from canned text.
// * Saved searches: Legacy's state `saveSearch` appended to
//   `savedSearches`; the destination state's `saveSearch` writes the
//   search *history* instead. The bookmark button here appends to
//   `state.savedSearches` directly (see `saveCurrentSearch`), preserving
//   Legacy behaviour; the destination `saveSearch` semantics are a
//   follow-up for the state file, not this view.
// * The `Todo` smart-folder filter keeps Legacy's exact expression,
//   including its operator-precedence quirk (see spec).
// * Window frame autosave name is `SwiftCodeProjectNotesWindow` (Legacy's
//   `ProjectNotesMainWindow` renamed per the rebrand's clean-break rule
//   for persisted state).
// * Linked files post the same `com.swiftcode.openFileInWorkspace`
//   notification Legacy posted; whether the workspace observes it is
//   unchanged from Legacy.
// * Reachability (menu entry / hub) is the parent's integration step;
//   see INTEGRATION.md.

private let logger = Logger(subsystem: "com.swiftcode.app", category: "ProjectNotesWorkspaceView")

public struct ProjectNotesWorkspaceView: View {
    @State private var state = ProjectNotesWorkspaceState()

    // Collapsible states
    @State private var showSidebar = false
    @State private var showInspector = false

    // Sidebar states
    @State private var editingNotebookId: UUID? = nil
    @State private var editingNotebookName = ""
    @State private var showNewNotebookAlert = false
    @State private var newNotebookName = ""

    // Batch Action states
    @State private var isBatchSelecting = false
    @State private var batchSelectedIds = Set<UUID>()

    // Sorting & Category Filters
    @State private var sortOption: SortOption = .updatedAt
    @State private var categoryFilter: String = "All"

    // Search query
    @State private var internalSearchQuery = ""

    // Scratch Pad quick edit
    @State private var scratchPadText = ""

    public init() {}

    private enum SortOption: String, CaseIterable, Identifiable {
        case title = "Title"
        case updatedAt = "Recently Edited"
        case createdAt = "Date Created"
        case wordCount = "Word Count"

        var id: String { self.rawValue }
    }

    // Available Categories
    private let categories = [
        "All", "Architecture", "API Documentation", "Build Notes", "Debugging Notes",
        "Deployment Notes", "Feature Planning", "Sprint Planning", "Bug Investigation",
        "Code Reviews", "Refactoring Plans", "Design Decisions", "Meeting Notes",
        "Release Notes", "Changelog Entries", "Security Reviews", "Database Documentation",
        "AI Prompts", "Research Notes", "Performance Analysis", "Testing Plans",
        "User Stories", "Feature Requests", "Technical Debt", "Migration Plans",
        "Dependency Notes", "General"
    ]

    // MARK: - Filter Logic
    private var filteredNotes: [ProjectNote] {
        var result = state.notes

        // 1. Notebook Filter (if not smart folder that overrides it)
        let overrideSmartFolders = ["Archived", "Favorites", "Pinned", "Recent", "Todo", "Daily Notes", "Scratch Pad"]
        if !overrideSmartFolders.contains(state.noteFilter) {
            if let selectedNotebookId = state.selectedNotebookId {
                result = result.filter { $0.notebookId == selectedNotebookId && !$0.isArchived }
            }
        }

        // 2. Smart Folder Filters
        switch state.noteFilter {
        case "Pinned":
            result = result.filter { $0.isPinned && !$0.isArchived }
        case "Favorites":
            result = result.filter { $0.isFavorite && !$0.isArchived }
        case "Archived":
            result = result.filter { $0.isArchived }
        case "Recent":
            let recents = state.recentNoteIds
            result = result.filter { recents.contains($0.id) && !$0.isArchived }
            result.sort { (a, b) -> Bool in
                let idxA = recents.firstIndex(of: a.id) ?? Int.max
                let idxB = recents.firstIndex(of: b.id) ?? Int.max
                return idxA < idxB
            }
        case "Todo":
            // Legacy's exact expression, precedence quirk preserved:
            // `&&` binds tighter than `||`, so this is
            // `category == "Todo" || (content.contains("- [ ]") && !isArchived)`.
            result = result.filter { $0.category == "Todo" || $0.content.contains("- [ ]") && !$0.isArchived }
        case "Daily Notes":
            result = result.filter { $0.tags.contains("Daily") && !$0.isArchived }
        case "Scratch Pad":
            result = result.filter { $0.tags.contains("Scratch") && !$0.isArchived }
        default:
            break
        }

        // 3. Category Filter
        if categoryFilter != "All" {
            result = result.filter { $0.category == categoryFilter }
        }

        // 4. Tag Filtering (if query starts with #)
        if internalSearchQuery.hasPrefix("#") {
            let tag = String(internalSearchQuery.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            if !tag.isEmpty {
                result = result.filter { $0.tags.contains { $0.localizedCaseInsensitiveCompare(tag) == .orderedSame } }
            }
        } else if !internalSearchQuery.isEmpty {
            // 5. Full-text search
            let q = internalSearchQuery.lowercased()
            result = result.filter {
                $0.title.lowercased().contains(q) ||
                $0.content.lowercased().contains(q) ||
                $0.category.lowercased().contains(q) ||
                $0.tags.contains { $0.lowercased().contains(q) } ||
                $0.linkedFiles.contains { $0.lowercased().contains(q) } ||
                $0.linkedSymbols.contains { $0.lowercased().contains(q) }
            }
        }

        // 6. Sorting (skip if "Recent" smart folder which has its own sort order)
        if state.noteFilter != "Recent" {
            switch sortOption {
            case .title:
                result.sort { $0.title.localizedCompare($1.title) == .orderedAscending }
            case .updatedAt:
                result.sort { $0.updatedAt > $1.updatedAt }
            case .createdAt:
                result.sort { $0.createdAt > $1.createdAt }
            case .wordCount:
                result.sort { $0.wordCount > $1.wordCount }
            }
        }

        return result
    }

    private var allTags: [String] {
        var tagsSet = Set<String>()
        for note in state.notes {
            for tag in note.tags {
                tagsSet.insert(tag)
            }
        }
        return Array(tagsSet).sorted()
    }

    // MARK: - Body Layout
    public var body: some View {
        HStack(spacing: 0) {
            // Sidebar Navigation (Left)
            if showSidebar && !state.isFocusMode {
                sidebarView()
                    .frame(width: 250)
                    .background(Color(NSColor.windowBackgroundColor))
                Divider()
            }

            // Middle Column: Notes List
            if !state.isFocusMode {
                notesListView()
                    .frame(width: 320)
                    .background(Color(NSColor.controlBackgroundColor))
                Divider()
            }

            // Right Column: Editor Workspace & Inspector
            HStack(spacing: 0) {
                editorWorkspaceView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showInspector && !state.isFocusMode && state.selectedNoteId != nil {
                    Divider()
                    inspectorPanelView()
                        .frame(width: 330)
                        .background(Color(NSColor.windowBackgroundColor))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 1000, minHeight: 700)
        .onAppear {
            state.loadData()
            // Sync internal search query from state if any
            internalSearchQuery = state.searchQuery
        }
        .onChange(of: state.searchQuery) { _, newValue in
            internalSearchQuery = newValue
        }
    }

    // MARK: - 1. Left Sidebar
    @ViewBuilder
    private func sidebarView() -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Label("KNOWLEDGE BASE", systemImage: "square.grid.3x3.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                Spacer()

                Button {
                    showNewNotebookAlert = true
                } label: {
                    Image(systemName: "folder.badge.plus")
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .help("Create New Notebook")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            List {
                // Smart Folders Section
                Section(header: Text("Smart Folders")) {
                    SidebarRowButton(title: "All Notes", icon: "doc.text.fill", color: .blue, isSelected: state.noteFilter == "All") {
                        state.noteFilter = "All"
                    }

                    SidebarRowButton(title: "Pinned", icon: "pin.fill", color: .accentColor, isSelected: state.noteFilter == "Pinned") {
                        state.noteFilter = "Pinned"
                    }

                    SidebarRowButton(title: "Favorites", icon: "star.fill", color: .yellow, isSelected: state.noteFilter == "Favorites") {
                        state.noteFilter = "Favorites"
                    }

                    SidebarRowButton(title: "Recently Viewed", icon: "clock.fill", color: .purple, isSelected: state.noteFilter == "Recent") {
                        state.noteFilter = "Recent"
                    }

                    SidebarRowButton(title: "Tasks & To-Dos", icon: "checkmark.circle.fill", color: .green, isSelected: state.noteFilter == "Todo") {
                        state.noteFilter = "Todo"
                    }

                    SidebarRowButton(title: "Daily Notes", icon: "calendar", color: .teal, isSelected: state.noteFilter == "Daily Notes") {
                        state.noteFilter = "Daily Notes"
                    }

                    SidebarRowButton(title: "Scratch Pad", icon: "note.text", color: .pink, isSelected: state.noteFilter == "Scratch Pad") {
                        state.noteFilter = "Scratch Pad"
                    }

                    SidebarRowButton(title: "Archived Notes", icon: "archivebox.fill", color: .secondary, isSelected: state.noteFilter == "Archived") {
                        state.noteFilter = "Archived"
                    }
                }

                // Notebooks Section
                Section(header: Text("My Notebooks")) {
                    ForEach(state.notebooks) { notebook in
                        HStack {
                            Image(systemName: "folder.fill")
                                .foregroundColor(.accentColor)

                            if editingNotebookId == notebook.id {
                                TextField("", text: $editingNotebookName, onCommit: {
                                    if !editingNotebookName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        if let idx = state.notebooks.firstIndex(where: { $0.id == notebook.id }) {
                                            state.notebooks[idx].name = editingNotebookName
                                            state.saveData()
                                        }
                                    }
                                    editingNotebookId = nil
                                })
                                .textFieldStyle(.plain)
                                .font(.subheadline)
                            } else {
                                Text(notebook.name)
                                    .font(.subheadline)
                                    .foregroundColor(.primary)

                                Spacer()

                                Text("\(state.notes.filter { $0.notebookId == notebook.id && !$0.isArchived }.count)")
                                    .font(.caption2.monospaced())
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.secondary.opacity(0.12), in: Capsule())
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            state.noteFilter = "Notebook"
                            state.selectedNotebookId = notebook.id
                            // select first note in notebook
                            if let firstNote = state.notes.first(where: { $0.notebookId == notebook.id && !$0.isArchived }) {
                                state.selectNote(firstNote.id)
                            }
                        }
                        .contextMenu {
                            Button("Rename") {
                                editingNotebookId = notebook.id
                                editingNotebookName = notebook.name
                            }
                            Button("Delete Notebook", role: .destructive) {
                                state.deleteNotebook(notebook.id)
                            }
                        }
                    }
                }

                // Saved Searches Section
                if !state.savedSearches.isEmpty {
                    Section(header: Text("Saved Searches")) {
                        ForEach(state.savedSearches) { saved in
                            HStack {
                                Image(systemName: "magnifyingglass")
                                    .foregroundColor(.secondary)
                                Text(saved.query)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Spacer()
                                Button {
                                    state.deleteSavedSearch(saved)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                internalSearchQuery = saved.query
                                state.searchQuery = saved.query
                            }
                        }
                    }
                }

                // Tags cloud section
                if !allTags.isEmpty {
                    Section(header: Text("Tags Cloud")) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(allTags, id: \.self) { tag in
                                    Button {
                                        internalSearchQuery = "#\(tag)"
                                        state.searchQuery = "#\(tag)"
                                    } label: {
                                        Text("#\(tag)")
                                            .font(.caption2)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.accentColor.opacity(0.12), in: Capsule())
                                            .foregroundColor(.accentColor)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .sheet(isPresented: $showNewNotebookAlert) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Create New Notebook")
                    .font(.headline)
                TextField("Notebook Name", text: $newNotebookName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        createNewNotebookAction()
                    }
                HStack {
                    Button("Cancel") {
                        showNewNotebookAlert = false
                        newNotebookName = ""
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Create") {
                        createNewNotebookAction()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newNotebookName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .frame(width: 300)
        }
    }

    private func createNewNotebookAction() {
        let name = newNotebookName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            state.createNotebook(name: name)
            showNewNotebookAlert = false
            newNotebookName = ""
        }
    }

    /// Legacy's state `saveSearch` appended to `savedSearches`; the
    /// destination state's `saveSearch` writes the search *history*
    /// instead, so the bookmark button saves here, directly, with
    /// Legacy's dedup rule (case-insensitive, no duplicates).
    private func saveCurrentSearch(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !state.savedSearches.contains(where: { $0.query.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            state.savedSearches.append(SavedSearch(query: trimmed))
            state.saveData()
        }
    }

    // Sidebar button helper
    private struct SidebarRowButton: View {
        let title: String
        let icon: String
        let color: Color
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .frame(width: 16)
                    Text(title)
                        .foregroundColor(isSelected ? .white : .primary)
                    Spacer()
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(isSelected ? Color.accentColor : Color.clear, in: RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 2. Middle Notes List
    @ViewBuilder
    private func notesListView() -> some View {
        VStack(spacing: 0) {
            // Search field
            HStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search title, tags, content...", text: $internalSearchQuery)
                        .textFieldStyle(.plain)
                        .onChange(of: internalSearchQuery) { _, newValue in
                            state.searchQuery = newValue
                        }

                    if !internalSearchQuery.isEmpty {
                        Button {
                            internalSearchQuery = ""
                            state.searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))

                Button {
                    saveCurrentSearch(query: internalSearchQuery)
                } label: {
                    Image(systemName: "bookmark")
                }
                .buttonStyle(.bordered)
                .disabled(internalSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("Save current search query")

                Button {
                    state.createNote(notebookId: state.selectedNotebookId)
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .buttonStyle(.borderedProminent)
                .help("Create New Note")
            }
            .padding(12)

            Divider()

            // Filters & Sorters toolbar
            HStack {
                Picker("", selection: $sortOption) {
                    ForEach(SortOption.allCases) { opt in
                        Text(opt.rawValue).tag(opt)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)

                Spacer()

                Picker("", selection: $categoryFilter) {
                    Text("All Categories").tag("All")
                    ForEach(categories.filter { $0 != "All" }, id: \.self) { cat in
                        Text(cat).tag(cat)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 130)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.secondary.opacity(0.04))

            Divider()

            // Batch action header
            if isBatchSelecting {
                HStack {
                    Text("\(batchSelectedIds.count) selected")
                        .font(.subheadline.bold())
                    Spacer()
                    Button("Delete Selected", role: .destructive) {
                        for id in batchSelectedIds {
                            if let note = state.notes.first(where: { $0.id == id }) {
                                state.deleteNote(note)
                            }
                        }
                        batchSelectedIds.removeAll()
                        isBatchSelecting = false
                    }
                    .buttonStyle(.bordered)
                    .disabled(batchSelectedIds.isEmpty)

                    Button("Done") {
                        isBatchSelecting = false
                        batchSelectedIds.removeAll()
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(8)
                .background(Color.red.opacity(0.08))
                Divider()
            }

            // Cards list
            if filteredNotes.isEmpty {
                ContentUnavailableView("No Notes Found", systemImage: "doc.text.magnifyingglass", description: Text("No documents match your filter. Write a new note or expand your keywords."))
                    .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredNotes) { note in
                        let isSelected = state.selectedNoteId == note.id

                        HStack(alignment: .top, spacing: 10) {
                            if isBatchSelecting {
                                Toggle("", isOn: Binding(
                                    get: { batchSelectedIds.contains(note.id) },
                                    set: { selected in
                                        if selected {
                                            batchSelectedIds.insert(note.id)
                                        } else {
                                            batchSelectedIds.remove(note.id)
                                        }
                                    }
                                ))
                                .toggleStyle(.checkbox)
                            }

                            VStack(alignment: .leading, spacing: 5) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text(note.title.isEmpty ? "Untitled Note" : note.title)
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(isSelected ? .white : .primary)
                                        .lineLimit(1)

                                    Spacer()

                                    if note.isPinned {
                                        Image(systemName: "pin.fill")
                                            .font(.caption2)
                                            .foregroundColor(.accentColor)
                                    }
                                    if note.isFavorite {
                                        Image(systemName: "star.fill")
                                            .font(.caption2)
                                            .foregroundColor(.yellow)
                                    }
                                }

                                Text(cleanSummary(note.content))
                                    .font(.caption2)
                                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                                    .lineLimit(2)

                                HStack(spacing: 6) {
                                    Text(note.category)
                                        .font(.system(size: 9, weight: .bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(isSelected ? .white.opacity(0.2) : Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
                                        .foregroundColor(isSelected ? .white : .accentColor)

                                    Spacer()

                                    Text(note.updatedAt.formatted(date: .abbreviated, time: .omitted))
                                        .font(.system(size: 9))
                                        .foregroundColor(isSelected ? .white.opacity(0.7) : .secondary)
                                }
                            }
                        }
                        .padding(10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(isSelected ? Color.accentColor : Color.clear)
                        )
                        .onTapGesture {
                            if isBatchSelecting {
                                if batchSelectedIds.contains(note.id) {
                                    batchSelectedIds.remove(note.id)
                                } else {
                                    batchSelectedIds.insert(note.id)
                                }
                            } else {
                                state.selectNote(note.id)
                            }
                        }
                        .contextMenu {
                            Button("Pin note") {
                                if let idx = state.notes.firstIndex(where: { $0.id == note.id }) {
                                    state.notes[idx].isPinned.toggle()
                                    state.saveData()
                                }
                            }
                            Button("Favorite note") {
                                if let idx = state.notes.firstIndex(where: { $0.id == note.id }) {
                                    state.notes[idx].isFavorite.toggle()
                                    state.saveData()
                                }
                            }
                            Button("Archive / Unarchive") {
                                if let idx = state.notes.firstIndex(where: { $0.id == note.id }) {
                                    state.notes[idx].isArchived.toggle()
                                    state.saveData()
                                }
                            }
                            Button("Duplicate Note") {
                                state.duplicateNote(note)
                            }
                            Button("Select Multiple") {
                                isBatchSelecting = true
                                batchSelectedIds.insert(note.id)
                            }
                            Divider()
                            Button("Delete", role: .destructive) {
                                state.deleteNote(note)
                            }
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private func cleanSummary(_ content: String) -> String {
        let lines = content.components(separatedBy: .newlines)
        let filtered = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        let text = filtered.joined(separator: " ")
        return text.isEmpty ? "No content." : text
    }

    // MARK: - 3. Right Editor Workspace
    @ViewBuilder
    private func editorWorkspaceView() -> some View {
        Group {
            if let note = state.activeNote {
                VStack(spacing: 0) {
                    // Toolbar
                    editorToolbarView(note)

                    Divider()

                    if state.isReadingMode {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(note.title)
                                    .font(.title.bold())
                                Divider()
                                MarkdownBlockListView(blocks: MarkdownParser.shared.parse(state.noteEditorText))
                            }
                            .padding(24)
                            .frame(maxWidth: 800, alignment: .leading)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(NSColor.controlBackgroundColor))
                    } else if state.isPresentationMode {
                        ScrollView {
                            VStack(alignment: .center, spacing: 32) {
                                Text(note.title)
                                    .font(.system(size: 42, weight: .black))
                                    .multilineTextAlignment(.center)
                                    .padding(.top, 40)

                                Divider().frame(width: 100)

                                MarkdownBlockListView(blocks: MarkdownParser.shared.parse(state.noteEditorText))
                                    .font(.title3)
                            }
                            .padding(40)
                            .frame(maxWidth: 900)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(NSColor.windowBackgroundColor))
                    } else {
                        // Regular HSplit view: Editor & Markdown Preview side-by-side
                        HSplitView {
                            // Editor text input (SwiftUI TextEditor — see the
                            // file header; Legacy's NSTextView wrapper is not
                            // carried over).
                            VStack(spacing: 0) {
                                if state.isEditingNote {
                                    TextEditor(text: $scratchPadText)
                                        .font(.system(.body, design: .monospaced))
                                        .padding(10)
                                        .scrollContentBackground(.hidden)
                                        .onChange(of: scratchPadText) { _, newValue in
                                            state.noteEditorText = newValue
                                            state.updateActiveNoteContent(newValue)
                                        }
                                        .onAppear {
                                            scratchPadText = note.content
                                        }
                                        .onChange(of: state.selectedNoteId) { _, _ in
                                            scratchPadText = note.content
                                        }
                                } else {
                                    ScrollView {
                                        Text(state.noteEditorText)
                                            .font(.system(.body, design: .monospaced))
                                            .textSelection(.enabled)
                                            .padding(12)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(NSColor.controlBackgroundColor))

                            Divider()

                            // Preview panel
                            ScrollView {
                                VStack(alignment: .leading, spacing: 16) {
                                    HStack {
                                        Label("LIVE PREVIEW", systemImage: "eye.fill")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.secondary)
                                        Spacer()
                                    }
                                    Divider()

                                    if state.noteEditorText.isEmpty {
                                        Text("*Empty note content*")
                                            .foregroundColor(.secondary)
                                            .font(.subheadline)
                                    } else {
                                        MarkdownBlockListView(blocks: MarkdownParser.shared.parse(state.noteEditorText))
                                    }
                                }
                                .padding(16)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(NSColor.windowBackgroundColor))
                        }
                    }
                }
            } else {
                ContentUnavailableView("No Note Selected", systemImage: "doc.text.fill", description: Text("Select a note from the list, or create a brand new guide to start writing."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    @ViewBuilder
    private func editorToolbarView(_ note: ProjectNote) -> some View {
        VStack(spacing: 0) {
            // Row 1: Note Details & Global Modes
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(note.title)
                            .font(.headline)

                        Button {
                            if let idx = state.notes.firstIndex(where: { $0.id == note.id }) {
                                state.notes[idx].isPinned.toggle()
                                state.saveData()
                            }
                        } label: {
                            Image(systemName: note.isPinned ? "pin.fill" : "pin")
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)

                        Button {
                            if let idx = state.notes.firstIndex(where: { $0.id == note.id }) {
                                state.notes[idx].isFavorite.toggle()
                                state.saveData()
                            }
                        } label: {
                            Image(systemName: note.isFavorite ? "star.fill" : "star")
                                .foregroundColor(.yellow)
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Words: \(note.wordCount) | Read: \(note.readingTime)m | Characters: \(note.characterCount)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Layout control buttons
                Group {
                    Button {
                        state.isFocusMode.toggle()
                    } label: {
                        Image(systemName: state.isFocusMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    }
                    .buttonStyle(.bordered)
                    .help("Toggle Focus Mode (Cmd+Opt+F)")

                    Button {
                        state.isReadingMode.toggle()
                        state.isPresentationMode = false
                    } label: {
                        Image(systemName: "book.fill")
                            .foregroundColor(state.isReadingMode ? .accentColor : .primary)
                    }
                    .buttonStyle(.bordered)
                    .help("Toggle Reading Mode")

                    Button {
                        state.isPresentationMode.toggle()
                        state.isReadingMode = false
                    } label: {
                        Image(systemName: "play.rectangle.fill")
                            .foregroundColor(state.isPresentationMode ? .accentColor : .primary)
                    }
                    .buttonStyle(.bordered)
                    .help("Toggle Presentation Mode")

                    Button {
                        showSidebar.toggle()
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.isFocusMode)
                    .help("Toggle Left Sidebar")

                    Button {
                        showInspector.toggle()
                    } label: {
                        Image(systemName: "sidebar.right")
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.isFocusMode)
                    .help("Toggle Right Inspector")
                }

                Divider().frame(height: 16)

                // Save or edit trigger
                if state.isEditingNote {
                    Button {
                        state.saveActiveNote(content: scratchPadText)
                    } label: {
                        Text("Save Note")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                } else {
                    Button {
                        state.isEditingNote = true
                    } label: {
                        Text("Edit Note")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            // Row 2: Formatting Toolbar Helpers (if editing)
            if state.isEditingNote && !state.isReadingMode && !state.isPresentationMode {
                Divider()
                HStack(spacing: 14) {
                    Button { insertText("- [ ] ") } label: { Image(systemName: "checkmark.square") }.buttonStyle(.plain).help("Add Checklist Item")
                    Button { insertText("\n| Col 1 | Col 2 |\n| --- | --- |\n| Cell | Cell |\n") } label: { Image(systemName: "tablecells") }.buttonStyle(.plain).help("Add Table Structure")
                    Button { insertText("\n```swift\n// Write Swift Code\n\n```\n") } label: { Image(systemName: "curlybraces") }.buttonStyle(.plain).help("Add Code Block")
                    Button { insertText("\n> [!NOTE]\n> This is an executive info block.\n") } label: { Image(systemName: "info.circle") }.buttonStyle(.plain).help("Add Note Callout")
                    Button { insertText("\n> [!WARNING]\n> This is a critical warning block.\n") } label: { Image(systemName: "exclamationmark.triangle") }.buttonStyle(.plain).help("Add Warning Callout")
                    Button { insertText("\n> [!TIP]\n> Here is a quick development tip.\n") } label: { Image(systemName: "lightbulb") }.buttonStyle(.plain).help("Add Tip Callout")

                    Divider().frame(height: 14)

                    // Template picker
                    Picker("Template:", selection: $state.selectedTemplateKey) {
                        Text("Choose a template...").tag("None")
                        ForEach(Array(ProjectNoteTemplates.builtInTemplates.keys).sorted(), id: \.self) { key in
                            Text(key).tag(key)
                        }
                    }
                    .frame(width: 210)
                    .onChange(of: state.selectedTemplateKey) { _, newValue in
                        if newValue != "None", let tText = ProjectNoteTemplates.builtInTemplates[newValue] {
                            state.noteEditorText = tText
                            scratchPadText = tText
                            state.updateActiveNoteContent(tText)
                        }
                    }

                    Spacer()

                    // Category dropdown modifier
                    Picker("Category:", selection: Binding(
                        get: { note.category },
                        set: { newCat in
                            if let idx = state.notes.firstIndex(where: { $0.id == note.id }) {
                                state.notes[idx].category = newCat
                                state.saveData()
                            }
                        }
                    )) {
                        ForEach(categories.filter { $0 != "All" }, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                    .frame(width: 180)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.04))
            }
        }
    }

    private func insertText(_ text: String) {
        scratchPadText += text
        state.noteEditorText = scratchPadText
        state.updateActiveNoteContent(scratchPadText)
    }

    // MARK: - 4. Collapsible Right Inspector Panel
    @ViewBuilder
    private func inspectorPanelView() -> some View {
        VStack(spacing: 0) {
            // Tab Selector Header
            HStack {
                InspectorTabButton(title: "AI", icon: "sparkles", selected: state.activeInspectorTab == "AI Copilot") {
                    state.activeInspectorTab = "AI Copilot"
                }
                InspectorTabButton(title: "Links", icon: "link", selected: state.activeInspectorTab == "Links") {
                    state.activeInspectorTab = "Links"
                }
                InspectorTabButton(title: "Files", icon: "paperclip", selected: state.activeInspectorTab == "Attachments") {
                    state.activeInspectorTab = "Attachments"
                }
                InspectorTabButton(title: "History", icon: "clock.arrow.circlepath", selected: state.activeInspectorTab == "History") {
                    state.activeInspectorTab = "History"
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)

            Divider()

            // Tab Content
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if state.activeInspectorTab == "AI Copilot" {
                        aiCopilotInspectorView()
                    } else if state.activeInspectorTab == "Links" {
                        linksInspectorView()
                    } else if state.activeInspectorTab == "Attachments" {
                        attachmentsInspectorView()
                    } else {
                        versionHistoryInspectorView()
                    }
                }
                .padding(14)
            }
        }
    }

    private struct InspectorTabButton: View {
        let title: String
        let icon: String
        let selected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                VStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.subheadline)
                    Text(title)
                        .font(.system(size: 9, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(selected ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                .foregroundColor(selected ? .accentColor : .primary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Inspector Tab A: AI Copilot
    //
    // Runs one-shot completions through the destination's real provider
    // dispatch (`LLMToolCompletionService`, gap-closure LLM wiring) using
    // the provider + model chosen in Settings — never a hardcoded model,
    // never canned text. Legacy streamed tokens live; this tab shows a
    // progress view and then the full reply. When no provider is usable
    // the error names the provider and what is missing (an API key, a
    // running server, an endpoint URL, an installed CLI, Apple
    // Intelligence); it is shown verbatim, never replaced by a fake.
    @State private var aiPrompt = ""
    @State private var aiOutputText = ""
    @State private var isAIProcessing = false
    @State private var aiErrorText: String? = nil

    @ViewBuilder
    private func aiCopilotInspectorView() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("AI DOCUMENT WORKSPACE")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)

            Text("Runs through the coding assistant's configured provider.")
                .font(.caption)
                .foregroundColor(.secondary)

            let aiShortcuts = [
                "Summarize and list key objectives": "Write a concise summary and highlight key bullet point objectives.",
                "Expand with technical references": "Expand the active note content with comprehensive details, APIs, and reference blocks.",
                "Shorten and make concise": "Rewrite this note to be highly concise, eliminating fluff while keeping key specifications.",
                "Improve grammar and structure": "Fix spelling, formatting, and improve structural hierarchy under professional iOS/macOS developer standards.",
                "Generate detailed unit test cases": "Analyze this content and compile a set of clean, fully-commented Swift unit testing cases.",
                "Review code block complexity": "Identify any potential inefficiencies or thread-safety issues inside code blocks and suggest safe optimizations."
            ]

            VStack(spacing: 8) {
                ForEach(Array(aiShortcuts.keys).sorted(), id: \.self) { label in
                    Button {
                        triggerAICopilot(prompt: aiShortcuts[label] ?? "")
                    } label: {
                        HStack {
                            Image(systemName: "sparkles")
                                .foregroundColor(.purple)
                            Text(label)
                                .font(.subheadline)
                            Spacer()
                        }
                        .padding(8)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .disabled(isAIProcessing)
                }
            }

            Divider()

            // Custom prompt box
            VStack(alignment: .leading, spacing: 6) {
                Text("Custom AI Prompt")
                    .font(.caption.bold())
                HStack {
                    TextField("Enter prompt...", text: $aiPrompt)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            triggerAICopilot(prompt: aiPrompt)
                        }

                    Button {
                        triggerAICopilot(prompt: aiPrompt)
                    } label: {
                        Image(systemName: "paperplane.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isAIProcessing || aiPrompt.isEmpty)
                }
            }

            if isAIProcessing || !aiOutputText.isEmpty || aiErrorText != nil {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("AI Generating Insights...")
                            .font(.subheadline.bold())
                            .foregroundColor(.purple)
                        Spacer()
                        if isAIProcessing {
                            ProgressView().controlSize(.small)
                        } else if !aiOutputText.isEmpty {
                            Button("Copy Result") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(aiOutputText, forType: .string)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)

                            Button("Prepend") {
                                scratchPadText = "## AI Assistant Insights\n\(aiOutputText)\n\n" + scratchPadText
                                state.noteEditorText = scratchPadText
                                state.updateActiveNoteContent(scratchPadText)
                                aiOutputText = ""
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.green)
                        }
                    }

                    if let aiErrorText {
                        Text(aiErrorText)
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .textSelection(.enabled)
                            .padding(8)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    } else if !aiOutputText.isEmpty {
                        ScrollView {
                            Text(aiOutputText)
                                .font(.subheadline)
                                .textSelection(.enabled)
                                .padding(8)
                                .background(Color.black.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                        }
                        .frame(maxHeight: 180)
                    }
                }
            }
        }
    }

    private func triggerAICopilot(prompt: String) {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        aiOutputText = ""
        aiErrorText = nil
        aiPrompt = ""
        isAIProcessing = true

        // Legacy's system prompt, with the active note as context.
        let systemPrompt = """
        You are a highly skilled, world-class technical documentation assistant.
        Help the developer refine, generate, format, structure, review, or summarize their markdown-based documentation.
        Always return beautiful, readable, fully-commented Markdown and inline code blocks where appropriate.

        Context of active note:
        [START ACTIVE NOTE CONTENT]
        \(state.noteEditorText)
        [END ACTIVE NOTE CONTENT]
        """

        Task {
            do {
                let service = LLMToolCompletionService(backends: CodingAssistantServices.shared.backends())
                let result = try await service.complete(systemPrompt: systemPrompt, userText: prompt)
                aiOutputText = result.text
            } catch {
                aiErrorText = error.localizedDescription
            }
            isAIProcessing = false
        }
    }

    // MARK: - Inspector Tab B: Links & References
    @State private var showAddLinkSheet = false
    @State private var showAddFileRefSheet = false
    @State private var newFileRefPath = ""
    @State private var newSymbolName = ""
    @State private var newCommitHash = ""

    @ViewBuilder
    private func linksInspectorView() -> some View {
        guard let note = state.activeNote else {
            return AnyView(EmptyView())
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 14) {
                // Outbound Internal Links
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("INTERNAL LINKS")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("+ Link Note") {
                            showAddLinkSheet = true
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                    }

                    let outbound = state.notes.filter { note.linkedNoteIds.contains($0.id) }
                    if outbound.isEmpty {
                        Text("None. Use Double Brackets [[Note Title]] in your markdown editor to link notes automatically.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(outbound) { linked in
                            HStack {
                                Image(systemName: "doc.text")
                                Text(linked.title)
                                    .font(.subheadline)
                                Spacer()
                                Button {
                                    state.unlinkNote(from: note.id, to: linked.id)
                                } label: {
                                    Image(systemName: "multiply.circle")
                                }
                                .buttonStyle(.plain)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                state.selectNote(linked.id)
                            }
                        }
                    }
                }

                Divider()

                // Backlinks
                VStack(alignment: .leading, spacing: 6) {
                    Text("BACKLINKS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)

                    let backlinks = state.notes.filter { note.backlinkNoteIds.contains($0.id) }
                    if backlinks.isEmpty {
                        Text("No inbound backlinks.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(backlinks) { backlinked in
                            HStack {
                                Image(systemName: "arrow.uturn.backward.square")
                                Text(backlinked.title)
                                    .font(.subheadline)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                state.selectNote(backlinked.id)
                            }
                        }
                    }
                }

                Divider()

                // Linked Files & Project Symbols
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("PROJECT REFERENCES")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("+ Ref") {
                            showAddFileRefSheet = true
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                    }

                    if note.linkedFiles.isEmpty && note.linkedSymbols.isEmpty && note.linkedGitCommits.isEmpty {
                        Text("None link registered yet.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(note.linkedFiles, id: \.self) { file in
                            HStack {
                                Image(systemName: "doc.text.fill")
                                    .foregroundColor(.accentColor)
                                Text(file)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Spacer()
                                Button {
                                    if let idx = state.notes.firstIndex(where: { $0.id == note.id }) {
                                        state.notes[idx].linkedFiles.removeAll { $0 == file }
                                        state.saveData()
                                    }
                                } label: {
                                    Image(systemName: "multiply.circle")
                                }
                                .buttonStyle(.plain)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                // post notification to open in workspace
                                NotificationCenter.default.post(
                                    name: NSNotification.Name("com.swiftcode.openFileInWorkspace"),
                                    object: nil,
                                    userInfo: ["filePath": file]
                                )
                            }
                        }

                        ForEach(note.linkedSymbols, id: \.self) { sym in
                            HStack {
                                Image(systemName: "cube.fill")
                                    .foregroundColor(.purple)
                                Text(sym)
                                    .font(.subheadline)
                                Spacer()
                                Button {
                                    if let idx = state.notes.firstIndex(where: { $0.id == note.id }) {
                                        state.notes[idx].linkedSymbols.removeAll { $0 == sym }
                                        state.saveData()
                                    }
                                } label: {
                                    Image(systemName: "multiply.circle")
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        ForEach(note.linkedGitCommits, id: \.self) { commit in
                            HStack {
                                Image(systemName: "arrow.triangle.branch")
                                    .foregroundColor(.green)
                                Text("Commit: \(commit)")
                                    .font(.system(.caption, design: .monospaced))
                                Spacer()
                                Button {
                                    if let idx = state.notes.firstIndex(where: { $0.id == note.id }) {
                                        state.notes[idx].linkedGitCommits.removeAll { $0 == commit }
                                        state.saveData()
                                    }
                                } label: {
                                    Image(systemName: "multiply.circle")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddLinkSheet) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Link Active Note with:")
                        .font(.headline)
                    List(state.notes.filter { $0.id != note.id }) { candidate in
                        Button {
                            state.linkNote(from: note.id, to: candidate.id)
                            showAddLinkSheet = false
                        } label: {
                            HStack {
                                Image(systemName: "doc.text")
                                Text(candidate.title)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }
                    Button("Cancel") {
                        showAddLinkSheet = false
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .frame(width: 320, height: 400)
            }
            .sheet(isPresented: $showAddFileRefSheet) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Add Project Reference")
                        .font(.headline)

                    Form {
                        TextField("File Path (Relative/Absolute)", text: $newFileRefPath)
                        TextField("Class/Struct Name", text: $newSymbolName)
                        TextField("Git Commit Hash", text: $newCommitHash)
                    }
                    .formStyle(.grouped)

                    HStack {
                        Button("Cancel") {
                            showAddFileRefSheet = false
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button("Register") {
                            if let idx = state.notes.firstIndex(where: { $0.id == note.id }) {
                                let fPath = newFileRefPath.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !fPath.isEmpty {
                                    state.notes[idx].linkedFiles.append(fPath)
                                }
                                let sym = newSymbolName.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !sym.isEmpty {
                                    state.notes[idx].linkedSymbols.append(sym)
                                }
                                let com = newCommitHash.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !com.isEmpty {
                                    state.notes[idx].linkedGitCommits.append(com)
                                }
                                state.saveData()
                            }
                            newFileRefPath = ""
                            newSymbolName = ""
                            newCommitHash = ""
                            showAddFileRefSheet = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding()
                .frame(width: 350)
            }
        )
    }

    // MARK: - Inspector Tab C: Attachments
    @State private var previewingAttachment: NoteAttachment? = nil
    @State private var attachmentPreviewContent = ""

    @ViewBuilder
    private func attachmentsInspectorView() -> some View {
        guard let note = state.activeNote else {
            return AnyView(EmptyView())
        }

        return AnyView(
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("NOTE ATTACHMENTS")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("+ Add Attachment") {
                        addAttachmentPanelAction(note)
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                }

                if note.attachments.isEmpty {
                    Text("No attachments yet. Link PDFs, JSON configurations, or YAML code assets.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(note.attachments) { attachment in
                        HStack {
                            Image(systemName: iconForAttachment(attachment.type))
                                .foregroundColor(.blue)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(attachment.name)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Text(attachment.type.uppercased())
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()

                            Button("Preview") {
                                previewAttachmentAction(attachment)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)

                            Button {
                                state.deleteAttachment(attachment, from: note)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.red)
                        }
                    }
                }
            }
            .sheet(item: $previewingAttachment) { att in
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Label(att.name, systemImage: iconForAttachment(att.type))
                            .font(.headline)
                        Spacer()
                        Button("Close") {
                            previewingAttachment = nil
                        }
                        .buttonStyle(.bordered)
                    }

                    Divider()

                    ScrollView {
                        if att.type == "image" {
                            let url = state.baseDirectoryURL.appendingPathComponent(att.relativePath)
                            if let img = NSImage(contentsOf: url) {
                                Image(nsImage: img)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                            } else {
                                Text("Failed to render image.")
                            }
                        } else {
                            Text(attachmentPreviewContent)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding()
                .frame(width: 500, height: 400)
            }
        )
    }

    private func iconForAttachment(_ type: String) -> String {
        switch type {
        case "image": return "photo"
        case "pdf": return "doc.richtext"
        case "markdown": return "text.justify"
        case "swift": return "swift"
        case "zip": return "archivebox"
        default: return "paperclip"
        }
    }

    private func addAttachmentPanelAction(_ note: ProjectNote) {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                state.attachFile(to: note, fileURL: url)
            }
        }
    }

    private func previewAttachmentAction(_ att: NoteAttachment) {
        let fileURL = state.baseDirectoryURL.appendingPathComponent(att.relativePath)
        if ["image", "pdf"].contains(att.type) {
            previewingAttachment = att
        } else {
            if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                attachmentPreviewContent = content
                previewingAttachment = att
            } else {
                attachmentPreviewContent = "Binary or unreadable file format."
                previewingAttachment = att
            }
        }
    }

    // MARK: - Inspector Tab D: Version History
    @ViewBuilder
    private func versionHistoryInspectorView() -> some View {
        guard let note = state.activeNote else {
            return AnyView(EmptyView())
        }

        let history = state.noteVersions.filter { $0.noteId == note.id }

        return AnyView(
            VStack(alignment: .leading, spacing: 14) {
                Text("REVISION HISTORY LOG")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)

                if history.isEmpty {
                    Text("No snapshots recorded yet. Versions are created when changes are manually saved.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(history) { version in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(version.timestamp.formatted())
                                        .font(.subheadline.bold())
                                    Text("\(version.content.count) characters")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button("Rollback") {
                                    state.rollbackToVersion(version)
                                    scratchPadText = version.content
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            Divider()
                        }
                    }
                }
            }
        )
    }
}

// MARK: - Native Window Manager & Controller
//
// Destination pattern (SQLite Explorer, CI, Deployment window controllers
// in SwiftCodeUI): a shared manager that raises the existing window or
// creates one, and an NSWindowController that builds the window. The
// manager is a singleton holding one window, so there is one live
// `ProjectNotesWorkspaceState` in practice (the view owns its state;
// see the file header).

@MainActor
public final class ProjectNotesWindowManager: NSObject {
    public static let shared = ProjectNotesWindowManager()
    private var windowController: ProjectNotesWindowController?

    private override init() {
        super.init()
    }

    public func showWindow() {
        if let existing = windowController {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let controller = ProjectNotesWindowController()
        self.windowController = controller
        controller.window?.delegate = self
        controller.window?.makeKeyAndOrderFront(nil)
    }

    public func closeWindow() {
        windowController?.close()
        windowController = nil
    }
}

extension ProjectNotesWindowManager: NSWindowDelegate {
    public func windowWillClose(_ notification: Notification) {
        windowController = nil
    }
}

@MainActor
public final class ProjectNotesWindowController: NSWindowController {
    public init() {
        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1000, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Project Notes"
        window.minSize = NSSize(width: 800, height: 600)
        window.setFrameAutosaveName("SwiftCodeProjectNotesWindow")
        window.isReleasedWhenClosed = false

        let hostedView = ProjectNotesWorkspaceView()
        window.contentView = NSHostingView(rootView: hostedView)

        super.init(window: window)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}
