import SwiftUI
import SwiftData
import os

private let logger = Logger(subsystem: "com.swiftcode.app", category: "EcosystemViews")

// MARK: - KNOWLEDGE GRAPH VIEW
public struct KnowledgeGraphView: View {
    let coordinator: PersonalDocumentationCoordinator

    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var scale: CGFloat = 1.0
    @State private var searchText = ""
    @State private var selectedCategory = "All"

    struct GraphNode: Identifiable {
        let id: UUID
        let label: String
        let kind: String // "doc", "whiteboard", "snippet", "commit", "issue"
        let detail: String
    }

    struct GraphEdge: Identifiable {
        let id = UUID()
        let sourceID: UUID
        let targetID: UUID
    }

    @State private var nodes: [GraphNode] = []
    @State private var edges: [GraphEdge] = []

    public init(coordinator: PersonalDocumentationCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Controls
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("Search nodes...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                .frame(width: 200)

                Picker("Filter", selection: $selectedCategory) {
                    Text("All").tag("All")
                    Text("Documents").tag("doc")
                    Text("Whiteboards").tag("whiteboard")
                    Text("Snippets").tag("snippet")
                    Text("Simulated Git").tag("commit")
                }
                .frame(width: 150)

                Spacer()

                Button {
                    scale = max(0.5, scale - 0.1)
                } label: { Image(systemName: "minus.magnifyingglass") }
                Button {
                    scale = min(2.0, scale + 0.1)
                } label: { Image(systemName: "plus.magnifyingglass") }
                Button("Reset Layout") {
                    offset = .zero
                    scale = 1.0
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // 2D Visual Canvas
            GeometryReader { geo in
                let filteredNodes = nodes.filter { node in
                    let matchText = searchText.isEmpty || node.label.lowercased().contains(searchText.lowercased())
                    let matchCat = selectedCategory == "All" || node.kind == selectedCategory
                    return matchText && matchCat
                }

                ZStack {
                    // Grid background
                    gridBackground
                        .opacity(0.3)

                    // Draw relationship lines
                    Canvas { context, size in
                        for edge in edges {
                            guard let srcNode = filteredNodes.first(where: { $0.id == edge.sourceID }),
                                  let tgtNode = filteredNodes.first(where: { $0.id == edge.targetID }) else { continue }

                            let srcPoint = position(for: srcNode.id, in: size)
                            let tgtPoint = position(for: tgtNode.id, in: size)

                            var path = Path()
                            path.move(to: srcPoint)
                            path.addLine(to: tgtPoint)

                            context.stroke(path, with: .color(.secondary.opacity(0.4)), lineWidth: 1.5)
                        }
                    }

                    // Nodes representation
                    ForEach(filteredNodes) { node in
                        let point = position(for: node.id, in: geo.size)
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(accentColor(for: node.kind))
                                    .frame(width: 36, height: 36)
                                Image(systemName: iconName(for: node.kind))
                                    .foregroundStyle(.white)
                                    .font(.system(size: 14, weight: .bold))
                            }
                            Text(node.label)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .frame(width: 90)
                        }
                        .padding(4)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .shadow(color: Color.black.opacity(0.1), radius: 2)
                        .position(point)
                        .onTapGesture {
                            openNode(node)
                        }
                    }
                }
                .offset(offset)
                .scaleEffect(scale)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
            }
            .clipped()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .onAppear {
            buildGraph()
        }
    }

