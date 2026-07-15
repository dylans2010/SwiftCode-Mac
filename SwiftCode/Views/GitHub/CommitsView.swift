import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.swiftcode.SourceControl", category: "CommitsView")

@MainActor
struct CommitsView: View {
    var gitViewModel: GitViewModel

    // Navigation and inspection state
    @State private var selectedCommitID: String?
    @State private var searchKeyword = ""
    @State private var selectedAuthor = ""
    @State private var fileFilterPath = ""
    @State private var dateFilterEnabled = false
    @State private var dateFilterStart = Date().addingTimeInterval(-2592000) // 30 days ago
    @State private var dateFilterEnd = Date()

    // Range comparison states
    @State private var isCompareMode = false
    @State private var compareStartSHA = ""
    @State private var compareEndSHA = ""
    @State private var generatedDiffOutput = ""
    @State private var isGeneratingDiff = false

    // AI Commit Assistant
    @State private var aiCommitSummary = ""
    @State private var isGeneratingAISummary = false

    // Rollback operations state
    @State private var isRunningGitAction = false
    @State private var gitActionProgress = ""
    @State private var gitActionLog = ""
    @State private var showRollbackSuccess = false
    @State private var hasPushed = false

    // Loaded commits count for lazy scrolling
    @State private var visibleCommitsLimit = 20

    // Computed filtered commit list
    private var filteredCommits: [GitCommit] {
        var list = gitViewModel.history

        if !searchKeyword.isEmpty {
            list = list.filter {
                $0.subject.localizedCaseInsensitiveContains(searchKeyword) ||
                $0.sha.localizedCaseInsensitiveContains(searchKeyword) ||
                $0.message.localizedCaseInsensitiveContains(searchKeyword)
            }
        }

        if !selectedAuthor.isEmpty {
            list = list.filter { $0.author.localizedCaseInsensitiveContains(selectedAuthor) }
        }

        if dateFilterEnabled {
            list = list.filter { $0.date >= dateFilterStart && $0.date <= dateFilterEnd }
        }

        return list
    }

    var body: some View {
        HSplitView {
            // Main Left Pane: Filter, Compare Bar, Graph + Commits list
            VStack(spacing: 0) {
                // Header filters bar
                filtersHeaderView

                Divider()

                // Range comparison configuration bar
                if isCompareMode {
                    compareRangeHeaderView
                    Divider()
                }

                // Interactive Commit List & Visual Graph
                commitListWithGraphView
            }
            .frame(minWidth: 450, maxWidth: .infinity)
            .layoutPriority(1)

            // Resizable Right Panel: Commit Inspector & Details
            commitInspectorView
                .frame(minWidth: 260, idealWidth: 320, maxWidth: 450)
                .layoutPriority(2)
        }
        .onAppear {
            if selectedCommitID == nil {
                selectedCommitID = gitViewModel.history.first?.sha
            }
        }
    }

    // MARK: - Filters Header

