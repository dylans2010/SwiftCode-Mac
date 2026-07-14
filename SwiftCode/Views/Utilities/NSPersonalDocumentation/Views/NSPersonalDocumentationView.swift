// ====================================================================
// NS PERSONAL DOCUMENTATION - MAIN ENTRY POINT (REFACTORED WORKSPACE)
// ====================================================================
// This view acts as the MAIN container view of the personal documentation feature,
// coordinating and accessing all sub-views/modules (Dashboard, Wiki,
// Knowledge Graph, Timeline, Whiteboards, Snippets, Snapshots, etc.) and
// is integrated to be accessible from WorkspaceView.
//
// Refactored to utilize a native macOS-like HSplitView for fluid multi-column resizing,
// a clean, modern collapsible sidebar, and full available workspace width.
// ====================================================================

import SwiftUI
import AppKit

public struct NSPersonalDocumentationView: View {
    @Environment(ProjectSessionStore.self) private var sessionStore
    @State private var coordinator: PersonalDocumentationCoordinator? = nil
    @State private var initializationError: String? = nil
    @State private var showingCommandPalette = false

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            if let error = initializationError {
                ContentUnavailableView {
                    Label("Database Error", systemImage: "exclamationmark.triangle.fill")
                } description: {
                    Text(error)
                }
            } else if let coord = coordinator {
                PersonalDocSplitViewRepresentable(coordinator: coord, showingCommandPalette: $showingCommandPalette)
                    .sheet(isPresented: $showingCommandPalette) {
                        PersonalDocCommandPalette(coordinator: coord) {
                            showingCommandPalette = false
                        }
                    }
            } else {
                ProgressView("Attaching project session database...")
                    .padding()
            }
        }
        .onAppear {
            attachCoordinator()
        }
        .onChange(of: sessionStore.activeProject) { _, _ in
            attachCoordinator()
        }
    }

    private func attachCoordinator() {
        guard let project = sessionStore.activeProject else {
            self.coordinator = nil
            self.initializationError = "No active project session found."
            return
        }

        do {
            self.coordinator = try PersonalDocumentationCoordinator(projectID: project.id, projectURL: project.directoryURL)
            self.initializationError = nil
        } catch {
            self.coordinator = nil
            self.initializationError = "Failed to initialize SwiftData project store: \(error.localizedDescription)"
        }
    }
}

// MARK: - AppKit-backed Native Search Field
struct NativeSearchField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = "Search..."

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField()
        searchField.placeholderString = placeholder
        searchField.delegate = context.coordinator
        searchField.bezelStyle = .roundedBezel
        return searchField
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSSearchFieldDelegate {
        var parent: NativeSearchField

        init(_ parent: NativeSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let searchField = obj.object as? NSSearchField else { return }
            parent.text = searchField.stringValue
        }
    }
}

// MARK: - AppKit-backed Native Split View Wrappers
struct PersonalDocSidebarWrapper: View {
    let coord: PersonalDocumentationCoordinator
    @Binding var showingCommandPalette: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Documentation")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    showingCommandPalette = true
                } label: {
                    Image(systemName: "terminal")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .help("Command Palette (Quick Open)")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            PersonalDocSidebarView(coordinator: coord)
        }
    }
}

struct PersonalDocMiddleWrapper: View {
    let coord: PersonalDocumentationCoordinator

