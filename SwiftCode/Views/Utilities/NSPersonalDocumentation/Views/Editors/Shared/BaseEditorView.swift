import SwiftUI
import AppKit

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

    // Left sidebar document browser state
    @State private var localDocs: [Document] = []
    @State private var browserSearchQuery = ""

    // Find and Replace state
    @State private var showFindBar = false
    @State private var searchText = ""
    @State private var replaceText = ""
    @State private var currentMatchIndex = -1
    @State private var totalMatches = 0

    // Table parameters
    @State private var tableRows = 3
    @State private var tableCols = 3
    @State private var showTableCreatorPopover = false

    // Visual inspector section expand/collapse states
    @State private var isDocInfoExpanded = true
    @State private var isCoreParamsExpanded = true
    @State private var isTagsExpanded = true
    @State private var isSpecializedExpanded = true
    @State private var isInsertionsExpanded = true

    @State private var newTagText = ""

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

    // Dynamic stats
    private var wordCount: Int {
        markdownText.split(whereSeparator: { $0.isWhitespace }).count
    }

    private var characterCount: Int {
        markdownText.count
    }

    private var estimatedReadTime: Int {
        max(1, Int(ceil(Double(wordCount) / 200.0)))
    }

    public var body: some View {
        @Bindable var state = workspaceState

        HStack(spacing: 0) {
            // Panel 1: Collapsible Left Browser (Xcode-style file list)
            if state.showLeftSidebar {
                VStack(spacing: 0) {
                    // Header with search & add
                    VStack(spacing: 8) {
                        HStack {
                            Text(kind.rawValue)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button {
                                createNewDocument()
                            } label: {
                                Image(systemName: "square.and.pencil")
                            }
                            .buttonStyle(.plain)
                            .help("Create new \(kind.rawValue) document")
                        }

                        // Search
                        HStack {
                            Image(systemName: "magnifyingglass")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("Filter...", text: $browserSearchQuery)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                            if !browserSearchQuery.isEmpty {
                                Button { browserSearchQuery = "" } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                        )
                    }
                    .padding(10)
                    .background(Color(NSColor.windowBackgroundColor))

                    Divider()

                    // Document List
                    if filteredLocalDocs.isEmpty {
                        VStack {
                            Spacer()
                            Text("No documents")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        ScrollView {
                            VStack(spacing: 2) {
                                ForEach(filteredLocalDocs, id: \.id) { doc in
                                    HStack {
                                        Image(systemName: kind.icon)
                                            .font(.caption)
                                            .foregroundStyle(doc.id == documentID ? .white : kind.accentColor)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(doc.title)
                                                .font(.system(size: 11, weight: doc.id == documentID ? .bold : .regular))
                                                .foregroundStyle(doc.id == documentID ? .white : .primary)
                                                .lineLimit(1)
                                            Text(doc.updatedAt.formatted(date: .abbreviated, time: .omitted))
                                                .font(.system(size: 9))
                                                .foregroundStyle(doc.id == documentID ? Color.white.opacity(0.8) : .secondary)
                                        }

                                        Spacer()
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(doc.id == documentID ? Color.accentColor : Color.clear)
                                    .cornerRadius(4)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        state.selectedDocumentID = doc.id
                                    }
                                }
                            }
                            .padding(4)
                        }
                    }
                }
                .frame(width: 200)
                .background(Color(NSColor.windowBackgroundColor))

                Divider()
            }

            // Center Panel: Primary Text Editor & Previews
            if let doc = document {
                VStack(spacing: 0) {
                    // Modern Header Bar
                    HStack(spacing: 12) {
                        // Title / Renaming HUD
                        HStack(spacing: 8) {
                            Image(systemName: kind.icon)
                                .font(.system(size: 14))
                                .foregroundStyle(kind.accentColor)

                            if isRenaming {
                                TextField("Title", text: $editTitleText)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 14, weight: .bold))
                                    .onSubmit {
                                        renameDocument(to: editTitleText)
                                    }
                                    .focused(.some(true))
                                    .frame(width: 250)

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
                                    .font(.system(size: 14, weight: .bold))
                                    .lineLimit(1)
                                    .truncationMode(.tail)

                                Button {
                                    editTitleText = titleText
                                    isRenaming = true
                                } label: {
                                    Image(systemName: "pencil")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        // Validation HUD Check Indicator
                        if let validation = validationMessage {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                Text(validation)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.orange.opacity(0.12))
                            .cornerRadius(5)
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.shield.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                                Text("Valid")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.12))
                            .cornerRadius(5)
                        }

                        Spacer()

                        // Stats Summary Badge
                        Text("\(wordCount) words  •  \(estimatedReadTime) min read")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)

                        // Split Toggles
                        Group {
                            Button {
                                withAnimation { state.showLeftSidebar.toggle() }
                            } label: {
                                Image(systemName: "sidebar.left")
                                    .foregroundStyle(state.showLeftSidebar ? Color.accentColor : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Toggle Sidebar (Cmd+Shift+L)")

                            Button {
                                withAnimation { state.showLivePreview.toggle() }
                            } label: {
                                Image(systemName: "sidebar.right")
                                    .foregroundStyle(state.showLivePreview ? Color.accentColor : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Toggle Live Preview (Cmd+Shift+P)")

                            Button {
                                withAnimation { state.showRightInspector.toggle() }
                            } label: {
                                Image(systemName: "sidebar.right.fill")
                                    .foregroundStyle(state.showRightInspector ? Color.accentColor : Color.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Toggle Right Inspector (Cmd+Shift+I)")
                        }
                        .font(.system(size: 12))
                        .padding(.horizontal, 2)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color(NSColor.windowBackgroundColor))

                    Divider()

                    // Keyboard Shortcut Observers
                    backgroundShortcuts

                    // Find & Replace Bar (Collapsible)
                    if showFindBar {
                        VStack(spacing: 0) {
                            findAndReplaceBar
                            Divider()
                        }
                    }

                    // Content Split Editor & Live Preview Panel
                    HStack(spacing: 0) {
                        // Editor View
                        DocNSTextView(text: Binding(
                            get: { markdownText },
                            set: { val in
                                markdownText = val
                                doc.markdownSource = val
                                try? coordinator.documents.updateDocument(doc)
                                countMatches()
                            }
                        ))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // Live Preview Panel
                        if state.showLivePreview {
                            Divider()

                            ScrollView {
                                VStack(alignment: .leading, spacing: 20) {
                                    if markdownText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        Text("Start typing to see live-rendered markdown preview.")
                                            .font(.system(size: 12, weight: .regular, design: .sansSerif))
                                            .foregroundStyle(.secondary)
                                            .italic()
                                    } else {
                                        MarkdownBlockListView(blocks: MarkdownParser.shared.parse(markdownText))
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                            }
                            .frame(width: 320)
                            .background(Color(NSColor.windowBackgroundColor))
                        }
                    }

                    Divider()

                    // Formatting Toolbar (Lower status bar aligned)
                    formattingToolbar
                }
                .frame(maxWidth: .infinity)

                // Panel 3: Collapsible Right Inspector (High density, professional stats & custom configs)
                if state.showRightInspector {
                    Divider()

                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            // Section 1: Document Properties
                            DisclosureGroup(isExpanded: $isDocInfoExpanded) {
                                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                                    GridRow {
                                        Text("Title:")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.secondary)
                                        Text(doc.title)
                                            .font(.system(size: 11))
                                            .lineLimit(1)
                                    }
                                    GridRow {
                                        Text("Words:")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.secondary)
                                        Text("\(wordCount)")
                                            .font(.system(size: 11))
                                    }
                                    GridRow {
                                        Text("Chars:")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.secondary)
                                        Text("\(characterCount)")
                                            .font(.system(size: 11))
                                    }
                                    GridRow {
                                        Text("Reading Time:")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.secondary)
                                        Text("\(estimatedReadTime) min")
                                            .font(.system(size: 11))
                                    }
                                    GridRow {
                                        Text("Created:")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.secondary)
                                        Text(doc.createdAt.formatted(date: .numeric, time: .shortened))
                                            .font(.system(size: 10))
                                    }
                                    GridRow {
                                        Text("Updated:")
                                            .font(.system(size: 11, weight: .bold))
                                            .foregroundStyle(.secondary)
                                        Text(doc.updatedAt.formatted(date: .numeric, time: .shortened))
                                            .font(.system(size: 10))
                                    }
                                }
                                .padding(.top, 4)
                            } label: {
                                Label("DOCUMENT INFO", systemImage: "info.circle.fill")
                                    .font(.system(size: 10, weight: .bold))
                            }

                            Divider()

                            // Section 2: Core Parameters
                            DisclosureGroup(isExpanded: $isCoreParamsExpanded) {
                                VStack(alignment: .leading, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("STATUS")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.secondary)
                                        Picker("", selection: Binding(
                                            get: { doc.status ?? "To Do" },
                                            set: { val in
                                                doc.status = val
                                                try? coordinator.documents.updateDocument(doc)
                                                refreshLocalDocs()
                                            }
                                        )) {
                                            Text("To Do").tag("To Do")
                                            Text("In Progress").tag("In Progress")
                                            Text("Done").tag("Done")
                                        }
                                        .pickerStyle(.segmented)
                                        .controlSize(.small)
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("PRIORITY")
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundStyle(.secondary)
                                        Picker("", selection: Binding(
                                            get: { doc.priority ?? "Medium" },
                                            set: { val in
                                                doc.priority = val
                                                try? coordinator.documents.updateDocument(doc)
                                                refreshLocalDocs()
                                            }
                                        )) {
                                            Text("High").tag("High")
                                            Text("Medium").tag("Medium")
                                            Text("Low").tag("Low")
                                        }
                                        .pickerStyle(.segmented)
                                        .controlSize(.small)
                                    }
                                }
                                .padding(.top, 6)
                            } label: {
                                Label("CORE PARAMETERS", systemImage: "slider.horizontal.3")
                                    .font(.system(size: 10, weight: .bold))
                            }

                            Divider()

                            // Section 3: Tag Manager
                            DisclosureGroup(isExpanded: $isTagsExpanded) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack(spacing: 4) {
                                        TextField("New tag...", text: $newTagText, onCommit: {
                                            addNewTag(to: doc)
                                        })
                                        .textFieldStyle(.roundedBorder)
                                        .controlSize(.small)

                                        Button {
                                            addNewTag(to: doc)
                                        } label: {
                                            Image(systemName: "plus")
                                                .font(.system(size: 10, weight: .bold))
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }

                                    FlowLayout(spacing: 4) {
                                        ForEach(doc.tags, id: \.self) { tag in
                                            HStack(spacing: 4) {
                                                Text(tag)
                                                    .font(.system(size: 10))
                                                    .foregroundStyle(.primary)
                                                Button {
                                                    removeTag(tag, from: doc)
                                                } label: {
                                                    Image(systemName: "xmark")
                                                        .font(.system(size: 7, weight: .bold))
                                                }
                                                .buttonStyle(.plain)
                                            }
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(Color.secondary.opacity(0.12))
                                            .cornerRadius(6)
                                        }
                                    }
                                }
                                .padding(.top, 6)
                            } label: {
                                Label("TAGS", systemImage: "tag.fill")
                                    .font(.system(size: 10, weight: .bold))
                            }

                            Divider()

                            // Section 4: Specialized Archetype Metadata
                            DisclosureGroup(isExpanded: $isSpecializedExpanded) {
                                VStack(alignment: .leading, spacing: 8) {
                                    specializedMetadata()
                                }
                                .padding(.top, 6)
                            } label: {
                                Label("ARCHETYPE METADATA", systemImage: "doc.plaintext.fill")
                                    .font(.system(size: 10, weight: .bold))
                            }

                            Divider()

                            // Section 5: Template Blocks & Helpers
                            DisclosureGroup(isExpanded: $isInsertionsExpanded) {
                                VStack(alignment: .leading, spacing: 6) {
                                    specializedToolbar()
                                        .controlSize(.small)

                                    Divider().padding(.vertical, 2)

                                    Text("INSERT QUICK CODE / BLOCKS")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.secondary)

                                    Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                                        GridRow {
                                            Button { formatText(with: "\n```\n", suffix: "\n```\n") } label: { Label("Code Block", systemImage: "curlybraces") }
                                            Button { formatText(with: "> ", suffix: "") } label: { Label("Quote", systemImage: "quote.opening") }
                                        }
                                        GridRow {
                                            Button { formatText(with: "[", suffix: "](url)") } label: { Label("Hyperlink", systemImage: "link") }
                                            Button { formatText(with: "\n---\n", suffix: "") } label: { Label("Separator", systemImage: "minus") }
                                        }
                                    }
                                    .controlSize(.small)
                                }
                                .padding(.top, 6)
                            } label: {
                                Label("INSERTION WORKSPACE", systemImage: "square.grid.3x1.below.line.grid.1x2")
                                    .font(.system(size: 10, weight: .bold))
                            }
                        }
                        .padding(14)
                    }
                    .frame(width: 250)
                    .background(Color(NSColor.windowBackgroundColor))
                }
            } else {
                ContentUnavailableView {
                    Label("\(kind.rawValue) Workspace", systemImage: kind.icon)
                } description: {
                    VStack(spacing: 16) {
                        Text("No active document selected. Choose one from the browser or create a new document.")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))
                            .frame(maxWidth: 400)
                            .multilineTextAlignment(.center)

                        Button("Create New Entry") {
                            createNewDocument()
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
            registerNotificationObserver()
            refreshLocalDocs()
        }
        .onChange(of: documentID) { _, _ in
            reloadData()
            isRenaming = false
        }
        .onChange(of: kind) { _, _ in
            refreshLocalDocs()
        }
    }

    // Helper views
    private var backgroundShortcuts: some View {
        @Bindable var state = workspaceState
        return HStack {
            // Left Sidebar Toggle
            Button("") { withAnimation { state.showLeftSidebar.toggle() } }
                .keyboardShortcut("l", modifiers: [.command, .shift])
                .opacity(0).frame(width: 0, height: 0)

            // Right Inspector Toggle
            Button("") { withAnimation { state.showRightInspector.toggle() } }
                .keyboardShortcut("i", modifiers: [.command, .shift])
                .opacity(0).frame(width: 0, height: 0)

            // Live Preview Toggle
            Button("") { withAnimation { state.showLivePreview.toggle() } }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .opacity(0).frame(width: 0, height: 0)

            // Find Bar Toggle
            Button("") { toggleFindBar() }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0)
        }
    }

    private var findAndReplaceBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            // Search
            VStack(spacing: 4) {
                HStack {
                    TextField("Find text...", text: $searchText, onCommit: { performFind(forward: true) })
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .onChange(of: searchText) { _, _ in countMatches() }

                    if totalMatches > 0 {
                        Text("\(currentMatchIndex + 1) of \(totalMatches)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    } else if !searchText.isEmpty {
                        Text("No matches")
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                    }

                    if !searchText.isEmpty {
                        Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(NSColor.separatorColor), lineWidth: 0.5))

                // Replace
                HStack {
                    TextField("Replace with...", text: $replaceText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))

                    if !replaceText.isEmpty {
                        Button { replaceText = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(4)
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(NSColor.separatorColor), lineWidth: 0.5))
            }
            .frame(width: 300)

            // Actions
            HStack(spacing: 4) {
                Button { performFind(forward: false) } label: { Image(systemName: "chevron.left") }
                    .help("Previous Match")
                Button { performFind(forward: true) } label: { Image(systemName: "chevron.right") }
                    .help("Next Match")

                Divider().frame(height: 18).padding(.horizontal, 4)

                Button("Replace") { performReplace() }
                    .disabled(totalMatches == 0)
                Button("All") { performReplaceAll() }
                    .disabled(totalMatches == 0)
            }
            .controlSize(.small)
            .buttonStyle(.bordered)

            Spacer()

            Button { toggleFindBar() } label: {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var formattingToolbar: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 8) {
                // Typography Headers
                ControlGroup {
                    Button { formatText(with: "# ", suffix: "") } label: { Text("H1").bold() }.help("Heading 1")
                    Button { formatText(with: "## ", suffix: "") } label: { Text("H2").bold() }.help("Heading 2")
                    Button { formatText(with: "### ", suffix: "") } label: { Text("H3").bold() }.help("Heading 3")
                }

                Divider().frame(height: 16)

                // Inline Styles
                ControlGroup {
                    Button { formatText(with: "**", suffix: "**") } label: { Image(systemName: "bold") }.help("Bold")
                    Button { formatText(with: "*", suffix: "*") } label: { Image(systemName: "italic") }.help("Italic")
                    Button { formatText(with: "~~", suffix: "~~") } label: { Image(systemName: "strikethrough") }.help("Strikethrough")
                }

                Divider().frame(height: 16)

                // Lists
                ControlGroup {
                    Button { formatText(with: "- ", suffix: "") } label: { Image(systemName: "list.bullet") }.help("Bullet List")
                    Button { formatText(with: "1. ", suffix: "") } label: { Image(systemName: "list.number") }.help("Numbered List")
                    Button { formatText(with: "- [ ] ", suffix: "") } label: { Image(systemName: "checkmark.square") }.help("Task List")
                }

                Divider().frame(height: 16)

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
                    .frame(width: 200)
                }

                Spacer()

                // Operations & Actions
                HStack(spacing: 6) {
                    Button {
                        duplicateDocument()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .help("Duplicate current document")

                    Button {
                        deleteDocument()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Delete current document")
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
        }
    }

    // List filtering
    private var filteredLocalDocs: [Document] {
        if browserSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return localDocs
        } else {
            return localDocs.filter { $0.title.localizedCaseInsensitiveContains(browserSearchQuery) }
        }
    }

    private func refreshLocalDocs() {
        if let all = try? coordinator.documents.fetchDocuments() {
            localDocs = all.filter { $0.moduleKind == kind }
        }
    }

    private func createNewDocument() {
        do {
            let doc = try coordinator.documents.createDocument(title: "Untitled \(kind.rawValue)", kind: kind)
            workspaceState.selectedDocumentID = doc.id
            refreshLocalDocs()
            reloadData()
        } catch {}
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
            countMatches()
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

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("PersonalDocDocumentRestored"),
            object: nil,
            queue: .main
        ) { _ in
            reloadData()
        }
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
        refreshLocalDocs()
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
            refreshLocalDocs()
        } catch {}
    }

    private func deleteDocument() {
        guard let doc = document else { return }
        let alert = NSAlert()
        alert.messageText = "Delete Document"
        alert.informativeText = "Are you sure you want to permanently delete '\(doc.title)'?"
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            try? coordinator.documents.deleteDocument(doc)
            workspaceState.selectedDocumentID = nil
            refreshLocalDocs()
            reloadData()
        }
    }

    // Search and Replace Logic
    private func toggleFindBar() {
        withAnimation {
            showFindBar.toggle()
            if !showFindBar {
                searchText = ""
                totalMatches = 0
                currentMatchIndex = -1
            }
        }
    }

    private func countMatches() {
        guard !searchText.isEmpty else {
            totalMatches = 0
            currentMatchIndex = -1
            return
        }
        let matches = occurrences(of: searchText, in: markdownText)
        totalMatches = matches.count
        if totalMatches > 0 && currentMatchIndex == -1 {
            currentMatchIndex = 0
        } else if totalMatches == 0 {
            currentMatchIndex = -1
        }
    }

    private func occurrences(of target: String, in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start = text.startIndex
        while start < text.endIndex, let range = text.range(of: target, options: .caseInsensitive, range: start..<text.endIndex) {
            ranges.append(range)
            start = range.upperBound == start ? text.index(after: start) : range.upperBound
        }
        return ranges
    }

    private func performFind(forward: Bool) {
        countMatches()
        guard totalMatches > 0 else { return }
        if forward {
            currentMatchIndex = (currentMatchIndex + 1) % totalMatches
        } else {
            currentMatchIndex = (currentMatchIndex - 1 + totalMatches) % totalMatches
        }
    }

    private func performReplace() {
        guard !searchText.isEmpty, totalMatches > 0, currentMatchIndex >= 0 else { return }
        let matches = occurrences(of: searchText, in: markdownText)
        guard currentMatchIndex < matches.count else { return }
        let rangeToReplace = matches[currentMatchIndex]
        markdownText.replaceSubrange(rangeToReplace, with: replaceText)

        document?.markdownSource = markdownText
        if let doc = document {
            try? coordinator.documents.updateDocument(doc)
        }
        countMatches()
    }

    private func performReplaceAll() {
        guard !searchText.isEmpty, totalMatches > 0 else { return }
        markdownText = markdownText.replacingOccurrences(of: searchText, with: replaceText, options: .caseInsensitive)

        document?.markdownSource = markdownText
        if let doc = document {
            try? coordinator.documents.updateDocument(doc)
        }
        countMatches()
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

// Reusable flow layout helper for tags
struct FlowLayout: Layout {
    var spacing: CGFloat

    init(spacing: CGFloat = 4) {
        self.spacing = spacing
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }
        totalHeight = currentY + lineHeight
        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX {
                currentX = bounds.minX
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: ProposedViewSize(size))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }
    }
}
