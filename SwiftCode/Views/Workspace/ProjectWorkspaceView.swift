import SwiftUI

struct ProjectWorkspaceView: View {
    let project: Project
    @EnvironmentObject private var projectManager: ProjectManager

    // Sheet state
    @State private var showNavigatorSheet = false
    @State private var showAISheet = false
    @State private var showBuildStatus = false
    @State private var showGitHubSheet = false
    @State private var showSettingsSheet = false
    @State private var showCodeSearch = false
    @State private var showErrorsPanel = false
    @State private var showDependencyManager = false
    @State private var showCommandPalette = false
    @State private var showGoToLine = false
    @State private var showSymbolNavigator = false
    @State private var showDiffViewer = false
    @State private var showToolbarCustomization = false
    @State private var showProjectSettings = false
    @State private var showBuildLogs = false
    @State private var showMinimapSettings = false
    @State private var showSFSymbolsBrowser = false
    // New sheets
    @State private var showTerminal = false
    @State private var showCodeReview = false
    @State private var showGitHistory = false
    @State private var showFilePreview = false
    @State private var showGitHubIssues = false
    @State private var showComplexityAnalyzer = false
    @State private var showSymbolOutline = false
    @State private var showLocalSimulation = false
    @State private var showPluginManager = false
    @State private var showSearchDocumentation = false
    @State private var showSnippetsLibrary = false
    @State private var showCodeRefactoring = false
    @State private var showErrorDiagnostics = false
    @State private var showExtensionMarketplace = false
    @State private var showCodeIntelligence = false
    @State private var showCrashLogAnalyzer = false
    @State private var showProjectDependencyGraph = false
    @State private var showSymbolIndex = false
    @State private var showCodeMetrics = false
    @State private var showDocumentationBrowser = false
    @State private var showWorkspaceProfiles = false
    @State private var showAssetManager = false
    @State private var showDebugTools = false
    @State private var showProjectTemplates = false
    @State private var showDeployments = false
    @State private var showTestTools = false
    @State private var showAllToolsSheet = false
    @State private var showPaywall = false
    @State private var showCollaboration = false
    @State private var showGistManager = false
    @State private var showAssistView = false

