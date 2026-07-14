import SwiftUI

@MainActor
struct RepositoryDashboardView: View {
    var gitViewModel: GitViewModel
    let project: Project?
    var onNavigateToSection: (GitHubSidebarItem) -> Void

    @State private var quickCommitMsg = ""
    @State private var isRunningQuickAction = false
    @State private var quickActionLog = ""

    // Suggestion structure representing actionable advice
    struct DashboardSuggestion: Identifiable {
        let id = UUID()
        let title: String
        let description: String
        let icon: String
        let accentColor: Color
        let actionLabel: String
        let action: () -> Void
    }

    private var activeSuggestions: [DashboardSuggestion] {
        var list: [DashboardSuggestion] = []

        // 1. Uncommitted changes suggestion
        let filesCount = gitViewModel.status?.files.count ?? 0
        if filesCount > 0 {
            list.append(
                DashboardSuggestion(
                    title: "Uncommitted Changes Detected",
                    description: "You have \(filesCount) modified file\(filesCount > 1 ? "s" : "") in your workspace. Build and record a commit to avoid losing your progress.",
                    icon: "pencil.and.outline",
                    accentColor: .orange,
                    actionLabel: "Commit Composer",
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
                    description: "Your workspace is \(aheadCount) commit\(aheadCount > 1 ? "s" : "") ahead of the remote repository branch. Push your commits to remote origin to share.",
                    icon: "arrow.up.circle.fill",
                    accentColor: .blue,
                    actionLabel: "Push to Remote",
                    action: { onNavigateToSection(.actions) }
                )
            )
        }

        // 3. No connected remote upstream suggestion
        let connectedRepo = project?.githubRepo ?? ""
        if connectedRepo.isEmpty {
            list.append(
                DashboardSuggestion(
                    title: "No Remote Repository Configured",
                    description: "Sync code with a GitHub remote to enable actions, pull requests, release packaging, and automatic backups.",
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
                    title: "Workspace is Fully Healthy & Clean",
                    description: "Your local branches are fully synchronized and there are no uncommitted changes. Run local workflows or perform code reviews.",
                    icon: "checkmark.shield.fill",
                    accentColor: .green,
                    actionLabel: "Run Workflows",
                    action: { onNavigateToSection(.dashboard) } // In SourceControlView we map .dashboard -> local workspace / workflows
                )
            )
        }

        return list
    }

