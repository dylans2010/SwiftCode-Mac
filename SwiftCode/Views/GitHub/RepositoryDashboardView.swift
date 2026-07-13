import SwiftUI

@MainActor
struct RepositoryDashboardView: View {
    var gitViewModel: GitViewModel
    let project: Project?
    var onNavigateToSection: (GitHubSidebarItem) -> Void

    @State private var quickCommitMsg = ""
    @State private var isRunningQuickAction = false
    @State private var quickActionLog = ""

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Overview & Connected Remote Status Header
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Repository Command Center", systemImage: "macbook.and.iphone")
                                .font(.title2.bold())
                                .foregroundStyle(.blue)

                            Spacer()

                            if let repoName = project?.githubRepo, !repoName.isEmpty {
                                Text("Connected to Remote")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.12))
                                    .foregroundStyle(.green)
                                    .clipShape(Capsule())
                            } else {
                                Text("Local Workspace Only")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.12))
                                    .foregroundStyle(.orange)
                                    .clipShape(Capsule())
                            }
                        }

                        Text(project?.name ?? "No Active Project")
                            .font(.title3.bold())

                        if let repo = project?.githubRepo, !repo.isEmpty {
                            Text("Linked GitHub Repository: \(repo)")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Initialize a GitHub remote to synchronize with remote branches, manage issues, actions, and collaborate.")
                                .font(.body)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Repository Health Indicators Card
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Repository Health Indicators", systemImage: "heart.text.square.fill")
                            .font(.headline)
                            .foregroundStyle(.green)

                        Divider()

                        HStack(spacing: 20) {
                            let filesCount = gitViewModel.status?.files.count ?? 0
                            healthBadge(
                                title: "Working Copy",
                                subtitle: filesCount == 0 ? "Clean State" : "\(filesCount) Modified",
                                isHealthy: filesCount == 0,
                                systemImage: "checkmark.circle.fill",
                                unhealthImage: "exclamationmark.triangle.fill"
                            )

                            let ahead = gitViewModel.status?.ahead ?? 0
                            healthBadge(
                                title: "Sync Status",
                                subtitle: ahead == 0 ? "Up to Date" : "\(ahead) Commits Ahead",
                                isHealthy: ahead == 0,
                                systemImage: "cloud.checkmark.fill",
                                unhealthImage: "arrow.up.circle.fill"
                            )

                            let hasRemote = !(project?.githubRepo ?? "").isEmpty
                            healthBadge(
                                title: "Remote Origin",
                                subtitle: hasRemote ? "Connected" : "No Upstream",
                                isHealthy: hasRemote,
                                systemImage: "link.circle.fill",
                                unhealthImage: "link.badge.plus"
                            )
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Developer Dashboard Quick Actions
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Quick Developer Actions", systemImage: "bolt.horizontal.circle.fill")
                            .font(.headline)
                            .foregroundStyle(.orange)

                        Divider()

                        HStack(spacing: 12) {
                            Button {
                                runQuickPull()
                            } label: {
                                Label("Pull Remote", systemImage: "arrow.down.circle.fill")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRunningQuickAction)

                            Button {
                                runQuickStageAll()
                            } label: {
                                Label("Stage All Changes", systemImage: "plus.circle.fill")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRunningQuickAction)

                            Button(role: .destructive) {
                                runQuickDiscardAll()
                            } label: {
                                Label("Discard All Changes", systemImage: "trash.fill")
                            }
                            .buttonStyle(.bordered)
                            .disabled(isRunningQuickAction)
                        }

                        if !quickActionLog.isEmpty {
                            Text(quickActionLog)
                                .font(.system(.caption, design: .monospaced))
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.black.opacity(0.15))
                                .cornerRadius(6)
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // Dynamic Status & Statistics Grid
                let columns = [
                    GridItem(.adaptive(minimum: 220), spacing: 16)
                ]

                LazyVGrid(columns: columns, spacing: 16) {
                    // Local Branch card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Current Branch", systemImage: "arrow.triangle.branch")
                                .font(.headline)
                                .foregroundStyle(.orange)

                            Text(gitViewModel.status?.branchName ?? "main")
                                .font(.title3.bold())
                                .lineLimit(1)

                            Button("Manage Branches") {
                                onNavigateToSection(.branches)
                            }
                            .buttonStyle(.link)
                            .foregroundStyle(.orange)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Working Changes card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Working Directory", systemImage: "doc.text.fill")
                                .font(.headline)
                                .foregroundStyle(.blue)

                            let changedCount = gitViewModel.status?.files.count ?? 0
                            Text("\(changedCount) Modified Files")
                                .font(.title3.bold())

                            Button("View Changes") {
                                onNavigateToSection(.repositories) // Navigates to changes panel
                            }
                            .buttonStyle(.link)
                            .foregroundStyle(.blue)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Commits count / Sync card
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Commit History", systemImage: "clock.arrow.circlepath")
                                .font(.headline)
                                .foregroundStyle(.purple)

                            let commitCount = gitViewModel.history.count
                            Text("\(commitCount) Local Commits")
                                .font(.title3.bold())

                            Button("History Timeline") {
                                onNavigateToSection(.commits)
                            }
                            .buttonStyle(.link)
                            .foregroundStyle(.purple)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())

                    // Remote Synced Card (Ahead / Behind)
                    GroupBox {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("Remote Synchronization", systemImage: "arrow.triangle.2.circlepath")
                                .font(.headline)
                                .foregroundStyle(.green)

                            let ahead = gitViewModel.status?.ahead ?? 0
                            let behind = gitViewModel.status?.behind ?? 0
                            Text("\(ahead) Ahead / \(behind) Behind")
                                .font(.title3.bold())

                            Button("Check Actions") {
                                onNavigateToSection(.actions)
                            }
                            .buttonStyle(.link)
                            .foregroundStyle(.green)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .groupBoxStyle(ModernGroupBoxStyle())
                }

                // Recent Commits Subsection
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Recent Commits", systemImage: "list.dash")
                            .font(.headline)
                            .foregroundStyle(.orange)

                        if gitViewModel.history.isEmpty {
                            Text("No commits recorded yet.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 8)
                        } else {
                            VStack(spacing: 0) {
                                ForEach(gitViewModel.history.prefix(5)) { commit in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(commit.subject)
                                                .font(.subheadline.bold())
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
                                            Text(String(commit.sha.prefix(7)))
                                                .font(.system(.caption2, design: .monospaced))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.secondary.opacity(0.12))
                                                .cornerRadius(4)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Copy full SHA")
                                    }
                                    .padding(.vertical, 8)

                                    if commit.id != gitViewModel.history.prefix(5).last?.id {
                                        Divider()
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding(24)
        }
    }

    private func healthBadge(title: String, subtitle: String, isHealthy: Bool, systemImage: String, unhealthImage: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill((isHealthy ? Color.green : Color.orange).opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: isHealthy ? systemImage : unhealthImage)
                    .font(.title3)
                    .foregroundColor(isHealthy ? .green : .orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)
                Text(subtitle)
                    .font(.subheadline.bold())
                    .foregroundStyle(isHealthy ? Color.primary : Color.orange)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.secondary.opacity(0.04))
        .cornerRadius(10)
        .frame(maxWidth: .infinity)
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
