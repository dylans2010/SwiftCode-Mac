import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.swiftcode.SourceControl", category: "SourceControlView")

// ====================================================================
// CENTRALIZED REPOSITORY CONTEXT
// ====================================================================
@Observable
@MainActor
final class RepositoryContext {
    static let shared = RepositoryContext()

    private init() {}

    enum DisplayMode: String, Codable, CaseIterable, Identifiable {
        case connectedRepository = "Connected Repository"
        case entireAccount = "Entire GitHub Account"

        var id: String { rawValue }
    }

    var displayMode: DisplayMode = .connectedRepository {
        didSet {
            syncEventsCount += 1
        }
    }

    var syncEventsCount: Int = 0
    var cachedMetadata: GitHubRepoDetail?
    var isLoadingMetadata = false
    var showingSetRepoSheet = false

    var activeProject: Project? {
        ProjectSessionStore.shared.activeProject
    }

    var connectedRepository: String? {
        activeProject?.githubRepo
    }

    var isAuthenticated: Bool {
        let token = KeychainService.shared.get(forKey: KeychainService.githubToken) ?? ""
        return !token.isEmpty
    }

    func triggerSync() {
        syncEventsCount += 1
    }

    func disconnectRepository() {
        guard let proj = activeProject else { return }
        ProjectSessionStore.shared.updateProjectSettings(description: proj.description, githubRepo: nil, for: proj)
        cachedMetadata = nil
        triggerSync()
    }

    func connectRepository(_ repoName: String) {
        guard let proj = activeProject else { return }
        ProjectSessionStore.shared.updateProjectSettings(description: proj.description, githubRepo: repoName, for: proj)
        triggerSync()
        Task {
            await fetchMetadata()
        }
    }

    func fetchMetadata() async {
        guard let repoStr = connectedRepository, !repoStr.isEmpty else {
            cachedMetadata = nil
            return
        }
        let parts = repoStr.split(separator: "/")
        guard parts.count == 2 else {
            cachedMetadata = nil
            return
        }
        let owner = String(parts[0])
        let repo = String(parts[1])

        guard let token = KeychainService.shared.get(forKey: KeychainService.githubToken), !token.isEmpty else {
            cachedMetadata = nil
            return
        }

        isLoadingMetadata = true
        defer { isLoadingMetadata = false }

        do {
            guard let url = URL(string: "https://api.github.com/repos/\(owner)/\(repo)") else { return }
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

            let (data, _) = try await URLSession.shared.data(for: request)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            self.cachedMetadata = try decoder.decode(GitHubRepoDetail.self, from: data)
        } catch {
            // silent catch
        }
    }
}

@MainActor
struct SourceControlView: View {
    var gitViewModel: GitViewModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(ProjectSessionStore.self) private var sessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var selection: GitHubSidebarItem = .dashboard
    @State private var showSetup = false
    @State private var isPerformingGitAction = false
    @State private var showInspector = true
    @State private var showRepoDetails = false

    @State private var successMessage: String?
    @State private var showSuccess = false
    @State private var errorMessage: String?
    @State private var showError = false

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
        @Bindable var context = RepositoryContext.shared
        VStack(spacing: 0) {
            // Unified macOS-Style Navigation Bar
            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                    Text("Source Control Workspace")
                        .font(.headline)
                }

                Spacer()

