import SwiftUI

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
        NavigationSplitView {
            // Left Sidebar: Connection & Local Git Actions
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 12) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 28))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Source Control")
                            .font(.headline)
                        Text("Git & GitHub Control")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()

                Divider()

                List {
                    Section("Repository Settings") {
                        Button {
                            fetchUserRepos()
                        } label: {
                            Label("Connect Repository", systemImage: "link.circle.fill")
                        }

                        Button {
                            showSetup = true
                        } label: {
                            Label("Configure Git Token", systemImage: "key.fill")
                        }
                    }

                    if let project = sessionStore.activeProject {
                        Section("GitHub Integration") {
                            NavigationLink(destination: GitHubIntegrationView(project: project)) {
                                Label("Manage Repository", systemImage: "folder.badge.gearshape")
                            }
                            NavigationLink(destination: GitHubIssuesView()) {
                                Label("Issues Tracker", systemImage: "exclamationmark.circle")
                            }
                            NavigationLink(destination: GistsView()) {
                                Label("Personal Gists", systemImage: "doc.on.doc")
                            }
                        }

                        Section("Local Git Utilities") {
                            NavigationLink(destination: GitChangesView(viewModel: gitViewModel)) {
                                Label("Unstaged Changes", systemImage: "plus.minus.circle")
                            }
                            NavigationLink(destination: GitBranchesView(branches: gitViewModel.branches)) {
                                Label("Branches", systemImage: "arrow.triangle.branch")
                            }
                            NavigationLink(destination: GitHistoryView(commits: gitViewModel.history)) {
                                Label("Commit History", systemImage: "clock.arrow.circlepath")
                            }
                            NavigationLink(destination: GitCLIView(project: project)) {
                                Label("Terminal Git CLI", systemImage: "terminal")
                            }
                        }
                    }
                }
                .listStyle(.sidebar)
            }
            .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 320)
        } detail: {
            // Right Detail: Repository Connection Dashboard or onboarding
            VStack(spacing: 0) {
                // Toolbar in detail header
                HStack {
                    if let project = sessionStore.activeProject, let linkedRepo = project.githubRepo, !linkedRepo.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Linked Repository")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                            Text(linkedRepo)
                                .font(.title3.bold())
                        }
                    } else {
                        Text("Repository Dashboard")
                            .font(.title3.bold())
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Text("Close")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(Color.orange.opacity(0.2), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    .buttonStyle(.plain)
                }
                .padding()
                .background(.background.opacity(0.4))

                Divider()

                if isSetupRequired {
                    setupRequiredView
                } else {
                    mainDashboardView
                }
            }
        }
        .frame(minWidth: 850, minHeight: 550)
        .sheet(isPresented: $showSetup) {
            SCSetupOnboard()
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

    // MARK: - Setup Check & Required View

    private func checkSetup() {
        if isSetupRequired {
            showSetup = true
        } else {
            // Automatically pre-load repos if authenticated
            fetchUserReposSilently()
        }
    }

    private var setupRequiredView: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: "lock.shield")
                    .font(.system(size: 40))
                    .foregroundStyle(.orange)
            }

            VStack(spacing: 8) {
                Text("Git Token Required")
                    .font(.title2.bold())
                Text("You must provide your GitHub Personal Access Token to explore and connect remote repositories.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 48)
            }

            Button("Configure Git & Token") {
                showSetup = true
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(.orange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Main Dashboard View

    private var mainDashboardView: some View {
        VStack(spacing: 0) {
            // Search & Filtering of GitHub repositories
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search your remote repositories...", text: $repoSearchQuery)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )

                Button {
                    fetchUserRepos()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .help("Refresh Repositories")
                }
                .disabled(isFetchingRepos)
            }
            .padding()

            Divider()

            // Repositories List
            Group {
                if isFetchingRepos {
                    VStack(spacing: 16) {
                        ProgressView()
                        Text("Fetching your repositories from GitHub…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let fetchError = repoFetchError {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.red)
                        Text("Could Not Load Repositories")
                            .font(.headline)
                        Text(fetchError)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)

                        Button("Retry Fetch") {
                            fetchUserRepos()
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if userRepos.isEmpty {
                    ContentUnavailableView(
                        "No Repositories Found",
                        systemImage: "folder.badge.questionmark",
                        description: Text("Verify your token scopes include repo accessibility on GitHub.")
                    )
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
                                    .frame(width: 24)

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

                                Button {
                                    connectRepository(repo)
                                } label: {
                                    Text("Connect")
                                        .font(.caption.bold())
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.orange, in: Capsule())
                                        .foregroundStyle(.white)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(Color.white.opacity(0.01))
                            .cornerRadius(8)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func fetchUserReposSilently() {
        Task {
            do {
                let repos = try await GitHubService.shared.listUserRepositories()
                await MainActor.run {
                    self.userRepos = repos
                    self.repoFetchError = nil
                }
            } catch {
                // Ignore silent fetch failures
            }
        }
    }

    private func fetchUserRepos() {
        isFetchingRepos = true
        repoFetchError = nil
        Task {
            do {
                let repos = try await GitHubService.shared.listUserRepositories()
                await MainActor.run {
                    self.userRepos = repos
                    self.isFetchingRepos = false
                    self.repoFetchError = nil
                }
            } catch {
                await MainActor.run {
                    self.isFetchingRepos = false
                    self.repoFetchError = error.localizedDescription
                }
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

                // Initialize local git if not done yet
                _ = try? await ProcessRunnerTool.shared.run(
                    executableURL: gitBinary,
                    arguments: ["init"],
                    workingDirectory: dirURL
                )

                // Configure credentials
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

                await MainActor.run {
                    if result.exitCode == 0 {
                        successMessage = "Successfully connected project to \(repo.fullName) and configured local Git remote."
                    } else {
                        successMessage = "Connected project to \(repo.fullName). remote set but notice: \(result.stderr)"
                    }
                    showSuccess = true
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to configure local git: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
}
