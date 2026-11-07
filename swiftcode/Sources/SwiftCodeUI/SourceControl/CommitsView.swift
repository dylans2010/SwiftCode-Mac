import SwiftUI
import os.log
import SwiftCodeAssistant
import SwiftCodeSDK
import SwiftCodeSubprocess

private let logger = Logger(subsystem: "com.swiftcode.SourceControl", category: "CommitsView")

private extension GitCommit {
    var subject: String { message.components(separatedBy: "\n").first ?? message }
    var sha: String { hash }
    var author: String { authorName }
    var email: String { authorEmail }
    var dateString: String { Self.dateFormatter.string(from: date) }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct ChangedFileStat: Sendable {
    let path: String
    let additions: Int?
    let deletions: Int?
}

@MainActor
struct CommitsView: View {
    var gitViewModel: GitViewModel

    @State private var selectedCommitID: String?
    @State private var searchKeyword = ""
    @State private var selectedAuthor = ""
    @State private var fileFilterPath = ""
    @State private var dateFilterEnabled = false
    @State private var dateFilterStart = Date().addingTimeInterval(-2592000)
    @State private var dateFilterEnd = Date()

    @State private var isCompareMode = false
    @State private var compareStartSHA = ""
    @State private var compareEndSHA = ""
    @State private var generatedDiffOutput = ""
    @State private var isGeneratingDiff = false

    @State private var aiCommitSummary = ""
    @State private var isGeneratingAISummary = false
    @State private var inspectorTab = 0

    @State private var isRunningGitAction = false
    @State private var gitActionProgress = ""
    @State private var gitActionLog = ""
    @State private var showRollbackSuccess = false
    @State private var hasPushed = false

    @State private var visibleCommitsLimit = 20

    @State private var changedFiles: [ChangedFileStat] = []
    @State private var changedFilesError: String?
    @State private var isLoadingChangedFiles = false

    private var changedFilesSummary: String {
        let totalAdds = changedFiles.compactMap(\.additions).reduce(0, +)
        let totalDels = changedFiles.compactMap(\.deletions).reduce(0, +)
        let binaryCount = changedFiles.count(where: { $0.additions == nil || $0.deletions == nil })
        let fileWord = changedFiles.count == 1 ? "File" : "Files"
        var summary = "\(changedFiles.count) \(fileWord) changed  •  +\(totalAdds) additions  •  -\(totalDels) deletions"
        if binaryCount > 0 { summary += "  •  \(binaryCount) binary" }
        return summary
    }

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
            VStack(spacing: 0) {
                filtersHeaderView

                Divider()

                if isCompareMode {
                    compareRangeHeaderView
                    Divider()
                }

                commitListWithGraphView
            }
            .frame(minWidth: 450, maxWidth: .infinity)
            .layoutPriority(1)

