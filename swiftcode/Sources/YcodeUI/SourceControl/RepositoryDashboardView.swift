import SwiftCodeGitHub
import YcodeIDECore
import YcodeSubprocess
import SwiftUI

@MainActor
public struct RepositoryDashboardView: View {
    public var repository: GitRepository
    public var client: GitHubClient?
    public var remote: (owner: String, repo: String)?
    public var aiAnalysis: ((String) async throws -> String)?
    public var onNavigateToSection: (GitHubSidebarItem) -> Void

    @State private var status: [String: GitRepository.FileStatus] = [:]
    @State private var aheadBehind: (ahead: Int, behind: Int)?
    @State private var localBranches: [String] = []
    @State private var recentCommits: [GitRepository.Commit] = []
    @State private var remoteRepo: GitHubRepository?
    @State private var remoteBranches: [GitHubBranch] = []
    @State private var openPullRequests = 0
    @State private var openIssues = 0
    @State private var releases: [GitHubRelease] = []
    @State private var languages: [String] = []
    @State private var workflowRuns: [SwiftCodeGitHub.GitHubWorkflowRun] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var aiReport = ""
    @State private var isRunningAI = false
    @State private var showDiscardConfirm = false
    @State private var actionMessage: String?

    public init(
        repository: GitRepository,
        client: GitHubClient? = nil,
        remote: (owner: String, repo: String)? = nil,
        aiAnalysis: ((String) async throws -> String)? = nil,
        onNavigateToSection: @escaping (GitHubSidebarItem) -> Void = { _ in }
    ) {
        self.repository = repository
        self.client = client
        self.remote = remote
        self.aiAnalysis = aiAnalysis
        self.onNavigateToSection = onNavigateToSection
    }