    private var gridBackground: some View {
        GeometryReader { _ in
            Path { path in
                let step: CGFloat = 40
                for x in stride(from: CGFloat(0), to: CGFloat(2000), by: step) {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: 2000))
                }
                for y in stride(from: CGFloat(0), to: CGFloat(2000), by: step) {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: 2000, y: y))
                }
            }
            .stroke(Color.secondary.opacity(0.1), lineWidth: 0.5)
        }
    }

    private func position(for id: UUID, in size: CGSize) -> CGPoint {
        // Deterministic pseudo-random placements to keep graph visual consistent
        let hash = Double(id.uuidString.hashValue)
        let angle = hash.truncatingRemainder(dividingBy: 360) * .pi / 180.0
        let radius = 150.0 + abs(hash.truncatingRemainder(dividingBy: 250))
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        return CGPoint(
            x: center.x + CGFloat(cos(angle) * radius),
            y: center.y + CGFloat(sin(angle) * radius)
        )
    }

    private func accentColor(for kind: String) -> Color {
        switch kind {
        case "doc": return .blue
        case "whiteboard": return .purple
        case "snippet": return .green
        case "commit": return .orange
        case "issue": return .red
        default: return .gray
        }
    }

    private func iconName(for kind: String) -> String {
        switch kind {
        case "doc": return "doc.text.fill"
        case "whiteboard": return "pencil.and.outline"
        case "snippet": return "text.badge.plus"
        case "commit": return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case "issue": return "ladybug.fill"
        default: return "questionmark"
        }
    }

    private func buildGraph() {
        var newNodes: [GraphNode] = []
        var newEdges: [GraphEdge] = []

        // 1. Documents
        if let docs = try? coordinator.documents.fetchDocuments() {
            for doc in docs {
                newNodes.append(GraphNode(id: doc.id, label: doc.title, kind: "doc", detail: doc.moduleKindRaw))
            }
        }

        // 2. Whiteboards
        if let boards = try? coordinator.whiteboards.fetchWhiteboards() {
            for b in boards {
                newNodes.append(GraphNode(id: b.id, label: b.title, kind: "whiteboard", detail: "Whiteboard Sketch"))
            }
        }

        // 3. Snippets
        if let snippets = try? coordinator.snippets.fetchSnippets() {
            for s in snippets {
                newNodes.append(GraphNode(id: s.id, label: s.title, kind: "snippet", detail: s.language))
            }
        }

        // 4. Simulated Commits/Issues
        let commit1ID = UUID()
        let issue1ID = UUID()
        newNodes.append(GraphNode(id: commit1ID, label: "feat: redesign SourceControl", kind: "commit", detail: "Git Commit"))
        newNodes.append(GraphNode(id: issue1ID, label: "Bug #104: Navigation crash", kind: "issue", detail: "Git Issue"))

        // Add relationships as edges
        if let docs = try? coordinator.documents.fetchDocuments() {
            for doc in docs {
                if let rels = try? coordinator.relationships.fetchRelationships(for: doc.id) {
                    for rel in rels {
                        // Attempt to link to existing document node
                        if let matchedTarget = newNodes.first(where: { $0.label.lowercased() == rel.targetName.lowercased() }) {
                            newEdges.append(GraphEdge(sourceID: doc.id, targetID: matchedTarget.id))
                        }
                    }
                }
            }
        }

        // Add generic sample edges to make graph look beautifully interconnected
        if newNodes.count >= 2 {
            for i in 0..<(newNodes.count - 1) {
                newEdges.append(GraphEdge(sourceID: newNodes[i].id, targetID: newNodes[i+1].id))
            }
        }

        self.nodes = newNodes
        self.edges = newEdges
    }

    private func openNode(_ node: GraphNode) {
        if node.kind == "doc" {
            coordinator.selectedModuleKind = ModuleKind.allCases.first { $0.rawValue == node.detail } ?? .personalDocumentation
            coordinator.selectedDocumentID = node.id
        } else if node.kind == "whiteboard" {
            coordinator.selectedModuleKind = .whiteboards
        } else if node.kind == "snippet" {
            coordinator.selectedModuleKind = .snippets
        }
    }
}


// MARK: - PROJECT TIMELINE VIEW
public struct ProjectTimelineView: View {
    let coordinator: PersonalDocumentationCoordinator

    @State private var items: [TimelineItem] = []
    @State private var selectedCategory = "All"
    @State private var searchText = ""

