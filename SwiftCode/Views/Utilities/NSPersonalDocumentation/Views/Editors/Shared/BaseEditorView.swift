import SwiftUI

public struct BaseEditorView<ToolbarContent: View, MetadataContent: View>: View {
    public let coordinator: PersonalDocumentationCoordinator
    public let kind: ModuleKind
    public let documentID: UUID?

    // Custom sections passed by specialized editors
    @ViewBuilder public let specializedToolbar: () -> ToolbarContent
    @ViewBuilder public let specializedMetadata: () -> MetadataContent
    public let validationMessage: String?

    // Shared state
    @State private var document: Document? = nil
    @State private var titleText = ""
    @State private var markdownText = ""
    @State private var isRenaming = false
    @State private var editTitleText = ""

    // Table parameters
    @State private var tableRows = 3
    @State private var tableCols = 3
    @State private var showTableCreatorPopover = false

    public init(
        coordinator: PersonalDocumentationCoordinator,
        kind: ModuleKind,
        documentID: UUID?,
        @ViewBuilder specializedToolbar: @escaping () -> ToolbarContent = { EmptyView() },
        @ViewBuilder specializedMetadata: @escaping () -> MetadataContent = { EmptyView() },
        validationMessage: String? = nil
    ) {
        self.coordinator = coordinator
        self.kind = kind
        self.documentID = documentID
        self.specializedToolbar = specializedToolbar
        self.specializedMetadata = specializedMetadata
        self.validationMessage = validationMessage
    }

    private var workspaceState: WorkspaceState {
        coordinator.state(for: kind)
    }

