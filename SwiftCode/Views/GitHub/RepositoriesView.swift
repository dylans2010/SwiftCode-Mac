import SwiftUI

@MainActor
struct RepositoriesView: View {
    var gitViewModel: GitViewModel
    let project: Project?
    @Binding var showSuccess: Bool
    @Binding var successMessage: String?
    @Binding var showError: Bool
    @Binding var errorMessage: String?

    @State private var remoteRepos: [GitHubRepoSummary] = []
    @State private var isFetching = false
    @State private var searchPattern = ""
    @State private var activeTab: RepoSubTab = .localChanges
    @State private var commitMessage = ""

    enum RepoSubTab: String, CaseIterable, Identifiable {
        case localChanges = "Local Changes"
        case remoteRepos = "Remote Repositories"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab Picker
            Picker("Workspace Mode", selection: $activeTab) {
                ForEach(RepoSubTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()
            .frame(maxWidth: 400)

            Divider()

            switch activeTab {
            case .localChanges:
                localChangesPane
            case .remoteRepos:
                remoteReposPane
            }
        }
        .onAppear {
            if remoteRepos.isEmpty {
                fetchRemoteRepos()
            }
        }
    }

    // MARK: - Local Changes Tab

    private var localChangesPane: some View {
        VStack(spacing: 0) {
            if let status = gitViewModel.status {
                HSplitView {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            // Stage / Unstage groups
                            let conflicts = status.files.filter { $0.status == .conflicted }
                            if !conflicts.isEmpty {
                                fileGroupView(title: "Conflicts", files: conflicts, color: .red)
                            }

                            let staged = status.files.filter { $0.isStaged }
                            fileGroupView(title: "Staged Changes", files: staged, color: .green)

                            let unstaged = status.files.filter { !$0.isStaged && $0.status != .conflicted }
                            fileGroupView(title: "Unstaged / Untracked", files: unstaged, color: .orange)
                        }
                        .padding()
                    }
                    .frame(minWidth: 400, maxWidth: .infinity)

                    // Commit composer - flat native macOS panel
                    VStack(alignment: .leading, spacing: 14) {
                        Label("Commit Changes", systemImage: "pencil.and.outline")
                            .font(.headline)
                            .foregroundStyle(.orange)

                        Text("Write a message to commit staged files to local history.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        GitCommitComposerView(message: $commitMessage) {
                            Task {
                                await gitViewModel.commit(message: commitMessage)
                                commitMessage = ""
                            }
                        }

                        Spacer()
                    }
                    .padding()
                    .frame(width: 320)
                }
            } else {
                noGitRepoPlaceholder
            }
        }
    }

    private func fileGroupView(title: String, files: [GitFileStatus], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(files.count)")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.12))
                    .foregroundStyle(color)
                    .clipShape(Capsule())
            }

            if files.isEmpty {
                Text("No changes in this group.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(files) { file in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.path.lastPathComponent)
                                    .font(.subheadline.bold())
                                Text(file.path.path)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text(file.status.rawValue.uppercased())
                                .font(.system(size: 9, weight: .bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(color.opacity(0.15))
                                .foregroundStyle(color)
                                .cornerRadius(4)

                            HStack(spacing: 8) {
                                if file.isStaged {
                                    Button("Unstage") {
                                        Task {
                                            await gitViewModel.unstage(file)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                } else {
                                    Button("Stage") {
                                        Task {
                                            await gitViewModel.stage(file)
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .tint(.blue)
                                    .controlSize(.small)
                                }
                            }
                        }
                        .padding(.vertical, 6)

                        if file.id != files.last?.id {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private var noGitRepoPlaceholder: some View {
        GitHubEmptyStateView(
            title: "Git Repository Not Initialized",
            description: "Initialize local Git history tracking in this workspace to record, branch, stage, and sync changes.",
            systemImage: "folder.badge.plus",
            accentColor: .orange,
            actionTitle: "Initialize Repository"
        ) {
            guard let project = project else { return }
            Task {
                let gitBinary = URL(fileURLWithPath: AppSettings.shared.gitPath.isEmpty ? "/usr/bin/git" : AppSettings.shared.gitPath)
                _ = try? await ProcessRunnerTool.shared.run(
                    executableURL: gitBinary,
                    arguments: ["init"],
                    workingDirectory: project.directoryURL
                )
                await gitViewModel.refreshStatus()
            }
        }
    }

    // MARK: - Remote Repos Tab

    private var remoteReposPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search GitHub repositories...", text: $searchPattern)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

                Button {
                    fetchRemoteRepos()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isFetching)
            }
            .padding()
            .background(Color.secondary.opacity(0.03))

            Divider()

            if isFetching {
                GitHubLoadingView(message: "Retrieving remote repositories...")
            } else if remoteRepos.isEmpty {
                GitHubEmptyStateView(
                    title: "No Repositories Resolved",
                    description: "Connect a GitHub authentication token or verify token scopes on GitHub.",
                    systemImage: "folder.badge.questionmark",
                    accentColor: .purple
                )
            } else {
                let filtered = searchPattern.isEmpty ? remoteRepos : remoteRepos.filter {
                    $0.fullName.localizedCaseInsensitiveContains(searchPattern) ||
                    ($0.description ?? "").localizedCaseInsensitiveContains(searchPattern)
                }

                if filtered.isEmpty {
                    ContentUnavailableView.search(text: searchPattern)
                } else {
                    List(filtered) { repo in
                        HStack(spacing: 16) {
                            Image(systemName: repo.isPrivate ? "lock.fill" : "globe")
                                .foregroundStyle(repo.isPrivate ? .yellow : .green)
                                .font(.title3)

                            VStack(alignment: .leading, spacing: 4) {
                                Text(repo.fullName)
                                    .font(.subheadline.bold())
                                if let desc = repo.description, !desc.isEmpty {
                                    Text(desc)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            Button("Connect Project") {
                                connectRepository(repo)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    // MARK: - Actions Helper

    private func fetchRemoteRepos() {
        isFetching = true
        Task {
            do {
                let repos = try await GitHubService.shared.listUserRepositories()
                self.remoteRepos = repos
            } catch {
                self.errorMessage = "Failed to list repositories: \(error.localizedDescription)"
                self.showError = true
            }
            isFetching = false
        }
    }

    private func connectRepository(_ repo: GitHubRepoSummary) {
        guard let project = project else { return }

        AppSettings.shared.httpsAuthToken = KeychainService.shared.get(forKey: KeychainService.githubToken) ?? ""
        let token = AppSettings.shared.httpsAuthToken

        Task {
            do {
                let dirURL = await project.directoryURL
                let gitBinary = URL(fileURLWithPath: AppSettings.shared.gitPath.isEmpty ? "/usr/bin/git" : AppSettings.shared.gitPath)

                _ = try? await ProcessRunnerTool.shared.run(
                    executableURL: gitBinary,
                    arguments: ["init"],
                    workingDirectory: dirURL
                )

                _ = try? await ProcessRunnerTool.shared.run(
                    executableURL: gitBinary,
                    arguments: ["config", "user.name", AppSettings.shared.gitUserName.isEmpty ? "SwiftCode" : AppSettings.shared.gitUserName],
                    workingDirectory: dirURL
                )
                _ = try? await ProcessRunnerTool.shared.run(
                    executableURL: gitBinary,
                    arguments: ["config", "user.email", AppSettings.shared.gitUserEmail.isEmpty ? "support@swiftcode.app" : AppSettings.shared.gitUserEmail],
                    workingDirectory: dirURL
                )

                let authenticatedURL = "https://\(token)@github.com/\(repo.fullName).git"

                _ = try? await ProcessRunnerTool.shared.run(
                    executableURL: gitBinary,
                    arguments: ["remote", "remove", "origin"],
                    workingDirectory: dirURL
                )

                let result = try await ProcessRunnerTool.shared.run(
                    executableURL: gitBinary,
                    arguments: ["remote", "add", "origin", authenticatedURL],
                    workingDirectory: dirURL
                )

                if result.exitCode == 0 {
                    successMessage = "Successfully connected project to \(repo.fullName) and configured local Git remote."
                } else {
                    successMessage = "Connected project to \(repo.fullName). remote set but notice: \(result.stderr)"
                }
                showSuccess = true
            } catch {
                errorMessage = "Failed to configure local git: \(error.localizedDescription)"
                showError = true
            }
        }
    }
}
