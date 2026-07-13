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
    @State private var sidebarSelection: GitHubSidebarItem = .dashboard
    @State private var isPerformingGitAction = false

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
        NavigationSplitView {
            GitHubSidebar(selection: $sidebarSelection)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showSetup = true
                        } label: {
                            Label("Token Config", systemImage: "key.fill")
                        }
                        .help("Configure Token")
                    }
                    ToolbarItem(placement: .secondaryAction) {
                        Button("Close") {
                            dismiss()
                        }
                    }
                }
        } detail: {
            HSplitView {
                VStack(spacing: 0) {
                    GitHubToolbar(
                        currentSelection: sidebarSelection,
                        isProjectConnected: sessionStore.activeProject?.githubRepo != nil && !(sessionStore.activeProject?.githubRepo ?? "").isEmpty,
                        isPerformingAction: isPerformingGitAction,
                        onRefresh: {
                            performAction {
                                await gitViewModel.refreshStatus()
                            }
                        },
                        onClone: {
                            // Handled by standard Clone trigger
                        },
                        onPull: {
                            performAction {
                                let gitBinary = URL(fileURLWithPath: settings.gitPath.isEmpty ? "/usr/bin/git" : settings.gitPath)
                                if let dirURL = sessionStore.activeProject?.directoryURL {
                                    _ = try? await ProcessRunnerTool.shared.run(
                                        executableURL: gitBinary,
                                        arguments: ["pull", "origin", "main"],
                                        workingDirectory: dirURL
                                    )
                                }
                                await gitViewModel.refreshStatus()
                            }
                        },
                        onPush: {
                            performAction {
                                let gitBinary = URL(fileURLWithPath: settings.gitPath.isEmpty ? "/usr/bin/git" : settings.gitPath)
                                if let dirURL = sessionStore.activeProject?.directoryURL {
                                    _ = try? await ProcessRunnerTool.shared.run(
                                        executableURL: gitBinary,
                                        arguments: ["push", "origin", "main"],
                                        workingDirectory: dirURL
                                    )
                                }
                                await gitViewModel.refreshStatus()
                            }
                        },
                        onFetch: {
                            performAction {
                                let gitBinary = URL(fileURLWithPath: settings.gitPath.isEmpty ? "/usr/bin/git" : settings.gitPath)
                                if let dirURL = sessionStore.activeProject?.directoryURL {
                                    _ = try? await ProcessRunnerTool.shared.run(
                                        executableURL: gitBinary,
                                        arguments: ["fetch"],
                                        workingDirectory: dirURL
                                    )
                                }
                                await gitViewModel.refreshStatus()
                            }
                        }
                    )

                    Divider()

                    if isSetupRequired {
                        setupRequiredPlaceholder
                    } else {
                        detailPaneView(for: sidebarSelection)
                            .transition(.opacity.animation(.easeInOut(duration: 0.15)))
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                GitHubInspector(project: sessionStore.activeProject, gitViewModel: gitViewModel)
                    .frame(width: 240)
            }
        }
        .frame(minWidth: 1000, minHeight: 650)
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

    // MARK: - Detail Switcher

    @ViewBuilder
    private func detailPaneView(for selection: GitHubSidebarItem) -> some View {
        let project = sessionStore.activeProject ?? Project(name: "Untitled")

        Group {
            switch selection {
            case .dashboard:
                RepositoryDashboardView(gitViewModel: gitViewModel, project: project) { item in
                    withAnimation {
                        sidebarSelection = item
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
            case .organizations:
                OrganizationsView()
            case .pullRequests:
                PullRequestsView(
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
            case .actions:
                ActionsView(
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
            case .tags:
                TagsView(
                    project: project,
                    showSuccess: $showSuccess,
                    successMessage: $successMessage,
                    showError: $showError,
                    errorMessage: $errorMessage
                )
            case .releases:
                ReleasesView(
                    project: project,
                    showSuccess: $showSuccess,
                    successMessage: $successMessage,
                    showError: $showError,
                    errorMessage: $errorMessage
                )
            case .discussions:
                DiscussionsView(project: project)
            case .notifications:
                NotificationsView()
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

    private func performAction(_ action: @escaping () async -> Void) {
        isPerformingGitAction = true
        Task {
            await action()
            isPerformingGitAction = false
        }
    }
}
