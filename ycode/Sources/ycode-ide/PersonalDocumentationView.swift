import SwiftUI

/// Personal Documentation — the SwiftUI window for Legacy's
/// `NSPersonalDocumentationView` + its module views (dashboard, record list,
/// record detail, editors, planning board, wiki, global search), rebuilt in
/// Ycode style on top of `PersonalDocStore`.
///
/// The window is a `NavigationSplitView`: modules in the sidebar, records in
/// the middle, a Markdown editor on the right. All state lives in the store
/// (JSON in Application Support); the view holds no document data itself.
public struct PersonalDocumentationView: View {
    @State private var coordinator: PersonalDocumentationCoordinator
    @State private var editedMarkdown: String = ""
    @State private var editedTitle: String = ""
    @State private var showingNewDocument = false
    @State private var newTitle = ""
    @State private var analysisResult: String?
    @State private var analysisRunning = false

    public init(store: PersonalDocStore) {
        _coordinator = State(initialValue: PersonalDocumentationCoordinator(store: store))
    }

    private var store: PersonalDocStore { coordinator.store }

    public var body: some View {
        NavigationSplitView {
            sidebar
        } content: {
            contentList
        } detail: {
            detail
        }
        .searchable(text: $coordinator.searchQuery, isPresented: $coordinator.searchActive, prompt: "Search documentation")
        .navigationTitle("Personal Documentation")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNewDocument = true } label: { Label("New Document", systemImage: "plus") }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await runAnalysis() } label: { Label("Analyze", systemImage: "sparkles") } }
                    .disabled(analysisRunning)
            }
        }
        .sheet(isPresented: $showingNewDocument) {
            newDocumentSheet
        }
        .sheet(item: Binding(
            get: { analysisResult.map { AnalysisSheet(text: $0) } },
            set: { if $0 == nil { analysisResult = nil } }
        )) { sheet in
            ScrollView { Text(sheet.text).padding().textSelection(.enabled) }
                .frame(minWidth: 480, minHeight: 320)
        }
        .onChange(of: coordinator.selectedDocumentID) { _, _ in syncEditor() }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $coordinator.selectedModuleKind) {
            ForEach(PersonalDocArchetype.allCases, id: \.self) { archetype in
                Section(archetype.rawValue) {
                    ForEach(PersonalDocModuleKind.allCases.filter { $0.archetype == archetype }) { kind in
                        Label(kind.rawValue, systemImage: kind.icon)
                            .tag(kind as PersonalDocModuleKind?)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Modules")
    }

    // MARK: - Content list

    private var contentList: some View {
        Group {
            if coordinator.searchActive, !coordinator.searchQuery.isEmpty {
                List(store.search(query: coordinator.searchQuery)) { result in
                    Button {
                        coordinator.selectDocument(result.document.id)
                        coordinator.selectedModuleKind = result.document.moduleKind
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.document.title).font(.headline)
                            Text(result.snippet).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } else if coordinator.selectedModuleKind == .dashboard {
                dashboardList
            } else if coordinator.selectedModuleKind == .projectWiki {
                wikiList
            } else if coordinator.selectedModuleKind == .templates {
                templateList
            } else if coordinator.selectedModuleKind == .timeline {
                timelineList
            } else if coordinator.selectedModuleKind == .snippets {
                snippetList
            } else if let kind = coordinator.selectedModuleKind {
                List(store.fetchDocuments(for: kind), selection: $coordinator.selectedDocumentID) { doc in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(doc.title).font(.headline).lineLimit(1)
                            if doc.pinned { Image(systemName: "pin.fill").font(.caption).foregroundStyle(.secondary) }
                        }
                        Text(doc.updatedAt, style: .relative).font(.caption).foregroundStyle(.secondary)
                        if !doc.tags.isEmpty {
                            Text(doc.tags.joined(separator: ", ")).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                    .tag(doc.id as UUID?)
                }
            } else {
                ContentUnavailableView("Select a module", systemImage: "doc.text")
            }
        }
        .navigationTitle(coordinator.selectedModuleKind?.rawValue ?? "Documentation")
    }

    private var dashboardList: some View {
        let snapshot = store.dashboardSnapshot()
        return List {
            Section("Overview") {
                LabeledContent("Documents", value: "\(snapshot.totalDocuments)")
                LabeledContent("Structured tasks", value: "\(snapshot.totalTasks)")
                LabeledContent("Completed", value: "\(snapshot.completedTasks)")
            }
            Section("Recently updated") {
                ForEach(snapshot.recentDocuments) { doc in
                    Button { coordinator.selectDocument(doc.id) } label: {
                        VStack(alignment: .leading) {
                            Text(doc.title).font(.headline)
                            Text(doc.moduleKind.rawValue).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var wikiList: some View {
        List(store.fetchWikiPages()) { page in
            Button { coordinator.selectedWikiPageID = page.id } label: {
                VStack(alignment: .leading) {
                    Text(page.title).font(.headline)
                    Text(page.lastUpdated, style: .relative).font(.caption).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private var templateList: some View {
        List(store.templates) { template in
            VStack(alignment: .leading, spacing: 4) {
                Text(template.title).font(.headline)
                Text(template.descriptionText).font(.caption).foregroundStyle(.secondary)
                Text(template.moduleKind.rawValue).font(.caption2).foregroundStyle(.secondary)
                Button("Use template") {
                    _ = store.createDocument(title: template.title, kind: template.moduleKind, markdown: template.markdownSource)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.vertical, 4)
        }
    }

    private var timelineList: some View {
        List(store.fetchTimeline()) { item in
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.headline)
                Text("\(item.detail) · \(item.date, style: .relative)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var snippetList: some View {
        List(store.fetchSnippets()) { snippet in
            VStack(alignment: .leading, spacing: 4) {
                Text(snippet.title).font(.headline)
                Text("\(snippet.language) · \(snippet.category)").font(.caption).foregroundStyle(.secondary)
                Text(snippet.code).font(.system(.caption, design: .monospaced)).lineLimit(3)
            }
        }
    }

    // MARK: - Detail

    private var detail: some View {
        Group {
            if let id = coordinator.selectedDocumentID, let doc = store.fetchDocument(id: id) {
                documentEditor(doc)
            } else if let pageID = coordinator.selectedWikiPageID, let page = store.wikiPages.first(where: { $0.id == pageID }) {
                wikiEditor(page)
            } else {
                ContentUnavailableView("Select a document", systemImage: "doc.text", description: Text("Pick a record from the list, or create a new one."))
            }
        }
    }

    private func documentEditor(_ doc: PersonalDocDocument) -> some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Title", text: $editedTitle)
                    .font(.title2.bold())
                    .textFieldStyle(.plain)
                Spacer()
                Button("Save") { saveEditor(doc) }
                    .buttonStyle(.borderedProminent)
                    .disabled(editedTitle == doc.title && editedMarkdown == doc.markdownSource)
            }
            .padding()
            Divider()
            TextEditor(text: $editedMarkdown)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
            Divider()
            HStack {
                Text("Updated \(doc.updatedAt, style: .relative)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !doc.tags.isEmpty {
                    Text(doc.tags.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                }
                Button(doc.pinned ? "Unpin" : "Pin") {
                    var updated = doc; updated.pinned.toggle(); store.updateDocument(updated)
                }
                .buttonStyle(.bordered).controlSize(.small)
                Button(doc.archived ? "Unarchive" : "Archive") {
                    var updated = doc; updated.archived.toggle(); store.updateDocument(updated)
                }
                .buttonStyle(.bordered).controlSize(.small)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .onAppear { syncEditor() }
    }

    private func wikiEditor(_ page: PersonalDocWikiPage) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(page.title).font(.title2.bold()).padding()
            Divider()
            ScrollView { Text(page.markdownSource).padding().textSelection(.enabled) }
        }
    }

    private func syncEditor() {
        guard let id = coordinator.selectedDocumentID, let doc = store.fetchDocument(id: id) else { return }
        editedTitle = doc.title
        editedMarkdown = doc.markdownSource
    }

    private func saveEditor(_ doc: PersonalDocDocument) {
        var updated = doc
        updated.title = editedTitle.isEmpty ? doc.title : editedTitle
        updated.markdownSource = editedMarkdown
        store.updateDocument(updated)
    }

    private var newDocumentSheet: some View {
        Form {
            TextField("Title", text: $newTitle)
            Picker("Module", selection: Binding(
                get: { coordinator.selectedModuleKind ?? .personalDocumentation },
                set: { coordinator.selectedModuleKind = $0 }
            )) {
                ForEach(PersonalDocModuleKind.allCases) { kind in Text(kind.rawValue).tag(kind) }
            }
            HStack {
                Button("Cancel") { showingNewDocument = false }
                Spacer()
                Button("Create") {
                    let kind = coordinator.selectedModuleKind ?? .personalDocumentation
                    let doc = store.createDocument(title: newTitle.isEmpty ? "Untitled" : newTitle, kind: kind)
                    coordinator.selectDocument(doc.id)
                    newTitle = ""
                    showingNewDocument = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 380)
    }

    private func runAnalysis() async {
        analysisRunning = true
        defer { analysisRunning = false }
        do {
            analysisResult = try await store.analyze(kind: .dailySummary)
        } catch {
            analysisResult = "Analysis failed: \(error.localizedDescription)"
        }
    }

    private struct AnalysisSheet: Identifiable {
        var id: String { text }
        let text: String
    }
}
