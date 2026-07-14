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
        List {
            // Overview & Connected Remote Status Section
            Section(header: Text("Repository Command Center").font(.system(size: 10, weight: .bold)).foregroundStyle(.blue)) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(project?.name ?? "No Active Project")
                            .font(.headline)

                        Spacer()

                        if let repoName = project?.githubRepo, !repoName.isEmpty {
                            Text("Connected to Remote")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.green)
                        } else {
                            Text("Local Workspace Only")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.orange)
                        }
                    }

                    if let repo = project?.githubRepo, !repo.isEmpty {
                        Text("Linked GitHub Repository: \(repo)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Initialize a GitHub remote to synchronize with remote branches, manage issues, actions, and collaborate.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            // Repository Health Indicators Section
            Section(header: Text("Repository Health Indicators").font(.system(size: 10, weight: .bold)).foregroundStyle(.green)) {
                let filesCount = gitViewModel.status?.files.count ?? 0
                healthRow(
                    title: "Working Copy",
                    subtitle: filesCount == 0 ? "Clean State" : "\(filesCount) Modified",
                    isHealthy: filesCount == 0,
                    systemImage: "checkmark.circle.fill",
                    unhealthImage: "exclamationmark.triangle.fill"
                )

                let ahead = gitViewModel.status?.ahead ?? 0
                healthRow(
                    title: "Sync Status",
                    subtitle: ahead == 0 ? "Up to Date" : "\(ahead) Commits Ahead",
                    isHealthy: ahead == 0,
                    systemImage: "cloud.checkmark.fill",
                    unhealthImage: "arrow.up.circle.fill"
                )

                let hasRemote = !(project?.githubRepo ?? "").isEmpty
                healthRow(
                    title: "Remote Origin",
                    subtitle: hasRemote ? "Connected" : "No Upstream",
                    isHealthy: hasRemote,
                    systemImage: "link.circle.fill",
                    unhealthImage: "link.badge.plus"
                )
            }

            // Quick Developer Actions Section
            Section(header: Text("Quick Developer Actions").font(.system(size: 10, weight: .bold)).foregroundStyle(.orange)) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Button {
                            runQuickPull()
                        } label: {
                            Label("Pull Remote", systemImage: "arrow.down.circle.fill")
                        }
                        .controlSize(.small)
                        .disabled(isRunningQuickAction)

                        Button {
                            runQuickStageAll()
                        } label: {
                            Label("Stage All", systemImage: "plus.circle.fill")
                        }
                        .controlSize(.small)
                        .disabled(isRunningQuickAction)

                        Button(role: .destructive) {
                            runQuickDiscardAll()
                        } label: {
                            Label("Discard All", systemImage: "trash.fill")
                        }
                        .controlSize(.small)
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
                .padding(.vertical, 4)
            }

            // Status & Statistics Section
            Section(header: Text("Repository Status & Statistics").font(.system(size: 10, weight: .bold)).foregroundStyle(.purple)) {
                // Current Branch
                HStack {
                    Label("Current Branch", systemImage: "arrow.triangle.branch")
                        .font(.subheadline)
                    Spacer()
                    Text(gitViewModel.status?.branchName ?? "main")
                        .font(.subheadline.bold())
                    Button("Manage") {
                        onNavigateToSection(.branches)
                    }
                    .buttonStyle(.link)
                }

                // Working Changes
                HStack {
                    Label("Working Directory", systemImage: "doc.text.fill")
                        .font(.subheadline)
                    Spacer()
                    let changedCount = gitViewModel.status?.files.count ?? 0
                    Text("\(changedCount) Modified")
                        .font(.subheadline.bold())
                    Button("View") {
                        onNavigateToSection(.repositories)
                    }
                    .buttonStyle(.link)
                }

                // Commits
                HStack {
                    Label("Commit History", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline)
                    Spacer()
                    let commitCount = gitViewModel.history.count
                    Text("\(commitCount) Local Commits")
                        .font(.subheadline.bold())
                    Button("History") {
                        onNavigateToSection(.commits)
                    }
                    .buttonStyle(.link)
                }

                // Sync
                HStack {
                    Label("Remote Synchronization", systemImage: "arrow.triangle.2.circlepath")
                        .font(.subheadline)
                    Spacer()
                    let ahead = gitViewModel.status?.ahead ?? 0
                    let behind = gitViewModel.status?.behind ?? 0
                    Text("\(ahead) Ahead / \(behind) Behind")
                        .font(.subheadline.bold())
                    Button("Actions") {
                        onNavigateToSection(.actions)
                    }
                    .buttonStyle(.link)
                }
            }

            // Recent Commits Section
            Section(header: Text("Recent Commits").font(.system(size: 10, weight: .bold)).foregroundStyle(.orange)) {
                if gitViewModel.history.isEmpty {
                    Text("No commits recorded yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                } else {
                    ForEach(gitViewModel.history.prefix(5)) { commit in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(commit.subject)
                                    .font(.subheadline.bold())
                                Text("\(commit.author) • \(commit.dateString)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()

                            Button {
                                let board = NSPasteboard.general
                                board.clearContents()
                                board.setString(commit.sha, forType: .string)
                            } label: {
                                Text(String(commit.sha.prefix(7)))
                                    .font(.system(.caption, design: .monospaced))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
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

    private func healthRow(title: String, subtitle: String, isHealthy: Bool, systemImage: String, unhealthImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isHealthy ? systemImage : unhealthImage)
                .font(.title3)
                .foregroundColor(isHealthy ? .green : .orange)
                .frame(width: 24, height: 24)

            Text(title)
                .font(.subheadline.bold())

            Spacer()

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(isHealthy ? Color.secondary : Color.orange)
        }
        .padding(.vertical, 2)
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
