import SwiftUI
import AppKit

public enum EditorLayoutMode {
    case compact
    case normal
    case wide
}

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

    // Collapsible & Visual metadata state
    @State private var newTagText = ""
    @State private var selectedSidePanelTab = 0 // 0 = Live Preview, 1 = Right Inspector

    // Search and Replace state
    @State private var showSearchAndReplace = false
    @State private var searchQuery = ""
    @State private var replaceQuery = ""

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

        GeometryReader { geometry in
            let width = geometry.size.width
            let mode: EditorLayoutMode = width < 680 ? .compact : (width < 1050 ? .normal : .wide)

            VStack(spacing: 0) {
                if let doc = document {
                    // Header Area
                    headerArea(for: doc, mode: mode, state: state)

                    Divider()

                    // Formatting Toolbar
                    adaptiveFormattingToolbar(mode: mode)

                    // Search & Replace Bar
                    if showSearchAndReplace {
                        searchAndReplaceBar()
                    }

                    // Content Split View
                    HStack(spacing: 0) {
                        // Left-Center: Editing Canvas
                        VStack(spacing: 0) {
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

                        // Conditional Side Panels (Live Preview and Inspector)
                        sidePanelsArea(for: doc, mode: mode, state: state)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                } else {
                    emptyStateView()
                }
            }
            .background(
                // Invisible shortcut button for Cmd+F
                ZStack {
                    Button("") {
                        withAnimation {
                            showSearchAndReplace.toggle()
                        }
                    }
                    .keyboardShortcut("f", modifiers: .command)
                    .buttonStyle(.plain)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                }
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            reloadData()
            registerNotificationObserver()
        }
        .onChange(of: documentID) { _, _ in
            reloadData()
            isRenaming = false
        }
    }

    // MARK: - Layout Component: Header Area

    @ViewBuilder
    private func headerArea(for doc: Document, mode: EditorLayoutMode, state: WorkspaceState) -> some View {
        HStack(spacing: mode == .compact ? 8 : 16) {
            HStack(spacing: mode == .compact ? 6 : 10) {
                Image(systemName: kind.icon)
                    .font(mode == .compact ? .body : .title2)
                    .foregroundStyle(kind.accentColor)

                if isRenaming {
                    TextField("Title", text: $editTitleText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: mode == .compact ? 12 : 16, weight: .bold))
                        .frame(maxWidth: mode == .compact ? 150 : 300)
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
                        .font(.system(size: mode == .compact ? 13 : 18, weight: .bold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .textSelection(.enabled)

                    Button {
                        editTitleText = titleText
                        isRenaming = true
                    } label: {
                        Image(systemName: "pencil")
                            .foregroundStyle(.secondary)
                            .font(.system(size: mode == .compact ? 10 : 13))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

            if mode != .compact {
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
                Toggle(isOn: Binding(
                    get: { state.showLivePreview },
                    set: { withAnimation { state.showLivePreview = $0 } }
                )) {
                    Label("Preview", systemImage: "sidebar.right")
                }
                .toggleStyle(.button)
                .help("Show/Hide live markdown preview side panel")

                Toggle(isOn: Binding(
                    get: { state.showRightInspector },
                    set: { withAnimation { state.showRightInspector = $0 } }
                )) {
                    Label("Inspector", systemImage: "info.circle")
                }
                .toggleStyle(.button)
                .help("Show/Hide document metadata inspector")

                // Action Buttons
                HStack(spacing: 8) {
                    Button {
                        duplicateDocument()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .help("Duplicate current document")
                    .buttonStyle(.bordered)
                }
            } else {
                // Compact Window Actions Menu
                Menu {
                    Toggle(isOn: Binding(
                        get: { state.showLivePreview },
                        set: { withAnimation { state.showLivePreview = $0 } }
                    )) {
                        Label("Live Preview", systemImage: "sidebar.right")
                    }
                    Toggle(isOn: Binding(
                        get: { state.showRightInspector },
                        set: { withAnimation { state.showRightInspector = $0 } }
                    )) {
                        Label("Inspector", systemImage: "info.circle")
                    }
                    Button {
                        duplicateDocument()
                    } label: {
                        Label("Duplicate", systemImage: "doc.on.doc")
                    }
                    if showSearchAndReplace {
                        Button("Hide Find") { showSearchAndReplace = false }
                    } else {
                        Button("Show Find (Cmd+F)") { showSearchAndReplace = true }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                }
                .menuStyle(.button)
            }
        }
        .padding(.horizontal, mode == .compact ? 12 : 24)
        .padding(.vertical, mode == .compact ? 8 : 14)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Layout Component: Formatting Toolbar

    @ViewBuilder
    private func adaptiveFormattingToolbar(mode: EditorLayoutMode) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if mode == .compact {
                    // Under compact window: collapse advanced tools into simple dropdowns/menus
                    Menu {
                        Section("Headers") {
                            Button("Header 1") { formatText(with: "# ", suffix: "") }
                            Button("Header 2") { formatText(with: "## ", suffix: "") }
                            Button("Header 3") { formatText(with: "### ", suffix: "") }
                        }
                        Section("Styles") {
                            Button("Bold") { formatText(with: "**", suffix: "**") }
                            Button("Italic") { formatText(with: "*", suffix: "*") }
                            Button("Inline Code") { formatText(with: "`", suffix: "`") }
                        }
                        Section("Blocks") {
                            Button("Quote") { formatText(with: "> ", suffix: "") }
                            Button("Link") { formatText(with: "[", suffix: "](url)") }
                            Button("Bullet List") { formatText(with: "- ", suffix: "") }
                            Button("Task List") { formatText(with: "- [ ] ", suffix: "") }
                        }
                    } label: {
                        Label("Insert...", systemImage: "plus")
                    }
                    .menuStyle(.button)
                    .controlSize(.small)

                    Menu {
                        Button {
                            tableRows = 3; tableCols = 3
                            insertCustomTable()
                        } label: { Label("3x3 Table", systemImage: "tablecells") }

                        Button {
                            tableRows = 5; tableCols = 4
                            insertCustomTable()
                        } label: { Label("5x4 Table", systemImage: "tablecells.fill") }

                        Divider()

                        Button { addTableRow() } label: { Label("Insert Row Below", systemImage: "plus.row.fill") }
                        Button { addTableColumn() } label: { Label("Insert Column Right", systemImage: "plus.column.fill") }
                    } label: {
                        Label("Table", systemImage: "tablecells")
                    }
                    .menuStyle(.button)
                    .controlSize(.small)

                    specializedToolbar()
                } else {
                    // Under normal/wide window: show primary formatting tools directly
                    ControlGroup {
                        Button { formatText(with: "# ", suffix: "") } label: { Text("H1").bold() }.help("Heading 1")
                        Button { formatText(with: "## ", suffix: "") } label: { Text("H2").bold() }.help("Heading 2")
                    }
                    .controlSize(.small)

                    Divider().frame(height: 16)

                    ControlGroup {
                        Button { formatText(with: "**", suffix: "**") } label: { Image(systemName: "bold") }.help("Bold")
                        Button { formatText(with: "*", suffix: "*") } label: { Image(systemName: "italic") }.help("Italic")
                        Button { formatText(with: "`", suffix: "`") } label: { Image(systemName: "curlybraces") }.help("Inline Code")
                    }
                    .controlSize(.small)

                    Divider().frame(height: 16)

                    ControlGroup {
                        Button { formatText(with: "\n```\n", suffix: "\n```\n") } label: { Image(systemName: "doc.plaintext") }.help("Code Block")
                        Button { formatText(with: "> ", suffix: "") } label: { Image(systemName: "quote.opening") }.help("Blockquote")
                        Button { formatText(with: "[", suffix: "](url)") } label: { Image(systemName: "link") }.help("Hyperlink")
                    }
                    .controlSize(.small)

                    Divider().frame(height: 16)

                    ControlGroup {
                        Button { formatText(with: "- ", suffix: "") } label: { Image(systemName: "list.bullet") }.help("Bullet List")
                        Button { formatText(with: "- [ ] ", suffix: "") } label: { Image(systemName: "checkmark.square") }.help("Task List")
                    }
                    .controlSize(.small)

                    Divider().frame(height: 16)

                    // Markdown Tables Menu
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
                    .controlSize(.small)
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

                    Divider().frame(height: 16)

                    specializedToolbar()
                }

                Spacer()
            }
            .padding(.horizontal, mode == .compact ? 12 : 20)
            .padding(.vertical, mode == .compact ? 4 : 8)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()
        }
    }

    // MARK: - Layout Component: Search & Replace Bar

    @ViewBuilder
    private func searchAndReplaceBar() -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)

                TextField("Find", text: $searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(width: 150)

                Image(systemName: "arrow.right.arrow.left")
                    .foregroundStyle(.secondary)
                    .font(.caption)

                TextField("Replace", text: $replaceQuery)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .frame(width: 150)

                Button("Replace") {
                    performReplace()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Replace All") {
                    performReplaceAll()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button {
                    withAnimation {
                        showSearchAndReplace = false
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))

            Divider()
        }
    }

    // MARK: - Layout Component: Side Panels

    @ViewBuilder
    private func sidePanelsArea(for doc: Document, mode: EditorLayoutMode, state: WorkspaceState) -> some View {
        if mode == .compact {
            EmptyView()
        } else if mode == .normal {
            if state.showLivePreview && state.showRightInspector {
                VStack(spacing: 0) {
                    Picker("", selection: $selectedSidePanelTab) {
                        Text("Live Preview").tag(0)
                        Text("Inspector").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(10)
                    .background(Color(NSColor.windowBackgroundColor))

                    Divider()

                    if selectedSidePanelTab == 0 {
                        livePreviewPanel()
                    } else {
                        rightInspectorPanel(for: doc)
                    }
                }
                .frame(width: 320)
                .background(Color(NSColor.windowBackgroundColor))
                .transition(.slide)
            } else if state.showLivePreview {
                livePreviewPanel()
                    .frame(width: 320)
                    .background(Color(NSColor.windowBackgroundColor))
                    .transition(.slide)
            } else if state.showRightInspector {
                rightInspectorPanel(for: doc)
                    .frame(width: 320)
                    .background(Color(NSColor.windowBackgroundColor))
                    .transition(.slide)
            }
        } else {
            HStack(spacing: 0) {
                if state.showLivePreview {
                    Divider()
                    livePreviewPanel()
                        .frame(width: 360)
                        .background(Color(NSColor.windowBackgroundColor))
                }

                if state.showRightInspector {
                    Divider()
                    rightInspectorPanel(for: doc)
                        .frame(width: 300)
                        .background(Color(NSColor.windowBackgroundColor))
                }
            }
            .transition(.slide)
        }
    }

    @ViewBuilder
    private func livePreviewPanel() -> some View {
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
            .padding(20)
        }
    }

    @ViewBuilder
    private func rightInspectorPanel(for doc: Document) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 1. Validation HUD (if any)
                if let validation = validationMessage {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text("Validation Alert")
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
                        }
                        Text(validation)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                    )
                }

                // 2. Document Status & Priority Pickers
                VStack(alignment: .leading, spacing: 10) {
                    Text("Parameters")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("STATUS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                        Picker("", selection: Binding(
                            get: { doc.status ?? "To Do" },
                            set: { val in
                                doc.status = val
                                try? coordinator.documents.updateDocument(doc)
                            }
                        )) {
                            Text("To Do").tag("To Do")
                            Text("In Progress").tag("In Progress")
                            Text("Done").tag("Done")
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("PRIORITY")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                        Picker("", selection: Binding(
                            get: { doc.priority ?? "Medium" },
                            set: { val in
                                doc.priority = val
                                try? coordinator.documents.updateDocument(doc)
                            }
                        )) {
                            Text("High").tag("High")
                            Text("Medium").tag("Medium")
                            Text("Low").tag("Low")
                        }
                        .pickerStyle(.segmented)
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // 3. Document Statistics
                VStack(alignment: .leading, spacing: 10) {
                    Text("Statistics")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    let stats = calculateDocumentStats()
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                        GridRow {
                            Text("Words:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(stats.words)")
                                .font(.caption.bold())
                        }
                        GridRow {
                            Text("Characters:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(stats.chars)")
                                .font(.caption.bold())
                        }
                        GridRow {
                            Text("Read Time:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(stats.readTime) min")
                                .font(.caption.bold())
                        }
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // 4. Tag Manager
                VStack(alignment: .leading, spacing: 10) {
                    Text("Tags")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        TextField("New tag...", text: $newTagText, onCommit: {
                            addNewTag(to: doc)
                        })
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)

                        Button {
                            addNewTag(to: doc)
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if !doc.tags.isEmpty {
                        HFlowLayout(doc.tags, spacing: 6) { tag in
                            HStack(spacing: 4) {
                                Text(tag)
                                    .font(.caption)
                                Button {
                                    removeTag(tag, from: doc)
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8, weight: .bold))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(10)
                        }
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // 5. Template Helpers
                VStack(alignment: .leading, spacing: 10) {
                    Text("Markdown Quick Templates")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 6) {
                        Button("Header 1") { formatText(with: "# ", suffix: "") }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button("Header 2") { formatText(with: "## ", suffix: "") }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button("Bold Text") { formatText(with: "**", suffix: "**") }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button("Code Block") { formatText(with: "\n```\n", suffix: "\n```\n") }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button("Task Checklist") { formatText(with: "- [ ] ", suffix: "") }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        Button("Table Template") {
                            tableRows = 3; tableCols = 3
                            insertCustomTable()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // 6. Specialized Metadata (rendered if present)
                let specMeta = specializedMetadata()
                if !(specMeta is EmptyView) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Specialized Fields")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        specMeta
                    }
                    .padding(12)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Layout Component: Empty State

    @ViewBuilder
    private func emptyStateView() -> some View {
        ContentUnavailableView {
            Label("\(kind.rawValue) Workspace", systemImage: kind.icon)
        } description: {
            VStack(spacing: 16) {
                Text("No active document selected. Choose one from the category browser or create a new document.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 400)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Core Operations & Calculations

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

    private func registerNotificationObserver() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("InsertEditorText"),
            object: nil,
            queue: .main
        ) { notification in
            guard let textToInsert = notification.userInfo?["text"] as? String else { return }
            if markdownText.isEmpty {
                markdownText = textToInsert
            } else {
                markdownText += "\n" + textToInsert
            }
            document?.markdownSource = markdownText
            if let doc = document {
                try? coordinator.documents.updateDocument(doc)
            }
        }
    }

    private func calculateDocumentStats() -> (words: Int, chars: Int, readTime: Int) {
        let text = markdownText
        let charCount = text.count
        let words = text.components(separatedBy: .whitespacesAndNewlines)
                        .filter { !$0.isEmpty }
        let wordCount = words.count
        let readTime = max(1, Int(ceil(Double(wordCount) / 200.0)))
        return (wordCount, charCount, readTime)
    }

    private func addNewTag(to doc: Document) {
        let tag = newTagText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return }
        if !doc.tags.contains(tag) {
            doc.tags.append(tag)
            try? coordinator.documents.updateDocument(doc)
        }
        newTagText = ""
    }

    private func removeTag(_ tag: String, from doc: Document) {
        if let idx = doc.tags.firstIndex(of: tag) {
            doc.tags.remove(at: idx)
            try? coordinator.documents.updateDocument(doc)
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

    // MARK: - Search and Replace Logic

    private func performReplace() {
        guard !searchQuery.isEmpty else { return }
        if let range = markdownText.range(of: searchQuery) {
            markdownText.replaceSubrange(range, with: replaceQuery)
            if let doc = document {
                doc.markdownSource = markdownText
                try? coordinator.documents.updateDocument(doc)
            }
        }
    }

    private func performReplaceAll() {
        guard !searchQuery.isEmpty else { return }
        markdownText = markdownText.replacingOccurrences(of: searchQuery, with: replaceQuery)
        if let doc = document {
            doc.markdownSource = markdownText
            try? coordinator.documents.updateDocument(doc)
        }
    }

    // MARK: - Markdown Tables Processing

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

// Simple Helper for Horizontal Flow Layout of Tags
struct HFlowLayout: View {
    let spacing: CGFloat
    let items: [AnyView]

    init<Data: RandomAccessCollection, Content: View>(
        _ data: Data,
        spacing: CGFloat = 8,
        @ViewBuilder content: @escaping (Data.Element) -> Content
    ) {
        self.spacing = spacing
        self.items = data.map { AnyView(content($0)) }
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 80))], spacing: spacing) {
            ForEach(0..<items.count, id: \.self) { index in
                items[index]
            }
        }
    }
}
