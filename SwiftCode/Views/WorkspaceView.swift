import SwiftUI
import os

struct WorkspaceView: View {
    @State var viewModel: WorkspaceViewModel
    @Environment(ThemeViewModel.self) var themeVM
    @Environment(ProjectSessionStore.self) private var sessionStore

    // Feature sheet states
    @State private var activeSheet: ToolbarActionManager.SheetDestination?
    @State private var showingExportSheet = false

    // Workflow Editor States
    @State private var workflowContent = ""
    @State private var workflowFileName = "main.yml"
    private let logger = Logger(subsystem: "com.swiftcode.app", category: "WorkspaceView")

    var body: some View {
        AdaptivePage {
            HSplitView {
                FileNavigatorSidebarView(viewModel: viewModel.projectTree)
                    .frame(minWidth: 200, idealWidth: 260, maxWidth: 500)

                EditorTextView(workspaceViewModel: viewModel)
            }
        }
        .environment(viewModel)
        .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        sessionStore.closeProject()
                    } label: {
                        Label("Close Project", systemImage: "xmark.square")
                    }
                    .help("Close current project")

                    BuildToolbarView(viewModel: viewModel.build, projectURL: viewModel.projectURL)
                }

                ToolbarItemGroup(placement: .secondaryAction) {
                    ControlGroup {
                        Button {
                            activeSheet = .codeSearch
                        } label: {
                            Label("Search", systemImage: "magnifyingglass")
                        }
                        .help("Global Search")
                    }

                    Menu {
                        Section("Project") {
                            Menu("Configuration Editors") {
                                Button("Project Overview") { routeToProjectSection(.overview) }
                                Button("General") { routeToProjectSection(.general) }
                                Button("Identity") { routeToProjectSection(.identity) }
                                Button("Targets") { routeToProjectSection(.targets) }
                                Button("Build Settings") { routeToProjectSection(.buildSettings) }
                                Button("Build Rules") { routeToProjectSection(.buildRules) }
                                Button("Build Phases") { routeToProjectSection(.buildPhases) }
                                Button("Build Configurations") { routeToProjectSection(.buildConfigurations) }
                                Button("Packages") { routeToProjectSection(.packages) }
                                Button("Frameworks") { routeToProjectSection(.frameworks) }
                                Button("Dependencies") { routeToProjectSection(.dependencies) }
                                Button("Signing & Capabilities") { routeToProjectSection(.signingCapabilities) }
                                Button("Entitlements") { routeToProjectSection(.entitlements) }
                                Button("Info.plist") { routeToProjectSection(.infoPlist) }
                                Button("Resources") { routeToProjectSection(.resources) }
                                Button("Assets") { routeToProjectSection(.assets) }
                                Button("Localization") { routeToProjectSection(.localization) }
                                Button("Products") { routeToProjectSection(.products) }
                                Button("Warnings") { routeToProjectSection(.warnings) }
                                Button("Diagnostics") { routeToProjectSection(.diagnostics) }
                                Button("Statistics") { routeToProjectSection(.projectStatistics) }
                                Button("Relationships") { routeToProjectSection(.relationships) }
                                Button("Metadata") { routeToProjectSection(.metadata) }
                            }
                            Button("Gists") { activeSheet = .gistManager }
                            Button("Deployments") { activeSheet = .deployments }
                            Button("Collaboration") { activeSheet = .collaboration }
                            Button("Licenses") { activeSheet = .licensesAdd }
                            Button("Export (.scproj)") { showingExportSheet = true }
                        }

                        Section("Tools") {
                            Button("Documentation") { activeSheet = .documentationBrowser }
                            Button("Extensions") { activeSheet = .extensionMarketplace }
                            Button("Debug Tools") { activeSheet = .debugTools }
                            Button("Plugin Manager") { activeSheet = .pluginManager }
                            Button("Dev Tools") { activeSheet = .devTools }
                            Button("Source Control") { activeSheet = .sourceControl }
                            Button("CI Build") { activeSheet = .ciBuild }
                            Button("Dependency Manager") { activeSheet = .dependencyManager }
                        }

                        Section("Analysis") {
                            Button("Crash Logs") { activeSheet = .crashLogAnalyzer }
                            Button("Dependency Graph") { activeSheet = .projectDependencyGraph }
                        }

                        Section("Additional Views") {
                            Button("Search") { activeSheet = .codeSearch }
                            Button("Terminal") { activeSheet = .terminal }
                            Button("Debug Sessions") { activeSheet = .debugSessions }
                            Button("Bookmarks") { activeSheet = .bookmarksSidebar }
                            Button("Breakpoints") { activeSheet = .breakpointsSidebar }
                            Button("Debug Inspector") { activeSheet = .debugInspectorSidebar }
                            Button("Workflows") { activeSheet = .workflowsSidebar }
                            Button("Tests") { activeSheet = .testsSidebar }
                            Button("Workflow Editor") { activeSheet = .workflowEditor }
                            Button("System Outline") { activeSheet = .symbolOutline }
                            Button("Minimap Settings") { activeSheet = .minimapSettings }
                            Button("Code Metrics Dashboard") { activeSheet = .codeMetrics }
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
            .sheet(item: $activeSheet) { destination in
                sheetView(for: destination)
            }
            .sheet(isPresented: $showingExportSheet) {
                ExportProjView()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowExportSheet"))) { _ in
                showingExportSheet = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .toolbarToolActivated)) { notification in
                if let toolId = notification.userInfo?["toolID"] as? String,
                   let destination = ToolbarActionManager.shared.destination(for: toolId) {
                    activeSheet = destination
                }
            }
            .background(Color(hex: themeVM.currentTheme.background))
            .foregroundStyle(Color(hex: themeVM.currentTheme.foreground))
            .navigationBarBackButtonHidden(true)
    }

    @ViewBuilder
    private func sheetView(for destination: ToolbarActionManager.SheetDestination) -> some View {
        let project = sessionStore.activeProject ?? Project(name: "Untitled")
        let owner = project.githubRepo?.split(separator: "/").first.map(String.init) ?? ""
        let repo = project.githubRepo?.split(separator: "/").last.map(String.init) ?? ""

        AdaptiveSheet {
            NavigationStack {
                Group {
                    switch destination {
                case .codeSearch: CodeSearchView()
                case .goToLine: GoToLineView { _ in activeSheet = nil }
                case .buildStatus: BuildStatusView(project: project, owner: owner, repo: repo)
                case .buildLogs: BuildLogsView(owner: owner, repo: repo)
                case .gistManager: GistsView()
                case .deployments: DeploymentsView()
                case .testTools: TestToolsView(project: project)
                case .collaboration:
                    CollaborationMainView(manager: CollaborationSessionStore.shared.manager(for: project, creatorID: Host.current().localizedName ?? "macOS"))
                case .documentationBrowser: DocumentationBrowserView()
                case .extensionMarketplace: ExtensionMarketplaceView()
                case .debugTools: DebuggingToolsView()
                case .pluginManager: PluginManagerView()
                case .assetManager: AssetManagerView()
                case .crashLogAnalyzer: CrashLogAnalyzerView()
                case .projectDependencyGraph: ProjectDependencyGraphView()
                case .dependencyManager: DependencyManagerView()
                case .diffViewer: DiffViewerView()
                case .symbolNavigator: SymbolNavigatorView()
                case .codeReview: CodeReviewView()
                case .gitHubIssues: GitHubIssuesView()
                case .complexityAnalyzer: ComplexityAnalyzerView()
                case .localSimulation: LocalSimulationView()
                case .searchDocumentation: SearchDocumentationView()
                case .snippetsLibrary: SnippetsLibraryView()
                case .codeRefactoring: CodeRefactoringView()
                case .errorDiagnostics: ErrorDiagnosticsView()
                case .codeIntelligence: CodeIntelligenceView()
                case .workspaceProfiles: WorkspaceProfilesView()
                case .gitHub: GitHubIntegrationView(project: project)
                case .devTools: DevToolsMainView()
                case .sourceControl: SourceControlView(gitViewModel: viewModel.git)
                case .ciBuild: CIBuildView(project: project)
                case .dependencyManager: DependencyManagerView()
                case .licensesAdd: LicencesAddView(project: project)

                // Relocated Sidebar & Inspector cases
                case .fileNavigator: FileNavigatorSidebarView(viewModel: viewModel.projectTree)
                case .debugSessions: DebugSessionsSidebarView(viewModel: viewModel.debug)
                case .bookmarksSidebar: BookmarksSidebarView()
                case .breakpointsSidebar: BreakpointsSidebarView()
                case .debugInspectorSidebar: DebugInspectorSidebarView(viewModel: viewModel.debug)
                case .workflowsSidebar: GitHubWorkflowsSidebarView()
                case .testsSidebar: TestsSidebarView()
                case .workflowEditor:
                    WorkflowEditorView(
                        content: $workflowContent,
                        fileName: workflowFileName,
                        onSave: { newContent in
                            saveWorkflow(content: newContent)
                            activeSheet = nil
                        }
                    )
                    .onAppear {
                        loadWorkflow()
                    }
                case .symbolOutline: SymbolOutlineView()
                case .minimapSettings: MinimapSettingsView()
                case .codeMetrics: CodeMetricsDashboardView()
                case .terminal: TerminalView()

                default:
                    ContentUnavailableView {
                        Label("Feature Detail", systemImage: "hammer")
                    } description: {
                        Text("The \(destination.rawValue) feature is accessible through the primary interface.")
                    }
                }
            }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { activeSheet = nil }
                    }
                }
            }
        }
    }

    private func loadWorkflow() {
        let fileURL = viewModel.projectURL.appendingPathComponent(".github/workflows/\(workflowFileName)")
        if FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                workflowContent = try String(contentsOf: fileURL, encoding: .utf8)
                return
            } catch {
                logger.error("Failed to load workflow file: \(error.localizedDescription)")
            }
        }

        // Default template
        workflowContent = """
name: CI

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - name: Build
        run: swift build
"""
    }

    private func saveWorkflow(content: String) {
        let workflowsDir = viewModel.projectURL.appendingPathComponent(".github/workflows")
        let fileURL = workflowsDir.appendingPathComponent(workflowFileName)
        do {
            try FileManager.default.createDirectory(at: workflowsDir, withIntermediateDirectories: true)
            // SAFETY: atomic writes prevent project file corruption
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
            if let project = sessionStore.activeProject {
                sessionStore.refreshFileTree(for: project)
            }
        } catch {
            logger.error("Failed to save workflow from editor: \(error.localizedDescription)")
        }
    }

    private func routeToProjectSection(_ section: ProjectEditorCoordinator.ProjectSection) {
        let coordinator = ProjectEditorCoordinator.shared
        coordinator.selectedTab = section

        // Find any active xcodeproj URL in our cached project dictionary
        if let firstProjURL = viewModel.parsedXcodeProjects.keys.first(where: { $0.pathExtension == "xcodeproj" }) {
            Task {
                await viewModel.editor.openFile(url: firstProjURL)
            }
        }
    }
}