    var body: some View {
        ZStack {
            Color(red: 0.10, green: 0.10, blue: 0.14).ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Header (Project Info & Navigation)
                projectHeader
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)

                Divider().opacity(0.3)

                // Horizontal toolbar at the top for iOS-friendly access
                MainToolbarView()
                    .environmentObject(projectManager)

                Divider().opacity(0.3)

                // Code Editor fills the available space
                CodeEditorView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationBarHidden(true)
        // File Navigator sheet
        .sheet(isPresented: $showNavigatorSheet) {
            NavigationStack {
                FileNavigatorView(project: project)
                    .background(Color(red: 0.12, green: 0.12, blue: 0.16))
                    .navigationTitle("Files")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showNavigatorSheet = false }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        // Auto-dismiss navigator when a file is selected
        .onChange(of: projectManager.activeFileNode) {
            if projectManager.activeFileNode != nil {
                showNavigatorSheet = false
            }
        }
        // AI Assistant sheet
        .sheet(isPresented: $showAISheet) {
            AIAssistantView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showBuildStatus) {
            BuildStatusView(project: project, owner: ownerFromRepo, repo: repoNameFromRepo)
        }
        .sheet(isPresented: $showGitHubSheet) {
            GitHubIntegrationView(project: project)
        }
        .sheet(isPresented: $showSettingsSheet) {
            GeneralSettingsView()
        }
        // New sheets
        .sheet(isPresented: $showCodeSearch) {
            CodeSearchView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showErrorsPanel) {
            ErrorsPanelView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDependencyManager) {
            DependencyManagerView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCommandPalette) {
            CommandPaletteView { action in
                handleCommandAction(action)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showGoToLine) {
            GoToLineView { _ in }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSymbolNavigator) {
            SymbolNavigatorView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDiffViewer) {
            DiffViewerView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showToolbarCustomization) {
            ToolbarCustomizationView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showProjectSettings) {
            ProjectSettingsView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showBuildLogs) {
            BuildLogsView(owner: ownerFromRepo, repo: repoNameFromRepo)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showMinimapSettings) {
            MinimapSettingsView()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSFSymbolsBrowser) {
            SFSymbolBrowserView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        // New feature sheets
        .sheet(isPresented: $showTerminal) {
            TerminalView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCodeReview) {
            CodeReviewView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showGitHistory) {
            GitHistoryView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showFilePreview) {
            FilePreviewView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showGitHubIssues) {
            GitHubIssuesView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showComplexityAnalyzer) {
            ComplexityAnalyzerView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSymbolOutline) {
            SymbolOutlineView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showLocalSimulation) {
            LocalSimulationView()
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        .sheet(isPresented: $showPluginManager) {
            PluginManagerView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showSearchDocumentation) {
            SearchDocumentationView()
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showSnippetsLibrary) { SnippetsLibraryView() }
        .sheet(isPresented: $showCodeRefactoring) { CodeRefactoringView() }
        .sheet(isPresented: $showErrorDiagnostics) { ErrorDiagnosticsView() }
        .sheet(isPresented: $showExtensionMarketplace) { ExtensionMarketplaceView() }
        .sheet(isPresented: $showCodeIntelligence) { CodeIntelligenceView() }
        .sheet(isPresented: $showCrashLogAnalyzer) { CrashLogAnalyzerView() }
        .sheet(isPresented: $showProjectDependencyGraph) { ProjectDependencyGraphView() }
        .sheet(isPresented: $showSymbolIndex) { SymbolIndexView() }
        .sheet(isPresented: $showCodeMetrics) { CodeMetricsDashboardView() }
        .sheet(isPresented: $showDocumentationBrowser) { DocumentationBrowserView() }
        .sheet(isPresented: $showWorkspaceProfiles) { WorkspaceProfilesView() }
        .sheet(isPresented: $showAssetManager) { AssetManagerView() }
        .sheet(isPresented: $showDebugTools) { DebuggingToolsView() }
        .sheet(isPresented: $showProjectTemplates) {
            ProjectTemplateView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDeployments) {
            DeploymentsView()
                .environmentObject(projectManager)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showTestTools) {
            TestToolsView(project: projectManager.activeProject ?? project)
                .environmentObject(projectManager)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showAllToolsSheet) {
            ToolbarExpandedPanelView(isPresented: $showAllToolsSheet)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .sheet(isPresented: $showCollaboration) {
            CollaborationMainView(
                manager: CollaborationSessionStore.shared.manager(
                    for: projectManager.activeProject ?? project,
                    creatorID: UIDevice.current.name
                )
            )
        }
        .sheet(isPresented: $showGistManager) {
            GistsView()
        }
        .sheet(isPresented: $showAssistView) {
            AssistMainView()
        }
        .onReceive(NotificationCenter.default.publisher(for: .toolbarToolActivated)) { notification in
            guard
                let toolId = notification.userInfo?["toolID"] as? String,
                let destination = ToolbarActionManager.shared.destination(for: toolId)
            else { return }

            Task { @MainActor in
                openSheet(for: destination)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showProjectTemplatesOnOpen)) { _ in
            showProjectTemplates = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowAllToolsPanel"))) { _ in
            showAllToolsSheet = true
        }
    }

    // MARK: - UI Components

    private var projectHeader: some View {
        HStack(spacing: 12) {
            Button {
                projectManager.closeProject()
            } label: {
                Image(systemName: "chevron.left")
                    .imageScale(.medium)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 0) {
                Text(project.name)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                if let branch = projectManager.activeProject?.githubRepo {
                    Text(branch)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Spacer()

            // Toolbar customization moved here as a small gear
            Button {
                showToolbarCustomization = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Tool Actions

    private func openSheet(for destination: ToolbarActionManager.SheetDestination) {
        if destination.isPro && !EntitlementManager.shared.proAccess {
            self.showPaywall = true
            return
        }

        switch destination {
        case .fileNavigator: self.showNavigatorSheet = true
        case .aiAgent: self.showAISheet = true
        case .buildStatus: self.showBuildStatus = true
        case .gitHub: self.showGitHubSheet = true
        case .codeSearch: self.showCodeSearch = true
        case .errorsPanel: self.showErrorsPanel = true
        case .dependencyManager: self.showDependencyManager = true
        case .commandPalette: self.showCommandPalette = true
        case .goToLine: self.showGoToLine = true
        case .symbolNavigator: self.showSymbolNavigator = true
        case .diffViewer: self.showDiffViewer = true
        case .toolbarCustomization: self.showToolbarCustomization = true
        case .projectSettings: self.showProjectSettings = true
        case .buildLogs: self.showBuildLogs = true
        case .minimapSettings: self.showMinimapSettings = true
        case .sfSymbolsBrowser: self.showSFSymbolsBrowser = true
        case .settings: self.showSettingsSheet = true
        case .terminal: self.showTerminal = true
        case .codeReview: self.showCodeReview = true
        case .gitHistory: self.showGitHistory = true
        case .filePreview: self.showFilePreview = true
        case .gitHubIssues: self.showGitHubIssues = true
        case .complexityAnalyzer: self.showComplexityAnalyzer = true
        case .symbolOutline: self.showSymbolOutline = true
        case .localSimulation: self.showLocalSimulation = true
        case .pluginManager: self.showPluginManager = true
        case .searchDocumentation: self.showSearchDocumentation = true
        case .snippetsLibrary: self.showSnippetsLibrary = true
        case .codeRefactoring: self.showCodeRefactoring = true
        case .errorDiagnostics: self.showErrorDiagnostics = true
        case .extensionMarketplace: self.showExtensionMarketplace = true
        case .codeIntelligence: self.showCodeIntelligence = true
        case .crashLogAnalyzer: self.showCrashLogAnalyzer = true
        case .projectDependencyGraph: self.showProjectDependencyGraph = true
        case .symbolIndex: self.showSymbolIndex = true
        case .codeMetrics: self.showCodeMetrics = true
        case .documentationBrowser: self.showDocumentationBrowser = true
        case .workspaceProfiles: self.showWorkspaceProfiles = true
        case .assetManager: self.showAssetManager = true
        case .debugTools: self.showDebugTools = true
        case .deployments: self.showDeployments = true
        case .testTools: self.showTestTools = true
        case .collaboration: self.showCollaboration = true
        case .gistManager: self.showGistManager = true
        case .assistView: self.showAssistView = true
        }
    }

    // MARK: - Command Palette Actions

    private func handleCommandAction(_ action: CommandPaletteView.CommandAction) {
        switch action {
        case .createFile, .createFolder: self.showNavigatorSheet = true
        case .searchProject: self.showCodeSearch = true
        case .runAgent: self.showAISheet = true
        case .installDependency, .openDependencies: self.showDependencyManager = true
        case .openSettings: self.showSettingsSheet = true
        case .runBuild: self.showBuildStatus = true
        case .goToLine: self.showGoToLine = true
        case .openSymbolNav: self.showSymbolNavigator = true
        case .openDiffViewer: self.showDiffViewer = true
        case .openErrors: self.showErrorsPanel = true
        case .openBuildLogs: self.showBuildLogs = true
        case .customizeToolbar: self.showToolbarCustomization = true
        case .openProjectSettings: self.showProjectSettings = true
        case .openMinimap: self.showMinimapSettings = true
        }
    }

    // MARK: - Helpers

    private var ownerFromRepo: String {
        guard let repo = (projectManager.activeProject ?? project).githubRepo else { return "" }
        return String(repo.split(separator: "/").first ?? "")
    }

    private var repoNameFromRepo: String {
        guard let repo = (projectManager.activeProject ?? project).githubRepo else { return "" }
        return String(repo.split(separator: "/").last ?? "")
    }
}