    var body: some View {
        List {
            // Section 1: Dashboard Welcome Header
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Repository Command Center")
                        .font(.title2.bold())
                    Text("High-fidelity workspace monitor for repository health, commit history, branch tracking, and DevOps actions.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
            .listRowSeparator(.hidden)

            // Section 2: AI-Powered Smart Suggestions
            Section(header: Text("AI-Powered Smart Suggestions").font(.caption.bold()).foregroundStyle(.blue)) {
                ForEach(activeSuggestions) { suggestion in
                    HStack(spacing: 16) {
                        Image(systemName: suggestion.icon)
                            .font(.title2)
                            .foregroundStyle(suggestion.accentColor)
                            .frame(width: 40, height: 40)
                            .background(suggestion.accentColor.opacity(0.1))
                            .cornerRadius(8)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(suggestion.title)
                                .font(.headline)
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
                    .padding(.vertical, 8)
                }
            }

            // Section 3: Project Overview & Status Feed
            Section(header: Text("Repository Status & Health Feed").font(.caption.bold()).foregroundStyle(.green)) {
                let filesCount = gitViewModel.status?.files.count ?? 0
                healthRow(
                    title: "Working Copy Status",
                    subtitle: filesCount == 0 ? "Clean State" : "\(filesCount) Modified Files",
                    isHealthy: filesCount == 0,
                    systemImage: "checkmark.circle.fill",
                    unhealthImage: "exclamationmark.triangle.fill",
                    healthyColor: .green,
                    unhealthyColor: .orange
                )

                let ahead = gitViewModel.status?.ahead ?? 0
                healthRow(
                    title: "Synchronize Balance",
                    subtitle: ahead == 0 ? "Up to Date" : "\(ahead) Commits Ahead",
                    isHealthy: ahead == 0,
                    systemImage: "cloud.checkmark.fill",
                    unhealthImage: "arrow.up.circle.fill",
                    healthyColor: .blue,
                    unhealthyColor: .orange
                )

                let hasRemote = !(project?.githubRepo ?? "").isEmpty
                healthRow(
                    title: "Remote Upstream Origin",
                    subtitle: hasRemote ? "Connected" : "No Upstream Target",
                    isHealthy: hasRemote,
                    systemImage: "link.circle.fill",
                    unhealthImage: "link.badge.plus",
                    healthyColor: .green,
                    unhealthyColor: .yellow
                )

                if let repo = project?.githubRepo, !repo.isEmpty {
                    HStack {
                        Image(systemName: "link")
                            .foregroundStyle(.secondary)
                        Text("Linked GitHub Repository")
                            .font(.subheadline)
                        Spacer()
                        Text(repo)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.blue)
                    }
                }
            }

            // Section 4: Quick Actions Hub
            Section(header: Text("Quick Actions Hub").font(.caption.bold()).foregroundStyle(.orange)) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Execute common Git operations instantly from the active working directory context.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 12) {
                        Button {
                            runQuickPull()
                        } label: {
                            Label("Pull Remote", systemImage: "arrow.down.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRunningQuickAction)

                        Button {
                            runQuickStageAll()
                        } label: {
                            Label("Stage All", systemImage: "plus.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRunningQuickAction)

                        Button(role: .destructive) {
                            runQuickDiscardAll()
                        } label: {
                            Label("Discard All", systemImage: "trash.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRunningQuickAction)
                    }

                    if !quickActionLog.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Execution Log Output:")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(.secondary)
                            ScrollView {
                                Text(quickActionLog)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.black.opacity(0.2))
                                    .cornerRadius(6)
                            }
                            .frame(height: 100)
                        }
                        .padding(.top, 4)
                    }
                }
                .padding(.vertical, 6)
            }

            // Section 5: Stats Explorer
            Section(header: Text("Status & Statistics").font(.caption.bold()).foregroundStyle(.purple)) {
                statRow(
                    icon: "arrow.triangle.branch",
                    title: "Current Branch",
                    value: gitViewModel.status?.branchName ?? "main",
                    actionTitle: "Manage"
                ) {
                    onNavigateToSection(.branches)
                }

                statRow(
                    icon: "doc.text.fill",
                    title: "Working Directory",
                    value: "\(gitViewModel.status?.files.count ?? 0) Modified Files",
                    actionTitle: "View Changes"
                ) {
                    onNavigateToSection(.repositories)
                }

                statRow(
                    icon: "clock.arrow.circlepath",
                    title: "Commit History",
                    value: "\(gitViewModel.history.count) Local Commits",
                    actionTitle: "Explore"
                ) {
                    onNavigateToSection(.commits)
                }

                statRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Synchronization",
                    value: "\(gitViewModel.status?.ahead ?? 0) Ahead / \(gitViewModel.status?.behind ?? 0) Behind",
                    actionTitle: "Sync Portal"
                ) {
                    onNavigateToSection(.actions)
                }
            }

            // Section 6: Recent Commits Feed
            Section(header: Text("Recent Commit History").font(.caption.bold()).foregroundStyle(.yellow)) {
                if gitViewModel.history.isEmpty {
                    ContentUnavailableView {
                        Label("No Commit History", systemImage: "clock.arrow.circlepath")
                            .font(.title2)
                    } description: {
                        Text("No local or remote commits have been parsed for this repository branch.")
                            .font(.caption)
                    }
                } else {
                    ForEach(gitViewModel.history.prefix(5)) { commit in
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(commit.subject)
                                    .font(.subheadline.bold())
                                    .lineLimit(1)
                                Text("\(commit.author) • \(commit.dateString)")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()

                            Button {
                                let board = NSPasteboard.general
                                board.clearContents()
                                board.setString(commit.sha, forType: .string)
                            } label: {
                                HStack(spacing: 4) {
                                    Text(String(commit.sha.prefix(7)))
                                        .font(.system(.caption, design: .monospaced))
                                    Image(systemName: "doc.on.doc")
                                        .font(.system(size: 9))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.12))
                                .cornerRadius(4)
                            }
                            .buttonStyle(.plain)
                            .help("Copy full SHA")
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Helper Views

    private func healthRow(
        title: String,
        subtitle: String,
        isHealthy: Bool,
        systemImage: String,
        unhealthImage: String,
        healthyColor: Color,
        unhealthyColor: Color
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill((isHealthy ? healthyColor : unhealthyColor).opacity(0.15))
                    .frame(width: 28, height: 28)
                Image(systemName: isHealthy ? systemImage : unhealthImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(isHealthy ? healthyColor : unhealthyColor)
            }

            Text(title)
                .font(.subheadline.bold())

            Spacer()

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(isHealthy ? Color.secondary : unhealthyColor)
        }
        .padding(.vertical, 2)
    }

    private func statRow(
        icon: String,
        title: String,
        value: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.subheadline.bold())
            }

            Spacer()

            Button(action: action) {
                Text(actionTitle)
                    .font(.caption2.bold())
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Quick Actions Implementations

    private func runQuickPull() {
        guard let proj = project else { return }
        isRunningQuickAction = true
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
            isRunningQuickAction = false
        }
    }

    private func runQuickStageAll() {
        guard let proj = project else { return }
        isRunningQuickAction = true
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
            isRunningQuickAction = false
        }
    }

    private func runQuickDiscardAll() {
        guard let proj = project else { return }
        isRunningQuickAction = true
        quickActionLog = "Discarding all uncommitted changes..."
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
            isRunningQuickAction = false
        }
    }
}
