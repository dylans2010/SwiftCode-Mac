import SwiftUI
import AppKit
import os.log

private let logger = Logger(subsystem: "com.swiftcode.SourceControl", category: "SourceControlView")

// MARK: - Native Source Control Window Manager
@MainActor
public final class SourceControlWindowManager: NSObject, NSWindowDelegate {
    public static let shared = SourceControlWindowManager()
    private var windowController: SourceControlWindowController?

    public func showWindow(for project: Project, gitViewModel: GitViewModel) {
        if let existing = windowController {
            existing.window?.makeKeyAndOrderFront(nil)
            return
        }

        let wc = SourceControlWindowController(gitViewModel: gitViewModel)
        wc.window?.delegate = self
        self.windowController = wc
        wc.window?.makeKeyAndOrderFront(nil)
    }

    public func closeWindow() {
        windowController?.close()
        windowController = nil
    }

    public func windowWillClose(_ notification: Notification) {
        windowController = nil
    }
}

// MARK: - Native Source Control Window Controller
@MainActor
public class SourceControlWindowController: NSWindowController {
    public init(gitViewModel: GitViewModel) {
        let window = NSWindow(
            contentRect: NSRect(x: 150, y: 150, width: 1200, height: 800),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Source Control Workspace"
        window.minSize = NSSize(width: 1200, height: 800)
        window.setFrameAutosaveName("SourceControlMainWindow")

        super.init(window: window)

        let contentView = StylingBootstrap.configureEnvironment(
            SourceControlView(gitViewModel: gitViewModel)
        )
        .environment(ProjectSessionStore.shared)
        .environmentObject(AppSettings.shared)
        let hostingVC = NSHostingController(rootView: contentView)
        hostingVC.sizingOptions = []
        window.contentViewController = hostingVC
    }

    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

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

// ====================================================================
// NAVIGATION SELECTIONS
// ====================================================================
enum SourceControlSelection: String, CaseIterable, Identifiable {
    case localWorkspace = "Local Workspace"
    case changes = "Changes"
    case branches = "Branches"
    case commitHistory = "Commit History"
    case pullRequests = "Pull Requests"
    case github = "GitHub"
    case actions = "Actions"
    case activityFeed = "Activity Feed"
    case discussions = "Discussions"
    case githubAccount = "GitHub Account"
    case githubCodeSearch = "GitHub Code Search"
    case notifications = "Notifications"
    case releases = "Releases"
    case tags = "Tags"
    case issues = "Issues"
    case repositoryExplorer = "Repository Explorer"
    case repositoryAutomationBuilder = "Repository Automation Builder"
    case swiftCodeWorkflows = "SwiftCode Workflows"
    case diffViewer = "Diff Viewer"
    case cli = "CLI"
    case repositorySettings = "Repository Settings"
    case onboarding = "Onboarding"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .localWorkspace: return "laptopcomputer"
        case .changes: return "doc.badge.plus"
        case .branches: return "arrow.triangle.branch"
        case .commitHistory: return "clock.arrow.circlepath"
        case .pullRequests: return "arrow.triangle.pull"
        case .github: return "square.grid.2x2.fill"
        case .actions: return "play.circle.fill"
        case .activityFeed: return "bolt.fill"
        case .discussions: return "bubble.left.and.bubble.right.fill"
        case .githubAccount: return "person.crop.circle.fill"
        case .githubCodeSearch: return "magnifyingglass"
        case .notifications: return "bell.fill"
        case .releases: return "shippingbox.fill"
        case .tags: return "tag.fill"
        case .issues: return "exclamationmark.bubble.fill"
        case .repositoryExplorer: return "folder.circle.fill"
        case .repositoryAutomationBuilder: return "arrow.triangle.2.circlepath.circle.fill"
        case .swiftCodeWorkflows: return "bolt.circle.fill"
        case .diffViewer: return "arrow.left.and.right.square"
        case .cli: return "terminal.fill"
        case .repositorySettings: return "gearshape.fill"
        case .onboarding: return "person.badge.key.fill"
        }
    }
}

@MainActor
struct SourceControlView: View {
    var gitViewModel: GitViewModel
    @EnvironmentObject private var settings: AppSettings
    @Environment(ProjectSessionStore.self) private var sessionStore
    @Environment(\.dismiss) private var dismiss

    @State private var selection: SourceControlSelection = .localWorkspace
    @State private var showSetup = false
    @State private var isPerformingGitAction = false
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

    var availableSelections: [SourceControlSelection] {
        if isSetupRequired {
            return [.onboarding]
        } else {
            return SourceControlSelection.allCases.filter { $0 != .onboarding }
        }
    }

    var body: some View {
        @Bindable var context = RepositoryContext.shared
        VStack(spacing: 0) {
            // Unified Top Toolbar (Replacer for sidebars)
            HStack(spacing: 16) {
                // Logo & Section Title
                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                    Text("Source Control")
                        .font(.headline)
                }

                Spacer()

                // Primary Navigation Picker in the Top Toolbar
                Picker("Navigation", selection: $selection) {
                    ForEach(availableSelections) { item in
                        Label(item.rawValue, systemImage: item.icon)
                            .tag(item)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 250)

                Spacer()

                // Repository Details Toggle and general actions
                HStack(spacing: 12) {
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

            // Main Content Area
            VStack(spacing: 0) {
                if isSetupRequired {
                    setupRequiredPlaceholder
                } else {
                    detailPaneView(for: selection)
                        .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    private func detailPaneView(for selection: SourceControlSelection) -> some View {
        let project = sessionStore.activeProject ?? Project(name: "Untitled")

        Group {
            switch selection {
            case .localWorkspace:
                RepositoryDashboardView(gitViewModel: gitViewModel, project: project) { item in
                    withAnimation {
                        switch item {
                        case .dashboard: self.selection = .localWorkspace
                        case .repositories: self.selection = .changes
                        case .organizations: self.selection = .github
                        case .pullRequests: self.selection = .pullRequests
                        case .issues: self.selection = .issues
                        case .actions: self.selection = .actions
                        case .branches: self.selection = .branches
                        case .commits: self.selection = .commitHistory
                        case .tags: self.selection = .tags
                        case .releases: self.selection = .releases
                        case .discussions: self.selection = .discussions
                        case .notifications: self.selection = .notifications
                        case .settings: self.selection = .repositorySettings
                        }
                    }
                }
            case .changes:
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
            case .commitHistory:
                CommitsView(gitViewModel: gitViewModel)
            case .pullRequests:
                PullRequestsView(
                    project: project,
                    showSuccess: $showSuccess,
                    successMessage: $successMessage,
                    showError: $showError,
                    errorMessage: $errorMessage
                )
            case .github:
                OrganizationsView()
            case .actions:
                ActionsView(
                    project: project,
                    showSuccess: $showSuccess,
                    successMessage: $successMessage,
                    showError: $showError,
                    errorMessage: $errorMessage
                )
            case .activityFeed:
                ActivityFeedView(project: project)
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
            case .repositoryExplorer:
                RepositoryExplorerView(gitViewModel: gitViewModel, project: project)
            case .repositoryAutomationBuilder:
                RepositoryAutomationBuilderView(project: project)
            case .swiftCodeWorkflows:
                WorkflowDashboardView(project: project, gitViewModel: gitViewModel)
            case .repositorySettings:
                GitHubSettingsView(project: project)
            case .onboarding:
                SCSetupOnboard()
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
            selection = .onboarding
            showSetup = true
        } else {
            if selection == .onboarding {
                selection = .localWorkspace
            }
            Task {
                await gitViewModel.refreshStatus()
            }
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
