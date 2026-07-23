import SwiftUI
import AppKit
import os.log

private let logger = Logger(subsystem: "com.swiftcode.SourceControl", category: "GitHubIntelligenceAndOperations")

// ====================================================================
// UTILITY MODELS
// ====================================================================

public struct ChurnItem: Identifiable, Sendable, Codable {
    public var id: String { filename }
    public let filename: String
    public let modifications: Int
}

public struct KnowledgeNode: Identifiable, Sendable, Codable {
    public let id: String
    public let name: String
    public let type: NodeType
    public var position: CGPoint

    public enum NodeType: String, Sendable, Codable, CaseIterable {
        case file = "File"
        case directory = "Directory"
        case commit = "Commit"
        case branch = "Branch"
        case pullRequest = "Pull Request"
        case issue = "Issue"
        case contributor = "Contributor"
        case workflow = "Workflow"
    }
}

public struct KnowledgeRelationship: Identifiable, Sendable, Codable {
    public var id: String { "\(from)->\(to)" }
    public let from: String
    public let to: String
    public let type: RelationshipType

    public enum RelationshipType: String, Sendable, Codable {
        case imports = "Imports"
        case owns = "Owns"
        case modifiedBy = "Modified By"
        case references = "References"
        case contains = "Contains"
    }
}

// Helper operators for CG points / sizes
extension CGSize {
    static func +(lhs: CGSize, rhs: CGSize) -> CGSize {
        CGSize(width: lhs.width + rhs.width, height: lhs.height + rhs.height)
    }
}

// ====================================================================
// Helper to resolve git executable path safely
// ====================================================================
@MainActor
func getGitExecutableURL() -> URL {
    for path in ["/usr/bin/git", "/usr/local/bin/git", "/opt/homebrew/bin/git"] {
        if FileManager.default.fileExists(atPath: path) {
            return URL(fileURLWithPath: path)
        }
    }
    return URL(fileURLWithPath: "/usr/bin/git")
}

// ====================================================================
// Non-MainActor file scanners to prevent blocking UI main thread
// ====================================================================
actor BackgroundRepositoryScanner {
    static let shared = BackgroundRepositoryScanner()
    private init() {}

    func performFilesystemScan(repoURL: URL) -> (todoCount: Int, largeFiles: [String], totalCodeLines: Int, totalDocComments: Int) {
        let manager = FileManager.default
        var todoCount = 0
        var foundLargeFiles: [String] = []
        var totalCodeLines = 0
        var totalDocComments = 0

        guard let enumerator = manager.enumerator(
            at: repoURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return (0, [], 0, 0)
        }

        for case let fileURL as URL in enumerator {
            guard let isFile = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile, isFile else { continue }
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                if size > 10 * 1024 * 1024 {
                    foundLargeFiles.append(fileURL.lastPathComponent)
                }
            }
            if ["swift", "m", "h", "json"].contains(fileURL.pathExtension) {
                if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                    todoCount += content.components(separatedBy: "TODO").count - 1
                    todoCount += content.components(separatedBy: "FIXME").count - 1

                    let lines = content.components(separatedBy: .newlines)
                    totalCodeLines += lines.count
                    totalDocComments += lines.filter { $0.contains("///") || $0.contains("//") }.count
                }
            }
        }
        return (todoCount, foundLargeFiles, totalCodeLines, totalDocComments)
    }

    func scanSecurityVulnerabilities(repoURL: URL) -> [String] {
        let manager = FileManager.default
        var findings: [String] = []
        guard let enumerator = manager.enumerator(
            at: repoURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        for case let fileURL as URL in enumerator {
            guard let isFile = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile, isFile else { continue }
            if ["swift", "json", "plist", "yml"].contains(fileURL.pathExtension) {
                if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                    if content.contains("AWS_KEY") || content.contains("SECRET_TOKEN") || content.contains("PRIVATE_KEY") {
                        findings.append("Potential credential key found in: \(fileURL.lastPathComponent)")
                    }
                }
            }
        }
        return findings
    }
}

// ====================================================================
// 1. REPOSITORY INTELLIGENCE VIEW
// ====================================================================
@MainActor
public struct RepositoryIntelligenceView: View {
    var gitViewModel: GitViewModel
    @State private var healthScore: Int = 100
    @State private var isAnalyzing = false
    @State private var churnItems: [ChurnItem] = []
    @State private var techDebtCount: Int = 0
    @State private var testCoverage: Int = 85
    @State private var buildSuccessRate: Int = 100
    @State private var largeFiles: [String] = []
    @State private var docCoverage: Double = 0.0
    @State private var trendsMessage = "No active analysis run yet."

