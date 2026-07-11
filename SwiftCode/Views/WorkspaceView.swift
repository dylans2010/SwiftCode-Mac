import SwiftUI
import os

struct WorkspaceView: View {
    @State var viewModel: WorkspaceViewModel
    @Environment(ThemeViewModel.self) var themeVM
    @Environment(ProjectSessionStore.self) private var sessionStore

    // Workflow Editor States
    @State private var workflowContent = ""
    @State private var workflowFileName = "main.yml"
    private let logger = Logger(subsystem: "com.swiftcode.app", category: "WorkspaceView")

    // App Details States
    @State private var appName = ""
    @State private var bundleIdentifier = ""
    @State private var marketingVersion = "1.0"
    @State private var buildVersion = "1"
    @State private var supportedDevices = "iPhone + iPad"

    var body: some View {
        AdaptivePage {
            HSplitView {
                FileNavigatorSidebarView(viewModel: viewModel.projectTree)
                    .frame(minWidth: 200, idealWidth: 260, maxWidth: 500)

                EditorTextView(workspaceViewModel: viewModel)

                // Docked right-side AI Agent Inspector
                if viewModel.isAgentChatVisible {
                    VStack(spacing: 0) {
                        HStack {
                            Label("SwiftCode Agent", systemImage: "sparkles")
                                .font(.headline)
                            Spacer()
                            Button(action: {
                                withAnimation {
                                    viewModel.isAgentChatVisible = false
                                }
                            }) {
                                Image(systemName: "xmark")
                            }
                            .buttonStyle(.plain)
                        }
                        .padding()
                        .background(Color(NSColor.controlBackgroundColor))

                        Divider()

                        AgentChatView()
                            .environment(viewModel.ai)
                    }
                    .frame(minWidth: 280, idealWidth: viewModel.agentChatWidth, maxWidth: 600)
                    .background(Color(NSColor.windowBackgroundColor))
                    .transition(.move(edge: .trailing))
                }
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

                    Button {
                        viewModel.activeSheet = .buildStatus
                    } label: {
                        Label("Build Status", systemImage: "gauge.with.needle")
                    }
                    .help("Open Build Status")

                    BuildToolbarView(viewModel: viewModel.build, projectURL: viewModel.projectURL)
                }

                ToolbarItemGroup(placement: .secondaryAction) {
                    ControlGroup {
                        Button {
                            viewModel.activeSheet = .codeSearch
                        } label: {
                            Label("Search", systemImage: "magnifyingglass")
                        }
                        .help("Global Search")

                        Button {
                            withAnimation {
                                viewModel.isAgentChatVisible.toggle()
                            }
                        } label: {
                            Label("AI Agent", systemImage: "sparkles")
                        }
                        .help("Toggle AI Agent Inspector")
                    }

                    Menu {
                        Section("Project") {
                            Menu("Configuration Editors") {
                                Button("Entitlements") { openEntitlements() }
                                Button("Info.plist") { openInfoPlist() }
                            }
                            Button("Gists") { viewModel.activeSheet = .gistManager }
                            Button("Deployments") { viewModel.activeSheet = .deployments }
                            Button("Collaboration") { viewModel.activeSheet = .collaboration }
                            Button("Licenses") { viewModel.activeSheet = .licensesAdd }
                            Button("App Details") { viewModel.activeSheet = .appDetailsInfo }
                            Button("Export (.scproj)") { viewModel.showingExportSheet = true }
                        }

                        Section("Tools") {
                            Button("Documentation") { viewModel.activeSheet = .documentationBrowser }
                            Button("Extensions") { viewModel.activeSheet = .extensionMarketplace }
                            Button("Debug Tools") { viewModel.activeSheet = .debugTools }
                            Button("Plugin Manager") { viewModel.activeSheet = .pluginManager }
                            Button("Dev Tools") { viewModel.activeSheet = .devTools }
                            Button("Source Control") { viewModel.activeSheet = .sourceControl }
                            Button("CI Build") { viewModel.activeSheet = .ciBuild }
                            Button("Dependency Manager") { viewModel.activeSheet = .dependencyManager }
                            Button("Xcode Build Settings") { viewModel.activeSheet = .xcodeBuildSettings }
                            Button("Xcode Build Logs") { viewModel.activeSheet = .xcodeBuildLogs }
                            Button("Apple Signing") { viewModel.activeSheet = .appleDeveloperAccount }
                        }

                        Section("Analysis") {
                            Button("Crash Logs") { viewModel.activeSheet = .crashLogAnalyzer }
                            Button("Dependency Graph") { viewModel.activeSheet = .projectDependencyGraph }
                        }

                        Section("Additional Views") {
                            Button("Search") { viewModel.activeSheet = .codeSearch }
                            Button("Terminal") { viewModel.activeSheet = .terminal }
                            Button("Debug Sessions") { viewModel.activeSheet = .debugSessions }
                            Button("Bookmarks") { viewModel.activeSheet = .bookmarksSidebar }
                            Button("Breakpoints") { viewModel.activeSheet = .breakpointsSidebar }
                            Button("Debug Inspector") { viewModel.activeSheet = .debugInspectorSidebar }
                            Button("Workflows") { viewModel.activeSheet = .workflowsSidebar }
                            Button("Tests") { viewModel.activeSheet = .testsSidebar }
                            Button("Workflow Editor") { viewModel.activeSheet = .workflowEditor }
                            Button("System Outline") { viewModel.activeSheet = .symbolOutline }
                            Button("Minimap Settings") { viewModel.activeSheet = .minimapSettings }
                            Button("Code Metrics Dashboard") { viewModel.activeSheet = .codeMetrics }
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
            .sheet(item: Bindable(viewModel).activeSheet) { destination in
                sheetView(for: destination)
            }
            .sheet(isPresented: Bindable(viewModel).showingExportSheet) {
                ExportProjView()
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowExportSheet"))) { _ in
                viewModel.showingExportSheet = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .toolbarToolActivated)) { notification in
                if let toolId = notification.userInfo?["toolID"] as? String {
                    if toolId == "ai_code_gen" {
                        withAnimation {
                            viewModel.isAgentChatVisible.toggle()
                        }
                    } else if let destination = ToolbarActionManager.shared.destination(for: toolId) {
                        viewModel.activeSheet = destination
                    }
                }
            }
            .onChange(of: ProjectResolutionService.shared.selectedTargetID) { _, _ in
                Task {
                    let project = sessionStore.activeProject ?? Project(name: "Untitled")
                    await viewModel.editor.updateActiveConfigurationURLs(for: project)
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
                case .commandPalette:
                    CommandPaletteView { action in
                        viewModel.activeSheet = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            switch action {
                            case .createFile:
                                NotificationCenter.default.post(name: NSNotification.Name("CreateNewFile"), object: nil)
                            case .createFolder:
                                NotificationCenter.default.post(name: NSNotification.Name("CreateNewFolder"), object: nil)
                            case .searchProject:
                                viewModel.activeSheet = .codeSearch
                            case .goToLine:
                                viewModel.activeSheet = .goToLine
                            case .openSymbolNav:
                                viewModel.activeSheet = .symbolNavigator
                            case .openSystemOutline:
                                viewModel.activeSheet = .symbolOutline
                            case .openMinimap:
                                viewModel.activeSheet = .minimapSettings

                            case .gitCommit:
                                NotificationCenter.default.post(name: NSNotification.Name("GitCommitAction"), object: nil)
                            case .gitPull:
                                NotificationCenter.default.post(name: NSNotification.Name("GitPullAction"), object: nil)
                            case .gitPush:
                                NotificationCenter.default.post(name: NSNotification.Name("GitPushAction"), object: nil)
                            case .gitCheckout:
                                viewModel.activeSheet = .sourceControl
                            case .gitNewBranch:
                                viewModel.activeSheet = .sourceControl
                            case .openDiffViewer:
                                viewModel.activeSheet = .diffViewer

                            case .runAgent:
                                withAnimation {
                                    viewModel.isAgentChatVisible = true
                                }
                            case .aiCodeReview:
                                viewModel.activeSheet = .codeReview
                            case .aiComplexity:
                                viewModel.activeSheet = .complexityAnalyzer

                            case .runBuild:
                                viewModel.activeSheet = .buildStatus
                            case .openXcodeBuildSettings:
                                viewModel.activeSheet = .xcodeBuildSettings
                            case .openXcodeBuildLogs:
                                viewModel.activeSheet = .xcodeBuildLogs
                            case .appleSigning:
                                viewModel.activeSheet = .appleDeveloperAccount

                            case .openSettings:
                                viewModel.activeSheet = .settings
                            case .openProjectSettings:
                                viewModel.activeSheet = .projectSettings
                            case .installDependency:
                                viewModel.activeSheet = .dependencyManager
                            case .openPluginManager:
                                viewModel.activeSheet = .pluginManager
                            case .openExtensionMarketplace:
                                viewModel.activeSheet = .extensionMarketplace
                            case .customizeToolbar:
                                viewModel.activeSheet = .toolbarCustomization

                            case .devHTTPStatus, .devJSONFormatter, .devBase64, .devJWTDecoder, .devPasswordGen, .devRegExTester, .devUUIDGen, .devURLEncoder, .devMarkdownPreview, .devDeviceInfo:
                                viewModel.activeSheet = .devTools
                            }
                        }
                    }
                case .codeSearch: CodeSearchView()
                case .goToLine: GoToLineView { _ in viewModel.activeSheet = nil }
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
                            viewModel.activeSheet = nil
                        }
                    )
                    .onAppear {
                        loadWorkflow()
                    }
                case .symbolOutline: SymbolOutlineView()
                case .minimapSettings: MinimapSettingsView()
                case .codeMetrics: CodeMetricsDashboardView()
                case .terminal: TerminalView()
                case .xcodeBuildSettings: XcodeBuildConfigurationView()
                case .xcodeBuildLogs: XcodeBuildLogView()
                case .appleDeveloperAccount: AppleSignInView()
                case .appDetailsInfo:
                    AppDetailsInfo(
                        appName: $appName,
                        bundleIdentifier: $bundleIdentifier,
                        marketingVersion: $marketingVersion,
                        buildVersion: $buildVersion,
                        supportedDevices: $supportedDevices,
                        onSkip: { viewModel.activeSheet = nil },
                        onContinue: { viewModel.activeSheet = nil }
                    )
                    .onAppear {
                        let project = sessionStore.activeProject ?? Project(name: "Untitled")
                        appName = project.name
                        let ciConfig = project.ciBuildConfiguration
                        bundleIdentifier = ciConfig?.bundleIdentifier ?? "com.example.\(project.name.lowercased())"
                    }
                    .frame(width: 500, height: 600)

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
                        Button("Done") { viewModel.activeSheet = nil }
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

    private func openInfoPlist() {
        let project = sessionStore.activeProject ?? Project(name: "Untitled")
        if let plistURL = ProjectResolutionService.shared.resolveInfoPlist(for: project) {
            Task {
                await viewModel.editor.openFile(url: plistURL)
            }
        } else {
            let dummyURL = project.directoryURL.appendingPathComponent("Unresolved-Info.plist")
            Task {
                await viewModel.editor.openFile(url: dummyURL)
            }
        }
    }

    private func openEntitlements() {
        let project = sessionStore.activeProject ?? Project(name: "Untitled")
        if let entitlementsURL = ProjectResolutionService.shared.resolveEntitlements(for: project) {
            Task {
                await viewModel.editor.openFile(url: entitlementsURL)
            }
        } else {
            let dummyURL = project.directoryURL.appendingPathComponent("Unresolved.entitlements")
            Task {
                await viewModel.editor.openFile(url: dummyURL)
            }
        }
    }
}