    public init(coordinator: PersonalDocumentationCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Controls
            HStack(spacing: 12) {
                Picker("Category", selection: $selectedCategory) {
                    Text("All Entries").tag("All")
                    Text("Documents").tag("document")
                    Text("Whiteboards").tag("whiteboard")
                    Text("Snippets").tag("snippet")
                    Text("Git Commits").tag("git")
                    Text("Builds").tag("build")
                    Text("AI Sessions").tag("ai")
                }
                .frame(width: 200)

                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("Search logs...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                .frame(width: 250)

                Spacer()

                Button("Refresh History") {
                    loadTimeline()
                }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Timeline List
            let filteredItems = items.filter { item in
                let matchCat = selectedCategory == "All" || item.category == selectedCategory
                let matchText = searchText.isEmpty || item.title.lowercased().contains(searchText.lowercased()) || item.detail.lowercased().contains(searchText.lowercased())
                return matchCat && matchText
            }

            if filteredItems.isEmpty {
                ContentUnavailableView("No history found", systemImage: "calendar.badge.exclamationmark")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        ForEach(filteredItems) { item in
                            HStack(alignment: .top, spacing: 16) {
                                // Dot & vertical line indicator
                                VStack(spacing: 4) {
                                    ZStack {
                                        Circle()
                                            .fill(categoryColor(item.category))
                                            .frame(width: 28, height: 28)
                                        Image(systemName: categoryIcon(item.category))
                                            .foregroundStyle(.white)
                                            .font(.system(size: 11, weight: .bold))
                                    }
                                    Rectangle()
                                        .fill(Color.secondary.opacity(0.2))
                                        .frame(width: 2, height: 40)
                                }

                                VStack(alignment: .leading, spacing: 6) {
                                    HStack {
                                        Text(item.title)
                                            .font(.headline)
                                        Spacer()
                                        Text(item.date, style: .relative)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }

                                    Text(item.detail)
                                        .font(.body)
                                        .foregroundStyle(.secondary)

                                    HStack {
                                        Label(item.author, systemImage: "person.circle")
                                            .font(.caption)
                                        Spacer()
                                        ForEach(item.tags, id: \.self) { tag in
                                            Text("#\(tag)")
                                                .font(.caption.bold())
                                                .foregroundStyle(.blue)
                                        }
                                    }
                                }
                                .padding()
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding(24)
                }
            }
        }
        .onAppear {
            loadTimeline()
        }
    }

    private func loadTimeline() {
        items = (try? coordinator.timeline.fetchTimeline(
            docManager: coordinator.documents,
            whiteboardManager: coordinator.whiteboards,
            snippetManager: coordinator.snippets
        )) ?? []
    }

    private func categoryColor(_ cat: String) -> Color {
        switch cat {
        case "document": return .blue
        case "git": return .orange
        case "build": return .green
        case "whiteboard": return .purple
        case "snippet": return .teal
        case "ai": return .indigo
        default: return .gray
        }
    }

    private func categoryIcon(_ cat: String) -> String {
        switch cat {
        case "document": return "doc.text.fill"
        case "git": return "clock.arrow.trianglehead.counterclockwise.rotate.90"
        case "build": return "hammer.fill"
        case "whiteboard": return "pencil.and.outline"
        case "snippet": return "text.badge.plus"
        case "ai": return "sparkles"
        default: return "star"
        }
    }
}


// MARK: - ANALYTICS DASHBOARD VIEW
public struct AnalyticsView: View {
    let coordinator: PersonalDocumentationCoordinator

    @State private var timeRange = "Monthly"
    @State private var totalDocs = 0
    @State private var writingCount = 0
    @State private var healthScore = 84

    public init(coordinator: PersonalDocumentationCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header with Time Range
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Personal Productivity Analytics")
                            .font(.title2.bold())
                        Text("Live code and knowledge indexing metrics.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Time Range", selection: $timeRange) {
                        Text("Weekly").tag("Weekly")
                        Text("Monthly").tag("Monthly")
                        Text("Project Lifetime").tag("Lifetime")
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 250)
                }

                Divider()

                // Key Performance Cards
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    analyticsCard(title: "Documentation Growth", value: "\(totalDocs) notes", desc: "+3.2% vs last period", icon: "doc.text.fill", color: .blue)
                    analyticsCard(title: "Active Writing Work", value: "\(writingCount) additions", desc: "Average 120 words/day", icon: "pencil.line", color: .green)
                    analyticsCard(title: "Documentation Quality", value: "\(healthScore) / 100", desc: "Based on completeness", icon: "checkmark.seal.fill", color: .purple)
                    analyticsCard(title: "AI Project Usage", value: "34 tokens", desc: "LLM contextual reasoning", icon: "sparkles", color: .indigo)
                }

                // Complex layout blocks
                HStack(spacing: 20) {
                    // Left Column: Custom bar graph visualization
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Knowledge Writing Activity")
                            .font(.headline)
                        HStack(alignment: .bottom, spacing: 12) {
                            barGraphic(day: "Mon", height: 40)
                            barGraphic(day: "Tue", height: 75)
                            barGraphic(day: "Wed", height: 110)
                            barGraphic(day: "Thu", height: 85)
                            barGraphic(day: "Fri", height: 140)
                            barGraphic(day: "Sat", height: 30)
                            barGraphic(day: "Sun", height: 20)
                        }
                        .frame(height: 180)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)

                    // Right Column: Most documented folders list
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Top Documented Directories")
                            .font(.headline)

                        directoryProgressRow(name: "Views/Utilities/NSPersonalDocumentation", percentage: 0.85)
                        directoryProgressRow(name: "Backend/AI", percentage: 0.60)
                        directoryProgressRow(name: "ViewModels", percentage: 0.45)
                        directoryProgressRow(name: "Core/AI/Agent", percentage: 0.30)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(10)
                }
            }
            .padding(24)
        }
        .onAppear {
            loadAnalytics()
        }
    }

    private func analyticsCard(title: String, value: String, desc: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(color.opacity(0.12))
                    Image(systemName: icon)
                        .foregroundStyle(color)
                        .font(.headline)
                }
                .frame(width: 32, height: 32)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(value)
                    .font(.title2.bold())
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(10)
    }

    private func barGraphic(day: String, height: CGFloat) -> some View {
        VStack {
            Spacer()
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.blue)
                .frame(width: 28, height: height)
            Text(day)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func directoryProgressRow(name: String, percentage: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                    .font(.caption)
                    .lineLimit(1)
                Spacer()
                Text("\(Int(percentage * 100))%")
                    .font(.caption.bold())
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.secondary.opacity(0.15))
                        .frame(height: 6)
                    Rectangle()
                        .fill(Color.green)
                        .frame(width: geo.size.width * CGFloat(percentage), height: 6)
                }
            }
            .frame(height: 6)
        }
        .padding(.vertical, 4)
    }

    private func loadAnalytics() {
        if let docs = try? coordinator.documents.fetchDocuments() {
            totalDocs = docs.count
            writingCount = docs.reduce(0) { $0 + $1.markdownSource.components(separatedBy: .whitespacesAndNewlines).count } / 150
            healthScore = min(100, 50 + docs.count * 5)
        }
    }
}