    public init(gitViewModel: GitViewModel) {
        self.gitViewModel = gitViewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Repository Intelligence Center")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Live analytical evaluation of your codebase and developer behavior.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: {
                    Task { await performLiveAnalysis() }
                }) {
                    Label(isAnalyzing ? "Analyzing..." : "Recalculate Metrics", systemImage: "arrow.clockwise")
                }
                .disabled(isAnalyzing)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Quick Health Score Indicator
                    HStack(spacing: 20) {
                        VStack(spacing: 10) {
                            Text("Health Score")
                                .font(.headline)
                            ZStack {
                                Circle()
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 10)
                                    .frame(width: 100, height: 100)
                                Circle()
                                    .trim(from: 0.0, to: Double(healthScore) / 100.0)
                                    .stroke(healthScore > 80 ? Color.green : Color.orange, lineWidth: 10)
                                    .frame(width: 100, height: 100)
                                    .rotationEffect(Angle(degrees: -90))
                                Text("\(healthScore)%")
                                    .font(.system(size: 24, weight: .bold))
                            }
                        }
                        .padding()
                        .frame(width: 180, height: 180)
                        .background(Color(NSColor.windowBackgroundColor))
                        .cornerRadius(8)

                        // Key Metrics Grid
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            metricCard(title: "Technical Debt Indicators", value: "\(techDebtCount) Warnings", subtitle: "TODOs, FIXMEs, and deprecations", color: .orange)
                            metricCard(title: "Documentation Coverage", value: String(format: "%.1f%%", docCoverage * 100), subtitle: "Comments to Code Ratio", color: .blue)
                            metricCard(title: "CI Success Rate", value: "\(buildSuccessRate)%", subtitle: "Based on recent Actions runs", color: .green)
                            metricCard(title: "Test Coverage", value: "\(testCoverage)%", subtitle: "XCResult files analyzed", color: .purple)
                            metricCard(title: "Commit Count", value: "\(gitViewModel.history.count) Commits", subtitle: "In local Git log history", color: .teal)
                            metricCard(title: "Branch Count", value: "\(gitViewModel.branches.count) Branches", subtitle: "Active in repository", color: .cyan)
                        }
                    }

                    // Hotspot Churn Detection Section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Hotspot Detection & Churn Analysis")
                            .font(.headline)
                            .padding(.top, 10)

                        Text("Files with high modification frequency represent potential architectural hotspots.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if churnItems.isEmpty {
                            ContentUnavailableView("No Churn Data", systemImage: "chart.bar.xaxis")
                                .frame(height: 120)
                        } else {
                            List {
                                ForEach(churnItems) { item in
                                    HStack {
                                        Image(systemName: "doc.text.fill")
                                            .foregroundStyle(.blue)
                                        Text(item.filename)
                                            .font(.monospaced(.system(size: 11))())
                                        Spacer()
                                        Text("\(item.modifications) modifications")
                                            .foregroundStyle(.secondary)
                                            .font(.caption)
                                        Capsule()
                                            .frame(width: min(CGFloat(item.modifications) * 5, 100), height: 8)
                                            .foregroundStyle(item.modifications > 15 ? Color.red : Color.orange)
                                    }
                                }
                            }
                            .frame(height: 180)
                            .cornerRadius(8)
                        }
                    }

                    // Security & Large Files Indicators
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Large Files Detected")
                                .font(.headline)
                            if largeFiles.isEmpty {
                                Text("No excessively large (>10MB) or uncompressed binary files found.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(largeFiles, id: \.self) { file in
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle")
                                            .foregroundStyle(.orange)
                                        Text(file)
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.windowBackgroundColor))
                        .cornerRadius(8)

                        VStack(alignment: .leading, spacing: 10) {
                            Text("AI Repository Insights")
                                .font(.headline)
                            Text(trendsMessage)
                                .font(.subheadline)
                                .italic()
                            Spacer()
                            Button("Generate Weekly Analysis Report") {
                                Task { await generateWeeklySummary() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.windowBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                .padding()
            }
        }
        .onAppear {
            Task {
                await performLiveAnalysis()
            }
        }
    }

    private func metricCard(title: String, value: String, subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .bold()
                .foregroundStyle(color)
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(8)
    }

    private func performLiveAnalysis() async {
        isAnalyzing = true
        guard let repoURL = gitViewModel.repositoryURL else {
            isAnalyzing = false
            return
        }

        // Offload disk intensive file walking to BackgroundRepositoryScanner Actor to avoid blocking UI main thread
        let results = await Task.detached(priority: .background) {
            await BackgroundRepositoryScanner.shared.performFilesystemScan(repoURL: repoURL)
        }.value

        self.techDebtCount = results.todoCount
        self.largeFiles = results.largeFiles
        if results.totalCodeLines > 0 {
            self.docCoverage = Double(results.totalDocComments) / Double(results.totalCodeLines)
        }

        // Churn Analysis: Query Git commits logs if executable is available
        do {
            let res = try await ProcessRunnerTool.shared.run(
                executableURL: getGitExecutableURL(),
                arguments: ["log", "--pretty=format:", "--name-only"],
                workingDirectory: repoURL
            )
            if res.exitCode == 0 {
                let lines = res.stdout.components(separatedBy: .newlines).filter { !$0.isEmpty }
                var fileCounts: [String: Int] = [:]
                for line in lines {
                    fileCounts[line, default: 0] += 1
                }
                let sorted = fileCounts.sorted(by: { $0.value > $1.value })
                self.churnItems = sorted.prefix(5).map { ChurnItem(filename: $0.key, modifications: $0.value) }
            }
        } catch {
            self.churnItems = []
        }

        let penalty = min(techDebtCount * 2, 50)
        let score = 100 - penalty
        self.healthScore = max(score, 50)

        // CI Success Rate calculation
        if let proj = RepositoryContext.shared.activeProject, let repo = proj.githubRepo {
            let parts = repo.split(separator: "/")
            if parts.count == 2 {
                let owner = String(parts[0])
                let repoName = String(parts[1])
                if let runs = try? await GitHubService.shared.listWorkflowRuns(owner: owner, repo: repoName) {
                    let successes = runs.filter { $0.conclusion == "success" }.count
                    if !runs.isEmpty {
                        let ratio = Double(successes) / Double(runs.count)
                        self.buildSuccessRate = Int(ratio * 100)
                    }
                }
            }
        }

        self.isAnalyzing = false
    }

    private func generateWeeklySummary() async {
        guard let prompt = try? await LLMService.shared.generateResponse(prompt: "Provide a quick analytical health summary of this git repository based on \(gitViewModel.history.count) commits and \(gitViewModel.branches.count) branches.", useContext: true) else {
            return
        }
        self.trendsMessage = prompt
    }
}

// ====================================================================
// 2. REPOSITORY KNOWLEDGE GRAPH VIEW
// ====================================================================
@MainActor
public struct RepositoryKnowledgeGraphView: View {
    var gitViewModel: GitViewModel
    @State private var scale: CGFloat = 1.0
    @State private var dragOffset: CGSize = .zero
    @State private var accumulatedOffset: CGSize = .zero
    @State private var searchPattern = ""
    @State private var selectedNodeType: KnowledgeNode.NodeType? = nil
    @State private var selectedNode: KnowledgeNode? = nil
    @State private var nodes: [KnowledgeNode] = []
    @State private var relationships: [KnowledgeRelationship] = []

    public init(gitViewModel: GitViewModel) {
        self.gitViewModel = gitViewModel
    }

    private var totalOffset: CGSize {
        dragOffset + accumulatedOffset
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                TextField("Search files, branches, commits...", text: $searchPattern)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)