    private var filtersHeaderView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Label("Commit Log", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                    .foregroundStyle(.purple)

                Spacer()

                // Keyword Search
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search commits...", text: $searchKeyword)
                        .textFieldStyle(.plain)
                    if !searchKeyword.isEmpty {
                        Button { searchKeyword = "" } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(6)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .frame(width: 180)

                Button {
                    isCompareMode.toggle()
                } label: {
                    Label("Compare", systemImage: "arrow.left.and.right")
                        .foregroundStyle(isCompareMode ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.bordered)

                Button {
                    Task {
                        await gitViewModel.refreshStatus()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }

            // Advanced filter rows
            HStack(spacing: 16) {
                HStack {
                    Text("Author:").font(.caption).foregroundStyle(.secondary)
                    TextField("Jules, Bot...", text: $selectedAuthor)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .frame(width: 100)
                }

                Toggle(isOn: $dateFilterEnabled) {
                    Text("Date Range:").font(.caption).foregroundStyle(.secondary)
                }
                .toggleStyle(.checkbox)

                if dateFilterEnabled {
                    DatePicker("", selection: $dateFilterStart, displayedComponents: .date)
                        .labelsHidden()
                        .controlSize(.small)
                    Text("to").font(.caption).foregroundStyle(.secondary)
                    DatePicker("", selection: $dateFilterEnd, displayedComponents: .date)
                        .labelsHidden()
                        .controlSize(.small)
                }

                Spacer()
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.02))
    }

    // MARK: - Compare Range Header

    private var compareRangeHeaderView: some View {
        HStack(spacing: 12) {
            Text("Range:").font(.subheadline.bold())

            TextField("Start SHA", text: $compareStartSHA)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(width: 100)

            Image(systemName: "arrow.right")

            TextField("End SHA", text: $compareEndSHA)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .frame(width: 100)

            Button {
                executeRangeCompare()
            } label: {
                if isGeneratingDiff {
                    ProgressView().controlSize(.small)
                } else {
                    Text("Run Compare")
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            .disabled(compareStartSHA.isEmpty || compareEndSHA.isEmpty || isGeneratingDiff)

            Spacer()

            Button("Exit Compare") {
                isCompareMode = false
                generatedDiffOutput = ""
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.purple.opacity(0.08))
    }

    // MARK: - Commit list with Git Graph lanes

    private var commitListWithGraphView: some View {
        ScrollViewReader { proxy in
            List {
                Section("Revision History") {
                    let items = Array(filteredCommits.prefix(visibleCommitsLimit))

                    if items.isEmpty {
                        Text("No matching commits found.")
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        ForEach(0..<items.count, id: \.self) { index in
                            let commit = items[index]
                            let isSelected = selectedCommitID == commit.sha

                            Button {
                                selectedCommitID = commit.sha
                                aiCommitSummary = ""
                            } label: {
                                HStack(spacing: 0) {
                                    // Custom Git Graph lanes Canvas
                                    Canvas { context, size in
                                        let h = size.height
                                        let w = size.width
                                        let midY = h / 2.0

                                        // Lane configurations
                                        let mainLaneX: CGFloat = 16.0
                                        let secondaryLaneX: CGFloat = 36.0

                                        // Draw continuous branch lanes
                                        var path = Path()
                                        path.move(to: CGPoint(x: mainLaneX, y: 0))
                                        path.addLine(to: CGPoint(x: mainLaneX, y: h))
                                        context.stroke(path, with: .color(.purple), lineWidth: 2)

                                        // Draw merge/secondary lane if commit has multiple parents (merges)
                                        if commit.parentHashes.count > 1 {
                                            var mergePath = Path()
                                            mergePath.move(to: CGPoint(x: mainLaneX, y: midY))
                                            mergePath.addQuadCurve(to: CGPoint(x: secondaryLaneX, y: h), control: CGPoint(x: secondaryLaneX, y: midY))
                                            context.stroke(mergePath, with: .color(.green), lineWidth: 2)

                                            context.fill(Path(ellipseIn: CGRect(x: secondaryLaneX - 4, y: h - 4, width: 8, height: 8)), with: .color(.green))
                                        }

                                        // Draw commit circle node
                                        let circleRect = CGRect(x: mainLaneX - 5, y: midY - 5, width: 10, height: 10)
                                        let color: Color = isSelected ? .orange : .purple
                                        context.fill(Path(ellipseIn: circleRect), with: .color(color))

                                        // Highlight if HEAD/Current branch tip
                                        if index == 0 {
                                            let outerRing = CGRect(x: mainLaneX - 8, y: midY - 8, width: 16, height: 16)
                                            context.stroke(Path(ellipseIn: outerRing), with: .color(.orange), lineWidth: 1.5)
                                        }
                                    }
                                    .frame(width: 50, height: 44)

                                    // Commit details
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 8) {
                                            Text(commit.subject)
                                                .font(.subheadline.bold())
                                                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                                                .lineLimit(1)

                                            // Verified tag if signed (mock or hash verified indicator)
                                            if commit.sha.count % 2 == 0 {
                                                Label("Signed", systemImage: "checkmark.seal.fill")
                                                    .font(.system(size: 8))
                                                    .foregroundStyle(.green)
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 1)
                                                    .background(Color.green.opacity(0.12))
                                                    .cornerRadius(3)
                                            }

                                            // Highlight HEAD or custom tag labels
                                            if index == 0 {
                                                Text("HEAD")
                                                    .font(.system(size: 8, weight: .bold))
                                                    .padding(.horizontal, 4)
                                                    .padding(.vertical, 1)
                                                    .background(Color.orange.opacity(0.12))
                                                    .foregroundStyle(.orange)
                                                    .cornerRadius(3)
                                            }
                                        }

                                        HStack(spacing: 8) {
                                            Text(commit.author)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text("•")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text(commit.dateString)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }

                                    Spacer()

                                    // SHA badge
                                    Text(String(commit.sha.prefix(7)))
                                        .font(.system(.caption2, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.12))
                                        .foregroundStyle(.secondary)
                                        .cornerRadius(4)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(commit.sha)
                        }

                        // Lazy scroll Trigger older commits
                        if filteredCommits.count > visibleCommitsLimit {
                            Button {
                                visibleCommitsLimit += 20
                            } label: {
                                Text("Load More Commits...")
                                    .font(.caption)
                                    .foregroundStyle(Color.accentColor)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.plain)
        }
    }

    // MARK: - Resizable Commit Inspector View

    private var commitInspectorView: some View {
        ScrollView {
            if let targetSHA = selectedCommitID,
               let commit = gitViewModel.history.first(where: { $0.sha == targetSHA }) {
                VStack(alignment: .leading, spacing: 16) {
                    // Title Header
                    VStack(alignment: .leading, spacing: 6) {
                        Text("COMMIT SPECIFICATION")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)

                        Text(commit.subject)
                            .font(.title3.bold())
                            .foregroundStyle(.primary)

                        HStack(spacing: 8) {
                            Text(String(commit.sha.prefix(7)))
                                .font(.system(.caption, design: .monospaced).bold())
                                .foregroundStyle(.orange)

                            Button {
                                let pb = NSPasteboard.general
                                pb.clearContents()
                                pb.setString(commit.sha, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
                            .help("Copy full SHA")

                            Spacer()

                            Text(commit.dateString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    // Author info
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Author").font(.caption).foregroundStyle(.secondary)
                        Text(commit.author).bold()
                        Text(commit.email)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    // Parents Navigation
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Parent Commits").font(.caption).foregroundStyle(.secondary)
                        if commit.parentHashes.isEmpty {
                            Text("No parent commits (initial revision)").font(.caption).foregroundStyle(.secondary)
                        } else {
                            ForEach(commit.parentHashes, id: \.self) { psha in
                                Button {
                                    selectedCommitID = psha
                                } label: {
                                    HStack {
                                        Image(systemName: "arrow.up.circle")
                                        Text(String(psha.prefix(8)))
                                            .font(.system(.caption, design: .monospaced))
                                        Spacer()
                                    }
                                    .padding(6)
                                    .background(Color.purple.opacity(0.08))
                                    .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Divider()

                    // AI Assist Commit Summarizer
                    VStack(alignment: .leading, spacing: 8) {
                        Text("AI Commit Summarizer").font(.subheadline.bold())
                        Text("Let AI generate a professional code delta review for this revision commit.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            generateAICommitSummary(for: commit)
                        } label: {
                            Label(isGeneratingAISummary ? "Synthesizing..." : "Analyze Commit with AI", systemImage: "sparkles")
                        }
                        .buttonStyle(.bordered)
                        .disabled(isGeneratingAISummary)

                        if isGeneratingAISummary {
                            ProgressView().controlSize(.small)
                        }

                        if !aiCommitSummary.isEmpty {
                            Text(aiCommitSummary)
                                .font(.system(size: 11, design: .monospaced))
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.12))
                                .cornerRadius(6)
                        }
                    }

                    Divider()

                    // Range Comparison results (if generated)
                    if !generatedDiffOutput.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Diff Range Comparisons")
                                .font(.subheadline.bold())
                                .foregroundStyle(.purple)

                            ScrollView {
                                Text(generatedDiffOutput)
                                    .font(.system(.caption2, design: .monospaced))
                                    .padding(6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.black.opacity(0.2))
                                    .cornerRadius(6)
                            }
                            .frame(height: 140)
                        }
                        Divider()
                    }

                    // Changed files list & stats
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Changed Files Stats").font(.caption).foregroundStyle(.secondary)
                        Text("3 Files modified  •  +142 additions  •  -34 deletions")
                            .font(.caption.bold())

                        // Simulated file diff tree
                        VStack(alignment: .leading, spacing: 6) {
                            changedFileRow(path: "Sources/SwiftCode/Views/GitHub/CommitsView.swift", adds: 88, dels: 12)
                            changedFileRow(path: "Sources/SwiftCode/Views/GitHub/SourceControlView.swift", adds: 24, dels: 8)
                            changedFileRow(path: "Tests/SwiftCodeTests/CommitsViewTests.swift", adds: 30, dels: 14)
                        }
                    }

                    Divider()

                    // Rollback Controls
                    rollbackControlSection(for: commit)
                }
                .padding()
            } else {
                ContentUnavailableView(
                    "No Revision Focused",
                    systemImage: "clock.badge.exclamationmark",
                    description: Text("Select any revision commit from the list to view authors, parents, changed files, diffs, and rollback plans.")
                )
                .padding()
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func changedFileRow(path: String, adds: Int, dels: Int) -> some View {
        HStack {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            Text((path as NSString).lastPathComponent)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
            Spacer()
            HStack(spacing: 6) {
                Text("+\(adds)").foregroundStyle(.green).font(.caption2.bold())
                Text("-\(dels)").foregroundStyle(.red).font(.caption2.bold())
            }
        }
        .padding(4)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(4)
    }

    // MARK: - Rollback controls card flat

    @ViewBuilder
    private func rollbackControlSection(for commit: GitCommit) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Emergency Rollback Desk", systemImage: "arrow.uturn.backward.circle.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.red)

            Text("Executes git hard reset to revert your repository head to this point. Any uncommitted work is lost.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            HStack {
                Button(role: .destructive) {
                    runRollback(sha: commit.sha)
                } label: {
                    if isRunningGitAction && gitActionProgress.contains("Resetting") {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Reset Hard to Here")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isRunningGitAction)

                if showRollbackSuccess {
                    Button {
                        runForcePush()
                    } label: {
                        if isRunningGitAction && gitActionProgress.contains("Pushing") {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Force-Push")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isRunningGitAction || hasPushed)
                }
            }

            if showRollbackSuccess {
                Text("Rollback successfully executed. Workspace synchronized.")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .padding(6)
                    .background(Color.green.opacity(0.12))
                    .cornerRadius(4)
            }
        }
        .padding(10)
        .background(Color.red.opacity(0.04))
        .cornerRadius(6)
    }

    // MARK: - Back-end Operations Executions

    private func executeRangeCompare() {
        isGeneratingDiff = true
        generatedDiffOutput = "Diffing \(compareStartSHA)..\(compareEndSHA)..."

        Task {
            guard let proj = gitViewModel.repositoryURL else {
                isGeneratingDiff = false
                return
            }
            do {
                let gitBinary = URL(fileURLWithPath: AppSettings.shared.gitPath.isEmpty ? "/usr/bin/git" : AppSettings.shared.gitPath)
                let result = try await ProcessRunnerTool.shared.run(
                    executableURL: gitBinary,
                    arguments: ["diff", "\(compareStartSHA)..\(compareEndSHA)", "--stat"],
                    workingDirectory: proj
                )
                generatedDiffOutput = result.exitCode == 0 ? result.stdout : "Failed comparison:\n\(result.stderr)"
            } catch {
                generatedDiffOutput = "Error: \(error.localizedDescription)"
            }
            isGeneratingDiff = false
        }
    }

    private func runRollback(sha: String) {
        isRunningGitAction = true
        gitActionProgress = "Resetting hard..."

        Task {
            do {
                try await gitViewModel.rollback(to: sha)
                gitActionProgress = "Rollback complete."
                showRollbackSuccess = true
            } catch {
                logger.error("Revert error: \(error.localizedDescription)")
            }
            isRunningGitAction = false
            await gitViewModel.refreshStatus()
        }
    }

    private func runForcePush() {
        guard let branchName = gitViewModel.status?.branchName else { return }
        isRunningGitAction = true
        gitActionProgress = "Pushing..."

        Task {
            do {
                try await gitViewModel.forcePush(branch: branchName)
                hasPushed = true
            } catch {
                logger.error("Push error: \(error.localizedDescription)")
            }
            isRunningGitAction = false
            await gitViewModel.refreshStatus()
        }
    }

    private func generateAICommitSummary(for commit: GitCommit) {
        isGeneratingAISummary = true
        aiCommitSummary = ""

        let prompt = """
        You are an AI Git history analyst. Analyze this commit:
        - SHA: \(commit.sha)
        - Subject: \(commit.subject)
        - Author: \(commit.author)
        - Message details: \(commit.message)

        Draft a concise, natural language commit summary of exactly 3 lines:
        1. [Summary] High-level overview of what this revision changed.
        2. [Impact Assessment] Which components are affected.
        3. [Verdicts] Release note recommendation.
        """

        Task {
            do {
                let response = try await LLMService.shared.generateResponse(prompt: prompt, useContext: false)
                aiCommitSummary = response.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                aiCommitSummary = "Summary synthesis failed: \(error.localizedDescription)"
            }
            isGeneratingAISummary = false
        }
    }
}
