import SwiftUI
import SwiftData
import Observation

@MainActor
public struct PersonalDocCommandPalette: View {
    @Bindable var coordinator: PersonalDocumentationCoordinator
    let onDismiss: () -> Void

    @State private var searchText = ""
    @State private var selectedCategory: PaletteCategory = .all

    // State cached lists to search locally after fetch
    @State private var documents: [Document] = []
    @State private var wikiPages: [WikiPage] = []
    @State private var whiteboards: [WhiteboardRecord] = []
    @State private var snippets: [CodeSnippetRecord] = []
    @State private var snapshots: [ProjectSnapshotRecord] = []

    enum PaletteCategory: String, CaseIterable, Identifiable {
        case all = "All"
        case nav = "Navigation"
        case docs = "Documents"
        case wiki = "Wiki Pages"
        case ecosystem = "Ecosystem"

        var id: String { rawValue }
    }

    struct PaletteItem: Identifiable {
        enum ItemType {
            case navigation(ModuleKind)
            case document(Document)
            case wikiPage(WikiPage)
            case whiteboard(WhiteboardRecord)
            case snippet(CodeSnippetRecord)
            case snapshot(ProjectSnapshotRecord)
            case createAction(title: String, icon: String, actionType: ActionType)
        }

        enum ActionType {
            case document
            case wikiPage
            case whiteboard
            case snippet
        }

        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let color: Color
        let type: ItemType
    }

    public init(coordinator: PersonalDocumentationCoordinator, onDismiss: @escaping () -> Void) {
        self.coordinator = coordinator
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Search Input
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)

                TextField("Search documentation modules, pages, files, snippets...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .frame(height: 36)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            // Category Bar
            Picker("Category", selection: $selectedCategory) {
                ForEach(PaletteCategory.allCases) { cat in
                    Text(cat.rawValue).tag(cat)
                }
            }
            .pickerStyle(.segmented)
            .controlSize(.small)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Filtered Items List
            List {
                let items = filteredItems
                if items.isEmpty {
                    ContentUnavailableView {
                        Label("No matching items", systemImage: "doc.text.magnifyingglass")
                    } description: {
                        Text("Try searching for a different keyword.")
                    }
                    .frame(height: 200)
                } else {
                    ForEach(items) { item in
                        Button {
                            handleSelection(item)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 14))
                                    .foregroundStyle(item.color)
                                    .frame(width: 20, height: 20)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.primary)
                                    Text(item.subtitle)
                                        .font(.system(size: 11))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 280, maxHeight: 400)

            Divider()

            // Footer bar
            HStack {
                Text("Double-click or press return to open selection")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Close") {
                    onDismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(12)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 500)
        .onAppear {
            fetchData()
        }
    }

    private func fetchData() {
        documents = (try? coordinator.documents.fetchDocuments()) ?? []
        wikiPages = (try? coordinator.wiki.fetchWikiPages()) ?? []
        whiteboards = (try? coordinator.whiteboards.fetchWhiteboards()) ?? []
        snippets = (try? coordinator.snippets.fetchSnippets()) ?? []
        snapshots = (try? coordinator.snapshots.fetchSnapshots()) ?? []
    }