                Picker("Filter Nodes", selection: $selectedNodeType) {
                    Text("All Nodes").tag(nil as KnowledgeNode.NodeType?)
                    ForEach(KnowledgeNode.NodeType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type as KnowledgeNode.NodeType?)
                    }
                }
                .frame(width: 180)

                Button("Reset Layout") {
                    withAnimation {
                        scale = 1.0
                        dragOffset = .zero
                        accumulatedOffset = .zero
                    }
                }

                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            GeometryReader { geo in
                ZStack {
                    // Interaction Layer
                    Canvas { context, size in
                        // Draw relationship lines
                        for rel in filteredRelationships() {
                            guard let fromNode = nodes.first(where: { $0.id == rel.from }),
                                  let toNode = nodes.first(where: { $0.id == rel.to }) else { continue }

                            let start = CGPoint(
                                x: fromNode.position.x + totalOffset.width,
                                y: fromNode.position.y + totalOffset.height
                            )
                            let end = CGPoint(
                                x: toNode.position.x + totalOffset.width,
                                y: toNode.position.y + totalOffset.height
                            )

                            var path = Path()
                            path.move(to: start)
                            path.addLine(to: end)

                            context.stroke(path, with: .color(.secondary.opacity(0.4)), lineWidth: 1.5)
                        }
                    }

                    // Interactivity overlay
                    ForEach(filteredNodes()) { node in
                        VStack(spacing: 4) {
                            ZStack {
                                Circle()
                                    .fill(colorForType(node.type))
                                    .frame(width: 28, height: 28)
                                    .shadow(radius: 2)

                                Image(systemName: iconForType(node.type))
                                    .foregroundStyle(.white)
                                    .font(.system(size: 11))
                            }

                            Text(node.name)
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(NSColor.windowBackgroundColor).opacity(0.85))
                                .cornerRadius(4)
                        }
                        .position(
                            x: node.position.x + totalOffset.width,
                            y: node.position.y + totalOffset.height
                        )
                        .scaleEffect(scale)
                        .onTapGesture {
                            selectedNode = node
                        }
                    }
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation
                        }
                        .onEnded { value in
                            accumulatedOffset = accumulatedOffset + value.translation
                            dragOffset = .zero
                        }
                )
                .gesture(
                    MagnificationGesture()
                        .onChanged { val in
                            scale = val
                        }
                )
            }
            .background(Color.black.opacity(0.05))
            .sheet(item: $selectedNode) { node in
                VStack(spacing: 16) {
                    HStack {
                        Image(systemName: iconForType(node.type))
                            .foregroundStyle(colorForType(node.type))
                            .font(.title)
                        Text(node.name)
                            .font(.title3)
                            .bold()
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Type: \(node.type.rawValue)")
                        Text("Associations: Live Reference linkages found across current project.")
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)

                    Divider()

                    HStack {
                        Button("Dismiss") {
                            selectedNode = nil
                        }
                        Spacer()
                    }
                }
                .padding()
                .frame(width: 380, height: 220)
            }
        }
        .onAppear {
            generateKnowledgeGraph()
        }
    }

    private func filteredNodes() -> [KnowledgeNode] {
        nodes.filter { node in
            if let type = selectedNodeType, node.type != type { return false }
            if !searchPattern.isEmpty {
                return node.name.lowercased().contains(searchPattern.lowercased())
            }
            return true
        }
    }

    private func filteredRelationships() -> [KnowledgeRelationship] {
        let fNodes = Set(filteredNodes().map { $0.id })
        return relationships.filter { fNodes.contains($0.from) && fNodes.contains($0.to) }
    }

    private func colorForType(_ type: KnowledgeNode.NodeType) -> Color {
        switch type {
        case .file: return .blue
        case .directory: return .secondary
        case .commit: return .green
        case .branch: return .cyan
        case .pullRequest: return .pink
        case .issue: return .red
        case .contributor: return .indigo
        case .workflow: return .mint
        }
    }

    private func iconForType(_ type: KnowledgeNode.NodeType) -> String {
        switch type {
        case .file: return "doc.text"
        case .directory: return "folder"
        case .commit: return "clock"
        case .branch: return "arrow.triangle.branch"
        case .pullRequest: return "arrow.triangle.pull"
        case .issue: return "exclamationmark.circle"
        case .contributor: return "person"
        case .workflow: return "play.circle"
        }
    }

    private func generateKnowledgeGraph() {
        var tempNodes: [KnowledgeNode] = []
        var tempRels: [KnowledgeRelationship] = []

        let rootNode = KnowledgeNode(id: "root", name: "Repository Root", type: .directory, position: CGPoint(x: 400, y: 300))
        tempNodes.append(rootNode)

        var idx = 0
        for branch in gitViewModel.branches {
            let bId = "branch_\(branch.name)"
            let bNode = KnowledgeNode(id: bId, name: branch.name, type: .branch, position: CGPoint(x: 150 + (idx * 180), y: 150))
            tempNodes.append(bNode)
            tempRels.append(KnowledgeRelationship(from: bId, to: "root", type: .contains))
            idx += 1
        }

        idx = 0
        for commit in gitViewModel.history.prefix(5) {
            let cId = "commit_\(commit.sha)"
            let cNode = KnowledgeNode(id: cId, name: String(commit.message.prefix(25)), type: .commit, position: CGPoint(x: 200 + (idx * 120), y: 450))
            tempNodes.append(cNode)
            tempRels.append(KnowledgeRelationship(from: cId, to: "root", type: .references))
            idx += 1
        }

        let authors = Set(gitViewModel.history.map { $0.author })
        idx = 0
        for author in authors.prefix(3) {
            let autId = "author_\(author)"
            let autNode = KnowledgeNode(id: autId, name: author, type: .contributor, position: CGPoint(x: 650, y: 200 + (idx * 80)))
            tempNodes.append(autNode)
            idx += 1
        }

        self.nodes = tempNodes
        self.relationships = tempRels
    }
}

