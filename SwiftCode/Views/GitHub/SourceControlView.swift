import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.swiftcode.SourceControl", category: "SourceControlView")

@MainActor
struct SourceControlView: View {
    var gitViewModel: GitViewModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(ProjectSessionStore.self) private var sessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var showSetup = false
    @State private var isFetchingRepos = false
    @State private var userRepos: [GitHubRepoSummary] = []
    @State private var repoFetchError: String?
    @State private var repoSearchQuery = ""
    @State private var successMessage: String?
    @State private var showSuccess = false
    @State private var errorMessage: String?
    @State private var showError = false

    // Detail Pane Selection state
    @State private var selectedTab: SourceControlTab = .localWorkspace
    @State private var commitMessage = ""
    @State private var selectedFileForDiscard: GitFileStatus?
    @State private var showingDiscardConfirmation = false
    @State private var isPerformingGitAction = false

    enum SourceControlTab: String, CaseIterable, Identifiable {
        case localWorkspace = "Local Workspace"
        case branches = "Branches"
        case commitHistory = "Commit History"
        case unstagedChanges = "Unstaged Changes"
        case gitTerminal = "Terminal Git CLI"
        case remoteRepos = "Remote Repositories"
        case manageRepo = "Manage Repository"
        case issues = "Issues Tracker"
        case gists = "Personal Gists"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .localWorkspace: return "macbook"
            case .branches: return "arrow.triangle.branch"
            case .commitHistory: return "clock.arrow.circlepath"
            case .unstagedChanges: return "plus.minus.circle"
            case .gitTerminal: return "terminal"
            case .remoteRepos: return "globe"
            case .manageRepo: return "folder.badge.gearshape"
            case .issues: return "exclamationmark.circle"
            case .gists: return "doc.on.doc"
            }
        }
    }

    private var isSetupRequired: Bool {
        let token = KeychainService.shared.get(forKey: KeychainService.githubToken) ?? ""
        let hasToken = !token.isEmpty
        let hasGit = !settings.gitPath.isEmpty && FileManager.default.fileExists(atPath: settings.gitPath)

        if hasToken {
            if hasGit {
                if settings.httpsAuthToken.isEmpty {
                    settings.httpsAuthToken = token
                }
                return false
            }

            for path in ["/usr/bin/git", "/usr/local/bin/git", "/opt/homebrew/bin/git"] {
                if FileManager.default.fileExists(atPath: path) {
                    settings.gitPath = path
                    if settings.httpsAuthToken.isEmpty {
                        settings.httpsAuthToken = token
                    }
                    return false
                }
            }
        }

        if !settings.gitPath.isEmpty && !settings.httpsAuthToken.isEmpty {
            return false
        }

        return true
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header Panel with Title, Active Project Status, and Section Picker
                HStack(spacing: 16) {
                    if let project = sessionStore.activeProject {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.name)
                                .font(.headline)
                            if let linkedRepo = project.githubRepo, !linkedRepo.isEmpty {
                                Text("Linked to: \(linkedRepo)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("No linked GitHub repository")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("Source Control Center")
                            .font(.headline)
                    }

                    Spacer()

                    // Section Selection Dropdown Picker (Replacing Sidebar)
                    Picker("Navigate Section", selection: $selectedTab) {
                        ForEach(SourceControlTab.allCases) { tab in
                            HStack {
                                Image(systemName: tab.icon)
                                Text(tab.rawValue)
                            }
                            .tag(tab)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 250)
                    .accessibilityLabel("Source Control Section Navigation Picker")

                    Button {
                        showSetup = true
                    } label: {
                        Label("Configure Token", systemImage: "key.fill")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        dismiss()
                    } label: {
                        Text("Close")
                            .fontWeight(.semibold)
                    }
                    .keyboardShortcut(.cancelAction)
                }
                .padding()
                .background(.ultraThinMaterial)

                Divider()

                if isSetupRequired {
                    setupRequiredView
                } else {
                    detailPaneView(for: selectedTab)
                }
            }
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(minWidth: 950, minHeight: 600)
        .sheet(isPresented: $showSetup) {
            SCSetupOnboard()
        }
        .alert("Success", isPresented: $showSuccess, presenting: successMessage) { _ in
            Button("OK") {}
        } message: { msg in Text(msg) }
        .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK") {}
        } message: { msg in Text(msg) }
        .confirmationDialog(
            "Discard Changes?",
            isPresented: $showingDiscardConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Changes Permanently", role: .destructive) {
                if let file = selectedFileForDiscard {
                    performAction {
                        await gitViewModel.discardChanges(file)
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to revert changes in \(selectedFileForDiscard?.path.lastPathComponent ?? "")? This action cannot be undone.")
        }
        .onAppear {
            checkSetup()
        }
    }

    // MARK: - Detail Switcher

    @ViewBuilder
    private func detailPaneView(for tab: SourceControlTab) -> some View {
        let project = sessionStore.activeProject ?? Project(name: "Untitled")

        switch tab {
        case .localWorkspace:
            localWorkspacePane
        case .unstagedChanges:
            GitChangesView(viewModel: gitViewModel)
        case .branches:
            GitBranchesView(branches: gitViewModel.branches)
        case .commitHistory:
            GitHistoryView(commits: gitViewModel.history)
        case .gitTerminal:
            GitCLIView(project: project)
        case .remoteRepos:
            remoteRepositoriesPane
        case .manageRepo:
            GitHubIntegrationView(project: project)
        case .issues:
            GitHubIssuesView()
        case .gists:
            GistsView()
        }
    }

    // MARK: - Local Workspace Detail Pane

    private var localWorkspacePane: some View {
        VStack(spacing: 0) {
            HStack {
                if let status = gitViewModel.status {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.triangle.branch")
                            .foregroundStyle(.blue)
                        Text(status.branchName)
                            .fontWeight(.semibold)

                        HStack(spacing: 8) {
                            Label("\(status.ahead)", systemImage: "arrow.up.circle.fill")
                                .help("Ahead of remote")
                            Label("\(status.behind)", systemImage: "arrow.down.circle.fill")
                                .help("Behind remote")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                } else {
                    Text("Not Initialized")
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    performAction {
                        await gitViewModel.refreshStatus()
                    }
                } label: {
                    Label("Refresh Status", systemImage: "arrow.clockwise")
                }
                .disabled(gitViewModel.isScanning || isPerformingGitAction)
            }
            .padding()
            .background(Color.secondary.opacity(0.04))

            Divider()

            if let status = gitViewModel.status {
                HSplitView {
                    // Left column: Changed Files lists
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            let conflicts = status.files.filter { $0.status == .conflicted }
                            if !conflicts.isEmpty {
                                GroupBox {
                                    fileGroupSection(title: "Conflicts", files: conflicts, badgeColor: .red)
                                }
                                .groupBoxStyle(ModernGroupBoxStyle())
                            }

                            let staged = status.files.filter { $0.isStaged }
                            GroupBox {
                                fileGroupSection(title: "Staged Changes", files: staged, badgeColor: .green)
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())

                            let unstaged = status.files.filter { !$0.isStaged && $0.status != .conflicted }
                            GroupBox {
                                fileGroupSection(title: "Unstaged / Untracked", files: unstaged, badgeColor: .orange)
                            }
                            .groupBoxStyle(ModernGroupBoxStyle())
                        }
                        .padding()
                    }
                    .frame(minWidth: 400, maxWidth: .infinity)

                    // Right column: Commit Composer Form
                    VStack(spacing: 20) {
                        GroupBox {
                            VStack(alignment: .leading, spacing: 14) {
                                Label("Commit Composer", systemImage: "pencil.and.outline")
                                    .font(.headline)
                                    .foregroundColor(.orange)

                                Text("Commit Message")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                TextEditor(text: $commitMessage)
                                    .font(.system(.body, design: .monospaced))
                                    .frame(minHeight: 100, maxHeight: 180)
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                    )

                                Button {
                                    performAction {
                                        await gitViewModel.commit(message: commitMessage)
                                        commitMessage = ""
                                    }
                                } label: {
                                    if isPerformingGitAction {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Text("Commit to Local Branch")
                                            .fontWeight(.semibold)
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.orange)
                                .controlSize(.large)
                                .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isPerformingGitAction)
                            }
                            .padding()
                        }
                        .groupBoxStyle(ModernGroupBoxStyle())
                        .frame(width: 320)

                        Spacer()
                    }
                    .padding()
                }
            } else {
                noGitRepoPlaceholder
            }
        }
    }

    private func fileGroupSection(title: String, files: [GitFileStatus], badgeColor: Color) -> some View {
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
                    .background(badgeColor.opacity(0.12))
                    .foregroundStyle(badgeColor)
                    .clipShape(Capsule())
            }

            if files.isEmpty {
                Text("No changes in this group.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
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

                        // Badge
                        Text(file.status.rawValue.uppercased())
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(colorForFileStatus(file.status).opacity(0.15))
                            .foregroundStyle(colorForFileStatus(file.status))
                            .cornerRadius(4)

                        // Actions
                        HStack(spacing: 8) {
                            if file.isStaged {
                                Button("Unstage") {
                                    performAction {
                                        await gitViewModel.unstage(file)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            } else {
                                Button("Stage") {
                                    performAction {
                                        await gitViewModel.stage(file)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.blue)
                                .controlSize(.small)

                                Button("Discard") {
                                    selectedFileForDiscard = file
                                    showingDiscardConfirmation = true
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .foregroundColor(.red)
                            }
                        }
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
            }
        }
    }

    private func colorForFileStatus(_ status: GitFileStatus.Status) -> Color {
        switch status {
        case .modified: return .orange
        case .added: return .green
        case .deleted: return .red
        case .renamed: return .purple
        case .untracked: return .secondary
        case .conflicted: return .red
        }
    }

    private var noGitRepoPlaceholder: some View {
        ContentUnavailableView {
            Label("Git Is Not Initialized", systemImage: "folder.badge.plus")
        } description: {
            Text("Initialize a local repository to start tracking and staging file changes.")
        } actions: {
            Button("Initialize Git Repository") {
                initializeGitRepo()
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
    }

    // MARK: - Remote Repositories detail Pane

    private var remoteRepositoriesPane: some View {
        VStack(spacing: 0) {
            // Search / Filter and Fetch row
            HStack(spacing: 12) {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search remote repositories...", text: $repoSearchQuery)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))

                Button {
                    fetchUserRepos()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isFetchingRepos)
            }
            .padding()
            .background(Color.secondary.opacity(0.03))

            Divider()

            if isFetchingRepos {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Retrieving your remote repositories from GitHub...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let fetchError = repoFetchError {
                ContentUnavailableView {
                    Label("Fetch Failed", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } description: {
                    Text(fetchError)
                } actions: {
                    Button("Retry Fetch") {
                        fetchUserRepos()
                    }
                    .buttonStyle(.bordered)
                }
            } else if userRepos.isEmpty {
                ContentUnavailableView {
                    Label("No Repositories", systemImage: "folder.badge.questionmark")
                } description: {
                    Text("Check your personal token scope on GitHub to make sure repos are accessible.")
                }
            } else {
                let filtered = repoSearchQuery.isEmpty ? userRepos : userRepos.filter {
                    $0.fullName.localizedCaseInsensitiveContains(repoSearchQuery) ||
                    ($0.description ?? "").localizedCaseInsensitiveContains(repoSearchQuery)
                }

                if filtered.isEmpty {
                    ContentUnavailableView.search(text: repoSearchQuery)
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

                            Button("Connect") {
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

    private var setupRequiredView: some View {
        ContentUnavailableView {
            Label("Git Token Required", systemImage: "lock.shield")
                .foregroundStyle(.orange)
        } description: {
            Text("Please provide your GitHub Personal Access Token to explore and connect to your remote repositories.")
        } actions: {
            Button("Configure Git & Token") {
                showSetup = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
    }

    // MARK: - Actions Helper

    private func checkSetup() {
        if isSetupRequired {
            showSetup = true
        } else {
            fetchUserReposSilently()
            Task {
                await gitViewModel.refreshStatus()
            }
        }
    }

    private func fetchUserReposSilently() {
        Task {
            do {
                let repos = try await GitHubService.shared.listUserRepositories()
                self.userRepos = repos
                self.repoFetchError = nil
            } catch {
                // Silent fetch fail is ignored
            }
        }
    }

    private func fetchUserRepos() {
        isFetchingRepos = true
        repoFetchError = nil
        Task {
            do {
                let repos = try await GitHubService.shared.listUserRepositories()
                self.userRepos = repos
                self.isFetchingRepos = false
            } catch {
                self.isFetchingRepos = false
                self.repoFetchError = error.localizedDescription
            }
        }
    }

    private func connectRepository(_ repo: GitHubRepoSummary) {
        guard let project = sessionStore.activeProject else { return }

        sessionStore.updateProjectSettings(description: project.description, githubRepo: repo.fullName, for: project)

        Task {
            do {
                let dirURL = await project.directoryURL
                let gitBinary = URL(fileURLWithPath: settings.gitPath.isEmpty ? "/usr/bin/git" : settings.gitPath)
                let token = settings.httpsAuthToken

                _ = try? await ProcessRunnerTool.shared.run(
                    executableURL: gitBinary,
                    arguments: ["init"],
                    workingDirectory: dirURL
                )

                _ = try? await ProcessRunnerTool.shared.run(
                    executableURL: gitBinary,
                    arguments: ["config", "user.name", settings.gitUserName.isEmpty ? "SwiftCode" : settings.gitUserName],
                    workingDirectory: dirURL
                )
                _ = try? await ProcessRunnerTool.shared.run(
                    executableURL: gitBinary,
                    arguments: ["config", "user.email", settings.gitUserEmail.isEmpty ? "support@swiftcode.app" : settings.gitUserEmail],
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

    private func initializeGitRepo() {
        guard let project = sessionStore.activeProject else { return }
        performAction {
            let gitBinary = URL(fileURLWithPath: settings.gitPath.isEmpty ? "/usr/bin/git" : settings.gitPath)
            _ = try? await ProcessRunnerTool.shared.run(
                executableURL: gitBinary,
                arguments: ["init"],
                workingDirectory: project.directoryURL
            )
            await gitViewModel.refreshStatus()
        }
    }

    private func performAction(_ action: @escaping () async -> Void) {
        isPerformingGitAction = true
        Task {
            await action()
            isPerformingGitAction = false
        }
    }
}
