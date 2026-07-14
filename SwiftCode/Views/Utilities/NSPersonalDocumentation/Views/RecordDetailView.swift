import SwiftUI

public struct RecordDetailView: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let documentID: UUID?

    @State private var document: Document? = nil
    @State private var wikiPage: WikiPage? = nil

    // Bindable editing fields
    @State private var titleText = ""
    @State private var markdownText = ""
    @State private var relationships: [Relationship] = []
    @State private var versions: [DocumentVersion] = []

    // Editor control states
    @State private var viewMode: ViewMode = .edit
    @State private var isRenaming = false
    @State private var editTitleText = ""
    @State private var showBrowserSheet = false

    // Table creation parameters
    @State private var tableRows = 3
    @State private var tableCols = 3
    @State private var showTableCreatorPopover = false

    // Relationship formulation states
    @State private var showAddLink = false
    @State private var targetName = ""
    @State private var targetType = "Swift File"

    // Versioning states
    @State private var selectedVersion: DocumentVersion? = nil

    // Delete Confirmation
    @State private var showingDeleteConfirmation = false

    public enum ViewMode: String, CaseIterable, Identifiable {
        case read = "Read Mode"
        case edit = "Edit Mode"

        public var id: String { rawValue }
    }

    public var body: some View {
        VStack(spacing: 0) {
            if hasActiveSelection {
                // REDESIGNED: Professional Desktop Editor Header
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 16) {
                        // Icon & Renameable Title
                        HStack(spacing: 10) {
                            Image(systemName: activeIcon)
                                .font(.title2)
                                .foregroundStyle(activeColor)

                            if isRenaming {
                                TextField("Title", text: $editTitleText)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.title3.bold())
                                    .frame(maxWidth: 300)
                                    .onSubmit {
                                        renameActiveDocument(to: editTitleText)
                                    }

                                Button {
                                    renameActiveDocument(to: editTitleText)
                                } label: {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                }
                                .buttonStyle(.plain)

                                Button {
                                    isRenaming = false
                                } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            } else {
                                Text(titleText)
                                    .font(.title2.bold())
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .textSelection(.enabled)

                                Button {
                                    editTitleText = titleText
                                    isRenaming = true
                                } label: {
                                    Image(systemName: "pencil")
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        Spacer()

                        // View mode switcher
                        Picker("View Mode", selection: $viewMode) {
                            ForEach(ViewMode.allCases) { mode in
                                Label(mode.rawValue, systemImage: mode == .read ? "eye.fill" : "pencil")
                                    .tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 200)

                        // Top header action controls
                        HStack(spacing: 10) {
                            Button {
                                showBrowserSheet = true
                            } label: {
                                Label("Browse", systemImage: "folder")
                            }
                            .buttonStyle(.bordered)
                            .help("Browse category documents")

                            Button {
                                duplicateActive()
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .help("Duplicate current document")
                            .buttonStyle(.bordered)

                            Button(role: .destructive) {
                                showingDeleteConfirmation = true
                            } label: {
                                Image(systemName: "trash")
                            }
                            .help("Delete current document")
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color(NSColor.windowBackgroundColor))

                    Divider()

                    // RICH MARKDOWN & ADVANCED TABLE EDITING TOOLBAR (VISIBLE IN EDIT MODE)
                    if viewMode == .edit {
                        markdownFormattingToolbar
                    }
                }

                // Workspace Editor Body Area
                VStack(spacing: 0) {
                    if viewMode == .edit {
                        // EDIT MODE: Non-scrolling container wraps NSTextView directly to eliminate scroll conflicts
                        VStack(spacing: 0) {
                            if document != nil {
                                // Status / Metadata panel for structured files
                                HStack(spacing: 24) {
                                    Picker("Status", selection: Binding(
                                        get: { document?.status ?? "To Do" },
                                        set: { val in
                                            if let doc = document {
                                                doc.status = val
                                                try? coordinator.documents.updateDocument(doc)
                                                reloadData()
                                            }
                                        }
                                    )) {
                                        Text("To Do").tag("To Do")
                                        Text("In Progress").tag("In Progress")
                                        Text("Done").tag("Done")
                                    }
                                    .frame(width: 180)

                                    Picker("Priority", selection: Binding(
                                        get: { document?.priority ?? "Medium" },
                                        set: { val in
                                            if let doc = document {
                                                doc.priority = val
                                                try? coordinator.documents.updateDocument(doc)
                                                reloadData()
                                            }
                                        }
                                    )) {
                                        Text("High").tag("High")
                                        Text("Medium").tag("Medium")
                                        Text("Low").tag("Low")
                                    }
                                    .frame(width: 180)

                                    Spacer()
                                }
                                .padding(.horizontal, 24)
                                .padding(.vertical, 12)
                                .background(Color(NSColor.controlBackgroundColor))

                                Divider()
                            }

                            // Desktop first native multi-line text editor
                            DocNSTextView(text: Binding(
                                get: { markdownText },
                                set: { val in
                                    markdownText = val
                                    saveActiveContent(val)
                                }
                            ))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        // READ MODE: High fidelity Markdown renderer
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                if document != nil {
                                    HStack(spacing: 16) {
                                        Text("Status: \(document?.status ?? "To Do")")
                                            .font(.caption.bold())
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(Color.blue.opacity(0.12))
                                            .cornerRadius(6)

                                        Text("Priority: \(document?.priority ?? "Medium")")
                                            .font(.caption.bold())
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(Color.orange.opacity(0.12))
                                            .cornerRadius(6)
                                    }
                                }

                                if markdownText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text("This document has no content yet. Click 'Edit Mode' above to write notes using rich markdown syntax and tables.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .italic()
                                } else {
                                    MarkdownBlockListView(blocks: MarkdownRenderer.shared.parse(markdownText))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(32)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else {
                // Elegant Empty State Workspace
                ContentUnavailableView {
                    Label("Editor Workspace", systemImage: "doc.text.fill")
                } description: {
                    VStack(spacing: 16) {
                        Text("Select an existing document from the sidebar category, or open the temporary document browser below to view and manage your files.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: 400)
                            .multilineTextAlignment(.center)

                        Button("Open Document Browser") {
                            showBrowserSheet = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            reloadData()
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("PersonalDocDocumentRestored"),
                object: nil,
                queue: .main
            ) { _ in
                reloadData()
            }
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("PersonalDocViewModeChanged"),
                object: nil,
                queue: .main
            ) { notification in
                if let isEdit = notification.userInfo?["isEdit"] as? Bool {
                    viewMode = isEdit ? .edit : .read
                }
            }
        }
        .onChange(of: documentID) { _, _ in
            reloadData()
            isRenaming = false
        }
        .onChange(of: coordinator.selectedWikiPageID) { _, _ in
            reloadData()
            isRenaming = false
        }
        .sheet(isPresented: $showBrowserSheet) {
            VStack(spacing: 0) {
                HStack {
                    Text("Browse Documents")
                        .font(.headline)
                    Spacer()
                    Button("Close Browser") {
                        showBrowserSheet = false
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                Divider()
                RecordListView(
                    coordinator: coordinator,
                    kind: document?.moduleKind ?? coordinator.selectedModuleKind ?? .personalDocumentation,
                    selectedDocumentID: Binding(
                        get: { coordinator.selectedDocumentID },
                        set: { coordinator.selectedDocumentID = $0 }
                    ),
                    onSelect: {
                        showBrowserSheet = false
                        reloadData()
                    }
                )
                .frame(width: 800, height: 600)
            }
        }
        .alert("Are you sure you want to delete this document?", isPresented: $showingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                deleteActive()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    // MARK: - Markdown and Table Formatting Toolbar Component

    private var markdownFormattingToolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                // Typography Headers
                ControlGroup {
                    Button { formatText(with: "# ", suffix: "") } label: { Text("H1").bold() }.help("Heading 1")
                    Button { formatText(with: "## ", suffix: "") } label: { Text("H2").bold() }.help("Heading 2")
                    Button { formatText(with: "### ", suffix: "") } label: { Text("H3").bold() }.help("Heading 3")
                }

                Divider().frame(height: 20)

                // Inline Styles
                ControlGroup {
                    Button { formatText(with: "**", suffix: "**") } label: { Image(systemName: "bold") }.help("Bold")
                    Button { formatText(with: "*", suffix: "*") } label: { Image(systemName: "italic") }.help("Italic")
                    Button { formatText(with: "~~", suffix: "~~") } label: { Image(systemName: "strikethrough") }.help("Strikethrough")
                    Button { formatText(with: "`", suffix: "`") } label: { Image(systemName: "curlybraces") }.help("Inline Code")
                }

                Divider().frame(height: 20)

                // Block Blocks
                ControlGroup {
                    Button { formatText(with: "\n```\n", suffix: "\n```\n") } label: { Image(systemName: "doc.plaintext") }.help("Code Block")
                    Button { formatText(with: "> ", suffix: "") } label: { Image(systemName: "quote.opening") }.help("Blockquote")
                    Button { formatText(with: "[", suffix: "](url)") } label: { Image(systemName: "link") }.help("Hyperlink")
                }

                Divider().frame(height: 20)

                // Lists and Rules
                ControlGroup {
                    Button { formatText(with: "- ", suffix: "") } label: { Image(systemName: "list.bullet") }.help("Bullet List")
                    Button { formatText(with: "1. ", suffix: "") } label: { Image(systemName: "list.number") }.help("Numbered List")
                    Button { formatText(with: "- [ ] ", suffix: "") } label: { Image(systemName: "checkmark.square") }.help("Task List")
                    Button { formatText(with: "\n---\n", suffix: "") } label: { Image(systemName: "minus") }.help("Horizontal Rule")
                }

                Divider().frame(height: 20)

                // ADVANCED MARKDOWN TABLE ACTIONS
                Menu {
                    Button {
                        tableRows = 3; tableCols = 3
                        insertCustomTable()
                    } label: { Label("3x3 Table", systemImage: "tablecells") }

                    Button {
                        tableRows = 5; tableCols = 4
                        insertCustomTable()
                    } label: { Label("5x4 Table", systemImage: "tablecells.fill") }

                    Button {
                        showTableCreatorPopover = true
                    } label: { Label("Custom Table Dimensions...", systemImage: "slider.horizontal.3") }

                    Divider()

                    Button { addTableRow() } label: { Label("Insert Row Below", systemImage: "plus.row.fill") }
                    Button { deleteTableRow() } label: { Label("Delete Active Row", systemImage: "minus.row.fill") }
                    Button { addTableColumn() } label: { Label("Insert Column Right", systemImage: "plus.column.fill") }
                    Button { deleteTableColumn() } label: { Label("Delete Active Column", systemImage: "minus.column.fill") }

                    Divider()

                    Button { alignTable(to: "left") } label: { Label("Align Columns Left", systemImage: "align.left") }
                    Button { alignTable(to: "center") } label: { Label("Align Columns Center", systemImage: "align.center") }
                    Button { alignTable(to: "right") } label: { Label("Align Columns Right", systemImage: "align.right") }

                } label: {
                    Label("Table Tools", systemImage: "tablecells")
                }
                .menuStyle(.button)
                .help("Create and edit Markdown tables")
                .popover(isPresented: $showTableCreatorPopover) {
                    VStack(spacing: 12) {
                        Text("Custom Table Creator")
                            .font(.headline)
                        Stepper("Rows: \(tableRows)", value: $tableRows, in: 1...15)
                        Stepper("Columns: \(tableCols)", value: $tableCols, in: 1...10)
                        Button("Insert Table") {
                            insertCustomTable()
                            showTableCreatorPopover = false
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(width: 220)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()
        }
    }

    // MARK: - Advanced Table Processing Operations

    private func insertCustomTable() {
        var tableMarkdown = "\n"
        // Generate Header Row
        tableMarkdown += "|"
        for c in 1...tableCols {
            tableMarkdown += " Header \(c) |"
        }
        tableMarkdown += "\n|"
        // Generate Divider Alignment Row
        for _ in 1...tableCols {
            tableMarkdown += " :--- |"
        }
        tableMarkdown += "\n"
        // Generate Content Rows
        for r in 1...tableRows {
            tableMarkdown += "|"
            for c in 1...tableCols {
                tableMarkdown += " Cell \(r),\(c) |"
            }
            tableMarkdown += "\n"
        }
        tableMarkdown += "\n"

        formatText(with: tableMarkdown, suffix: "")
    }

    private func addTableRow() {
        // Appends a new empty row to the table at the current position or end of text
        let newRow = "\n|" + String(repeating: "  |", count: max(1, countActiveTableColumns()))
        formatText(with: newRow, suffix: "")
    }

    private func deleteTableRow() {
        // Removes the last table row found in text
        var lines = markdownText.components(separatedBy: .newlines)
        if let lastRowIdx = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("|") && !$0.contains(":---") }) {
            lines.remove(at: lastRowIdx)
            markdownText = lines.joined(separator: "\n")
            saveActiveContent(markdownText)
        }
    }

    private func addTableColumn() {
        // Modifies all lines that start with "|" to include an extra cell
        var lines = markdownText.components(separatedBy: .newlines)
        var modified = false
        for i in 0..<lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") {
                if trimmed.contains(":---") || trimmed.contains("---:") {
                    lines[i] += " :--- |"
                } else {
                    lines[i] += " Cell |"
                }
                modified = true
            }
        }
        if modified {
            markdownText = lines.joined(separator: "\n")
            saveActiveContent(markdownText)
        }
    }

    private func deleteTableColumn() {
        // Removes the last cell from each row of the table
        var lines = markdownText.components(separatedBy: .newlines)
        var modified = false
        for i in 0..<lines.count {
            var parts = lines[i].components(separatedBy: "|")
            if parts.count > 3 && parts.first?.trimmingCharacters(in: .whitespaces) == "" && parts.last?.trimmingCharacters(in: .whitespaces) == "" {
                parts.remove(at: parts.count - 2)
                lines[i] = parts.joined(separator: "|")
                modified = true
            }
        }
        if modified {
            markdownText = lines.joined(separator: "\n")
            saveActiveContent(markdownText)
        }
    }

    private func alignTable(to alignment: String) {
        var lines = markdownText.components(separatedBy: .newlines)
        let replacement: String
        switch alignment {
        case "center": replacement = " :---: "
        case "right": replacement = " ---: "
        default: replacement = " :--- "
        }

        var modified = false
        for i in 0..<lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("|") && (trimmed.contains(":---") || trimmed.contains("---:") || trimmed.contains("---")) {
                let parts = trimmed.components(separatedBy: "|")
                var newParts: [String] = []
                for part in parts {
                    let tPart = part.trimmingCharacters(in: .whitespaces)
                    if tPart.isEmpty {
                        newParts.append("")
                    } else {
                        newParts.append(replacement)
                    }
                }
                lines[i] = newParts.joined(separator: "|")
                modified = true
            }
        }
        if modified {
            markdownText = lines.joined(separator: "\n")
            saveActiveContent(markdownText)
        }
    }

    private func countActiveTableColumns() -> Int {
        let lines = markdownText.components(separatedBy: .newlines)
        if let dividerLine = lines.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("|") && $0.contains(":---") }) {
            return dividerLine.components(separatedBy: "|").count - 2
        }
        return 3
    }

    // MARK: - Core Formatting Insertion Engine

    private func formatText(with prefix: String, suffix: String) {
        // In this implementation, we append or wrap format template nicely
        if markdownText.isEmpty {
            markdownText = prefix + "Document Content" + suffix
        } else {
            markdownText += prefix + suffix
        }
        saveActiveContent(markdownText)
    }

    // MARK: - State & Active Property Resolvers

    private var hasActiveSelection: Bool {
        if coordinator.selectedModuleKind == .projectWiki {
            return coordinator.selectedWikiPageID != nil
        }
        return documentID != nil
    }

    private var activeIcon: String {
        if coordinator.selectedModuleKind == .projectWiki {
            return "globe.americas.fill"
        }
        return document?.moduleKind.icon ?? "doc.text"
    }

    private var activeColor: Color {
        if coordinator.selectedModuleKind == .projectWiki {
            return .purple
        }
        return document?.moduleKind.accentColor ?? .blue
    }

    // MARK: - Actions Helper

    private func reloadData() {
        if coordinator.selectedModuleKind == .projectWiki {
            if let id = coordinator.selectedWikiPageID,
               let pages = try? coordinator.wiki.fetchWikiPages(),
               let match = pages.first(where: { $0.id == id }) {
                self.wikiPage = match
                self.document = nil
                self.titleText = match.title
                self.markdownText = match.markdownSource
            } else {
                self.wikiPage = nil
                self.document = nil
                self.titleText = ""
                self.markdownText = ""
            }
        } else if let id = documentID {
            document = try? coordinator.documents.fetchDocument(id: id)
            if let doc = document {
                self.wikiPage = nil
                self.titleText = doc.title
                self.markdownText = doc.markdownSource
                relationships = (try? coordinator.relationships.fetchRelationships(for: doc.id)) ?? []
                versions = (try? coordinator.versionHistory.fetchVersions(for: doc.id)) ?? []
            }
        } else {
            document = nil
            wikiPage = nil
            titleText = ""
            markdownText = ""
            relationships = []
            versions = []
        }
    }

    private func saveActiveContent(_ newContent: String) {
        if coordinator.selectedModuleKind == .projectWiki {
            if let wp = wikiPage {
                wp.markdownSource = newContent
                try? coordinator.wiki.createOrUpdateWikiPage(title: wp.title, content: newContent)
            }
        } else if let doc = document {
            doc.markdownSource = newContent
            try? coordinator.documents.updateDocument(doc)
        }
    }

    private func renameActiveDocument(to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if coordinator.selectedModuleKind == .projectWiki {
            if let wp = wikiPage {
                wp.title = trimmed
                try? coordinator.wiki.createOrUpdateWikiPage(title: trimmed, content: wp.markdownSource)
            }
        } else if let doc = document {
            doc.title = trimmed
            try? coordinator.documents.updateDocument(doc)
        }

        isRenaming = false
        reloadData()
    }

    private func duplicateActive() {
        if coordinator.selectedModuleKind == .projectWiki, let wp = wikiPage {
            _ = try? coordinator.wiki.createOrUpdateWikiPage(title: "\(wp.title) Copy", content: wp.markdownSource)
        } else if let doc = document {
            do {
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
            } catch {
                // silent
            }
        }
        reloadData()
    }

    private func deleteActive() {
        if coordinator.selectedModuleKind == .projectWiki {
            if let wp = wikiPage {
                coordinator.storage.context.delete(wp)
                try? coordinator.storage.context.save()
                coordinator.selectedWikiPageID = nil
            }
        } else if let doc = document {
            try? coordinator.documents.deleteDocument(doc)
            coordinator.selectedDocumentID = nil
        }
        reloadData()
    }
}