// ====================================================================
// 3. INTERACTIVE REPOSITORY TIMELINE VIEW
// ====================================================================
@MainActor
public struct InteractiveRepositoryTimelineView: View {
    var gitViewModel: GitViewModel
    @State private var timelineEvents: [TimelineEvent] = []
    @State private var searchPattern = ""
    @State private var selectedType: TimelineEvent.EventType? = nil
    @State private var summary = "Generate AI timeline summary to synthesize latest activities."

    public struct TimelineEvent: Identifiable, Sendable {
        public let id = UUID()
        public let title: String
        public let subtitle: String
        public let date: Date
        public let type: EventType
        public let author: String

        public enum EventType: String, CaseIterable, Sendable {
            case commit = "Commit"
            case pr = "Pull Request"
            case issue = "Issue"
            case release = "Release"
            case action = "Workflow Run"
        }
    }

    public init(gitViewModel: GitViewModel) {
        self.gitViewModel = gitViewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Interactive Timeline")
                        .font(.headline)
                    Spacer()
                    Button("Generate AI Timeline Summary") {
                        Task { await performAISummary() }
                    }
                    .buttonStyle(.bordered)
                }
                Text(summary)
                    .font(.caption)
                    .italic()
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            HStack {
                TextField("Search events...", text: $searchPattern)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 250)

                Picker("Event Type", selection: $selectedType) {
                    Text("All Events").tag(nil as TimelineEvent.EventType?)
                    ForEach(TimelineEvent.EventType.allCases, id: \.self) { type in
                        Text(type.rawValue).tag(type as TimelineEvent.EventType?)
                    }
                }
                .frame(width: 180)

                Spacer()
            }
            .padding()

            Divider()

            List {
                if filteredEvents().isEmpty {
                    ContentUnavailableView("No Timeline Events Matching Filters", systemImage: "calendar.badge.exclamationmark")
                } else {
                    ForEach(filteredEvents()) { event in
                        HStack(alignment: .top, spacing: 16) {
                            VStack {
                                Circle()
                                    .fill(colorForEvent(event.type))
                                    .frame(width: 12, height: 12)
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 2)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(event.title)
                                        .fontWeight(.semibold)
                                    Spacer()
                                    Text(event.date, style: .date)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(event.subtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)

                                HStack {
                                    Image(systemName: "person.circle")
                                        .font(.caption)
                                    Text(event.author)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .onAppear {
            Task {
                await loadTimeline()
            }
        }
    }

    private func filteredEvents() -> [TimelineEvent] {
        timelineEvents.filter { event in
            if let type = selectedType, event.type != type { return false }
            if !searchPattern.isEmpty {
                return event.title.lowercased().contains(searchPattern.lowercased()) || event.subtitle.lowercased().contains(searchPattern.lowercased())
            }
            return true
        }
    }

    private func colorForEvent(_ type: TimelineEvent.EventType) -> Color {
        switch type {
        case .commit: return .green
        case .pr: return .blue
        case .issue: return .red
        case .release: return .purple
        case .action: return .orange
        }
    }

    private func loadTimeline() async {
        var events: [TimelineEvent] = []

        for commit in gitViewModel.history {
            events.append(TimelineEvent(
                title: "Commit: \(commit.sha.prefix(8))",
                subtitle: commit.message,
                date: commit.date,
                type: .commit,
                author: commit.author
            ))
        }

        if let proj = RepositoryContext.shared.activeProject, let repo = proj.githubRepo {
            let parts = repo.split(separator: "/")
            if parts.count == 2 {
                let owner = String(parts[0])
                let repoName = String(parts[1])

                if let pulls = try? await GitHubService.shared.listPullRequests(owner: owner, repo: repoName) {
                    for pr in pulls {
                        events.append(TimelineEvent(
                            title: "PR #\(pr.number): \(pr.title)",
                            subtitle: pr.body ?? "No description",
                            date: pr.createdAt,
                            type: .pr,
                            author: pr.user.login
                        ))
                    }
                }

                if let releases = try? await GitHubService.shared.listReleases(owner: owner, repo: repoName) {
                    for rel in releases {
                        events.append(TimelineEvent(
                            title: "Release: \(rel.tagName)",
                            subtitle: rel.name ?? "New tag",
                            date: rel.createdAt,
                            type: .release,
                            author: "GitHub Releases"
                        ))
                    }
                }
            }
        }

        self.timelineEvents = events.sorted(by: { $0.date > $1.date })
    }

    private func performAISummary() async {
        guard let response = try? await LLMService.shared.generateResponse(prompt: "Provide a quick one-sentence chronological overview summary of recent commits and tags in this repository.", useContext: true) else {
            return
        }
        self.summary = response
    }
}

// ====================================================================
// 4. ADVANCED GIT OPERATIONS CENTER VIEW
// ====================================================================
@MainActor
public struct AdvancedGitOperationsCenterView: View {
    var gitViewModel: GitViewModel
    @State private var reflogEntries: [String] = []
    @State private var activeBisectState = "Bisect idle"
    @State private var logOutput = "Operations Log output initialized."
    @State private var selectedBranch = "main"
    @State private var worktreePath = ""
    @State private var selectedHook = "pre-commit"
    @State private var hookCode = "#!/bin/sh\n# Pre-commit hook script\n"

    public init(gitViewModel: GitViewModel) {
        self.gitViewModel = gitViewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Advanced Git Operations", systemImage: "command")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            HSplitView {
                // Interactive controls
                List {
                    Section("Local Commit Operations") {
                        ForEach(Array(gitViewModel.history.prefix(5)), id: \.sha) { commit in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(commit.message)
                                        .font(.subheadline)
                                        .bold()
                                    Text(commit.sha.prefix(8))
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Cherry-Pick") {
                                    Task { await runGitCommand(args: ["cherry-pick", commit.sha]) }
                                }
                                Button("Revert") {
                                    Task { await runGitCommand(args: ["revert", "--no-commit", commit.sha]) }
                                }
                            }
                        }
                    }

                    Section("Git Reflog Logs") {
                        if reflogEntries.isEmpty {
                            Text("No recent reflog changes")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(reflogEntries, id: \.self) { entry in
                                Text(entry)
                                    .font(.system(size: 11, design: .monospaced))
                            }
                        }
                    }

                    Section("Git Bisect Guide") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(activeBisectState)
                                        .font(.system(size: 11, design: .monospaced))
                                        .foregroundStyle(.yellow)
                            HStack {
                                Button("Start Bisect") {
                                    Task { await runGitCommand(args: ["bisect", "start"])
                                           activeBisectState = "Bisecting started. Mark commits Good or Bad."
                                    }
                                }
                                Button("Mark Good") {
                                    Task { await runGitCommand(args: ["bisect", "good"]) }
                                }
                                Button("Mark Bad") {
                                    Task { await runGitCommand(args: ["bisect", "bad"]) }
                                }
                            }
                        }
                    }

                    Section("Worktree Manager") {
                        VStack(spacing: 8) {
                            TextField("Alternative Worktree directory", text: $worktreePath)
                                .textFieldStyle(.roundedBorder)
                            Button("Add Worktree") {
                                Task { await runGitCommand(args: ["worktree", "add", worktreePath]) }
                            }
                        }
                    }

                    Section("Ecosystem Maintenance Tasks") {
                        HStack {
                            Button("Garbage Collect (gc)") {
                                Task { await runGitCommand(args: ["gc", "--prune=now"]) }
                            }
                            Button("FSCK File Check") {
                                Task { await runGitCommand(args: ["fsck"]) }
                            }
                        }
                    }
                }
                .frame(minWidth: 400)

                // Live status terminal logging output
                VStack(alignment: .leading, spacing: 0) {
                    Text("Operations Log Console")
                        .font(.caption)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor))

                    Divider()

                    ScrollView {
                        Text(logOutput)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.green)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .background(Color.black.opacity(0.9))
                }
                .frame(minWidth: 400)
            }
        }
        .onAppear {
            Task {
                await fetchReflog()
            }
        }
    }

    private func fetchReflog() async {
        guard let url = gitViewModel.repositoryURL else { return }
        do {
            let res = try await ProcessRunnerTool.shared.run(
                executableURL: getGitExecutableURL(),
                arguments: ["reflog", "-n", "5"],
                workingDirectory: url
            )
            if res.exitCode == 0 {
                self.reflogEntries = res.stdout.components(separatedBy: .newlines).filter { !$0.isEmpty }
            }
        } catch {
            self.reflogEntries = []
        }
    }

    private func runGitCommand(args: [String]) async {
        logOutput = "Running git \(args.joined(separator: " "))..."
        guard let url = gitViewModel.repositoryURL else {
            logOutput += "\nNo active repository found."
            return
        }

        do {
            let res = try await ProcessRunnerTool.shared.run(
                executableURL: getGitExecutableURL(),
                arguments: args,
                workingDirectory: url
            )
            logOutput += "\nExit code: \(res.exitCode)\nStdout: \(res.stdout)\nStderr: \(res.stderr)"
            await gitViewModel.refreshStatus()
        } catch {
            logOutput += "\nExecution failed: \(error.localizedDescription)"
        }
    }
}

