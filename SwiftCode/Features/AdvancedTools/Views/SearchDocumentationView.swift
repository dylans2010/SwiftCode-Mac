import SwiftUI
import AppKit

// MARK: - Smart Note Version Snapshot
struct NoteVersion: Identifiable, Codable, Hashable {
    let id: UUID
    var notePath: String
    var contentSnapshot: String
    var timestamp: Date
}

struct SearchDocumentationView: View {
    @ObservedObject private var settings = AppSettings.shared

    // Overall view mode
    @State private var activeWorkspaceMode = 0 // 0 = Link Summarizer, 1 = Project Notes Workspace

    // ==================================================
    // 1. LINK SUMMARIZER STATE
    // ==================================================
    @State private var urlInput = ""
    @State private var summaryResponse = ""
    @State private var isSummarizing = false
    @State private var summaryTitle = "Documentation Summary"

    private var parsedBlocks: [MarkdownBlock] {
        MarkdownRenderer.shared.parse(summaryResponse)
    }

    // ==================================================
    // 2. PROJECT NOTES WORKSPACE STATE
    // ==================================================
    @State private var notes: [ProjectNote] = []
    @State private var selectedNote: ProjectNote?
    @State private var noteEditorText = ""
    @State private var noteSearchQuery = ""
    @State private var isEditingNote = false
    @State private var noteFilter = "All" // All, Pinned, Favorites, Todo, Meeting, Build
    @State private var isAIProcessingNote = false
    @State private var aiNoteResult = ""
    @State private var showAISheet = false

    // Note Snapshots Version History
    @State private var noteVersions: [NoteVersion] = []
    @State private var showVersionHistorySheet = false

    // Selected Template
    @State private var selectedTemplate = "None"

    let noteCategories = ["General", "Todo", "Meeting", "Build"]
    let noteTemplates = [
        "None": "",
        "Technical Architecture Spec": "# Technical Architecture Specification\n\n## Overview\nState the project's purpose and system context.\n\n## Component Diagram\n- [ ] UI Layer (SwiftUI)\n- [ ] Core Engine (Actors)\n- [ ] Persistence (SQLite3)\n\n## Data Flow\nExplain how elements communicate.",
        "Engineering Meeting Notes": "# Engineering Sync Notes\n**Date:** 2026-01-01\n**Attendees:** Engineering Team\n\n## Discussion Points\n1. Module Refactoring\n2. SQL Performance benchmarks\n\n## Action Items\n- [ ] Rebuild table constraint indexes\n- [ ] Setup scheduled automatic cloud backups",
        "Release Notes Template": "# Release Notes - Version 1.0.0\n\n## Summary\nConcise recap of this build cycle.\n\n## Highlights & Fixes\n- **Feature:** Expanded database performance analyzer\n- **Fix:** Add Row button constraint integrity resolver"
    ]

