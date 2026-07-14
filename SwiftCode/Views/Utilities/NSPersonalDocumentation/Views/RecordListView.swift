import SwiftUI
import AppKit

@MainActor
public func collapseMiddlePane() {
    // Safe no-op in the modernized two-region desktop architecture
}

public struct RecordListView: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let kind: ModuleKind
    @Binding public var selectedDocumentID: UUID?
    public var onSelect: (() -> Void)? = nil

    // Unified list of all browseable items
    @State private var items: [UnifiedBrowserItem] = []

    // Search, Filter, Sort States
    @State private var searchQuery = ""
    @State private var selectedKind: BrowserItemKind = .document
    @State private var sortOption: SortOption = .updatedAt

    // Creation States
    @State private var showingCreateSheet = false
    @State private var newTitle = ""
    @State private var newKind: BrowserItemKind = .document
    @State private var newDocModuleKind: ModuleKind = .personalDocumentation

    // Snippet-specific creation states
    @State private var snippetLanguage = "Swift"
    @State private var snippetCategory = "Utility"
    @State private var snippetCode = ""

    // Snapshot-specific creation state
    @State private var snapshotDescription = ""

    public enum SortOption: String, CaseIterable, Identifiable {
        case updatedAt = "Recently Updated"
        case createdAt = "Date Created"
        case title = "Title (A-Z)"

        public var id: String { rawValue }
    }

    public enum BrowserItemKind: String, CaseIterable, Identifiable, Sendable {
        case document = "Standard Document"
        case wikiPage = "Wiki Page"
        case whiteboard = "Advanced Whiteboard"
        case snippet = "Code Snippet"
        case snapshot = "Project Snapshot"

        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .document: return "doc.text.fill"
            case .wikiPage: return "globe.americas.fill"
            case .whiteboard: return "pencil.and.outline"
            case .snippet: return "text.badge.plus"
            case .snapshot: return "clock.arrow.trianglehead.counterclockwise.rotate.90"
            }
        }

        public var color: Color {
            switch self {
            case .document: return .blue
            case .wikiPage: return .purple
            case .whiteboard: return .cyan
            case .snippet: return .green
            case .snapshot: return .orange
            }
        }
    }

    public struct UnifiedBrowserItem: Identifiable {
        public let id: UUID
        public let title: String
        public let subtitle: String
        public let iconName: String
        public let accentColor: Color
        public let kind: BrowserItemKind
        public let updatedAt: Date
        public let createdAt: Date
        public var rawDocument: Document? = nil
        public var rawWikiPage: WikiPage? = nil
        public var rawWhiteboard: WhiteboardRecord? = nil
        public var rawSnippet: CodeSnippetRecord? = nil
        public var rawSnapshot: ProjectSnapshotRecord? = nil
    }

    private var availableCreationKinds: [ModuleKind] {
        ModuleKind.allCases.filter {
            $0.archetype == .freeform || $0.archetype == .structured
        }
    }

    public init(
        coordinator: PersonalDocumentationCoordinator,
        kind: ModuleKind,
        selectedDocumentID: Binding<UUID?>,
        onSelect: (() -> Void)? = nil
    ) {
        self.coordinator = coordinator
        self.kind = kind
        self._selectedDocumentID = selectedDocumentID
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Document Browser Control Bar
            VStack(spacing: 8) {
                HStack(spacing: 12) {
                    NativeSearchField(text: $searchQuery, placeholder: "Search documentation titles or contents...")

                    Picker("Type Filter", selection: $selectedKind) {
                        ForEach(BrowserItemKind.allCases) { kind in
                            Label(kind.rawValue, systemImage: kind.icon)
                                .tag(kind)
                        }
                    }
                    .frame(width: 180)

                    Picker("Sort By", selection: $sortOption) {
                        ForEach(SortOption.allCases) { opt in
                            Text(opt.rawValue).tag(opt)
                        }
                    }
                    .frame(width: 150)

                    Button {
                        newTitle = ""
                        newKind = selectedKind
                        snippetCode = ""
                        snapshotDescription = ""
                        showingCreateSheet = true
                    } label: {
                        Label("Create", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(14)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Main List Content
            if filteredAndSortedItems.isEmpty {
                ContentUnavailableView {
                    Label(searchQuery.isEmpty ? "No Items Found" : "No Results", systemImage: "doc.text")
                } description: {
                    Text(searchQuery.isEmpty ? "Create a document, whiteboard, or code snippet to start." : "No entries match your active query filters.")
                }
                .frame(maxHeight: .infinity)
            } else {
                List(filteredAndSortedItems) { item in
                    HStack(spacing: 14) {
                        Image(systemName: item.iconName)
                            .font(.title3)
                            .foregroundStyle(item.accentColor)
                            .frame(width: 32, height: 32)
                            .background(item.accentColor.opacity(0.12))
                            .cornerRadius(6)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)

                            HStack(spacing: 8) {
                                Text(item.subtitle)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.secondary)

                                Text("•")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)

                                Text("Updated \(item.updatedAt, style: .date)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectItem(item)
                    }
                    .contextMenu {
                        Button {
                            duplicateItem(item)
                        } label: {
                            Label("Duplicate", systemImage: "doc.on.doc")
                        }

                        Button(role: .destructive) {
                            deleteItem(item)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .onAppear {
            determineInitialKind()
            loadAllItems()
        }
        .onChange(of: kind) { _, _ in
            determineInitialKind()
            loadAllItems()
        }
        .onChange(of: selectedKind) { _, _ in
            loadAllItems()
        }
        .sheet(isPresented: $showingCreateSheet) {
            VStack(spacing: 16) {
                Text("Create New Entry")
                    .font(.headline)

                Form {
                    Section {
                        Picker("Category Type", selection: $newKind) {
                            ForEach(BrowserItemKind.allCases) { k in
                                Text(k.rawValue).tag(k)
                            }
                        }
                        .pickerStyle(.menu)

                        TextField("Entry Title", text: $newTitle)
                            .textFieldStyle(.roundedBorder)

                        if newKind == .document {
                            Picker("Document Subtype", selection: $newDocModuleKind) {
                                ForEach(availableCreationKinds) { mKind in
                                    Text(mKind.rawValue).tag(mKind)
                                }
                            }
                            .pickerStyle(.menu)
                        }

                        if newKind == .snippet {
                            TextField("Language", text: $snippetLanguage)
                                .textFieldStyle(.roundedBorder)
                            TextField("Category", text: $snippetCategory)
                                .textFieldStyle(.roundedBorder)
                            TextEditor(text: $snippetCode)
                                .font(.system(.body, design: .monospaced))
                                .frame(height: 120)
                                .border(Color.secondary.opacity(0.2))
                        }

                        if newKind == .snapshot {
                            TextField("Description / Milestone", text: $snapshotDescription)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .formStyle(.grouped)

                HStack {
                    Button("Cancel") {
                        showingCreateSheet = false
                    }
                    Spacer()
                    Button("Create Entry") {
                        createNewEntry()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(newTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding()
            .frame(width: 440, height: 480)
        }
    }

    private func determineInitialKind() {
        switch kind {
        case .projectWiki:
            selectedKind = .wikiPage
        case .whiteboards:
            selectedKind = .whiteboard
        case .snippets:
            selectedKind = .snippet
        case .snapshots:
            selectedKind = .snapshot
        default:
            selectedKind = .document
        }
    }

    private func loadAllItems() {
        var loadedItems: [UnifiedBrowserItem] = []

        switch selectedKind {
        case .document:
            let docs = (try? coordinator.documents.fetchDocuments()) ?? []
            loadedItems = docs.map { doc in
                UnifiedBrowserItem(
                    id: doc.id,
                    title: doc.title,
                    subtitle: doc.moduleKind.rawValue,
                    iconName: doc.moduleKind.icon,
                    accentColor: doc.moduleKind.accentColor,
                    kind: .document,
                    updatedAt: doc.updatedAt,
                    createdAt: doc.createdAt,
                    rawDocument: doc
                )
            }

        case .wikiPage:
            let pages = (try? coordinator.wiki.fetchWikiPages()) ?? []
            loadedItems = pages.map { page in
                UnifiedBrowserItem(
                    id: page.id,
                    title: page.title,
                    subtitle: "Wiki Wiki",
                    iconName: "globe.americas.fill",
                    accentColor: .purple,
                    kind: .wikiPage,
                    updatedAt: page.lastUpdated,
                    createdAt: page.lastUpdated,
                    rawWikiPage: page
                )
            }

        case .whiteboard:
            let boards = (try? coordinator.whiteboards.fetchWhiteboards()) ?? []
            loadedItems = boards.map { board in
                UnifiedBrowserItem(
                    id: board.id,
                    title: board.title,
                    subtitle: "Whiteboard Sketch",
                    iconName: "pencil.and.outline",
                    accentColor: .cyan,
                    kind: .whiteboard,
                    updatedAt: board.updatedAt,
                    createdAt: board.createdAt,
                    rawWhiteboard: board
                )
            }

        case .snippet:
            let snips = (try? coordinator.snippets.fetchSnippets()) ?? []
            loadedItems = snips.map { snip in
                UnifiedBrowserItem(
                    id: snip.id,
                    title: snip.title,
                    subtitle: "\(snip.language) • \(snip.category)",
                    iconName: "text.badge.plus",
                    accentColor: .green,
                    kind: .snippet,
                    updatedAt: snip.updatedAt,
                    createdAt: snip.createdAt,
                    rawSnippet: snip
                )
            }

        case .snapshot:
            let snaps = (try? coordinator.snapshots.fetchSnapshots()) ?? []
            loadedItems = snaps.map { snap in
                UnifiedBrowserItem(
                    id: snap.id,
                    title: snap.title,
                    subtitle: snap.descriptionText,
                    iconName: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                    accentColor: .orange,
                    kind: .snapshot,
                    updatedAt: snap.createdAt,
                    createdAt: snap.createdAt,
                    rawSnapshot: snap
                )
            }
        }

        self.items = loadedItems
    }

    private var filteredAndSortedItems: [UnifiedBrowserItem] {
        var filtered = items

        if !searchQuery.isEmpty {
            filtered = filtered.filter { item in
                item.title.localizedCaseInsensitiveContains(searchQuery) ||
                item.subtitle.localizedCaseInsensitiveContains(searchQuery)
            }
        }

        switch sortOption {
        case .updatedAt:
            filtered.sort { $0.updatedAt > $1.updatedAt }
        case .createdAt:
            filtered.sort { $0.createdAt > $1.createdAt }
        case .title:
            filtered.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }

        return filtered
    }

    private func selectItem(_ item: UnifiedBrowserItem) {
        switch item.kind {
        case .document:
            coordinator.selectedModuleKind = item.rawDocument?.moduleKind ?? .personalDocumentation
            coordinator.selectedDocumentID = item.id
            selectedDocumentID = item.id

        case .wikiPage:
            coordinator.selectedModuleKind = .projectWiki
            coordinator.selectedWikiPageID = item.id

        case .whiteboard:
            coordinator.selectedModuleKind = .whiteboards
            coordinator.selectedWhiteboardID = item.id

        case .snippet:
            coordinator.selectedModuleKind = .snippets
            coordinator.selectedSnippetID = item.id

        case .snapshot:
            coordinator.selectedModuleKind = .snapshots
            coordinator.selectedSnapshotID = item.id
        }

        onSelect?()
    }

    private func createNewEntry() {
        let trimmedTitle = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        do {
            switch newKind {
            case .document:
                let doc = try coordinator.documents.createDocument(title: trimmedTitle, kind: newDocModuleKind)
                coordinator.selectedModuleKind = newDocModuleKind
                coordinator.selectedDocumentID = doc.id
                selectedDocumentID = doc.id

            case .wikiPage:
                let page = try coordinator.wiki.createOrUpdateWikiPage(title: trimmedTitle, content: "# \(trimmedTitle)\n\nStart writing wiki content here.")
                coordinator.selectedModuleKind = .projectWiki
                coordinator.selectedWikiPageID = page.id

            case .whiteboard:
                let board = try coordinator.whiteboards.createWhiteboard(title: trimmedTitle)
                coordinator.selectedModuleKind = .whiteboards
                coordinator.selectedWhiteboardID = board.id

            case .snippet:
                let snip = try coordinator.snippets.createSnippet(
                    title: trimmedTitle,
                    code: snippetCode,
                    language: snippetLanguage,
                    category: snippetCategory
                )
                coordinator.selectedModuleKind = .snippets
                coordinator.selectedSnippetID = snip.id

            case .snapshot:
                let docs = (try? coordinator.documents.fetchDocuments()) ?? []
                let whiteboards = (try? coordinator.whiteboards.fetchWhiteboards()) ?? []
                let snippets = (try? coordinator.snippets.fetchSnippets()) ?? []

                let snap = try coordinator.snapshots.createSnapshot(
                    title: trimmedTitle,
                    description: snapshotDescription,
                    documents: docs,
                    whiteboards: whiteboards,
                    snippets: snippets
                )
                coordinator.selectedModuleKind = .snapshots
                coordinator.selectedSnapshotID = snap.id
            }

            loadAllItems()
            showingCreateSheet = false
            onSelect?()
        } catch {
            // silent catch
        }
    }

    private func duplicateItem(_ item: UnifiedBrowserItem) {
        do {
            switch item.kind {
            case .document:
                if let doc = item.rawDocument {
                    let duplicate = Document(
                        projectID: doc.projectID,
                        archetype: doc.archetype,
                        moduleKind: doc.moduleKind,
                        title: "\(doc.title) Copy",
                        markdownSource: doc.markdownSource,
                        attachments: doc.attachments,
                        tags: doc.tags,
                        createdAt: Date(),
                        updatedAt: Date()
                    )
                    coordinator.storage.context.insert(duplicate)
                    try coordinator.storage.context.save()
                }

            case .wikiPage:
                if let page = item.rawWikiPage {
                    _ = try coordinator.wiki.createOrUpdateWikiPage(
                        title: "\(page.title) Copy",
                        content: page.markdownSource
                    )
                }

            case .whiteboard:
                if let board = item.rawWhiteboard {
                    let duplicate = try coordinator.whiteboards.createWhiteboard(title: "\(board.title) Copy")
                    duplicate.elementsJSON = board.elementsJSON
                    try coordinator.whiteboards.updateWhiteboard(duplicate)
                }

            case .snippet:
                if let snip = item.rawSnippet {
                    _ = try coordinator.snippets.createSnippet(
                        title: "\(snip.title) Copy",
                        code: snip.code,
                        language: snip.language,
                        category: snip.category
                    )
                }

            case .snapshot:
                if let snap = item.rawSnapshot {
                    _ = try coordinator.snapshots.createSnapshot(
                        title: "\(snap.title) Copy",
                        description: snap.descriptionText,
                        documents: (try? coordinator.documents.fetchDocuments()) ?? [],
                        whiteboards: (try? coordinator.whiteboards.fetchWhiteboards()) ?? [],
                        snippets: (try? coordinator.snippets.fetchSnippets()) ?? []
                    )
                }
            }

            loadAllItems()
        } catch {
            // silent catch
        }
    }

    private func deleteItem(_ item: UnifiedBrowserItem) {
        do {
            switch item.kind {
            case .document:
                if let doc = item.rawDocument {
                    try coordinator.documents.deleteDocument(doc)
                    if coordinator.selectedDocumentID == doc.id {
                        coordinator.selectedDocumentID = nil
                        selectedDocumentID = nil
                    }
                }

            case .wikiPage:
                if let page = item.rawWikiPage {
                    coordinator.storage.context.delete(page)
                    try coordinator.storage.context.save()
                    if coordinator.selectedWikiPageID == page.id {
                        coordinator.selectedWikiPageID = nil
                    }
                }

            case .whiteboard:
                if let board = item.rawWhiteboard {
                    try coordinator.whiteboards.deleteWhiteboard(board)
                    if coordinator.selectedWhiteboardID == board.id {
                        coordinator.selectedWhiteboardID = nil
                    }
                }

            case .snippet:
                if let snip = item.rawSnippet {
                    try coordinator.snippets.deleteSnippet(snip)
                    if coordinator.selectedSnippetID == snip.id {
                        coordinator.selectedSnippetID = nil
                    }
                }

            case .snapshot:
                if let snap = item.rawSnapshot {
                    coordinator.storage.context.delete(snap)
                    try coordinator.storage.context.save()
                    if coordinator.selectedSnapshotID == snap.id {
                        coordinator.selectedSnapshotID = nil
                    }
                }
            }

            loadAllItems()
        } catch {
            // silent catch
        }
    }
}
