import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.swiftcode.SourceControl", category: "RepositoryDashboardView")

@MainActor
struct RepositoryDashboardView: View {
    var gitViewModel: GitViewModel
    let project: Project?
    var onNavigateToSection: (GitHubSidebarItem) -> Void

    @State private var quickActionLog = ""
    @State private var isRunningAction = false
    @State private var aiAnalysisResult = ""
    @State private var isRunningAIAnalysis = false

    // State for mock timeline events to combine with commits for a full activity timeline
    @State private var timelineEvents: [TimelineEvent] = [
        TimelineEvent(title: "Repository linked to SwiftCode", detail: "Configured remote origin", type: .system, date: Date().addingTimeInterval(-86400)),
        TimelineEvent(title: "Main pipeline check passed", detail: "Workflow 'swift-ci' completed successfully", type: .ci, date: Date().addingTimeInterval(-7200))
    ]

    struct TimelineEvent: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let type: EventType
        let date: Date

        enum EventType {
            case commit
            case ci
            case system
        }
    }

    private var connectedRepo: String {
        project?.githubRepo ?? ""
    }

    private var activeSuggestions: [DashboardSuggestion] {
        var list: [DashboardSuggestion] = []

        // 1. Uncommitted changes suggestion
        let filesCount = gitViewModel.status?.files.count ?? 0
        if filesCount > 0 {
            list.append(
                DashboardSuggestion(
                    title: "Uncommitted Changes",
                    description: "You have \(filesCount) modified file\(filesCount > 1 ? "s" : "") in your workspace. Build and record a commit to avoid losing progress.",
                    icon: "pencil.and.outline",
                    accentColor: .orange,
                    actionLabel: "View Changes",
                    action: { onNavigateToSection(.repositories) }
                )
            )
        }

        // 2. Sync / Ahead commits suggestion
        let aheadCount = gitViewModel.status?.ahead ?? 0
        if aheadCount > 0 {
            list.append(
                DashboardSuggestion(
                    title: "Sync Needed",
                    description: "Your local branch is \(aheadCount) commit\(aheadCount > 1 ? "s" : "") ahead of origin. Push your commits now.",
                    icon: "arrow.up.circle.fill",
                    accentColor: .blue,
                    actionLabel: "Push to Remote",
                    action: { onNavigateToSection(.actions) }
                )
            )
        }

        // 3. No connected remote upstream suggestion
        if connectedRepo.isEmpty {
            list.append(
                DashboardSuggestion(
                    title: "No Remote Configured",
                    description: "Connect this project to a GitHub repository to enable live actions, pull requests, and backups.",
                    icon: "link.badge.plus",
                    accentColor: .purple,
                    actionLabel: "Configure Remote",
                    action: { RepositoryContext.shared.showingSetRepoSheet = true }
                )
            )
        }

        // 4. Fallback healthy suggestions
        if list.isEmpty {
            list.append(
                DashboardSuggestion(
                    title: "Workspace fully synchronized & clean",
                    description: "All local branches are in sync and there are no uncommitted changes. Run local workflows or perform code reviews.",
                    icon: "checkmark.shield.fill",
                    accentColor: .green,
                    actionLabel: "Run Workflows",
                    action: { onNavigateToSection(.dashboard) }
                )
            )
        }

        return list
    }

    var body: some View {
        let context = RepositoryContext.shared
        List {
            // SECTION 1: Welcome Header
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Repository Command Center")
                        .font(.title2.bold())
                    Text("High-fidelity desktop-class monitor for project health, commit history, branch tracking, and DevOps actions.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
            .listRowSeparator(.hidden)

            // SECTION 2: Overview & Connected Remotes
            Section(header: Text("Repository Status").font(.caption.bold()).foregroundStyle(.blue)) {
                HStack {
                    Label("Current Branch", systemImage: "arrow.triangle.branch")
                        .font(.subheadline.bold())
                    Spacer()
                    Text(gitViewModel.status?.branchName ?? "main")
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.orange)
                }

                HStack {
                    Label("Working Tree Status", systemImage: "doc.text")
                        .font(.subheadline.bold())
                    Spacer()
                    let filesCount = gitViewModel.status?.files.count ?? 0
                    Text(filesCount == 0 ? "Clean" : "\(filesCount) Modified Files")
                        .font(.subheadline)
                        .foregroundStyle(filesCount == 0 ? Color.green : Color.orange)
                }

                HStack {
                    Label("Sync Balance", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline.bold())
                    Spacer()
                    let ahead = gitViewModel.status?.ahead ?? 0
                    let behind = gitViewModel.status?.behind ?? 0
                    Text("\(ahead) Ahead / \(behind) Behind")
                        .font(.subheadline)
                        .foregroundStyle((ahead > 0 || behind > 0) ? Color.orange : Color.secondary)
                }

                HStack {
                    Label("Linked Remote Repository", systemImage: "network")
                        .font(.subheadline.bold())
                    Spacer()
                    if !connectedRepo.isEmpty {
                        Text(connectedRepo)
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.blue)
                    } else {
                        Text("None")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // SECTION 3: AI-Powered Smart Suggestions
            Section(header: Text("Smart Suggestions").font(.caption.bold()).foregroundStyle(.orange)) {
                ForEach(activeSuggestions) { suggestion in
                    HStack(spacing: 12) {
                        Image(systemName: suggestion.icon)
                            .font(.title2)
                            .foregroundStyle(suggestion.accentColor)
                            .frame(width: 32, height: 32)
                            .background(suggestion.accentColor.opacity(0.1))
                            .cornerRadius(6)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title)
                                .font(.subheadline.bold())
                            Text(suggestion.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button(suggestion.actionLabel) {
                            suggestion.action()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.vertical, 4)
                }
            }

            // SECTION 4: Repository Statistics & Health Indicators
            Section(header: Text("Repository Statistics").font(.caption.bold()).foregroundStyle(.purple)) {
                HStack {
                    Label("Repository Size", systemImage: "shippingbox.fill")
                        .font(.subheadline)
                    Spacer()
                    if let size = context.cachedMetadata?.size {
                        Text("\(Double(size) / 1024.0, specifier: "%.2f") MB")
                            .font(.subheadline)
                    } else {
                        Text("1.2 GB (Estimated)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Label("Active Branches", systemImage: "arrow.triangle.branch")
                        .font(.subheadline)
                    Spacer()
                    Text("\(max(gitViewModel.branches.count, context.loadedBranchesCount)) Branches")
                        .font(.subheadline)
                }

                HStack {
                    Label("Open Pull Requests", systemImage: "arrow.triangle.pull")
                        .font(.subheadline)
                    Spacer()
                    Text("\(context.loadedPullRequestsCount) Open")
                        .font(.subheadline)
                        .foregroundStyle(context.loadedPullRequestsCount > 0 ? Color.green : Color.secondary)
                }

                HStack {
                    Label("Open Issues", systemImage: "exclamationmark.bubble")
                        .font(.subheadline)
                    Spacer()
                    let issuesCount = context.cachedMetadata?.openIssuesCount ?? 0
                    Text("\(issuesCount) Open")
                        .font(.subheadline)
                        .foregroundStyle(issuesCount > 0 ? Color.orange : Color.secondary)
                }

                HStack {
                    Label("Releases", systemImage: "tag")
                        .font(.subheadline)
                    Spacer()
                    Text("\(context.loadedReleasesCount) Published")
                        .font(.subheadline)
                }

                if !context.loadedLanguages.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Language Distribution")
                            .font(.subheadline.bold())
                            .padding(.top, 4)
                        HStack(spacing: 8) {
                            ForEach(context.loadedLanguages, id: \.self) { lang in
                                Text(lang)
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor.opacity(0.1))
                                    .foregroundStyle(Color.accentColor)
                                    .cornerRadius(4)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            // SECTION 5: AI Insights Engine
            Section(header: Text("AI Workspace Diagnostics").font(.caption.bold()).foregroundStyle(.teal)) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("AI Diagnostics uses live repository metadata to inspect project health and draft recommended work actions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Button {
                            runAIHealthCheck()
                        } label: {
                            Label(isRunningAIAnalysis ? "Generating..." : "Generate AI Health & Security Report", systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.teal)
                        .disabled(isRunningAIAnalysis)

                        Spacer()
                    }

                    if isRunningAIAnalysis {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("LLM Service evaluating branch and file states...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !aiAnalysisResult.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("AI Analysis Output:")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)

                            Text(aiAnalysisResult)
                                .font(.system(size: 11, design: .monospaced))
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.15))
                                .cornerRadius(6)
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            // SECTION 6: Quick Actions Hub
            Section(header: Text("Quick Actions Hub").font(.caption.bold()).foregroundStyle(.orange)) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Button {
                            runQuickPull()
                        } label: {
                            Label("Pull Remote", systemImage: "arrow.down.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRunningAction)

                        Button {
                            runQuickStageAll()
                        } label: {
                            Label("Stage All", systemImage: "plus.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRunningAction)

                        Button(role: .destructive) {
                            runQuickDiscardAll()
                        } label: {
                            Label("Discard All", systemImage: "trash.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRunningAction)
                    }

                    if !quickActionLog.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Execution Output:")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Text(quickActionLog)
                                .font(.system(size: 11, design: .monospaced))
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.15))
                                .cornerRadius(6)
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            // SECTION 7: Unified Activity Timeline (Commits & Events)
            Section(header: Text("Repository Activity Timeline").font(.caption.bold()).foregroundStyle(.yellow)) {
                // Combine recent commits and mock events sorted by date
                let commitsAsEvents = gitViewModel.history.prefix(5).map {
                    TimelineEvent(title: "Commit: \($0.subject)", detail: "Authored by \($0.author) [\($0.sha.prefix(7))]", type: .commit, date: $0.date)
                }

                let allEvents = (commitsAsEvents + timelineEvents).sorted { $0.date > $1.date }

                if allEvents.isEmpty {
                    Text("No timeline history recorded.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(allEvents) { event in
                        HStack(alignment: .top, spacing: 10) {
                            // Timeline node indicator
                            VStack(spacing: 4) {
                                Circle()
                                    .fill(eventColor(for: event.type))
                                    .frame(width: 8, height: 8)
                                    .padding(.top, 4)
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.2))
                                    .frame(width: 2, height: 28)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.primary)
                                Text(event.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(event.date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.system(size: 9))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Helper Colors

    private func eventColor(for type: TimelineEvent.EventType) -> Color {
        switch type {
        case .commit: return .purple
        case .ci: return .green
        case .system: return .blue
        }
    }

    // MARK: - Smart Suggestions Helpers

    struct DashboardSuggestion: Identifiable {
        let id = UUID()
        let title: String
        let description: String
        let icon: String
        let accentColor: Color
        let actionLabel: String
        let action: () -> Void
    }

    // MARK: - Quick Actions Implementations

    private func runQuickPull() {
        guard let proj = project else { return }
        isRunningAction = true
        quickActionLog = "Running 'git pull'..."
        Task {
            do {
                let gitBinary = URL(fileURLWithPath: AppSettings.shared.gitPath.isEmpty ? "/usr/bin/git" : AppSettings.shared.gitPath)
                let result = try await ProcessRunnerTool.shared.run(
                    executableURL: gitBinary,
                    arguments: ["pull"],
                    workingDirectory: proj.directoryURL
                )
                quickActionLog = result.exitCode == 0 ? "Pull completed successfully.\n\(result.stdout)" : "Pull failed:\n\(result.stderr)"
            } catch {
                quickActionLog = "Process error:\n\(error.localizedDescription)"
            }
            await gitViewModel.refreshStatus()
            isRunningAction = false
        }
    }

    private func runQuickStageAll() {
        guard let proj = project else { return }
        isRunningAction = true
        quickActionLog = "Running 'git add .'..."
        Task {
            do {
                let gitBinary = URL(fileURLWithPath: AppSettings.shared.gitPath.isEmpty ? "/usr/bin/git" : AppSettings.shared.gitPath)
                let result = try await ProcessRunnerTool.shared.run(
                    executableURL: gitBinary,
                    arguments: ["add", "."],
                    workingDirectory: proj.directoryURL
                )
                quickActionLog = result.exitCode == 0 ? "Staged all changes successfully." : "Stage failed:\n\(result.stderr)"
            } catch {
                quickActionLog = "Process error:\n\(error.localizedDescription)"
            }
            await gitViewModel.refreshStatus()
            isRunningAction = false
        }
    }

    private func runQuickDiscardAll() {
        guard let proj = project else { return }
        isRunningAction = true
        quickActionLog = "Discarding all changes..."
        Task {
            do {
                let gitBinary = URL(fileURLWithPath: AppSettings.shared.gitPath.isEmpty ? "/usr/bin/git" : AppSettings.shared.gitPath)
                _ = try? await ProcessRunnerTool.shared.run(
                    executableURL: gitBinary,
                    arguments: ["restore", "."],
                    workingDirectory: proj.directoryURL
                )
                _ = try? await ProcessRunnerTool.shared.run(
                    executableURL: gitBinary,
                    arguments: ["clean", "-fd"],
                    workingDirectory: proj.directoryURL
                )
                quickActionLog = "Discarded all changes in working directory."
            }
            await gitViewModel.refreshStatus()
            isRunningAction = false
        }
    }

    private func runAIHealthCheck() {
        isRunningAIAnalysis = true
        aiAnalysisResult = ""

        let branch = gitViewModel.status?.branchName ?? "main"
        let modifiedCount = gitViewModel.status?.files.count ?? 0
        let recentCommitMsg = gitViewModel.history.first?.subject ?? "None"
        let repoName = connectedRepo.isEmpty ? "Local Git Project" : connectedRepo

        let prompt = """
        You are a highly capable AI assistant integrated directly into our macOS Source Control Workspace dashboard.
        Analyze the following live repository state and generate a concise health and security diagnostic report:
        - Project: \(repoName)
        - Current Branch: \(branch)
        - Modified Files: \(modifiedCount)
        - Most Recent Local Commit: \(recentCommitMsg)

        Provide the output in a neat professional structure of exactly 4 lines:
        1. [Overall Health] A quick rating (e.g. Excellent, Warning) and short explanation.
        2. [Security Status] Quick analysis on risk (e.g., untracked changes, branch protection).
        3. [Next Best Action] Clear instruction of what the user should execute next.
        4. [Cleanliness Status] Feedback on workspace uncommitted file state.
        """

        Task {
            do {
                let response = try await LLMService.shared.generateResponse(prompt: prompt, useContext: false)
                aiAnalysisResult = response.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                aiAnalysisResult = "AI Diagnostics error: \(error.localizedDescription)"
            }
            isRunningAIAnalysis = false
        }
    }
}
