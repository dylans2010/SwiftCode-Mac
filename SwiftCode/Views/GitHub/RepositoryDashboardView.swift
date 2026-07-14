import SwiftUI

@MainActor
struct RepositoryDashboardView: View {
    var gitViewModel: GitViewModel
    let project: Project?
    var onNavigateToSection: (GitHubSidebarItem) -> Void

    @State private var quickCommitMsg = ""
    @State private var isRunningQuickAction = false
    @State private var quickActionLog = ""

    // Desktop Adaptive Grid Layout Columns
    private let columns = [GridItem(.adaptive(minimum: 320, maximum: 550), spacing: 20)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Dashboard Header
                VStack(alignment: .leading, spacing: 6) {
                    Text("Repository Command Center")
                        .font(.title2.bold())
                    Text("High-fidelity workspace monitor for repository health, commit history, branch tracking, and DevOps actions.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.bottom, 4)

                // Modular Widgets Layout Flow - Desktop Adaptive Grid
                LazyVGrid(columns: columns, spacing: 20) {
                    // 1. Overview Card
                    overviewCard

                    // 2. Health Indicators Section
                    healthIndicatorsCard

                    // 3. Quick Actions Widget
                    quickActionsCard

                    // 4. Status & Statistics Widget
                    statisticsCard

                    // 5. Recent Commits Widget
                    recentCommitsCard
                }
            }
            .padding(24)
        }
    }

    // MARK: - Widget Subviews

    private var overviewCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 16) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.title)
                        .foregroundStyle(.blue)
                        .frame(width: 44, height: 44)
                        .background(Color.blue.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(project?.name ?? "No Active Project")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if let repoName = project?.githubRepo, !repoName.isEmpty {
                            Text("Connected to Remote")
                                .font(.caption.bold())
                                .foregroundColor(.green)
                        } else {
                            Text("Local Workspace Only")
                                .font(.caption.bold())
                                .foregroundColor(.orange)
                        }
                    }
                    Spacer()
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    if let repo = project?.githubRepo, !repo.isEmpty {
                        Text("Linked GitHub Repository")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(repo)
                            .font(.system(.body, design: .monospaced))
                            .lineLimit(1)
                            .textSelection(.enabled)
                    } else {
                        Text("No Upstream Repository Associated")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Initialize a GitHub remote to synchronize code with origin branch trackers.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } label: {
            HStack {
                Label("Repository Connection", systemImage: "link")
                    .font(.headline)
                    .foregroundStyle(.blue)
            }
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }

    private var healthIndicatorsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
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
            }
        } label: {
            HStack {
                Label("Health Indicators", systemImage: "heart.text.square.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
            }
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }

    private var quickActionsCard: some View {
        GroupBox {
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
                        .frame(maxHeight: 120)
                    }
                    .padding(.top, 4)
                }
            }
        } label: {
            HStack {
                Label("Quick Developer Actions", systemImage: "bolt.circle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
            }
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }

    private var statisticsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
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
        } label: {
            HStack {
                Label("Status & Statistics", systemImage: "chart.bar.xaxis.ascending")
                    .font(.headline)
                    .foregroundStyle(.purple)
            }
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }

    private var recentCommitsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
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
                        if commit.id != gitViewModel.history.prefix(5).last?.id {
                            Divider()
                        }
                    }
                }
            }
        } label: {
            HStack {
                Label("Recent Commit History", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                    .foregroundStyle(.yellow)
            }
        }
        .groupBoxStyle(ModernGroupBoxStyle())
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