                HStack(spacing: 12) {
                    // Toggle Sidebar
                    Button {
                        withAnimation {
                            showInspector.toggle()
                        }
                    } label: {
                        Label("Toggle Inspector", systemImage: "sidebar.right")
                    }
                    .help("Toggle right-hand repository inspector")

                    Button {
                        showRepoDetails = true
                    } label: {
                        Label("Repository Details", systemImage: "info.circle")
                    }
                    .help("View repository connection details and metadata")

                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Main Desktop Workspace Layout
            if isSetupRequired {
                setupRequiredPlaceholder
            } else {
                HSplitView {
                    // Left Column: Navigation Sidebar
                    GitHubSidebar(selection: $selection)
                        .frame(minWidth: 200, idealWidth: 220, maxWidth: 300)

                    // Center Column: Primary Workspace with Toolbar
                    VStack(spacing: 0) {
                        GitHubToolbar(
                            currentSelection: selection,
                            isProjectConnected: sessionStore.activeProject?.githubRepo?.isEmpty == false,
                            isPerformingAction: isPerformingGitAction,
                            onRefresh: {
                                Task {
                                    isPerformingGitAction = true
                                    await gitViewModel.refreshStatus()
                                    isPerformingGitAction = false
                                }
                            },
                            onClone: {
                                showSetup = true
                            },
                            onPull: {
                                runGitPull()
                            },
                            onPush: {
                                runGitPush()
                            },
                            onFetch: {
                                runGitFetch()
                            },
                            onSync: {
                                runGitSync()
                            }
                        )

                        Divider()

                        detailPaneView(for: selection)
                            .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                    }
                    .frame(minWidth: 500, maxWidth: .infinity, maxHeight: .infinity)

                    // Right Column: Inspector (Collapsible)
                    if showInspector {
                        GitHubInspector(project: sessionStore.activeProject, gitViewModel: gitViewModel)
                            .frame(minWidth: 220, idealWidth: 240, maxWidth: 320)
                            .transition(.move(edge: .trailing))
                    }
                }
            }
        }
        .frame(minWidth: 1000, minHeight: 650)
        .sheet(isPresented: $showSetup) {
            SCSetupOnboard()
        }
        .sheet(isPresented: $showRepoDetails) {
            VStack(spacing: 0) {
                HStack {
                    Text("Repository Details")
                        .font(.headline)
                    Spacer()
                    Button("Done") {
                        showRepoDetails = false
                    }
                    .buttonStyle(.bordered)
                }
                .padding()

                Divider()

                RepositoryDetailView(
                    project: sessionStore.activeProject,
                    gitViewModel: gitViewModel,
                    onDismiss: { showRepoDetails = false }
                )
                .frame(width: 550, height: 500)
            }
        }
        .sheet(isPresented: $context.showingSetRepoSheet) {
            VStack(spacing: 0) {
                HStack {
                    Text("Repository Association Manager")
                        .font(.headline)
                    Spacer()
                    Button("Done") {
                        context.showingSetRepoSheet = false
                    }
                    .buttonStyle(.bordered)
                }
                .padding()

                Divider()

                SetRepoInProject()
                    .frame(width: 580, height: 520)
            }
        }
        .alert("Success", isPresented: $showSuccess, presenting: successMessage) { _ in
            Button("OK") {}
        } message: { msg in Text(msg) }
        .alert("Error", isPresented: $showError, presenting: errorMessage) { _ in
            Button("OK") {}
        } message: { msg in Text(msg) }
        .onAppear {
            if gitViewModel.repositoryURL == nil {
                gitViewModel.repositoryURL = sessionStore.activeProject?.directoryURL
            }
            checkSetup()
        }
    }

    // MARK: - Detail Switcher

    @ViewBuilder
    private func detailPaneView(for item: GitHubSidebarItem) -> some View {
        let project = sessionStore.activeProject ?? Project(name: "Untitled")

        Group {
            switch item {
            case .dashboard:
                RepositoryDashboardView(gitViewModel: gitViewModel, project: project) { section in
                    withAnimation {
                        self.selection = section
                    }
                }
            case .repositories:
                RepositoriesView(
                    gitViewModel: gitViewModel,
                    project: project,
                    showSuccess: $showSuccess,
                    successMessage: $successMessage,
                    showError: $showError,
                    errorMessage: $errorMessage
                )
            case .branches:
                BranchesView(
                    gitViewModel: gitViewModel,
                    project: project,
                    showSuccess: $showSuccess,
                    successMessage: $successMessage,
                    showError: $showError,
                    errorMessage: $errorMessage
                )
            case .commits:
                CommitsView(gitViewModel: gitViewModel)
            case .pullRequests:
                PullRequestsView(
                    project: project,
                    showSuccess: $showSuccess,
                    successMessage: $successMessage,
                    showError: $showError,
                    errorMessage: $errorMessage
                )
            case .organizations:
                OrganizationsView()
            case .actions:
                ActionsView(
                    project: project,
                    showSuccess: $showSuccess,
                    successMessage: $successMessage,
                    showError: $showError,
                    errorMessage: $errorMessage
                )
            case .discussions:
                DiscussionsView(project: project)
            case .githubAccount:
                GitHubAccountView()
            case .githubCodeSearch:
                GitHubCodeSearchView(project: project)
            case .notifications:
                NotificationsView()
            case .releases:
                ReleasesView(
                    project: project,
                    showSuccess: $showSuccess,
                    successMessage: $successMessage,
                    showError: $showError,
                    errorMessage: $errorMessage
                )
            case .tags:
                TagsView(
                    project: project,
                    showSuccess: $showSuccess,
                    successMessage: $successMessage,
                    showError: $showError,
                    errorMessage: $errorMessage
                )
            case .issues:
                IssuesView(
                    project: project,
                    showSuccess: $showSuccess,
                    successMessage: $successMessage,
                    showError: $showError,
                    errorMessage: $errorMessage
                )
            case .diffViewer:
                UnifiedDiffView(gitViewModel: gitViewModel)
            case .cli:
                GitCLIView(project: project)
            case .settings:
                GitHubSettingsView(project: project)
            }
        }
        .sourceControlEmbedded()
    }

    private var setupRequiredPlaceholder: some View {
        GitHubEmptyStateView(
            title: "GitHub Authentication Required",
            description: "Please provide your GitHub Personal Access Token and Git credentials to authorize repository connections, issue trackers, and pull requests.",
            systemImage: "lock.shield",
            accentColor: .orange,
            actionTitle: "Configure Credentials"
        ) {
            showSetup = true
        }
    }

    // MARK: - Actions Helper

    private func checkSetup() {
        if isSetupRequired {
            showSetup = true
        } else {
            Task {
                await gitViewModel.refreshStatus()
            }
        }
    }

    private func runGitPull() {
        guard let proj = sessionStore.activeProject else { return }
        isPerformingGitAction = true
        Task {
            do {
                let gitBinary = URL(fileURLWithPath: settings.gitPath.isEmpty ? "/usr/bin/git" : settings.gitPath)
                let result = try await ProcessRunnerTool.shared.run(
                    executableURL: gitBinary,
                    arguments: ["pull"],
                    workingDirectory: proj.directoryURL
                )
                if result.exitCode == 0 {
                    successMessage = "Git pull completed successfully."
                    showSuccess = true
                } else {
                    errorMessage = "Pull failed:\n\(result.stderr)"
                    showError = true
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            await gitViewModel.refreshStatus()
            isPerformingGitAction = false
        }
    }

    private func runGitPush() {
        guard let proj = sessionStore.activeProject else { return }
        isPerformingGitAction = true
        Task {
            do {
                let gitBinary = URL(fileURLWithPath: settings.gitPath.isEmpty ? "/usr/bin/git" : settings.gitPath)
                let result = try await ProcessRunnerTool.shared.run(
                    executableURL: gitBinary,
                    arguments: ["push"],
                    workingDirectory: proj.directoryURL
                )
                if result.exitCode == 0 {
                    successMessage = "Git push completed successfully."
                    showSuccess = true
                } else {
                    errorMessage = "Push failed:\n\(result.stderr)"
                    showError = true
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            await gitViewModel.refreshStatus()
            isPerformingGitAction = false
        }
    }

    private func runGitFetch() {
        guard let proj = sessionStore.activeProject else { return }
        isPerformingGitAction = true
        Task {
            do {
                let gitBinary = URL(fileURLWithPath: settings.gitPath.isEmpty ? "/usr/bin/git" : settings.gitPath)
                let result = try await ProcessRunnerTool.shared.run(
                    executableURL: gitBinary,
                    arguments: ["fetch"],
                    workingDirectory: proj.directoryURL
                )
                if result.exitCode == 0 {
                    successMessage = "Git fetch completed successfully."
                    showSuccess = true
                } else {
                    errorMessage = "Fetch failed:\n\(result.stderr)"
                    showError = true
                }
            } catch {
                errorMessage = error.localizedDescription
                showError = true
            }
            await gitViewModel.refreshStatus()
            isPerformingGitAction = false
        }
    }

    private func runGitSync() {
        guard let proj = sessionStore.activeProject else { return }
        isPerformingGitAction = true
        Task {
            do {
                let gitBinary = URL(fileURLWithPath: settings.gitPath.isEmpty ? "/usr/bin/git" : settings.gitPath)
                _ = try? await ProcessRunnerTool.shared.run(
                    executableURL: gitBinary,
                    arguments: ["fetch", "--all"],
                    workingDirectory: proj.directoryURL
                )
                successMessage = "Sync and update status completed."
                showSuccess = true
            }
            await gitViewModel.refreshStatus()
            isPerformingGitAction = false
        }
    }
}

// ====================================================================
// UNIFIED DIFF VIEW
// ====================================================================
struct UnifiedDiffView: View {
    var gitViewModel: GitViewModel
    @State private var hunks: [GitDiffHunk] = []
    @State private var isLoading = false

    var body: some View {
        VStack {
            if isLoading {
                ProgressView("Loading unified diff...")
            } else {
                GitDiffView(hunks: hunks)
            }
        }
        .onAppear {
            isLoading = true
            Task {
                hunks = await gitViewModel.getDiff()
                isLoading = false
            }
        }
    }
}