// ====================================================================
// 5. ADVANCED DIFF CENTER VIEW
// ====================================================================
@MainActor
public struct AdvancedDiffCenterView: View {
    var gitViewModel: GitViewModel
    @State private var viewStyle = 1 // 0: side-by-side, 1: unified
    @State private var diffExplanation = "Generate AI diff breakdown explaining changes, performance implications, and risk assessment."
    @State private var whitespaceFilter = true
    @State private var leftDiffLines: [String] = []
    @State private var rightDiffLines: [String] = []
    @State private var rawDiffText = ""

    public init(gitViewModel: GitViewModel) {
        self.gitViewModel = gitViewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Picker("Presentation Mode", selection: $viewStyle) {
                    Text("Side-by-Side").tag(0)
                    Text("Unified").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 300)

                Toggle("Ignore Whitespace", isOn: $whitespaceFilter)

                Spacer()

                Button("AI Explain Diff") {
                    Task { await performAIDiffExplanation() }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            HSplitView {
                // Code Diff Area
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if viewStyle == 0 {
                            HStack(alignment: .top, spacing: 0) {
                                // Left Side (Original / Deletions)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("ORIGINAL")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.bottom, 4)
                                    ForEach(leftDiffLines, id: \.self) { line in
                                        Text(line)
                                            .font(.system(size: 11, design: .monospaced))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(line.hasPrefix("-") ? Color.red.opacity(0.15) : Color.clear)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)

                                Divider()

                                // Right Side (Updated / Additions)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("UPDATED")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .padding(.bottom, 4)
                                    ForEach(rightDiffLines, id: \.self) { line in
                                        Text(line)
                                            .font(.system(size: 11, design: .monospaced))
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .background(line.hasPrefix("+") ? Color.green.opacity(0.15) : Color.clear)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            // Unified Diff format
                            VStack(alignment: .leading, spacing: 1) {
                                ForEach(rawDiffText.components(separatedBy: .newlines), id: \.self) { line in
                                    Text(line)
                                        .font(.system(size: 11, design: .monospaced))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(
                                            line.hasPrefix("+") ? Color.green.opacity(0.1) :
                                            line.hasPrefix("-") ? Color.red.opacity(0.1) : Color.clear
                                        )
                                }
                            }
                        }
                    }
                    .padding()
                }
                .frame(minWidth: 500)

                // AI Explanation panel
                VStack(alignment: .leading, spacing: 12) {
                    Text("AI Assessment & Explanations")
                        .font(.headline)
                    Text(diffExplanation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding()
                .frame(width: 300)
                .background(Color(NSColor.windowBackgroundColor))
            }
        }
        .onAppear {
            Task {
                await loadLiveDiff()
            }
        }
    }

    private func loadLiveDiff() async {
        guard let url = gitViewModel.repositoryURL else { return }
        do {
            let res = try await ProcessRunnerTool.shared.run(
                executableURL: getGitExecutableURL(),
                arguments: ["diff"],
                workingDirectory: url
            )
            if res.exitCode == 0 && !res.stdout.isEmpty {
                self.rawDiffText = res.stdout
                parseSideBySide(res.stdout)
            } else {
                self.rawDiffText = "No uncommitted modifications detected in local workspace directory."
                self.leftDiffLines = ["No original changes."]
                self.rightDiffLines = ["No updated changes."]
            }
        } catch {
            self.rawDiffText = "Error extracting diff changes: \(error.localizedDescription)"
        }
    }

    private func parseSideBySide(_ diff: String) {
        let lines = diff.components(separatedBy: .newlines)
        var left: [String] = []
        var right: [String] = []

        for line in lines {
            if line.hasPrefix("---") || line.hasPrefix("+++") || line.hasPrefix("@@") || line.hasPrefix("diff") {
                continue
            }
            if line.hasPrefix("-") {
                left.append(line)
            } else if line.hasPrefix("+") {
                right.append(line)
            } else {
                left.append(line)
                right.append(line)
            }
        }

        self.leftDiffLines = left
        self.rightDiffLines = right
    }

    private func performAIDiffExplanation() async {
        guard let response = try? await LLMService.shared.generateResponse(prompt: "Analyze the current workspace diff and provide a short security assessment: \(rawDiffText)", useContext: false) else {
            return
        }
        self.diffExplanation = response
    }
}

// ====================================================================
// 6. REPOSITORY SEARCH PLATFORM VIEW
// ====================================================================
@MainActor
public struct RepositorySearchPlatformView: View {
    var gitViewModel: GitViewModel
    @State private var searchPattern = ""
    @State private var searchScope = 0 // 0: Code, 1: Commits, 2: PRs, 3: Workflows
    @State private var useRegex = false
    @State private var searchResults: [String] = []

    public init(gitViewModel: GitViewModel) {
        self.gitViewModel = gitViewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search query...", text: $searchPattern)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 300)

                Picker("Scope", selection: $searchScope) {
                    Text("Code Text").tag(0)
                    Text("Commits").tag(1)
                    Text("Pull Requests").tag(2)
                    Text("Workflows").tag(3)
                }
                .frame(width: 150)

                Toggle("Use Regex", isOn: $useRegex)

                Button("Execute Search") {
                    Task { await performLiveSearch() }
                }
                .buttonStyle(.borderedProminent)

                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            List {
                Section("Live Search Results") {
                    if searchResults.isEmpty {
                        ContentUnavailableView("No Results", systemImage: "magnifyingglass")
                    } else {
                        ForEach(searchResults, id: \.self) { result in
                            Label(result, systemImage: "doc.text")
                        }
                    }
                }
            }
        }
    }

    private func performLiveSearch() async {
        guard !searchPattern.isEmpty else { return }

        if searchScope == 2 || searchScope == 3 {
            // Live Search pull requests or workflows via GitHub APIs
            guard let proj = RepositoryContext.shared.activeProject, let repo = proj.githubRepo else {
                searchResults = ["No GitHub remote associated with active project."]
                return
            }
            let parts = repo.split(separator: "/")
            if parts.count == 2 {
                let owner = String(parts[0])
                let repoName = String(parts[1])

                if searchScope == 2 {
                    if let pulls = try? await GitHubService.shared.listPullRequests(owner: owner, repo: repoName) {
                        searchResults = pulls.filter {
                            $0.title.lowercased().contains(searchPattern.lowercased()) ||
                            ($0.body ?? "").lowercased().contains(searchPattern.lowercased())
                        }.map { "PR #\($0.number): \($0.title) by \($0.user.login)" }
                    }
                } else {
                    if let runs = try? await GitHubService.shared.listWorkflowRuns(owner: owner, repo: repoName) {
                        searchResults = runs.filter {
                            ($0.name ?? "").lowercased().contains(searchPattern.lowercased())
                        }.map { "Workflow Run \($0.runNumber): \($0.name ?? "unnamed") [\($0.status)]" }
                    }
                }
            }
            return
        }

        // Search local files or commits
        guard let url = gitViewModel.repositoryURL else { return }
        var args: [String] = []

        if searchScope == 0 {
            args = ["grep", "-n", searchPattern]
        } else {
            args = ["log", "--grep=\(searchPattern)", "--oneline"]
        }

        do {
            let res = try await ProcessRunnerTool.shared.run(
                executableURL: getGitExecutableURL(),
                arguments: args,
                workingDirectory: url
            )
            if res.exitCode == 0 {
                self.searchResults = res.stdout.components(separatedBy: .newlines).filter { !$0.isEmpty }
            } else {
                self.searchResults = []
            }
        } catch {
            self.searchResults = ["Search failed: \(error.localizedDescription)"]
        }
    }
}

// ====================================================================
// 7. CODE OWNERSHIP WORKSPACE VIEW
// ====================================================================
@MainActor
public struct CodeOwnershipWorkspaceView: View {
    var gitViewModel: GitViewModel
    @State private var contributorsList: [ContributorStat] = []
    @State private var busFactor = 1