    public var body: some View {
        @Bindable var state = workspaceState

        VStack(spacing: 0) {
            if let doc = document {
                // Header Area
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 16) {
                        HStack(spacing: 10) {
                            Image(systemName: kind.icon)
                                .font(.title2)
                                .foregroundStyle(kind.accentColor)

                            if isRenaming {
                                TextField("Title", text: $editTitleText)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.title3.bold())
                                    .frame(maxWidth: 300)
                                    .onSubmit {
                                        renameDocument(to: editTitleText)
                                    }

                                Button {
                                    renameDocument(to: editTitleText)
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

                        // Validation Message Indicator
                        if let validation = validationMessage {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                Text(validation)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(6)
                        }

                        // Preview Toggler
                        Toggle(isOn: $state.showLivePreview) {
                            Label("Live Preview", systemImage: "sidebar.right")
                        }
                        .toggleStyle(.button)
                        .help("Show/Hide live markdown preview side panel")

                        // Action Buttons
                        HStack(spacing: 10) {
                            Button {
                                state.showBrowserSheet = true
                            } label: {
                                Label("Browse", systemImage: "folder")
                            }
                            .buttonStyle(.bordered)
                            .help("Browse category documents")

                            Button {
                                duplicateDocument()
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .help("Duplicate current document")
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color(NSColor.windowBackgroundColor))

                    Divider()

                    // Formatting Toolbar
                    formattingToolbar
                }

                // Split Editing Pane
                HStack(spacing: 0) {
                    // Editor view (always editable, comfortable width)
                    VStack(spacing: 0) {
                        // Standard & Specialized Metadata Pane
                        VStack(spacing: 12) {
                            HStack(spacing: 24) {
                                Picker("Status", selection: Binding(
                                    get: { doc.status },
                                    set: { val in
                                        doc.status = val
                                        try? coordinator.documents.updateDocument(doc)
                                    }
                                )) {
                                    Text("To Do").tag("To Do")
                                    Text("In Progress").tag("In Progress")
                                    Text("Done").tag("Done")
                                }
                                .frame(width: 180)

                                Picker("Priority", selection: Binding(
                                    get: { doc.priority },
                                    set: { val in
                                        doc.priority = val
                                        try? coordinator.documents.updateDocument(doc)
                                    }
                                )) {
                                    Text("High").tag("High")
                                    Text("Medium").tag("Medium")
                                    Text("Low").tag("Low")
                                }
                                .frame(width: 180)

                                Spacer()
                            }

                            // Inject specialized editor's own metadata UI here
                            specializedMetadata()
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(Color(NSColor.controlBackgroundColor))

                        Divider()

                        DocNSTextView(text: Binding(
                            get: { markdownText },
                            set: { val in
                                markdownText = val
                                doc.markdownSource = val
                                try? coordinator.documents.updateDocument(doc)
                            }
                        ))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(maxWidth: .infinity)

                    if state.showLivePreview {
                        Divider()

                        // Premium Live Markdown Preview
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                if markdownText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text("Start typing on the left to see live-rendered markdown preview.")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .italic()
                                } else {
                                    MarkdownBlockListView(blocks: MarkdownParser.shared.parse(markdownText))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(24)
                        }
                        .frame(width: 400)
                        .background(Color(NSColor.underlyingWindowBackgroundColor))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            } else {
                ContentUnavailableView {
                    Label("\(kind.rawValue) Workspace", systemImage: kind.icon)
                } description: {
                    VStack(spacing: 16) {
                        Text("No active document selected. Choose one from the category browser or create a new document.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: 400)
                            .multilineTextAlignment(.center)

                        Button("Browse Documents") {
                            state.showBrowserSheet = true
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
        }
        .onChange(of: documentID) { _, _ in
            reloadData()
            isRenaming = false
        }
        .sheet(isPresented: $state.showBrowserSheet) {
            VStack(spacing: 0) {
                HStack {
                    Text("Browse \(kind.rawValue)")
                        .font(.headline)
                    Spacer()
                    Button("Close") {
                        state.showBrowserSheet = false
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                Divider()
                RecordListView(
                    coordinator: coordinator,
                    kind: kind,
                    selectedDocumentID: $state.selectedDocumentID,
                    onSelect: {
                        state.showBrowserSheet = false
                        reloadData()
                    }
                )
                .frame(width: 800, height: 600)
            }
        }
    }

    private var formattingToolbar: some View {
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

                // Lists
                ControlGroup {
                    Button { formatText(with: "- ", suffix: "") } label: { Image(systemName: "list.bullet") }.help("Bullet List")
                    Button { formatText(with: "1. ", suffix: "") } label: { Image(systemName: "list.number") }.help("Numbered List")
                    Button { formatText(with: "- [ ] ", suffix: "") } label: { Image(systemName: "checkmark.square") }.help("Task List")
                    Button { formatText(with: "\n---\n", suffix: "") } label: { Image(systemName: "minus") }.help("Horizontal Rule")
                }

                Divider().frame(height: 20)

                // Advanced Markdown Tables
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
                    } label: { Label("Custom Table...", systemImage: "slider.horizontal.3") }

                    Divider()

                    Button { addTableRow() } label: { Label("Insert Row Below", systemImage: "plus.row.fill") }
                    Button { deleteTableRow() } label: { Label("Delete Active Row", systemImage: "minus.row.fill") }
                    Button { addTableColumn() } label: { Label("Insert Column Right", systemImage: "plus.column.fill") }
                    Button { deleteTableColumn() } label: { Label("Delete Active Column", systemImage: "minus.column.fill") }

                    Divider()

                    Button { alignTable(to: "left") } label: { Label("Align Left", systemImage: "align.left") }
                    Button { alignTable(to: "center") } label: { Label("Align Center", systemImage: "align.center") }
                    Button { alignTable(to: "right") } label: { Label("Align Right", systemImage: "align.right") }
                } label: {
                    Label("Table", systemImage: "tablecells")
                }
                .menuStyle(.button)
                .help("Create and edit tables")
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

                Divider().frame(height: 20)

                // Inject specialized editor's custom actions
                specializedToolbar()

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()
        }
    }

    private func reloadData() {
        guard let id = documentID else {
            document = nil
            titleText = ""
            markdownText = ""
            return
        }
        if let doc = try? coordinator.documents.fetchDocument(id: id) {
            document = doc
            titleText = doc.title
            markdownText = doc.markdownSource
        }
    }

    private func formatText(with prefix: String, suffix: String) {
        if markdownText.isEmpty {
            markdownText = prefix + "Content" + suffix
        } else {
            markdownText += prefix + suffix
        }
        document?.markdownSource = markdownText
        if let doc = document {
            try? coordinator.documents.updateDocument(doc)
        }
    }

    private func renameDocument(to newTitle: String) {
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        document?.title = trimmed
        if let doc = document {
            try? coordinator.documents.updateDocument(doc)
        }
        isRenaming = false
        titleText = trimmed
    }

    private func duplicateDocument() {
        guard let doc = document else { return }
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
            workspaceState.selectedDocumentID = duplicate.id
        } catch {}
    }

    // Markdown Tables Processing
    private func insertCustomTable() {
        var tableMarkdown = "\n"
        tableMarkdown += "|"
        for c in 1...tableCols {
            tableMarkdown += " Header \(c) |"
        }
        tableMarkdown += "\n|"
        for _ in 1...tableCols {
            tableMarkdown += " :--- |"
        }
        tableMarkdown += "\n"
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
        let cols = countColumns()
        let newRow = "\n|" + String(repeating: "  |", count: max(1, cols))
        formatText(with: newRow, suffix: "")
    }

    private func deleteTableRow() {
        var lines = markdownText.components(separatedBy: .newlines)
        if let lastIdx = lines.lastIndex(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("|") && !$0.contains(":---") }) {
            lines.remove(at: lastIdx)
            markdownText = lines.joined(separator: "\n")
            document?.markdownSource = markdownText
            if let doc = document { try? coordinator.documents.updateDocument(doc) }
        }
    }

    private func addTableColumn() {
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
            document?.markdownSource = markdownText
            if let doc = document { try? coordinator.documents.updateDocument(doc) }
        }
    }

    private func deleteTableColumn() {
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
            document?.markdownSource = markdownText
            if let doc = document { try? coordinator.documents.updateDocument(doc) }
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
            document?.markdownSource = markdownText
            if let doc = document { try? coordinator.documents.updateDocument(doc) }
        }
    }

    private func countColumns() -> Int {
        let lines = markdownText.components(separatedBy: .newlines)
        if let dividerLine = lines.first(where: { $0.trimmingCharacters(in: .whitespaces).hasPrefix("|") && $0.contains(":---") }) {
            return dividerLine.components(separatedBy: "|").count - 2
        }
        return 3
    }
}