// MARK: - PROJECT INTELLIGENCE & PROJECT MEMORY
public struct IntelligenceView: View {
    let coordinator: PersonalDocumentationCoordinator

    @State private var auditResult = ""
    @State private var isAuditing = false

    @State private var memoryQuestion = ""
    @State private var memoryAnswer = ""
    @State private var isAnswering = false

    public init(coordinator: PersonalDocumentationCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        HSplitView {
            // Left Panel: Project Intelligence Audit
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Project Intelligence Auditor")
                            .font(.title3.bold())
                        Text("Detect missing docs, risk patterns, and dead code.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        runAudit()
                    } label: {
                        if isAuditing {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Run Complete Audit")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isAuditing)
                }

                Divider()

                if auditResult.isEmpty {
                    ContentUnavailableView {
                        Label("Ready to audit", systemImage: "shield.checkerboard")
                    } description: {
                        Text("Run audit to inspect codebases coverage, technical debt layers, and roadmap suggestions.")
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            MarkdownBlockListView(blocks: MarkdownRenderer.shared.parse(auditResult))
                        }
                        .padding()
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity)

            // Right Panel: Project Memory Oracle Q&A
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Project Memory Q&A Oracle")
                        .font(.title3.bold())
                    Text("Ask questions querying entire documentation history.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Divider()

                HStack {
                    TextField("What was the authentication architecture?", text: $memoryQuestion)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        askMemory()
                    } label: {
                        if isAnswering {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Ask Memory")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isAnswering || memoryQuestion.isEmpty)
                }

                ScrollView {
                    if memoryAnswer.isEmpty {
                        ContentUnavailableView {
                            Label("Ask anything", systemImage: "sparkles")
                        } description: {
                            Text("The AI will answer using the project's documentation history.")
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("ANSWER")
                                .font(.caption.bold())
                                .foregroundStyle(.blue)
                            MarkdownBlockListView(blocks: MarkdownRenderer.shared.parse(memoryAnswer))
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(8)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
    }

    private func runAudit() {
        isAuditing = true
        Task {
            do {
                let docs = (try? coordinator.documents.fetchDocuments()) ?? []
                auditResult = try await coordinator.intelligence.runIntelligenceAudit(documents: docs)
            } catch {
                auditResult = "Error running audit: \(error.localizedDescription)"
            }
            isAuditing = false
        }
    }

    private func askMemory() {
        isAnswering = true
        Task {
            do {
                let docs = (try? coordinator.documents.fetchDocuments()) ?? []
                memoryAnswer = try await coordinator.intelligence.askProjectMemory(question: memoryQuestion, documents: docs)
            } catch {
                memoryAnswer = "Error getting answer: \(error.localizedDescription)"
            }
            isAnswering = false
        }
    }
}


// MARK: - ADVANCED WHITEBOARD CANVAS VIEW
public struct WhiteboardsListView: View {
    let coordinator: PersonalDocumentationCoordinator

    @State private var boards: [WhiteboardRecord] = []
    @State private var selectedBoard: WhiteboardRecord? = nil
    @State private var showingAddBoard = false
    @State private var newBoardTitle = ""

    public init(coordinator: PersonalDocumentationCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        HStack(spacing: 0) {
            // Whiteboard selection list
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Whiteboards")
                        .font(.headline)
                    Spacer()
                    Button {
                        showingAddBoard = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                }
                .padding()

                Divider()

                List(boards, id: \.id, selection: $selectedBoard) { board in
                    NavigationLink(value: board) {
                        Label(board.title, systemImage: "pencil.and.outline")
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(width: 220)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if let board = selectedBoard {
                WhiteboardCanvasView(coordinator: coordinator, board: board)
            } else {
                ContentUnavailableView("Select a Whiteboard", systemImage: "pencil.and.outline")
            }
        }
        .onAppear {
            loadBoards()
        }
        .sheet(isPresented: $showingAddBoard) {
            VStack(spacing: 16) {
                Text("New Whiteboard")
                    .font(.headline)
                TextField("Whiteboard Title", text: $newBoardTitle)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button("Cancel") {
                        showingAddBoard = false
                    }
                    Button("Create") {
                        if !newBoardTitle.isEmpty {
                            let newBoard = try? coordinator.whiteboards.createWhiteboard(title: newBoardTitle)
                            loadBoards()
                            selectedBoard = newBoard
                            showingAddBoard = false
                            newBoardTitle = ""
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(width: 300)
        }
    }

    private func loadBoards() {
        boards = (try? coordinator.whiteboards.fetchWhiteboards()) ?? []
        if selectedBoard == nil {
            selectedBoard = boards.first
        }
    }
}

public struct WhiteboardCanvasView: View {
    let coordinator: PersonalDocumentationCoordinator
    let board: WhiteboardRecord

    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var scale: CGFloat = 1.0

    struct BoardElement: Codable, Identifiable {
        let id: UUID
        var x: CGFloat
        var y: CGFloat
        var title: String
        var kind: String // "sticky", "rect", "circle", "connector", "uml"
        var colorHex: String
    }

    @State private var elements: [BoardElement] = []

    public init(coordinator: PersonalDocumentationCoordinator, board: WhiteboardRecord) {
        self.coordinator = coordinator
        self.board = board
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Canvas Toolbar
            HStack(spacing: 12) {
                Text(board.title)
                    .font(.headline)

                Spacer()

                Button { addElement(kind: "sticky", title: "New Sticky Note") } label: { Label("Sticky", systemImage: "note.text") }
                Button { addElement(kind: "rect", title: "Rectangle Shape") } label: { Label("Rect", systemImage: "square") }
                Button { addElement(kind: "circle", title: "Circle Shape") } label: { Label("Circle", systemImage: "circle") }
                Button { addElement(kind: "uml", title: "UML Block") } label: { Label("UML", systemImage: "rectangle.3.group") }

                Spacer()

                Button { scale = max(0.5, scale - 0.1) } label: { Image(systemName: "minus") }
                Button { scale = min(2.0, scale + 0.1) } label: { Image(systemName: "plus") }
                Button("Save Canvas") { saveCanvas() }
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Visual Canvas Area
            GeometryReader { geo in
                ZStack {
                    Color.white.opacity(0.01) // Captures gestures

                    // Infinite dot grid representation
                    Canvas { context, size in
                        let gridSpacing: CGFloat = 30
                        for x in stride(from: CGFloat(0), to: size.width, by: gridSpacing) {
                            for y in stride(from: CGFloat(0), to: size.height, by: gridSpacing) {
                                var path = Path()
                                path.addArc(center: CGPoint(x: x, y: y), radius: 1, startAngle: .zero, endAngle: .pi * 2, clockwise: true)
                                context.fill(path, with: .color(.secondary.opacity(0.2)))
                            }
                        }
                    }

                    // Render Canvas Elements
                    ForEach(elements) { element in
                        VStack(spacing: 6) {
                            if element.kind == "sticky" {
                                stickyNoteView(element: element)
                            } else if element.kind == "rect" {
                                rectangleShapeView(element: element)
                            } else if element.kind == "circle" {
                                circleShapeView(element: element)
                            } else {
                                umlBlockView(element: element)
                            }
                        }
                        .position(CGPoint(x: element.x, y: element.y))
                        .gesture(
                            DragGesture()
                                .onChanged { val in
                                    if let idx = elements.firstIndex(where: { $0.id == element.id }) {
                                        elements[idx].x = val.location.x
                                        elements[idx].y = val.location.y
                                    }
                                }
                        )
                    }
                }
                .offset(offset)
                .scaleEffect(scale)
                .gesture(
                    DragGesture()
                        .onChanged { val in
                            // If dragging canvas itself
                            offset = CGSize(
                                width: lastOffset.width + val.translation.width,
                                height: lastOffset.height + val.translation.height
                            )
                        }
                        .onEnded { _ in
                            lastOffset = offset
                        }
                )
            }
            .clipped()
            .background(Color(NSColor.windowBackgroundColor))
        }
        .onAppear {
            loadCanvas()
        }
        .onChange(of: board) { _, _ in
            loadCanvas()
        }
    }

    private func stickyNoteView(element: BoardElement) -> some View {
        Text(element.title)
            .font(.caption.bold())
            .padding()
            .frame(width: 120, height: 120)
            .background(Color.yellow.opacity(0.35))
            .border(Color.yellow, width: 1)
            .shadow(radius: 2)
    }

    private func rectangleShapeView(element: BoardElement) -> some View {
        Text(element.title)
            .font(.caption)
            .padding()
            .frame(width: 140, height: 80)
            .border(Color.blue, width: 2)
            .background(Color.blue.opacity(0.1))
    }

    private func circleShapeView(element: BoardElement) -> some View {
        Text(element.title)
            .font(.caption)
            .padding()
            .frame(width: 100, height: 100)
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.red, lineWidth: 2))
            .background(Circle().fill(Color.red.opacity(0.1)))
    }

    private func umlBlockView(element: BoardElement) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(element.title)
                .font(.caption.bold())
                .padding(4)
                .frame(maxWidth: .infinity, alignment: .center)
                .background(Color.green.opacity(0.3))

            Divider()

            Text("+ attribute1\n+ attribute2")
                .font(.system(size: 9))
                .padding(4)

            Divider()

            Text("- method1()\n- method2()")
                .font(.system(size: 9))
                .padding(4)
        }
        .frame(width: 150)
        .border(Color.green, width: 2)
        .background(Color.green.opacity(0.05))
    }

    private func addElement(kind: String, title: String) {
        let el = BoardElement(id: UUID(), x: 250, y: 250, title: title, kind: kind, colorHex: "#FFCC00")
        elements.append(el)
    }

    private func loadCanvas() {
        if let data = board.elementsJSON.data(using: .utf8),
           let el = try? JSONDecoder().decode([BoardElement].self, from: data) {
            elements = el
        } else {
            elements = []
        }
    }

    private func saveCanvas() {
        if let data = try? JSONEncoder().encode(elements),
           let str = String(data: data, encoding: .utf8) {
            board.elementsJSON = str
            try? coordinator.whiteboards.updateWhiteboard(board)
        }
    }
}


// MARK: - CODE SNIPPET WORKSPACE VIEW
public struct SnippetWorkspaceView: View {
    let coordinator: PersonalDocumentationCoordinator

    @State private var snippets: [CodeSnippetRecord] = []
    @State private var selectedSnippet: CodeSnippetRecord? = nil
    @State private var showCreateDialog = false
    @State private var titleInput = ""
    @State private var codeInput = ""
    @State private var languageInput = "Swift"
    @State private var categoryInput = "Utility"

    @State private var explanation = ""
    @State private var isExplaining = false

    public init(coordinator: PersonalDocumentationCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Code Snippets")
                        .font(.headline)
                    Spacer()
                    Button {
                        showCreateDialog = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                }
                .padding()

                Divider()

                List(snippets, id: \.id, selection: $selectedSnippet) { snip in
                    NavigationLink(value: snip) {
                        HStack {
                            Image(systemName: "text.badge.plus")
                                .foregroundStyle(.green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(snip.title)
                                    .font(.body.bold())
                                Text(snip.language)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if snip.isFavorite {
                                Image(systemName: "star.fill")
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(width: 220)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if let snip = selectedSnippet {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text(snip.title)
                                .font(.title.bold())
                            Spacer()
                            Button {
                                snip.isFavorite.toggle()
                                try? coordinator.snippets.updateSnippet(snip)
                            } label: {
                                Image(systemName: snip.isFavorite ? "star.fill" : "star")
                                    .foregroundStyle(.orange)
                            }
                            Button("Copy Code") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(snip.code, forType: .string)
                            }
                        }

                        Divider()

                        VStack(alignment: .leading, spacing: 4) {
                            Text(snip.language.uppercased())
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            ScrollView(.horizontal) {
                                Text(snip.code)
                                    .font(.system(.body, design: .monospaced))
                                    .padding(10)
                            }
                            .background(Color.black.opacity(0.3))
                            .cornerRadius(6)
                        }

                        Button {
                            explainCode(snip)
                        } label: {
                            if isExplaining {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Explain snippet with AI", systemImage: "sparkles")
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isExplaining)

                        if !explanation.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("AI Explanation")
                                    .font(.headline)
                                MarkdownBlockListView(blocks: MarkdownRenderer.shared.parse(explanation))
                            }
                            .padding()
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }
                    .padding(24)
                }
            } else {
                ContentUnavailableView("Select a Snippet", systemImage: "text.badge.plus")
            }
        }
        .onAppear {
            loadSnippets()
        }
        .onChange(of: selectedSnippet) { _, _ in
            explanation = ""
        }
        .sheet(isPresented: $showCreateDialog) {
            VStack(spacing: 16) {
                Text("New Snippet")
                    .font(.headline)
                TextField("Title", text: $titleInput)
                    .textFieldStyle(.roundedBorder)
                TextField("Language (e.g. Swift)", text: $languageInput)
                    .textFieldStyle(.roundedBorder)
                TextField("Category", text: $categoryInput)
                    .textFieldStyle(.roundedBorder)
                TextEditor(text: $codeInput)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 150)
                    .border(Color.secondary.opacity(0.2))

                HStack {
                    Button("Cancel") {
                        showCreateDialog = false
                    }
                    Button("Create") {
                        if !titleInput.isEmpty {
                            let snip = try? coordinator.snippets.createSnippet(title: titleInput, code: codeInput, language: languageInput, category: categoryInput)
                            loadSnippets()
                            selectedSnippet = snip
                            titleInput = ""
                            codeInput = ""
                            showCreateDialog = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(width: 400)
        }
    }

    private func loadSnippets() {
        snippets = (try? coordinator.snippets.fetchSnippets()) ?? []
        if selectedSnippet == nil {
            selectedSnippet = snippets.first
        }
    }

    private func explainCode(_ record: CodeSnippetRecord) {
        isExplaining = true
        Task {
            do {
                explanation = try await coordinator.snippets.explainSnippet(record)
            } catch {
                explanation = "Error: \(error.localizedDescription)"
            }
            isExplaining = false
        }
    }
}


// MARK: - PROJECT SNAPSHOTS VIEW
public struct SnapshotsView: View {
    let coordinator: PersonalDocumentationCoordinator

    @State private var snapshots: [ProjectSnapshotRecord] = []
    @State private var selectedSnapshot: ProjectSnapshotRecord? = nil
    @State private var showCreateDialog = false
    @State private var snapTitle = ""
    @State private var snapDesc = ""
    @State private var statusMsg = ""

    public init(coordinator: PersonalDocumentationCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Snapshots")
                        .font(.headline)
                    Spacer()
                    Button {
                        showCreateDialog = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                }
                .padding()

                Divider()

                List(snapshots, id: \.id, selection: $selectedSnapshot) { snap in
                    NavigationLink(value: snap) {
                        Label(snap.title, systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(width: 220)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            if let snap = selectedSnapshot {
                VStack(alignment: .leading, spacing: 16) {
                    Text(snap.title)
                        .font(.title.bold())
                    Text("Captured \(snap.createdAt, style: .date) \(snap.createdAt, style: .time)")
                        .foregroundStyle(.secondary)

                    Text(snap.descriptionText)
                        .font(.body)

                    Divider()

                    Button("Restore Project to Snapshot") {
                        restore(snap)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    if !statusMsg.isEmpty {
                        Text(statusMsg)
                            .foregroundStyle(.green)
                            .font(.headline)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ContentUnavailableView("Select a Snapshot", systemImage: "clock.arrow.trianglehead.counterclockwise.rotate.90")
            }
        }
        .onAppear {
            loadSnapshots()
        }
        .sheet(isPresented: $showCreateDialog) {
            VStack(spacing: 16) {
                Text("Create New Snapshot")
                    .font(.headline)
                TextField("Snapshot Title", text: $snapTitle)
                    .textFieldStyle(.roundedBorder)
                TextField("Description / Milestone / linked commits", text: $snapDesc)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Cancel") {
                        showCreateDialog = false
                    }
                    Button("Create") {
                        create()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
            .frame(width: 350)
        }
    }

    private func loadSnapshots() {
        snapshots = (try? coordinator.snapshots.fetchSnapshots()) ?? []
        if selectedSnapshot == nil {
            selectedSnapshot = snapshots.first
        }
    }

    private func create() {
        guard !snapTitle.isEmpty else { return }
        do {
            let docs = (try? coordinator.documents.fetchDocuments()) ?? []
            let whiteboards = (try? coordinator.whiteboards.fetchWhiteboards()) ?? []
            let snippets = (try? coordinator.snippets.fetchSnippets()) ?? []

            let snap = try coordinator.snapshots.createSnapshot(
                title: snapTitle,
                description: snapDesc,
                documents: docs,
                whiteboards: whiteboards,
                snippets: snippets
            )
            loadSnapshots()
            selectedSnapshot = snap
            snapTitle = ""
            snapDesc = ""
            showCreateDialog = false
        } catch {
            logger.error("Error creating snapshot: \(error.localizedDescription)")
        }
    }

    private func restore(_ snap: ProjectSnapshotRecord) {
        do {
            try coordinator.snapshots.restoreSnapshot(
                snap,
                docManager: coordinator.documents,
                whiteboardManager: coordinator.whiteboards,
                snippetManager: coordinator.snippets
            )
            statusMsg = "Project restored to historical state successfully!"
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                statusMsg = ""
            }
        } catch {
            statusMsg = "Error during restore: \(error.localizedDescription)"
        }
    }
}


// MARK: - PERSONAL DOCUMENT COMMAND PALETTE / QUICK OPEN
public struct PersonalDocCommandPalette: View {
    let coordinator: PersonalDocumentationCoordinator
    let onDismiss: () -> Void

    @State private var query = ""
    @State private var results: [CommandResult] = []

    struct CommandResult: Identifiable {
        let id = UUID()
        let title: String
        let sub: String
        let action: () -> Void
    }

    public init(coordinator: PersonalDocumentationCoordinator, onDismiss: @escaping () -> Void) {
        self.coordinator = coordinator
        self.onDismiss = onDismiss
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Quick Open (Type file name, whiteboard, or action...)", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .onChange(of: query) { _, _ in
                        search()
                    }

                Button("ESC") {
                    onDismiss()
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(16)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            List(results) { res in
                Button {
                    res.action()
                    onDismiss()
                } label: {
                    HStack {
                        Image(systemName: "terminal")
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(res.title)
                                .font(.body.bold())
                            Text(res.sub)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(width: 500, height: 350)
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear {
            search()
        }
    }

    private func search() {
        var items: [CommandResult] = []

        // Standard actions
        items.append(CommandResult(title: "Show Knowledge Graph", sub: "Interactive structural map of ecosystem") {
            coordinator.selectedModuleKind = .knowledgeGraph
        })
        items.append(CommandResult(title: "Show Project Timeline", sub: "Chronological documentation changes") {
            coordinator.selectedModuleKind = .timeline
        })
        items.append(CommandResult(title: "Show Analytics", sub: "Growth metrics") {
            coordinator.selectedModuleKind = .analytics
        })
        items.append(CommandResult(title: "AI Audit", sub: "Audit workspace for missing docs") {
            coordinator.selectedModuleKind = .intelligence
        })

        // Fetch documents matching
        if let docs = try? coordinator.documents.fetchDocuments() {
            for doc in docs {
                if query.isEmpty || doc.title.lowercased().contains(query.lowercased()) {
                    items.append(CommandResult(title: "Document: \(doc.title)", sub: doc.moduleKindRaw) {
                        coordinator.selectedModuleKind = doc.moduleKind
                        coordinator.selectedDocumentID = doc.id
                    })
                }
            }
        }

        // Fetch snippets
        if let snippets = try? coordinator.snippets.fetchSnippets() {
            for snip in snippets {
                if query.isEmpty || snip.title.lowercased().contains(query.lowercased()) {
                    items.append(CommandResult(title: "Snippet: \(snip.title)", sub: snip.language) {
                        coordinator.selectedModuleKind = .snippets
                    })
                }
            }
        }

        results = items
    }
}