    var body: some View {
        Group {
            if let kind = coord.selectedModuleKind, hasMiddleList(kind) {
                middleListView(for: kind, coord: coord)
            } else {
                Color.clear
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func hasMiddleList(_ kind: ModuleKind) -> Bool {
        switch kind {
        case .dashboard, .smartCollections, .knowledgeGraph, .timeline, .analytics, .intelligence:
            return false
        default:
            return true
        }
    }

    @ViewBuilder
    private func middleListView(for kind: ModuleKind, coord: PersonalDocumentationCoordinator) -> some View {
        @Bindable var coord = coord
        switch kind {
        case .projectWiki:
            WikiPageListView(coordinator: coord)
        case .whiteboards:
            WhiteboardListView(coordinator: coord)
        case .snippets:
            SnippetListView(coordinator: coord)
        case .snapshots:
            SnapshotListView(coordinator: coord)
        default:
            RecordListView(coordinator: coord, kind: kind, selectedDocumentID: $coord.selectedDocumentID)
        }
    }
}

struct PersonalDocMainWrapper: View {
    let coord: PersonalDocumentationCoordinator

    var body: some View {
        mainWorkspaceView(for: coord.selectedModuleKind, coord: coord)
            .background(Color(NSColor.controlBackgroundColor))
    }

    @ViewBuilder
    private func mainWorkspaceView(for kind: ModuleKind?, coord: PersonalDocumentationCoordinator) -> some View {
        if let kind = kind {
            switch kind {
            case .dashboard:
                DashboardView(coordinator: coord)
            case .projectWiki:
                WikiPageDetailView(coordinator: coord)
            case .smartCollections:
                GlobalSearchView(coordinator: coord)
            case .knowledgeGraph:
                KnowledgeGraphView(coordinator: coord)
            case .timeline:
                ProjectTimelineView(coordinator: coord)
            case .analytics:
                AnalyticsView(coordinator: coord)
            case .intelligence:
                IntelligenceView(coordinator: coord)
            case .whiteboards:
                WhiteboardCanvasDetailView(coordinator: coord)
            case .snippets:
                SnippetDetailView(coordinator: coord)
            case .snapshots:
                SnapshotDetailView(coordinator: coord)
            default:
                RecordDetailView(coordinator: coord, documentID: coord.selectedDocumentID)
            }
        } else {
            ContentUnavailableView {
                Label("Select an Item", systemImage: "doc.text")
            } description: {
                Text("Choose a category and document to get started.")
            }
        }
    }
}

class PersonalDocSplitViewController: NSSplitViewController {
    let coordinator: PersonalDocumentationCoordinator
    @Binding var showingCommandPalette: Bool

    private var sidebarItem: NSSplitViewItem?
    private var middleItem: NSSplitViewItem?
    private var mainItem: NSSplitViewItem?

    init(coordinator: PersonalDocumentationCoordinator, showingCommandPalette: Binding<Bool>) {
        self.coordinator = coordinator
        self._showingCommandPalette = showingCommandPalette
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupSplitView()
    }

    private func setupSplitView() {
        splitView.isVertical = true
        splitView.dividerStyle = .thin

        // Panel 1: Sidebar
        let sidebarView = PersonalDocSidebarWrapper(coord: coordinator, showingCommandPalette: $showingCommandPalette)
        let sidebarVC = NSHostingController(rootView: sidebarView)
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
        sidebarItem.minimumThickness = 200
        sidebarItem.maximumThickness = 320
        sidebarItem.holdingPriority = .defaultLow
        self.sidebarItem = sidebarItem
        addSplitViewItem(sidebarItem)

        // Panel 2: Middle List
        let middleView = PersonalDocMiddleWrapper(coord: coordinator)
        let middleVC = NSHostingController(rootView: middleView)
        let middleItem = NSSplitViewItem(viewController: middleVC)
        middleItem.minimumThickness = 240
        middleItem.maximumThickness = 400
        middleItem.holdingPriority = .defaultLow
        self.middleItem = middleItem
        addSplitViewItem(middleItem)

        // Panel 3: Main Workspace
        let mainView = PersonalDocMainWrapper(coord: coordinator)
        let mainVC = NSHostingController(rootView: mainView)
        let mainItem = NSSplitViewItem(viewController: mainVC)
        mainItem.minimumThickness = 400
        mainItem.holdingPriority = .defaultHigh
        self.mainItem = mainItem
        addSplitViewItem(mainItem)

        updateSplitItems(animate: false)
    }

    func updateSplitItems(animate: Bool) {
        let hasMiddle: Bool
        if let kind = coordinator.selectedModuleKind {
            hasMiddle = hasMiddleList(kind)
        } else {
            hasMiddle = false
        }

        let isCollapsed = !hasMiddle
        if let middleItem = middleItem, middleItem.isCollapsed != isCollapsed {
            if animate {
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.22
                    middleItem.animator().isCollapsed = isCollapsed
                }
            } else {
                middleItem.isCollapsed = isCollapsed
            }
        }
    }

    private func hasMiddleList(_ kind: ModuleKind) -> Bool {
        switch kind {
        case .dashboard, .smartCollections, .knowledgeGraph, .timeline, .analytics, .intelligence:
            return false
        default:
            return true
        }
    }
}

struct PersonalDocSplitViewRepresentable: NSViewControllerRepresentable {
    let coordinator: PersonalDocumentationCoordinator
    @Binding var showingCommandPalette: Bool

    func makeNSViewController(context: Context) -> PersonalDocSplitViewController {
        return PersonalDocSplitViewController(coordinator: coordinator, showingCommandPalette: $showingCommandPalette)
    }

    func updateNSViewController(_ nsViewController: PersonalDocSplitViewController, context: Context) {
        nsViewController.updateSplitItems(animate: true)
    }
}

// MARK: - AppKit-backed Native Sidebar
public class SidebarNode: NSObject {
    public let title: String
    public let icon: String?
    public let color: NSColor?
    public let kind: ModuleKind?
    public let isGroup: Bool
    public var children: [SidebarNode] = []

    public init(title: String, icon: String? = nil, color: NSColor? = nil, kind: ModuleKind? = nil, isGroup: Bool = false) {
        self.title = title
        self.icon = icon
        self.color = color
        self.kind = kind
        self.isGroup = isGroup
    }
}

class SidebarCellView: NSTableCellView {
    let iconView = NSImageView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        let text = NSTextField(labelWithString: "")
        text.translatesAutoresizingMaskIntoConstraints = false
        text.font = .systemFont(ofSize: 13)
        text.textColor = .labelColor
        addSubview(text)
        self.textField = text

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            text.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            text.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            text.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

func buildSidebarNodes() -> [SidebarNode] {
    var nodes: [SidebarNode] = []

    // 1. Overview
    let overview = SidebarNode(title: "OVERVIEW", isGroup: true)
    overview.children = [
        SidebarNode(title: "Dashboard", icon: "square.grid.2x2.fill", color: .systemBlue, kind: .dashboard),
        SidebarNode(title: "Global Search", icon: "magnifyingglass", color: .systemTeal, kind: .smartCollections)
    ]
    nodes.append(overview)

    // 2. Productivity Ecosystem
    let eco = SidebarNode(title: "PRODUCTIVITY ECOSYSTEM", isGroup: true)
    eco.children = [
        SidebarNode(title: "Knowledge Graph", icon: ModuleKind.knowledgeGraph.icon, color: .systemPurple, kind: .knowledgeGraph),
        SidebarNode(title: "Project Timeline", icon: ModuleKind.timeline.icon, color: .systemBlue, kind: .timeline),
        SidebarNode(title: "Project Analytics", icon: ModuleKind.analytics.icon, color: .systemOrange, kind: .analytics),
        SidebarNode(title: "Project Intelligence", icon: ModuleKind.intelligence.icon, color: .systemPurple, kind: .intelligence),
        SidebarNode(title: "Advanced Whiteboards", icon: ModuleKind.whiteboards.icon, color: .systemBlue, kind: .whiteboards),
        SidebarNode(title: "Snippet Workspace", icon: ModuleKind.snippets.icon, color: .systemGreen, kind: .snippets),
        SidebarNode(title: "Project Snapshots", icon: ModuleKind.snapshots.icon, color: .systemOrange, kind: .snapshots)
    ]
    nodes.append(eco)

    // 3. Libraries - Freeform Documents
    let freeform = SidebarNode(title: "FREEFORM DOCUMENTS", isGroup: true)
    freeform.children = ModuleKind.allCases.filter { $0.archetype == .freeform }.map { kind in
        SidebarNode(title: kind.rawValue, icon: kind.icon, color: .systemBlue, kind: kind)
    }
    nodes.append(freeform)

    // 4. Libraries - Structured Records
    let structured = SidebarNode(title: "STRUCTURED RECORDS", isGroup: true)
    structured.children = ModuleKind.allCases.filter { $0.archetype == .structured }.map { kind in
        SidebarNode(title: kind.rawValue, icon: kind.icon, color: .systemOrange, kind: kind)
    }
    nodes.append(structured)

    // 5. Libraries - Generated & Wiki
    let generated = SidebarNode(title: "GENERATED & WIKI", isGroup: true)
    var genChildren = [SidebarNode(title: "Project Wiki", icon: "globe.americas.fill", color: .systemPurple, kind: .projectWiki)]
    genChildren.append(contentsOf: ModuleKind.allCases.filter {
        $0.archetype == .generated &&
        $0 != .dashboard &&
        $0 != .knowledgeGraph &&
        $0 != .timeline &&
        $0 != .analytics &&
        $0 != .intelligence &&
        $0 != .whiteboards &&
        $0 != .snippets &&
        $0 != .snapshots &&
        $0 != .projectWiki
    }.map { kind in
        SidebarNode(title: kind.rawValue, icon: kind.icon, color: .systemPurple, kind: kind)
    })
    generated.children = genChildren
    nodes.append(generated)

    return nodes
}

struct PersonalDocSidebarView: NSViewRepresentable {
    let coordinator: PersonalDocumentationCoordinator

    func makeNSView(context: Context) -> NSVisualEffectView {
        let visualEffectView = NSVisualEffectView()
        visualEffectView.material = .sidebar
        visualEffectView.blendingMode = .behindWindow
        visualEffectView.state = .active

        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]

        let outlineView = NSOutlineView()
        outlineView.autoresizingMask = [.width]
        outlineView.headerView = nil
        outlineView.selectionHighlightStyle = .sourceList
        outlineView.style = .sourceList
        outlineView.floatsGroupRows = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("SidebarColumn"))
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column

        outlineView.dataSource = context.coordinator
        outlineView.delegate = context.coordinator

        scrollView.documentView = outlineView

        visualEffectView.addSubview(scrollView)
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: visualEffectView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: visualEffectView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: visualEffectView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: visualEffectView.bottomAnchor)
        ])

        context.coordinator.outlineView = outlineView

        for group in context.coordinator.nodes {
            outlineView.expandItem(group)
        }

        return visualEffectView
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        guard let outlineView = context.coordinator.outlineView else { return }

        if let currentKind = coordinator.selectedModuleKind {
            if let node = context.coordinator.findNode(for: currentKind) {
                let row = outlineView.row(forItem: node)
                if row >= 0, outlineView.selectedRow != row {
                    outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                }
            }
        } else {
            outlineView.deselectAll(nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
        var parent: PersonalDocSidebarView
        weak var outlineView: NSOutlineView?
        let nodes: [SidebarNode]

        init(_ parent: PersonalDocSidebarView) {
            self.parent = parent
            self.nodes = buildSidebarNodes()
        }

        func findNode(for kind: ModuleKind) -> SidebarNode? {
            for group in nodes {
                for child in group.children {
                    if child.kind == kind {
                        return child
                    }
                }
            }
            return nil
        }

        // MARK: - NSOutlineViewDataSource

        func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
            if item == nil {
                return nodes.count
            }
            if let node = item as? SidebarNode {
                return node.children.count
            }
            return 0
        }

        func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
            if item == nil {
                return nodes[index]
            }
            guard let node = item as? SidebarNode else { return SidebarNode(title: "") }
            return node.children[index]
        }

        func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
            if let node = item as? SidebarNode {
                return node.isGroup
            }
            return false
        }

        // MARK: - NSOutlineViewDelegate

        func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
            if let node = item as? SidebarNode {
                return node.isGroup
            }
            return false
        }

        func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
            if let node = item as? SidebarNode {
                return !node.isGroup
            }
            return true
        }

        func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
            guard let node = item as? SidebarNode else { return nil }

            if node.isGroup {
                let identifier = NSUserInterfaceItemIdentifier("HeaderView")
                var textField = outlineView.makeView(withIdentifier: identifier, owner: self) as? NSTextField
                if textField == nil {
                    textField = NSTextField(labelWithString: node.title)
                    textField?.identifier = identifier
                    textField?.font = .systemFont(ofSize: 11, weight: .bold)
                    textField?.textColor = .headerTextColor
                } else {
                    textField?.stringValue = node.title
                }
                return textField
            } else {
                let identifier = NSUserInterfaceItemIdentifier("SidebarCell")
                var cell = outlineView.makeView(withIdentifier: identifier, owner: self) as? SidebarCellView
                if cell == nil {
                    cell = SidebarCellView(frame: .zero)
                    cell?.identifier = identifier
                }

                cell?.textField?.stringValue = node.title
                if let iconName = node.icon {
                    if let image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil) {
                        cell?.iconView.image = image
                    } else {
                        cell?.iconView.image = nil
                    }
                } else {
                    cell?.iconView.image = nil
                }
                if let color = node.color {
                    cell?.iconView.contentTintColor = color
                } else {
                    cell?.iconView.contentTintColor = .controlAccentColor
                }

                return cell
            }
        }

        func outlineViewSelectionDidChange(_ notification: Notification) {
            guard let outlineView = notification.object as? NSOutlineView else { return }
            let selectedRow = outlineView.selectedRow
            if selectedRow >= 0, let node = outlineView.item(atRow: selectedRow) as? SidebarNode, let kind = node.kind {
                parent.coordinator.selectedModuleKind = kind
            }
        }
    }
}

// MARK: - AppKit-backed Native Text View
struct DocNSTextView: NSViewRepresentable {
    @Binding var text: String
    var isEditable: Bool = true

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autoresizingMask = [.width, .height]

        let contentSize = scrollView.contentSize

        let textContainer = NSTextContainer(containerSize: NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true

        let layoutManager = NSLayoutManager()
        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.isEditable = isEditable
        textView.font = .systemFont(ofSize: 13, weight: .regular)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.drawsBackground = false

        textView.isContinuousSpellCheckingEnabled = true
        textView.isGrammarCheckingEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.isAutomaticTextReplacementEnabled = true
        textView.isIncrementalSearchingEnabled = true
        textView.allowsUndo = true

        textView.textContainerInset = NSSize(width: 12, height: 12)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        if textView.string != text {
            let selectedRanges = textView.selectedRanges
            textView.string = text
            if !selectedRanges.isEmpty {
                textView.selectedRanges = selectedRanges
            }
        }

        if textView.isEditable != isEditable {
            textView.isEditable = isEditable
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: DocNSTextView

        init(_ parent: DocNSTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}