            commitInspectorView
                .frame(minWidth: 260, idealWidth: 320, maxWidth: 450)
                .layoutPriority(2)
        }
        .onAppear {
            if selectedCommitID == nil {
                selectedCommitID = gitViewModel.history.first?.sha
            }
        }
        .task(id: selectedCommitID) {
            await loadChangedFiles(for: selectedCommitID)
        }
    }

    private var filtersHeaderView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Label("Commit Log", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                    .foregroundStyle(.purple)

                Spacer()

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
        .liquidGlass(style: .subtle, cornerRadius: 10)
    }

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
                                    Canvas { context, size in
                                        let h = size.height
                                        let w = size.width
                                        let midY = h / 2.0

                                        let mainLaneX: CGFloat = 16.0
                                        let secondaryLaneX: CGFloat = 36.0

                                        var path = Path()
                                        path.move(to: CGPoint(x: mainLaneX, y: 0))
                                        path.addLine(to: CGPoint(x: mainLaneX, y: h))
                                        context.stroke(path, with: .color(.purple), lineWidth: 2)

                                        if commit.parentHashes.count > 1 {
                                            var mergePath = Path()
                                            mergePath.move(to: CGPoint(x: mainLaneX, y: midY))
                                            mergePath.addQuadCurve(to: CGPoint(x: secondaryLaneX, y: h), control: CGPoint(x: secondaryLaneX, y: midY))
                                            context.stroke(mergePath, with: .color(.green), lineWidth: 2)

                                            context.fill(Path(ellipseIn: CGRect(x: secondaryLaneX - 4, y: h - 4, width: 8, height: 8)), with: .color(.green))
                                        }

                                        let circleRect = CGRect(x: mainLaneX - 5, y: midY - 5, width: 10, height: 10)
                                        let color: Color = isSelected ? .orange : .purple
                                        context.fill(Path(ellipseIn: circleRect), with: .color(color))

                                        if index == 0 {
                                            let outerRing = CGRect(x: mainLaneX - 8, y: midY - 8, width: 16, height: 16)
                                            context.stroke(Path(ellipseIn: outerRing), with: .color(.orange), lineWidth: 1.5)
                                        }
                                    }
                                    .frame(width: 50, height: 44)

                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(spacing: 8) {
                                            Text(commit.subject)
                                                .font(.subheadline.bold())
                                                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                                                .lineLimit(1)

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

    private var commitInspectorView: some View {
        ScrollView {
            if let targetSHA = selectedCommitID,
               let commit = gitViewModel.history.first(where: { $0.sha == targetSHA }) {
                VStack(alignment: .leading, spacing: 16) {
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

                    Picker("Category", selection: $inspectorTab) {
                        Text("Stats").tag(0)
                        Text("AI Analyst").tag(1)
                        Text("Safety Actions").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Divider()

                    if inspectorTab == 0 {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Author").font(.caption).foregroundStyle(.secondary)
                                Text(commit.author).bold()
                                Text(commit.email)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }

                            Divider()

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

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Changed Files Stats").font(.caption).foregroundStyle(.secondary)
                                if isLoadingChangedFiles {
                                    HStack(spacing: 6) {
                                        ProgressView().controlSize(.small)
                                        Text("Loading changed files…").font(.caption).foregroundStyle(.secondary)
                                    }
                                } else if let error = changedFilesError {
                                    Text(error).font(.caption).foregroundStyle(.red)
                                } else if changedFiles.isEmpty {
                                    Text("No files changed in this commit.").font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Text(changedFilesSummary).font(.caption.bold())
                                    VStack(alignment: .leading, spacing: 6) {
                                        ForEach(changedFiles, id: \.path) { file in
                                            changedFileRow(path: file.path, adds: file.additions, dels: file.deletions)
                                        }
                                    }
                                }
                            }

                            Divider()

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
                        }
                    } else if inspectorTab == 1 {
                        VStack(alignment: .leading, spacing: 12) {
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
                    } else {
                        rollbackControlSection(for: commit)
                    }
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

    private func changedFileRow(path: String, adds: Int?, dels: Int?) -> some View {
        HStack {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            Text((path as NSString).lastPathComponent)
                .font(.system(size: 11, design: .monospaced))
                .lineLimit(1)
            Spacer()
            if let adds, let dels {
                HStack(spacing: 6) {
                    Text("+\(adds)").foregroundStyle(.green).font(.caption2.bold())
                    Text("-\(dels)").foregroundStyle(.red).font(.caption2.bold())
                }
            } else {
                Text("binary").foregroundStyle(.secondary).font(.caption2.bold())
            }
        }
        .padding(4)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(4)
        .help(path)
    }

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

    private func loadChangedFiles(for sha: String?) async {
        guard let sha,
              let commit = gitViewModel.history.first(where: { $0.sha == sha }),
              let repo = gitViewModel.repositoryURL else {
            changedFiles = []
            changedFilesError = sha == nil ? nil : "No repository selected."
            isLoadingChangedFiles = false
            return
        }
        isLoadingChangedFiles = true
        changedFilesError = nil
        let gitPath = AppSettings.shared.gitPath.isEmpty ? "/usr/bin/git" : AppSettings.shared.gitPath
        let parent = commit.parentHashes.first
        let outcome = await Task.detached(priority: .userInitiated) { () -> (files: [ChangedFileStat], error: String?) in
            do {
                let args: [String]
                if let parent {
                    args = ["diff", "--numstat", parent, sha]
                } else {
                    args = ["show", "--numstat", "--format=", "--root", sha]
                }
                let output = try Subprocess.run(gitPath, args, currentDirectory: repo)
                guard output.status == 0 else {
                    let detail = output.stderrText.trimmingCharacters(in: .whitespacesAndNewlines)
                    return ([], detail.isEmpty ? "git exited with status \(output.status)." : detail)
                }
                let rows = output.stdoutText.split(separator: "\n").compactMap { line -> ChangedFileStat? in
                    let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
                    guard parts.count >= 3 else { return nil }
                    let adds = parts[0] == "-" ? nil : Int(parts[0])
                    let dels = parts[1] == "-" ? nil : Int(parts[1])
                    let path = parts[2...].joined(separator: "\t")
                    return ChangedFileStat(path: path, additions: adds, deletions: dels)
                }
                return (rows, nil)
            } catch {
                return ([], error.localizedDescription)
            }
        }.value
        guard !Task.isCancelled else { return }
        changedFiles = outcome.files
        changedFilesError = outcome.error
        isLoadingChangedFiles = false
    }

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
                let result = try Subprocess.run(
                    gitBinary.path,
                    ["diff", "\(compareStartSHA)..\(compareEndSHA)", "--stat"],
                    currentDirectory: proj
                )
                generatedDiffOutput = result.status == 0 ? result.stdoutText : "Failed comparison:\n\(result.stderrText)"
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
                let response = try await LLMService.shared.generateExternalResponse(prompt: prompt, useContext: false)
                aiCommitSummary = response.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                aiCommitSummary = "Summary synthesis failed: \(error.localizedDescription)"
            }
            isGeneratingAISummary = false
        }
    }
}