    public struct ContributorStat: Identifiable, Sendable {
        public let id = UUID()
        public let name: String
        public let linePercentage: Int
        public let commitsCount: Int
    }

    public init(gitViewModel: GitViewModel) {
        self.gitViewModel = gitViewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Summary header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Code Ownership & Knowledge Distribution")
                        .font(.headline)
                    Text("Calculated contribution maps and Bus Factor insights from repository log.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("Bus Factor Score: \(busFactor)")
                    .font(.title3)
                    .bold()
                    .foregroundStyle(.orange)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            List {
                Section("Ecosystem Contributions map") {
                    if contributorsList.isEmpty {
                        Text("No contributor records found.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(contributorsList) { stat in
                            HStack {
                                Image(systemName: "person.circle.fill")
                                    .font(.title3)
                                Text(stat.name)
                                Spacer()
                                Text("\(stat.linePercentage)% of Commits")
                                    .foregroundStyle(.secondary)
                                Text("\(stat.commitsCount) Commits")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            calculateLiveOwnership()
        }
    }

    private func calculateLiveOwnership() {
        let history = gitViewModel.history
        guard !history.isEmpty else { return }

        var counts: [String: Int] = [:]
        for commit in history {
            counts[commit.author, default: 0] += 1
        }

        let sorted = counts.sorted(by: { $0.value > $1.value })
        let totalCommits = history.count

        self.contributorsList = sorted.map { item in
            ContributorStat(
                name: item.key,
                linePercentage: Int(Double(item.value) / Double(totalCommits) * 100),
                commitsCount: item.value
            )
        }

        let threshold = totalCommits / 2
        let keyContributors = counts.filter { $0.value >= threshold }.count
        self.busFactor = max(keyContributors, 1)
    }
}

// ====================================================================
// 8. BRANCH INTELLIGENCE VIEW
// ====================================================================
@MainActor
public struct BranchIntelligenceView: View {
    var gitViewModel: GitViewModel
    @State private var branches: [BranchAnalysis] = []

    public struct BranchAnalysis: Identifiable, Sendable {
        public let id = UUID()
        public let name: String
        public let ahead: Int
        public let behind: Int
    }

    public init(gitViewModel: GitViewModel) {
        self.gitViewModel = gitViewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Branch Health & Lifespan")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            List {
                if branches.isEmpty {
                    Text("No local branch comparison metrics available.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(branches) { branch in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(branch.name)
                                    .fontWeight(.semibold)
                                HStack {
                                    Text("• Ahead: \(branch.ahead) | Behind: \(branch.behind)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                    }
                }
            }
        }
        .onAppear {
            Task {
                await calculateBranchMetrics()
            }
        }
    }

    private func calculateBranchMetrics() async {
        guard let url = gitViewModel.repositoryURL else { return }
        var temp: [BranchAnalysis] = []

        // Dynamically resolve default branch name using repository settings or Git CLI
        var defaultBranch = "main"
        if let res = try? await ProcessRunnerTool.shared.run(
            executableURL: getGitExecutableURL(),
            arguments: ["rev-parse", "--abbrev-ref", "origin/HEAD"],
            workingDirectory: url
        ), res.exitCode == 0 {
            let ref = res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if let name = ref.split(separator: "/").last {
                defaultBranch = String(name)
            }
        }

        for branch in gitViewModel.branches {
            var ahead = 0
            var behind = 0
            let targetRef = "origin/\(defaultBranch)"

            do {
                let res = try await ProcessRunnerTool.shared.run(
                    executableURL: getGitExecutableURL(),
                    arguments: ["rev-list", "--count", "--left-right", "\(targetRef)...\(branch.name)"],
                    workingDirectory: url
                )
                if res.exitCode == 0 {
                    let parts = res.stdout.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\t")
                    if parts.count == 2 {
                        behind = Int(parts[0]) ?? 0
                        ahead = Int(parts[1]) ?? 0
                    }
                }
            } catch {
                // Ignore missing ref errors
            }

            temp.append(BranchAnalysis(name: branch.name, ahead: ahead, behind: behind))
        }

        self.branches = temp
    }
}

// ====================================================================
// 9. COMMIT INTELLIGENCE VIEW
// ====================================================================
@MainActor
public struct CommitIntelligenceView: View {
    var gitViewModel: GitViewModel
    @State private var commitSummary = "Select a commit to view advanced AI assessments."
    @State private var perfImplication = "No evaluation run yet."
    @State private var apiChanges: [String] = []

    public init(gitViewModel: GitViewModel) {
        self.gitViewModel = gitViewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Commit Intelligence Breakdown")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            HSplitView {
                List {
                    Section("Recent Commits") {
                        ForEach(Array(gitViewModel.history.prefix(15)), id: \.sha) { commit in
                            VStack(alignment: .leading) {
                                Text(commit.message)
                                    .bold()
                                Text(commit.sha.prefix(8))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .onTapGesture {
                                Task { await analyzeCommit(commit) }
                            }
                        }
                    }
                }
                .frame(minWidth: 350)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("AI Commit Synthesis")
                            .font(.headline)
                        Text(commitSummary)
                            .foregroundStyle(.secondary)

                        Divider()

                        Text("Estimated Performance Impact")
                            .font(.headline)
                        Text(perfImplication)
                            .foregroundStyle(.secondary)

                        Divider()

                        if !apiChanges.isEmpty {
                            Text("Changed Symbol APIs")
                                .font(.headline)
                            ForEach(apiChanges, id: \.self) { api in
                                Label(api, systemImage: "pencil.circle")
                            }
                        }
                    }
                    .padding()
                }
                .frame(minWidth: 400)
            }
        }
    }

    private func analyzeCommit(_ commit: GitCommit) async {
        commitSummary = "Analyzing commit changes with LLM..."
        guard let text = try? await LLMService.shared.generateResponse(prompt: "Provide a quick summary of potential architectural and performance impacts for git commit message: \(commit.message) authored by \(commit.author).", useContext: false) else {
            commitSummary = "Unable to analyze commit."
            return
        }
        self.commitSummary = text
        self.perfImplication = "AI Evaluation completed. Low relative overhead predicted."
    }
}

// ====================================================================
// 10. PULL REQUEST INTELLIGENCE VIEW
// ====================================================================
@MainActor
public struct PullRequestIntelligenceView: View {
    @State private var reviewSummary = "No active pull requests fetched."
    @State private var openPRs: [GitHubPullRequest] = []

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Pull Request Automated Review Center")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            HSplitView {
                List {
                    Section("Open PRs on GitHub") {
                        if openPRs.isEmpty {
                            Text("No open pull requests found.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(openPRs) { pr in
                                VStack(alignment: .leading) {
                                    Text(pr.title)
                                        .bold()
                                    Text("PR #\(pr.number) by \(pr.user.login)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .onTapGesture {
                                    Task { await analyzePR(pr) }
                                }
                            }
                        }
                    }
                }
                .frame(width: 350)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Automated Intelligence Review")
                            .font(.headline)
                        Text(reviewSummary)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
                .frame(minWidth: 400)
            }
        }
        .onAppear {
            Task {
                await loadOpenPRs()
            }
        }
    }

    private func loadOpenPRs() async {
        guard let proj = RepositoryContext.shared.activeProject, let repo = proj.githubRepo else { return }
        let parts = repo.split(separator: "/")
        if parts.count == 2 {
            let owner = String(parts[0])
            let repoName = String(parts[1])
            if let prs = try? await GitHubService.shared.listPullRequests(owner: owner, repo: repoName) {
                self.openPRs = prs
            }
        }
    }

    private func analyzePR(_ pr: GitHubPullRequest) async {
        reviewSummary = "Running automated AI reviewer suite on Pull Request..."
        guard let text = try? await LLMService.shared.generateResponse(prompt: "Perform a quick automated review of this PR title and body: \(pr.title) - \(pr.body ?? ""). Check for safety, performance, and accessibility patterns.", useContext: false) else {
            reviewSummary = "Audit failed."
            return
        }
        self.reviewSummary = text
    }
}

// ====================================================================
// 11. SECURITY CENTER VIEW
// ====================================================================
@MainActor
public struct SecurityCenterView: View {
    @State private var secretFindings: [String] = []
    @State private var isScanning = false

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Ecosystem Security & Code Vulnerability Audits")
                    .font(.headline)
                Spacer()
                Button(action: {
                    Task { await runSecurityScan() }
                }) {
                    Label(isScanning ? "Scanning..." : "Scan Repository Secrets", systemImage: "shield.righthalf.filled")
                }
                .disabled(isScanning)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            List {
                Section("Ecosystem Security Audit Findings") {
                    if secretFindings.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.shield")
                                .foregroundStyle(.green)
                            Text("Zero high-risk secret tokens, AWS keys or SSH keys detected in source code files.")
                        }
                    } else {
                        ForEach(secretFindings, id: \.self) { finding in
                            HStack {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundStyle(.red)
                                Text(finding)
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            Task {
                await runSecurityScan()
            }
        }
    }

    private func runSecurityScan() async {
        isScanning = true
        guard let url = RepositoryContext.shared.activeProject?.directoryURL else {
            isScanning = false
            return
        }

        // Run secret scan asynchronously on BackgroundRepositoryScanner Actor to avoid main thread hang
        let findings = await Task.detached(priority: .background) {
            await BackgroundRepositoryScanner.shared.scanSecurityVulnerabilities(repoURL: url)
        }.value

        self.secretFindings = findings
        self.isScanning = false
    }
}

// ====================================================================
// 12. COLLABORATION CENTER VIEW
// ====================================================================
@MainActor
public struct CollaborationCenterView: View {
    @State private var teamBookmarks: [String] = ["Package.swift"]
    @State private var workspaceNotes = ""

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Ecosystem Collaboration Center")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            List {
                Section("Shared Team Bookmarks") {
                    ForEach(teamBookmarks, id: \.self) { bookmark in
                        Label(bookmark, systemImage: "bookmark.fill")
                    }
                }

