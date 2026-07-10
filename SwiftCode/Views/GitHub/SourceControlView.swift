import SwiftUI

struct SourceControlView: View {
    var gitViewModel: GitViewModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(ProjectSessionStore.self) private var sessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var showSetup = false
    @State private var showRepoPicker = false
    @State private var isFetchingRepos = false
    @State private var userRepos: [GitHubRepoSummary] = []
    @State private var repoFetchError: String?
    @State private var repoSearchQuery = ""
    @State private var successMessage: String?
    @State private var showSuccess = false
    @State private var errorMessage: String?
    @State private var showError = false

    private var isSetupRequired: Bool {
        // Retrieve token from Keychain
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

            // Auto-detect standard git executable if empty or invalid
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
            Group {
                if isSetupRequired {
                    VStack(spacing: 20) {
                        Image(systemName: "gearshape.2")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                        Text("Git not configured")
                            .font(.title2.bold())
                        Text("Please complete the setup to use Source Control features.")
                            .foregroundStyle(.secondary)
                        Button("Start Setup") {
                            showSetup = true
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                } else {
                    dashboard
                }
            }
            .navigationTitle("Source Control")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showSetup) {
                SCSetupOnboard()
            }
            .sheet(isPresented: $showRepoPicker) {
                repoPickerSheet
            }
            .alert("Success", isPresented: $showSuccess, presenting: successMessage) { _ in
                Button("OK") {}
            } message: { msg in Text(msg) }
            .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
                Button("OK") {}
            } message: { msg in Text(msg) }
            .onAppear {
                checkSetup()
            }
        }
    }

    private func checkSetup() {
        if isSetupRequired {
            showSetup = true
        }
    }

    private var dashboard: some View {
        List {
            Section("Repository Connection") {
                Button {
                    fetchUserRepos()
                } label: {
                    Label("Connect Repository", systemImage: "link.circle.fill")
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
            }

            Section("GitHub Integration") {
                if let project = sessionStore.activeProject {
                    NavigationLink(destination: GitHubIntegrationView(project: project)) {
                        Label("Manage Repo", systemImage: "folder.badge.gearshape")
                    }
                    NavigationLink(destination: GitHubIssuesView()) {
                        Label("Issues", systemImage: "exclamationmark.circle")
                    }
                }

                NavigationLink(destination: GistsView()) {
                    Label("Gists", systemImage: "doc.on.doc")
                }
            }

            Section("Local Git") {
                if let project = sessionStore.activeProject {
                    NavigationLink(destination: GitChangesView(viewModel: gitViewModel)) {
                        Label("Changes", systemImage: "plus.minus.circle")
                    }
                    NavigationLink(destination: GitBranchesView(branches: gitViewModel.branches)) {
                        Label("Branches", systemImage: "arrow.triangle.branch")
                    }
                    NavigationLink(destination: GitHistoryView(commits: gitViewModel.history)) {
                        Label("History", systemImage: "clock.arrow.circlepath")
                    }
                    NavigationLink(destination: GitCLIView(project: project)) {
                        Label("Git CLI", systemImage: "terminal")
                    }
                }
            }

            Section("Settings") {
                Button {
                    showSetup = true
                } label: {
                    Label("Configure Git / Token", systemImage: "gear")
                }
            }
        }
    }

    // MARK: - Repo Picker Sheet

    private var filteredRepos: [GitHubRepoSummary] {
        if repoSearchQuery.isEmpty { return userRepos }
        return userRepos.filter {
            $0.fullName.localizedCaseInsensitiveContains(repoSearchQuery) ||
            ($0.description ?? "").localizedCaseInsensitiveContains(repoSearchQuery)
        }
    }

    private var repoPickerSheet: some View {
        NavigationStack {
            Group {
                if isFetchingRepos {
                    ProgressView("Loading Repositories…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let fetchError = repoFetchError {
                    ContentUnavailableView(
                        "Could Not Load Repositories",
                        systemImage: "exclamationmark.triangle.fill",
                        description: Text(fetchError)
                    )
                } else if userRepos.isEmpty {
                    ContentUnavailableView(
                        "No Repositories Found",
                        systemImage: "folder.badge.questionmark",
                        description: Text("No repositories are accessible with your current token.")
                    )
                } else if filteredRepos.isEmpty {
                    ContentUnavailableView(
                        "No Results",
                        systemImage: "magnifyingglass",
                        description: Text("No repositories match \(repoSearchQuery).")
                    )
                } else {
                    List(filteredRepos) { repo in
                        Button {
                            connectRepository(repo)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: repo.isPrivate ? "lock.fill" : "globe")
                                    .foregroundStyle(repo.isPrivate ? .yellow : .green)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(repo.fullName)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    if let desc = repo.description, !desc.isEmpty {
                                        Text(desc)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                Spacer()
                                Image(systemName: "checkmark.circle")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .searchable(text: $repoSearchQuery, prompt: "Search Repositories")
            .navigationTitle("Connect Repository")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        repoSearchQuery = ""
                        showRepoPicker = false
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        fetchUserRepos()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isFetchingRepos)
                }
            }
        }
    }

    // MARK: - Actions

    private func fetchUserRepos() {
        isFetchingRepos = true
        repoFetchError = nil
        showRepoPicker = true
        Task {
            do {
                let repos = try await GitHubService.shared.listUserRepositories()
                await MainActor.run {
                    userRepos = repos
                    isFetchingRepos = false
                }
            } catch {
                await MainActor.run {
                    isFetchingRepos = false
                    repoFetchError = error.localizedDescription
                }
            }
        }
    }

    private func connectRepository(_ repo: GitHubRepoSummary) {
        guard let project = sessionStore.activeProject else { return }
        showRepoPicker = false

        sessionStore.updateProjectSettings(description: project.description, githubRepo: repo.fullName, for: project)

        Task {
            do {
                let dirURL = await project.directoryURL
                let gitBinary = URL(fileURLWithPath: settings.gitPath.isEmpty ? "/usr/bin/git" : settings.gitPath)
                let token = settings.httpsAuthToken

                // Initialize local git if not done yet
                _ = try? await ProcessRunnerTool.shared.run(
                    executableURL: gitBinary,
                    arguments: ["init"],
                    workingDirectory: dirURL
                )

                // Configure local credentials for git push/pull
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

                // Set authenticated remote URL
                let authenticatedURL = "https://\(token)@github.com/\(repo.fullName).git"

                // Try removing existing origin and re-adding
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

                await MainActor.run {
                    if result.exitCode == 0 {
                        successMessage = "Successfully connected project to \(repo.fullName) and configured local Git remote."
                    } else {
                        successMessage = "Connected project to \(repo.fullName). Configured remote URL but encountered minor git notice: \(result.stderr)"
                    }
                    showSuccess = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Connected metadata but failed to configure local git: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
}