    var filteredNotes: [ProjectNote] {
        var list = notes
        switch noteFilter {
        case "Pinned":
            list = list.filter { $0.isPinned }
        case "Favorites":
            list = list.filter { $0.isFavorite }
        case "Todo":
            list = list.filter { $0.category == "Todo" }
        case "Meeting":
            list = list.filter { $0.category == "Meeting" }
        case "Build":
            list = list.filter { $0.category == "Build" }
        default:
            break
        }

        if !noteSearchQuery.isEmpty {
            list = list.filter { $0.title.localizedCaseInsensitiveContains(noteSearchQuery) || $0.content.localizedCaseInsensitiveContains(noteSearchQuery) }
        }
        return list
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Main Workspace Top Navigator
                HStack {
                    Picker("Workspace", selection: $activeWorkspaceMode) {
                        Text("Web Link Summarizer").tag(0)
                        Text("Project Notes Workspace").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 450)

                    Spacer()
                }
                .padding(14)
                .background(Color(NSColor.windowBackgroundColor))

                Divider()

                if activeWorkspaceMode == 0 {
                    // Link Summarizer Layout
                    linkSummarizerWorkspace()
                } else {
                    // Project Notes Workspace Layout
                    projectNotesWorkspace()
                }
            }
            .navigationTitle(activeWorkspaceMode == 0 ? "Link Summarizer" : "Project Knowledge Workspace")
        }
        .onAppear {
            loadLocalNotes()
        }
    }

    // ====================================================================
    // LINK SUMMARIZER INTERFACE
    // ====================================================================
    @ViewBuilder
    private func linkSummarizerWorkspace() -> some View {
        VStack(spacing: 0) {
            // Top control bar
            VStack(alignment: .leading, spacing: 12) {
                Text("Web Link & Documentation Summarizer")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Text("Paste any GitHub repository link, generic documentation page, or developer guide below. The default AI model will analyze and summarize its contents with comprehensive markdown formatting, structural tables, and code snippets.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    HStack {
                        Image(systemName: "link")
                            .foregroundStyle(.secondary)
                        TextField("Paste GitHub repository or documentation link here (e.g., https://github.com/...)", text: $urlInput)
                            .textFieldStyle(.plain)
                            .onSubmit {
                                startSummarization()
                            }
                    }
                    .padding(10)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                    Button(action: startSummarization) {
                        if isSummarizing {
                            ProgressView()
                                .scaleEffect(0.6)
                                .padding(.horizontal, 8)
                        } else {
                            Label("Summarize", systemImage: "sparkles")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(isSummarizing || urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                HStack {
                    Image(systemName: "cpu")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Powered by selected model: \(settings.selectedModel.isEmpty ? "meta-llama/llama-3-70b-instruct" : settings.selectedModel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .padding(16)
            .background(.ultraThinMaterial)

            Divider()

            // Summarization Content Area
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if summaryResponse.isEmpty {
                        VStack(spacing: 16) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 48))
                                .foregroundStyle(.secondary)
                            Text("No Summary Generated Yet")
                                .font(.title3.bold())
                            Text("Paste a link and click 'Summarize' above to receive a highly detailed summary including markdown lists, tables, and usage blocks.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 400)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 100)
                    } else {
                        // Render summarized content using MarkdownBlockListView
                        MarkdownBlockListView(blocks: parsedBlocks)
                            .textSelection(.enabled)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Footer toolbar
            if !summaryResponse.isEmpty {
                HStack {
                    Button("Clear Summary") {
                        summaryResponse = ""
                        urlInput = ""
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                    Spacer()

                    Button("Copy Summary Markdown") {
                        let pb = NSPasteboard.general
                        pb.clearContents()
                        pb.setString(summaryResponse, forType: .string)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.orange)
                }
                .padding()
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
    }

    private func startSummarization() {
        let link = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !link.isEmpty else { return }

        isSummarizing = true
        summaryResponse = ""

        let systemPrompt = """
You are an advanced documentation analyst and software engineering assistant.
The user has provided a link: \(link).
Your goal is to write a highly descriptive, comprehensive summary of the provided web documentation or GitHub repository link.
Your output MUST be structured using beautiful, clean Markdown. You must include:
1. An H1 title for the resource.
2. A concise introduction section.
3. A detailed table outlining key highlights, components, APIs, or files, with descriptive columns.
4. Structured headings (H2/H3) explaining major architectural concepts.
5. Bulleted lists of advantages, use cases, or setup steps.
6. A standard code block showing sample usage or installation commands.
7. A blockquote summarizing the overall utility.
Avoid returning conversational fluff or preambles before or after the markdown. Output ONLY the beautiful formatted markdown blocks.
"""

        let messages = [
            AIMessage(role: .user, content: "Please summarize the documentation or repository at link: \(link)")
        ]

        let model = settings.selectedModel.isEmpty ? "meta-llama/llama-3-70b-instruct" : settings.selectedModel

        Task {
            do {
                try await OpenRouterService.shared.streamChat(
                    messages: messages,
                    model: model,
                    systemPrompt: systemPrompt
                ) { token in
                    await MainActor.run {
                        summaryResponse += token
                    }
                }
                await MainActor.run {
                    isSummarizing = false
                }
            } catch {
                await MainActor.run {
                    summaryResponse = "# Summarization Failed\n\nCould not analyze the link. Error: \(error.localizedDescription)"
                    isSummarizing = false
                }
            }
        }
    }

    // ====================================================================
    // PROJECT KNOWLEDGE WORKSPACE INTERFACE
    // ====================================================================
    @ViewBuilder
    private func projectNotesWorkspace() -> some View {
        HSplitView {
            // Left Column: Note Browser sidebar
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search notes...", text: $noteSearchQuery)
                        .textFieldStyle(.plain)

                    Button(action: createNewLocalNote) {
                        Image(systemName: "doc.badge.plus")
                            .foregroundColor(.blue)
                    }
                    .buttonStyle(.plain)
                    .help("Create New Project Note (Cmd+N)")
                }
                .padding(10)
                .background(Color.secondary.opacity(0.1))
                .cornerRadius(6)
                .padding(10)

                Picker("", selection: $noteFilter) {
                    Text("All Notes").tag("All")
                    Text("📌 Pinned").tag("Pinned")
                    Text("⭐ Favorites").tag("Favorites")
                    Text("✅ Todos").tag("Todo")
                    Text("👥 Meetings").tag("Meeting")
                    Text("🛠️ Builds").tag("Build")
                }
                .pickerStyle(.menu)
                .padding(.horizontal, 10)
                .padding(.bottom, 8)

                Divider()

                List(filteredNotes, selection: $selectedNote) { note in
                    HStack {
                        Image(systemName: note.category == "Todo" ? "checkmark.circle.fill" : (note.category == "Meeting" ? "person.2.fill" : "doc.text.fill"))
                            .foregroundColor(note.category == "Todo" ? .green : (note.category == "Meeting" ? .purple : .blue))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(note.title)
                                .font(.subheadline.bold())
                                .foregroundColor(.primary)
                            Text(note.path)
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        if note.isPinned {
                            Image(systemName: "pin.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 9))
                        }
                        if note.isFavorite {
                            Image(systemName: "star.fill")
                                .foregroundColor(.yellow)
                                .font(.system(size: 9))
                        }
                    }
                    .padding(.vertical, 4)
                    .tag(note)
                }
                .listStyle(.inset)
            }
            .frame(width: 250)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Right Column: Split Note Editor & Rendered Preview Layout
            VStack(spacing: 0) {
                if let note = selectedNote {
                    VStack(spacing: 0) {
                        // Title bar
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(note.title)
                                        .font(.title3.bold())
                                    if note.isPinned {
                                        Image(systemName: "pin.fill")
                                            .foregroundColor(.orange)
                                    }
                                    if note.isFavorite {
                                        Image(systemName: "star.fill")
                                            .foregroundColor(.yellow)
                                    }
                                }
                                Text("Category: \(note.category) | Tags: \(note.tags.joined(separator: ", "))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            // Toolbar actions
                            Group {
                                Button {
                                    toggleNoteMeta("[PINNED]")
                                } label: {
                                    Image(systemName: note.isPinned ? "pin.slash.fill" : "pin.fill")
                                        .foregroundColor(.orange)
                                }
                                .buttonStyle(.bordered)
                                .help("Pin Note")

                                Button {
                                    toggleNoteMeta("[FAVORITE]")
                                } label: {
                                    Image(systemName: note.isFavorite ? "star.slash.fill" : "star.fill")
                                        .foregroundColor(.yellow)
                                }
                                .buttonStyle(.bordered)
                                .help("Favorite Note")

                                Menu {
                                    Button("General") { setNoteCategory("General") }
                                    Button("Todo") { setNoteCategory("Todo") }
                                    Button("Meeting") { setNoteCategory("Meeting") }
                                    Button("Build") { setNoteCategory("Build") }
                                } label: {
                                    Label("Category", systemImage: "tag")
                                }
                                .menuStyle(.borderlessButton)
                                .frame(width: 90)

                                Button {
                                    duplicateNote()
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                }
                                .buttonStyle(.bordered)
                                .help("Duplicate Note")

                                Button {
                                    showVersionHistorySheet = true
                                } label: {
                                    Image(systemName: "clock.arrow.circlepath")
                                }
                                .buttonStyle(.bordered)
                                .help("Snapshots & History")
                            }

                            Toggle("Edit Mode", isOn: $isEditingNote)
                                .toggleStyle(.button)

                            if isEditingNote {
                                Button("Save File") {
                                    saveNoteChanges()
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)
                            }
                        }
                        .padding(12)
                        .background(Color(NSColor.windowBackgroundColor))

                        Divider()

                        // Editing toolbar helpers
                        if isEditingNote {
                            HStack(spacing: 12) {
                                Button { insertEditorText("- [ ] ") } label: { Label("Todo", systemImage: "checkmark.square") }.buttonStyle(.plain)
                                Button { insertEditorText("\n| Col 1 | Col 2 |\n| --- | --- |\n| Cell | Cell |\n") } label: { Label("Table", systemImage: "tablecells") }.buttonStyle(.plain)
                                Button { insertEditorText("\n```swift\n// Code snippet\n```\n") } label: { Label("Code Block", systemImage: "curlybraces") }.buttonStyle(.plain)

                                Picker("Note Template:", selection: $selectedTemplate) {
                                    ForEach(Array(noteTemplates.keys).sorted(), id: \.self) { key in
                                        Text(key).tag(key)
                                    }
                                }
                                .frame(width: 200)
                                .onChange(of: selectedTemplate) { _, newValue in
                                    if let tText = noteTemplates[newValue], !tText.isEmpty {
                                        noteEditorText = tText
                                    }
                                }

                                Spacer()

                                Button {
                                    runAINoteAnalysis(mode: "Summary")
                                } label: {
                                    Label("AI Summarize", systemImage: "sparkles")
                                        .foregroundColor(.purple)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    runAINoteAnalysis(mode: "ActionItems")
                                } label: {
                                    Label("AI Action Items", systemImage: "checklist")
                                        .foregroundColor(.indigo)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.04))
                            Divider()
                        }

                        // Split pane layout
                        HSplitView {
                            // Editor pane
                            VStack {
                                if isEditingNote {
                                    TextEditor(text: $noteEditorText)
                                        .font(.system(.body, design: .monospaced))
                                        .padding(8)
                                } else {
                                    ScrollView {
                                        Text(noteEditorText)
                                            .font(.system(.body, design: .monospaced))
                                            .padding(12)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(NSColor.controlBackgroundColor))

                            Divider()

                            // Preview pane
                            ScrollView {
                                VStack(alignment: .leading, spacing: 14) {
                                    Text("DOCUMENTATION LIVE PREVIEW")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.secondary)

                                    Divider()

                                    if noteEditorText.isEmpty {
                                        Text("*Empty file content*")
                                            .foregroundColor(.secondary)
                                            .font(.subheadline)
                                    } else {
                                        MarkdownBlockListView(blocks: MarkdownParser.shared.parse(noteEditorText))
                                    }
                                }
                                .padding(16)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color(NSColor.windowBackgroundColor))
                        }
                    }
                } else {
                    ContentUnavailableView("No Technical Note Selected", systemImage: "doc.text", description: Text("Choose a markdown guide or release sync notes in the sidebar, or create a new file."))
                }
            }
        }
        .sheet(isPresented: $showAISheet) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("AI Technical Analysis", systemImage: "sparkles")
                        .font(.headline)
                        .foregroundColor(.purple)
                    Spacer()
                    Button("Dismiss") { showAISheet = false }
                        .buttonStyle(.bordered)
                }

                Divider()

                ScrollView {
                    Text(aiNoteResult)
                        .font(.body)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                }

                HStack {
                    Button("Prepend to Top of Document") {
                        noteEditorText = "# AI Insights\n\(aiNoteResult)\n\n" + noteEditorText
                        showAISheet = false
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)

                    Spacer()
                }
            }
            .padding()
            .frame(width: 550, height: 420)
        }
        .sheet(isPresented: $showVersionHistorySheet) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label("Note Snapshot Snapshots (Version History)", systemImage: "clock")
                        .font(.headline)
                    Spacer()
                    Button("Close") { showVersionHistorySheet = false }
                        .buttonStyle(.bordered)
                }

                Divider()

                let history = noteVersions.filter { $0.notePath == selectedNote?.path }
                if history.isEmpty {
                    Text("No local history snapshots recorded for this file yet. Save edits to generate snapshots.")
                        .foregroundColor(.secondary)
                        .padding()
                } else {
                    List(history) { version in
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Version Saved at: " + version.timestamp.formatted())
                                    .font(.subheadline.bold())
                                Text("\(version.contentSnapshot.count) characters")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Restore This Version") {
                                noteEditorText = version.contentSnapshot
                                saveNoteChanges()
                                showVersionHistorySheet = false
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
            .padding()
            .frame(width: 500, height: 350)
        }
        .onChange(of: selectedNote) { _, newValue in
            if let note = newValue {
                noteEditorText = note.content
                isEditingNote = false
            }
        }
    }

    // ====================================================================
    // OPERATIONS LOGIC
    // ====================================================================
    private func loadLocalNotes() {
        Task.detached(priority: .userInitiated) {
            let rootPath = FileManager.default.currentDirectoryPath
            let rootURL = URL(fileURLWithPath: rootPath)

            var notesList: [ProjectNote] = []
            let enumerator = FileManager.default.enumerator(at: rootURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])

            if let enumerator {
                let fileURLs = enumerator.allObjects.compactMap { $0 as? URL }
                for fileURL in fileURLs {
                    let ext = fileURL.pathExtension.lowercased()
                    if ext == "md" {
                        let title = fileURL.deletingPathExtension().lastPathComponent
                        let relPath = fileURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
                        if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                            notesList.append(ProjectNote(title: title, path: relPath, content: content, isMarkdown: true))
                        }
                    }
                }
            }

            if notesList.isEmpty {
                notesList = [
                    ProjectNote(title: "Architecture Decisions", path: "Docs/Architecture.md", content: """
# System Architecture Decisions
This outlines the core design specifications.

## Module Segments
1. **Model Persistence**: Clean sqlite integrations.
2. **AI Co-pilot**: Secure API streaming chat.
""", isMarkdown: true)
                ]
            }

            let finalNotes = notesList
            await MainActor.run {
                self.notes = finalNotes
                self.selectedNote = finalNotes.first
            }
        }
    }

    private func createNewLocalNote() {
        let newTitle = "Untitled Note \(notes.count + 1)"
        let newPath = "Docs/\(newTitle).md"
        let newNote = ProjectNote(title: newTitle, path: newPath, content: "# \(newTitle)\n\nStart drafting technical guidelines here.", isMarkdown: true)
        notes.append(newNote)
        selectedNote = newNote
        noteEditorText = newNote.content
        isEditingNote = true
    }

    private func duplicateNote() {
        guard let note = selectedNote else { return }
        let newTitle = "\(note.title) Copy"
        let newPath = "Docs/\(newTitle).md"
        let newNote = ProjectNote(title: newTitle, path: newPath, content: note.content, isMarkdown: note.isMarkdown)
        notes.append(newNote)
        selectedNote = newNote
        noteEditorText = newNote.content
        isEditingNote = false
    }

    private func saveNoteChanges() {
        guard let note = selectedNote, let idx = notes.firstIndex(where: { $0.path == note.path }) else { return }

        // Save current version snapshot before overwriting
        let snap = NoteVersion(id: UUID(), notePath: note.path, contentSnapshot: note.content, timestamp: Date())
        noteVersions.append(snap)

        let updatedNote = ProjectNote(title: note.title, path: note.path, content: noteEditorText, isMarkdown: note.isMarkdown)
        notes[idx] = updatedNote
        selectedNote = updatedNote
        isEditingNote = false

        // Write directly to project files on disk
        let projectURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let fileURL = projectURL.appendingPathComponent(note.path)

        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try noteEditorText.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            print("Disk write failed: \(error.localizedDescription)")
        }
    }

    private func toggleNoteMeta(_ meta: String) {
        guard let note = selectedNote, let idx = notes.firstIndex(where: { $0.path == note.path }) else { return }
        var currentContent = note.content
        if currentContent.contains(meta) {
            currentContent = currentContent.replacingOccurrences(of: "\n" + meta, with: "")
            currentContent = currentContent.replacingOccurrences(of: meta, with: "")
        } else {
            currentContent += "\n" + meta
        }

        let updatedNote = ProjectNote(title: note.title, path: note.path, content: currentContent, isMarkdown: note.isMarkdown)
        notes[idx] = updatedNote
        selectedNote = updatedNote
        noteEditorText = currentContent

        // Write back to disk
        let projectURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let fileURL = projectURL.appendingPathComponent(note.path)
        try? currentContent.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func setNoteCategory(_ cat: String) {
        guard let note = selectedNote, let idx = notes.firstIndex(where: { $0.path == note.path }) else { return }
        var currentContent = note.content

        let categoriesList = ["[CATEGORY:Todo]", "[CATEGORY:Meeting]", "[CATEGORY:Build]"]
        for c in categoriesList {
            currentContent = currentContent.replacingOccurrences(of: "\n" + c, with: "")
            currentContent = currentContent.replacingOccurrences(of: c, with: "")
        }

        if cat != "General" {
            currentContent += "\n[CATEGORY:\(cat)]"
        }

        let updatedNote = ProjectNote(title: note.title, path: note.path, content: currentContent, isMarkdown: note.isMarkdown)
        notes[idx] = updatedNote
        selectedNote = updatedNote
        noteEditorText = currentContent

        // Write back to disk
        let projectURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let fileURL = projectURL.appendingPathComponent(note.path)
        try? currentContent.write(to: fileURL, atomically: true, encoding: .utf8)
    }

    private func insertEditorText(_ text: String) {
        noteEditorText += text
    }

    private func runAINoteAnalysis(mode: String) {
        guard !noteEditorText.isEmpty else { return }
        isAIProcessingNote = true
        aiNoteResult = ""

        let prompt: String
        if mode == "Summary" {
            prompt = "Generate a technical overview summary and bulleted design highlights of the following document:\n\n\(noteEditorText)"
        } else {
            prompt = "Scan the document below and compile an engineering action items checklist to-do log:\n\n\(noteEditorText)"
        }

        Task {
            do {
                let response = try await LLMService.shared.generateResponse(prompt: prompt, useContext: false)
                await MainActor.run {
                    aiNoteResult = response
                    showAISheet = true
                    isAIProcessingNote = false
                }
            } catch {
                await MainActor.run {
                    aiNoteResult = "AI processing error: \(error.localizedDescription)"
                    showAISheet = true
                    isAIProcessingNote = false
                }
            }
        }
    }
}