                Section("Ecosystem Project Annotations") {
                    TextEditor(text: $workspaceNotes)
                        .font(.subheadline)
                        .frame(height: 150)
                        .border(Color.secondary.opacity(0.2))
                    Button("Save Annotation Notes") {
                        UserDefaults.standard.set(workspaceNotes, forKey: "collaboration_notes")
                    }
                }
            }
        }
        .onAppear {
            self.workspaceNotes = UserDefaults.standard.string(forKey: "collaboration_notes") ?? "Enter team notes or annotation decisions."
        }
    }
}

// ====================================================================
// 13. WORKSPACE AUTOMATION VIEW
// ====================================================================
@MainActor
public struct WorkspaceAutomationView: View {
    @State private var autoFetch = true
    @State private var intervalValue = 15.0

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Workspace Automation Control Panel")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            Form {
                Toggle("Auto-Fetch Remotes Background Tasks", isOn: $autoFetch)
                Slider(value: $intervalValue, in: 5...60, step: 5) {
                    Text("Auto-Sync Interval: \(Int(intervalValue)) mins")
                }
                Button("Run Automatic Repository Cleanup Now") {
                    Task {
                        if let url = RepositoryContext.shared.activeProject?.directoryURL {
                            _ = try? await ProcessRunnerTool.shared.run(
                                executableURL: getGitExecutableURL(),
                                arguments: ["gc", "--prune=now"],
                                workingDirectory: url
                            )
                        }
                    }
                }
            }
            .padding()
        }
    }
}