    private var filteredItems: [PaletteItem] {
        var result: [PaletteItem] = []

        // 1. Navigation items (ModuleKind links)
        if selectedCategory == .all || selectedCategory == .nav {
            for kind in ModuleKind.allCases {
                if searchText.isEmpty || kind.rawValue.localizedCaseInsensitiveContains(searchText) {
                    result.append(PaletteItem(
                        id: "nav-\(kind.id)",
                        title: "Go to \(kind.rawValue)",
                        subtitle: "Navigation • Archetype: \(kind.archetype.rawValue)",
                        icon: kind.icon,
                        color: kind.accentColor,
                        type: .navigation(kind)
                    ))
                }
            }
        }

        // 2. Document items
        if selectedCategory == .all || selectedCategory == .docs {
            for doc in documents {
                if searchText.isEmpty || doc.title.localizedCaseInsensitiveContains(searchText) {
                    result.append(PaletteItem(
                        id: "doc-\(doc.id.uuidString)",
                        title: doc.title,
                        subtitle: "Document • \(doc.moduleKind.rawValue)",
                        icon: doc.moduleKind.icon,
                        color: doc.moduleKind.accentColor,
                        type: .document(doc)
                    ))
                }
            }
        }

        // 3. Wiki page items
        if selectedCategory == .all || selectedCategory == .wiki {
            for page in wikiPages {
                if searchText.isEmpty || page.title.localizedCaseInsensitiveContains(searchText) {
                    result.append(PaletteItem(
                        id: "wiki-\(page.id.uuidString)",
                        title: page.title,
                        subtitle: "Wiki Page • Last updated \(page.lastUpdated.formatted(date: .abbreviated, time: .omitted))",
                        icon: "globe.americas.fill",
                        color: .purple,
                        type: .wikiPage(page)
                    ))
                }
            }
        }

        // 4. Ecosystem items (Whiteboards, Snippets, Snapshots)
        if selectedCategory == .all || selectedCategory == .ecosystem {
            for wb in whiteboards {
                if searchText.isEmpty || wb.title.localizedCaseInsensitiveContains(searchText) {
                    result.append(PaletteItem(
                        id: "wb-\(wb.id.uuidString)",
                        title: wb.title,
                        subtitle: "Whiteboard • Last modified \(wb.updatedAt.formatted(date: .abbreviated, time: .omitted))",
                        icon: "pencil.and.outline",
                        color: .blue,
                        type: .whiteboard(wb)
                    ))
                }
            }

            for snip in snippets {
                if searchText.isEmpty || snip.title.localizedCaseInsensitiveContains(searchText) {
                    result.append(PaletteItem(
                        id: "snip-\(snip.id.uuidString)",
                        title: snip.title,
                        subtitle: "Code Snippet • Language: \(snip.language)",
                        icon: "text.badge.plus",
                        color: .green,
                        type: .snippet(snip)
                    ))
                }
            }

            for snap in snapshots {
                if searchText.isEmpty || snap.title.localizedCaseInsensitiveContains(searchText) {
                    result.append(PaletteItem(
                        id: "snap-\(snap.id.uuidString)",
                        title: snap.title,
                        subtitle: "Project Snapshot • Created \(snap.createdAt.formatted(date: .abbreviated, time: .omitted))",
                        icon: "clock.arrow.trianglehead.counterclockwise.rotate.90",
                        color: .orange,
                        type: .snapshot(snap)
                    ))
                }
            }
        }

        // 5. Add Quick Creation Actions at the top or bottom of the search
        if selectedCategory == .all {
            let actions = [
                PaletteItem(
                    id: "action-doc",
                    title: "Create New Freeform Document",
                    subtitle: "Action • Opens document creator",
                    icon: "doc.badge.plus",
                    color: .blue,
                    type: .createAction(title: "New Freeform Document", icon: "doc.badge.plus", actionType: .document)
                ),
                PaletteItem(
                    id: "action-wiki",
                    title: "Create New Wiki Page",
                    subtitle: "Action • Creates a blank Wiki page",
                    icon: "globe.badge.plus",
                    color: .purple,
                    type: .createAction(title: "New Wiki Page", icon: "globe.badge.plus", actionType: .wikiPage)
                ),
                PaletteItem(
                    id: "action-wb",
                    title: "Create New Whiteboard",
                    subtitle: "Action • Creates a new whiteboard",
                    icon: "pencil.and.outline",
                    color: .blue,
                    type: .createAction(title: "New Whiteboard", icon: "pencil.and.outline", actionType: .whiteboard)
                ),
                PaletteItem(
                    id: "action-snip",
                    title: "Create New Code Snippet",
                    subtitle: "Action • Opens snippet builder",
                    icon: "text.badge.plus",
                    color: .green,
                    type: .createAction(title: "New Code Snippet", icon: "text.badge.plus", actionType: .snippet)
                )
            ]

            let filteredActions = actions.filter {
                searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText)
            }
            result.insert(contentsOf: filteredActions, at: 0)
        }

        return result
    }

    private func handleSelection(_ item: PaletteItem) {
        switch item.type {
        case .navigation(let kind):
            coordinator.selectedModuleKind = kind

        case .document(let doc):
            coordinator.selectedModuleKind = doc.moduleKind
            coordinator.selectedDocumentID = doc.id

        case .wikiPage(let page):
            coordinator.selectedModuleKind = .projectWiki
            coordinator.selectedWikiPageID = page.id

        case .whiteboard(let wb):
            coordinator.selectedModuleKind = .whiteboards
            coordinator.selectedWhiteboardID = wb.id

        case .snippet(let snip):
            coordinator.selectedModuleKind = .snippets
            coordinator.selectedSnippetID = snip.id

        case .snapshot(let snap):
            coordinator.selectedModuleKind = .snapshots
            coordinator.selectedSnapshotID = snap.id

        case .createAction(_, _, let actionType):
            switch actionType {
            case .document:
                coordinator.selectedModuleKind = .personalDocumentation
                if let newDoc = try? coordinator.documents.createDocument(title: "Untitled Document", kind: .personalDocumentation) {
                    coordinator.selectedDocumentID = newDoc.id
                }
            case .wikiPage:
                coordinator.selectedModuleKind = .projectWiki
                if let newPage = try? coordinator.wiki.createOrUpdateWikiPage(title: "New Page", content: "# New Wiki Page\n\nWrite your wiki content here.") {
                    coordinator.selectedWikiPageID = newPage.id
                }
            case .whiteboard:
                coordinator.selectedModuleKind = .whiteboards
                if let newWB = try? coordinator.whiteboards.createWhiteboard(title: "Untitled Whiteboard") {
                    coordinator.selectedWhiteboardID = newWB.id
                }
            case .snippet:
                coordinator.selectedModuleKind = .snippets
                if let newSnip = try? coordinator.snippets.createSnippet(title: "Untitled Snippet", code: "// Write code here", language: "Swift", category: "Utility") {
                    coordinator.selectedSnippetID = newSnip.id
                }
            }
        }
        onDismiss()
    }
}
