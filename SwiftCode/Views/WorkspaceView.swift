import SwiftUI
import os

struct WorkspaceTool: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let description: String
    let iconName: String
    let colorHex: String
    let category: String
    let destination: String // RawValue of ToolbarActionManager.SheetDestination
}

struct WorkspaceView: View {
    @State var viewModel: WorkspaceViewModel
    @Environment(ThemeViewModel.self) var themeVM
    @Environment(ProjectSessionStore.self) private var sessionStore

    // Collapsible Agent Inspector
    @AppStorage("com.swiftcode.workspace.showAgentInspector") private var showAgentInspector = false
    @AppStorage("com.swiftcode.workspace.showFileNavigator") private var showFileNavigator = true
    @AppStorage("com.swiftcode.workspace.agentInspectorWidth") private var agentInspectorWidth = 320.0
    @State private var dragStartWidth: CGFloat? = nil

    // Feature sheet states
    @State private var activeSheet: ToolbarActionManager.SheetDestination?
    @State private var showingExportSheet = false

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
            HStack(spacing: 0) {
                if showFileNavigator {
                    VStack(spacing: 0) {
                        HStack {
                            Label("Files", systemImage: "folder.fill")
                                .font(.headline)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)

                        FileNavigatorSidebarView(viewModel: viewModel.projectTree)
                    }
                    .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .padding(8)
                    .transition(.move(edge: .leading).combined(with: .opacity))

                    Divider()
                }

                // Center Code Editor View
                EditorView(viewModel: viewModel.editor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showAgentInspector {
                    // Custom drag handle divider
                    Rectangle()
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 4)
                        .contentShape(Rectangle())
                        .onHover { isHovered in
                            if isHovered {
                                NSCursor.resizeLeftRight.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    if dragStartWidth == nil {
                                        dragStartWidth = agentInspectorWidth
                                    }
                                    let delta = value.translation.width
                                    let newWidth = (dragStartWidth ?? 320.0) - delta
                                    agentInspectorWidth = max(280, min(600, newWidth))
                                }
                                .onEnded { _ in
                                    dragStartWidth = nil
                                }
                        )

                    AssistMainView()
                        .frame(width: agentInspectorWidth)
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
                    withAnimation(.spring()) { showFileNavigator.toggle() }
                } label: {
                    Label(showFileNavigator ? "Hide Files" : "Show Files", systemImage: "sidebar.left")
                }
                .help(showFileNavigator ? "Hide File Navigator" : "Show File Navigator")

                Button {
                    activeSheet = .buildStatus
                } label: {
                    Label("Build Status", systemImage: "gauge.with.needle")
                }
                .help("Open Build Status")

                Button {
                    withAnimation(.spring()) {
                        showAgentInspector.toggle()
                    }
                } label: {
                    Image(systemName: "sparkles")
                        .foregroundColor(showAgentInspector ? .accentColor : .secondary)
                }
                .help("Toggle AI Agent Inspector")

                BuildToolbarView(viewModel: viewModel.build, projectURL: viewModel.projectURL, editorViewModel: viewModel.editor)
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
            if let toolId = notification.userInfo?["toolID"] as? String {
                if toolId == "ai_code_gen" || toolId == "assist_view" || toolId == "runAgent" || toolId == "ai_agent" {
                    withAnimation(.spring()) {
                        showAgentInspector = true
                    }
                } else if let destination = ToolbarActionManager.shared.destination(for: toolId) {
                    activeSheet = destination
                }
            }
        }
        .background(Color(hex: themeVM.currentTheme.background))
        .foregroundStyle(Color(hex: themeVM.currentTheme.foreground))
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Sheet Switching

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
                        activeSheet = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            switch action {
                            case .createFile:
                                NotificationCenter.default.post(name: NSNotification.Name("CreateNewFile"), object: nil)
                            case .createFolder:
                                NotificationCenter.default.post(name: NSNotification.Name("CreateNewFolder"), object: nil)
                            case .searchProject:
                                activeSheet = .codeSearch
                            case .goToLine:
                                activeSheet = .goToLine
                            case .openSymbolNav:
                                activeSheet = .symbolNavigator
                            case .openSystemOutline:
                                activeSheet = .symbolOutline
                            case .openMinimap:
                                activeSheet = .minimapSettings

                            case .gitCommit:
                                NotificationCenter.default.post(name: NSNotification.Name("GitCommitAction"), object: nil)
                            case .gitPull:
                                NotificationCenter.default.post(name: NSNotification.Name("GitPullAction"), object: nil)
                            case .gitPush:
                                NotificationCenter.default.post(name: NSNotification.Name("GitPushAction"), object: nil)
                            case .gitCheckout:
                                activeSheet = .sourceControl
                            case .gitNewBranch:
                                activeSheet = .sourceControl
                            case .openDiffViewer:
                                activeSheet = .diffViewer

                            case .runAgent:
                                activeSheet = .aiAgent
                            case .aiCodeReview:
                                activeSheet = .codeReview
                            case .aiComplexity:
                                activeSheet = .complexityAnalyzer

                            case .runBuild:
                                activeSheet = .buildStatus
                            case .openXcodeBuildSettings:
                                activeSheet = .xcodeBuildSettings
                            case .openXcodeBuildLogs:
                                activeSheet = .xcodeBuildLogs
                            case .appleSigning:
                                activeSheet = .appleDeveloperAccount

                            case .openSettings:
                                activeSheet = .settings
                            case .openProjectSettings:
                                activeSheet = .projectSettings
                            case .installDependency:
                                activeSheet = .dependencyManager
                            case .openPluginManager:
                                activeSheet = .pluginManager
                            case .openExtensionMarketplace:
                                activeSheet = .extensionMarketplace
                            case .customizeToolbar:
                                activeSheet = .toolbarCustomization

                            case .devHTTPStatus, .devJSONFormatter, .devBase64, .devJWTDecoder, .devPasswordGen, .devRegExTester, .devUUIDGen, .devURLEncoder, .devMarkdownPreview, .devDeviceInfo:
                                activeSheet = .devTools
                            }
                        }
                    }
                case .mainTools: MainToolsView()
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
                case .gitHubIssues: LegacyGitHubIssuesView()
                case .complexityAnalyzer: ComplexityAnalyzerView()
                case .localSimulation: LocalSimulationView()
                case .simulatorMain: SimulatorMainView()
                case .searchDocumentation: SearchDocumentationView()
                case .sfSymbolsBrowser: SFSymbolPickerView()
                case .snippetsLibrary: SnippetsLibraryView()
                case .codeRefactoring: CodeRefactoringView()
                case .errorDiagnostics: ErrorDiagnosticsView()
                case .codeIntelligence: CodeIntelligenceView()
                case .workspaceProfiles: WorkspaceProfilesView()
                case .gitHub: GitHubIntegrationView(project: project)
                case .devTools: DevToolsMainView()
                case .sourceControl:
                    Color.clear
                        .frame(width: 0, height: 0)
                        .onAppear {
                            let scView = SourceControlView(gitViewModel: viewModel.git)
                            scView.show(for: project)
                            activeSheet = nil
                        }
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
                        onSkip: { activeSheet = nil },
                        onContinue: { activeSheet = nil }
                    )
                    .onAppear {
                        let project = sessionStore.activeProject ?? Project(name: "Untitled")
                        appName = project.name
                        let ciConfig = project.ciBuildConfiguration
                        bundleIdentifier = ciConfig?.bundleIdentifier ?? "com.example.\(project.name.lowercased())"
                    }
                    .frame(width: 820, height: 650)

                case .personalDocumentation:
                    NSPersonalDocumentationView()
                        .frame(minWidth: 800, minHeight: 600)

                case .settings:
                    SettingsView()
                        .environmentObject(AppSettings.shared)
                        .frame(width: 500, height: 400)

                case .ipaBuild:
                    IPABuildView()

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