    private var currentBranch: String { repository.currentBranch() ?? "HEAD" }
    private var changedCount: Int { status.count }
    private var contributors: [String] {
        Array(Set(recentCommits.map(\.authorName))).sorted()
    }
    private var topAuthorShare: Double {
        guard !recentCommits.isEmpty else { return 0 }
        let counts = Dictionary(grouping: recentCommits, by: \.authorName).mapValues(\.count)
        let top = counts.values.max() ?? 0
        return Double(top) / Double(recentCommits.count)
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                welcomeHeader
                statusSection
                suggestionsSection
                statisticsSection
                aiDiagnosticsSection
                quickActionsSection
                timelineSection
                if let errorMessage {
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }
            .padding(20)
        }
        .task { await load() }
    }

    private var welcomeHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(repository.root.lastPathComponent)
                .font(.title2.bold())
            Text("Branch \(currentBranch) · \(repository.root.path)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Repository Status")
                .font(.headline)
            HStack(spacing: 16) {
                statusChip(title: "Working tree", value: changedCount == 0 ? "Clean" : "\(changedCount) changed")
                if let aheadBehind {
                    statusChip(title: "Sync", value: "↑\(aheadBehind.ahead) ↓\(aheadBehind.behind)")
                }
                if let remote {
                    statusChip(title: "Remote", value: "\(remote.owner)/\(remote.repo)")
                } else {
                    statusChip(title: "Remote", value: "Not linked")
                }
            }
        }
    }

    private func statusChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.subheadline.bold())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    private var suggestionsSection: some View {
        let suggestions = smartSuggestions
        return VStack(alignment: .leading, spacing: 8) {
            Text("Smart Suggestions")
                .font(.headline)
            if suggestions.isEmpty {
                Text("Nothing needs attention.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(suggestions, id: \.self) { suggestion in
                    Label(suggestion, systemImage: "lightbulb")
                        .font(.subheadline)
                }
            }
        }
    }

    private var smartSuggestions: [String] {
        var out: [String] = []
        if changedCount > 0 {
            out.append("You have \(changedCount) uncommitted change(s) — commit them to keep the tree clean.")
        }
        if let aheadBehind {
            if aheadBehind.behind > 0 {
                out.append("This branch is \(aheadBehind.behind) commit(s) behind — pull to catch up.")
            }
            if aheadBehind.ahead > 0 {
                out.append("This branch is \(aheadBehind.ahead) commit(s) ahead — push to share your work.")
            }
        }
        if remote == nil {
            out.append("No remote is linked — add one to enable push, pull, and pull requests.")
        }
        return out
    }

    private var statisticsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Repository Statistics & Health")
                    .font(.headline)
                Spacer()
                Button("Branches") { onNavigateToSection(.branches) }
                    .buttonStyle(.borderless)
                Button("Pull Requests") { onNavigateToSection(.pullRequests) }
                    .buttonStyle(.borderless)
                Button("Releases") { onNavigateToSection(.releases) }
                    .buttonStyle(.borderless)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 10) {
                statCard(title: "Size", value: sizeText, subtitle: "Repository size")
                statCard(title: "Branches", value: "\(localBranches.count) local · \(remoteBranches.count) remote", subtitle: "All branches")
                statCard(title: "Pull Requests", value: "\(openPullRequests) open", subtitle: "On the remote")
                statCard(title: "Issues", value: "\(openIssues) open", subtitle: "On the remote")
                statCard(title: "Releases", value: "\(releases.count)", subtitle: "Published releases")
                statCard(title: "Languages", value: languages.prefix(3).joined(separator: ", ").isEmpty ? "—" : languages.prefix(3).joined(separator: ", "), subtitle: "Top languages")
                statCard(title: "Contributors", value: "\(contributors.count)", subtitle: "In recent history")
                statCard(title: "Code Ownership", value: topAuthorShare == 0 ? "—" : "\(Int(topAuthorShare * 100))% by top author", subtitle: "Recent commits")
            }
        }
    }

    private var sizeText: String {
        guard let size = remoteRepo?.size else { return "—" }
        if size >= 1024 {
            return String(format: "%.1f MB", Double(size) / 1024)
        }
        return "\(size) KB"
    }

    private func statCard(title: String, value: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.title3.bold()).lineLimit(1)
            Text(title).font(.caption).bold().foregroundStyle(.secondary)
            Text(subtitle).font(.system(size: 9)).foregroundStyle(.tertiary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .cornerRadius(8)
    }

    private var aiDiagnosticsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI Workspace Diagnostics")
                .font(.headline)
            Text("Generate a health report from the live repository state: branch, sync balance, uncommitted changes, open pull requests and issues, and recent commit activity.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                Task { await runAIDiagnostics() }
            } label: {
                Label(isRunningAI ? "Analysing…" : "Run AI Diagnostics", systemImage: "sparkles")
            }
            .buttonStyle(.borderedProminent)
            .disabled(aiAnalysis == nil || isRunningAI)
            .help(aiAnalysis == nil ? "AI diagnostics are not wired up — pass aiAnalysis to enable them." : "")
            if isRunningAI {
                ProgressView().controlSize(.small)
            }
            if !aiReport.isEmpty {
                Text(aiReport)
                    .font(.system(size: 11, design: .monospaced))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(6)
            }
        }
    }

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Actions")
                .font(.headline)
            HStack(spacing: 12) {
                Button("Pull") { Task { await quickAction("Pull") } }
                    .buttonStyle(.bordered)
                Button("Stage All") { Task { await quickAction("Stage All") } }
                    .buttonStyle(.bordered)
                Button("Discard All", role: .destructive) { showDiscardConfirm = true }
                    .buttonStyle(.bordered)
            }
            if let actionMessage {
                Text(actionMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .alert("Discard all uncommitted changes?", isPresented: $showDiscardConfirm) {
            Button("Discard All", role: .destructive) { Task { await quickAction("Discard All") } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This discards every uncommitted change and deletes untracked files. It cannot be undone.")
        }
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Activity Timeline")
                .font(.headline)
            ForEach(timelineEntries) { entry in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: entry.isCI ? "play.circle" : "clock.arrow.circlepath")
                        .foregroundStyle(entry.isCI ? .blue : .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title)
                            .font(.subheadline)
                            .lineLimit(1)
                        Text(entry.date, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 2)
            }
            if timelineEntries.isEmpty {
                Text("No recent activity.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var timelineEntries: [TimelineEntry] {
        var entries: [TimelineEntry] = recentCommits.map {
            TimelineEntry(id: "commit-\($0.hash)", title: $0.subject, date: $0.date, isCI: false)
        }
        entries += workflowRuns.map {
            TimelineEntry(id: "run-\($0.id)", title: "Workflow: \($0.name ?? "run") — \($0.statusSummary)", date: $0.updatedAt, isCI: true)
        }
        return entries.sorted { $0.date > $1.date }.prefix(30).map { $0 }
    }

    private struct TimelineEntry: Identifiable {
        var id: String
        var title: String
        var date: Date
        var isCI: Bool
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let repository = repository
        do {
            let (loadedStatus, loadedBranches, loadedCommits, loadedAheadBehind) = try await Task.detached {
                let status = try repository.status()
                let branches = (try? repository.branches().map(\.name)) ?? []
                let commits = repository.log(limit: 200)
                let aheadBehind = repository.aheadBehind(repository.currentBranch() ?? "HEAD")
                return (status, branches, commits, aheadBehind)
            }.value
            status = loadedStatus
            localBranches = loadedBranches
            recentCommits = loadedCommits
            aheadBehind = loadedAheadBehind
        } catch {
            errorMessage = error.localizedDescription
        }
        guard let client, let remote else { return }
        do {
            async let repo = client.getRepository(owner: remote.owner, repo: remote.repo)
            async let branches = client.listBranches(owner: remote.owner, repo: remote.repo, perPage: 100)
            async let prs = client.listPullRequests(owner: remote.owner, repo: remote.repo, state: "open", perPage: 1)
            async let issues = client.listIssues(owner: remote.owner, repo: remote.repo, state: "open", perPage: 1)
            async let releases = client.listReleases(owner: remote.owner, repo: remote.repo, perPage: 10)
            async let languages = client.listLanguages(owner: remote.owner, repo: remote.repo)
            async let runs = client.listWorkflowRuns(owner: remote.owner, repo: remote.repo, perPage: 10)
            remoteRepo = try await repo
            remoteBranches = try await branches
            openPullRequests = try await prs.count
            openIssues = try await issues.count
            self.releases = try await releases
            self.languages = try await languages
            workflowRuns = try await runs
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func runAIDiagnostics() async {
        guard let aiAnalysis else { return }
        isRunningAI = true
        defer { isRunningAI = false }
        let prompt = """
        Analyse this repository's health and report issues and next steps:
        - Branch: \(currentBranch); working tree: \(changedCount) changed file(s); ahead \(aheadBehind?.ahead ?? 0), behind \(aheadBehind?.behind ?? 0).
        - Remote: \(remote.map { "\($0.owner)/\($0.repo)" } ?? "none").
        - Open pull requests: \(openPullRequests); open issues: \(openIssues); releases: \(releases.count).
        - Contributors in recent history: \(contributors.count); top author share: \(Int(topAuthorShare * 100))%.
        - Recent commits: \(recentCommits.prefix(5).map(\.subject).joined(separator: "; ")).
        """
        do {
            aiReport = try await aiAnalysis(prompt)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func quickAction(_ action: String) async {
        let repository = repository
        actionMessage = nil
        do {
            switch action {
            case "Pull":
                try await Task.detached { try repository.pull() }.value
                actionMessage = "Pulled."
            case "Stage All":
                try await Task.detached { try repository.stageAll() }.value
                actionMessage = "Staged all changes."
            case "Discard All":
                let gitPath = GitRepository.resolvedGitPath()
                let root = repository.root
                try await Task.detached {
                    let status = try repository.status()
                    for (path, fileStatus) in status where fileStatus != .untracked {
                        try repository.discard(path)
                    }
                    _ = try Subprocess.run(gitPath, ["clean", "-fd"], currentDirectory: root)
                }.value
                actionMessage = "Discarded all changes."
            default:
                break
            }
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