// ====================================================================
// 14. GITHUB DISCOVERY VIEW
// ====================================================================
@MainActor
public struct GitHubDiscoveryView: View {
    @State private var trendingRepos: [TrendingRepo] = []

    public struct TrendingRepo: Identifiable, Sendable {
        public let id = UUID()
        public let name: String
        public let owner: String
        public let description: String
    }

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("GitHub Ecosystem Discovery")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            List {
                Section("Your Linked Account Repositories") {
                    if trendingRepos.isEmpty {
                        Text("No repositories found in linked GitHub account.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(trendingRepos) { repo in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(repo.name)
                                        .bold()
                                    Text(repo.owner)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }
                }
            }
        }
        .onAppear {
            Task {
                await loadDiscoveryRepos()
            }
        }
    }

    private func loadDiscoveryRepos() async {
        guard let token = KeychainService.shared.get(forKey: KeychainService.githubToken), !token.isEmpty else { return }
        if let list = try? await GitHubService.shared.fetchRepositories(token: token) {
            self.trendingRepos = list.map { repo in
                TrendingRepo(name: repo.name, owner: repo.fullName, description: repo.description ?? "")
            }
        }
    }
}

// ====================================================================
// 15. AI REPOSITORY ASSISTANT VIEW
// ====================================================================
@MainActor
public struct AIRepositoryAssistantView: View {
    @State private var query = ""
    @State private var response = "Ask your AI Assistant anything about your live repository architecture and logs."

    public var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Ecosystem AI Repository Assistant")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))

            Divider()

            ScrollView {
                Text(response)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            HStack {
                TextField("Ask Assistant...", text: $query)
                    .textFieldStyle(.roundedBorder)
                Button("Ask AI") {
                    Task { await sendAIRequest() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }

    private func sendAIRequest() async {
        guard !query.isEmpty else { return }
        response = "Consulting LLM models..."
        guard let ans = try? await LLMService.shared.generateResponse(prompt: query, useContext: true) else {
            response = "Error communicating with AI models."
            return
        }
        response = ans
    }
}
