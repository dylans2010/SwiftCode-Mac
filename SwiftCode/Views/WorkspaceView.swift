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
    @State private var showAgentInspector = false
    @State private var showFileNavigator = true
    @AppStorage("com.swiftcode.workspace.agentInspectorWidth") private var agentInspectorWidth = 320.0
    @State private var dragStartWidth: CGFloat? = nil

    // Collapsible Artboard Simulator Panel
    @State private var showArtboardSimulator = false
    @AppStorage("com.swiftcode.workspace.artboardSimulatorWidth") private var artboardSimulatorWidth = 360.0
    @State private var dragStartWidthSimulator: CGFloat? = nil

    // Collapsible App Details Sidebar Panel
    @State private var showAppDetailsSidebar = false

    // Legacy full-pane special-editor chrome hiding, driven by
    // .specialEditorActive. No current editor posts it (swiftcode.json
    // and .xcstrings are both in-pane now), so this stashes nothing
    // in practice; it is kept only so an older posting view could
    // not leave the workspace chrome hidden.
    @State private var specialEditorActive = false
    @State private var stashedChrome: (fileNavigator: Bool, artboard: Bool, agent: Bool, appDetails: Bool, infoProj: Bool)?
    // Collapsible SwiftCode Project Archive Info Sidebar
    @State private var showInfoProjSidebar = false
    @AppStorage("com.swiftcode.workspace.appDetailsSidebarWidth") private var appDetailsSidebarWidth = 320.0
    @State private var dragStartWidthAppDetails: CGFloat? = nil

    // Feature sheet states
    @State private var activeSheet: ToolbarActionManager.SheetDestination?
    @State private var showingExportSheet = false
    // Extensions sidebar, toggled from the code-editor toolbar next to
    // the Assist button. Renders as a column beside the editor, like Assist.
    @State private var showExtensionsSidebar = false
    @AppStorage("com.swiftcode.workspace.extensionsSidebarWidth") private var extensionsSidebarWidth = 720.0
    @State private var dragStartWidthExtensions: CGFloat? = nil

    // Coding Tools Modal State
    @State private var showCodingToolsModal = false
    @State private var codingToolsAction: CodingToolsUI.CodingAction = .refactor
    @State private var codingToolsCode = ""
    @State private var codingToolsRange: NSRange? = nil
    @State private var codingToolsFilePath = ""

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
                    .liquidGlass(style: .sidebar, cornerRadius: 18)
                    .padding(8)
                    .transition(.move(edge: .leading).combined(with: .opacity))

                    Divider()
                }

                // Center Code Editor View
                EditorView(viewModel: viewModel.editor)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if showArtboardSimulator {
                    // Resizing drag handle for Simulator
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
                                    if dragStartWidthSimulator == nil {
                                        dragStartWidthSimulator = artboardSimulatorWidth
                                    }
                                    let delta = value.translation.width
                                    let newWidth = (dragStartWidthSimulator ?? 360.0) - delta
                                    artboardSimulatorWidth = max(280, min(800, newWidth))
                                }
                                .onEnded { _ in
                                    dragStartWidthSimulator = nil
                                }
                        )

                    ArtboardSimulator(onClose: {
                        withAnimation(.spring()) {
                            showArtboardSimulator = false
                        }
                    })
                    .frame(width: artboardSimulatorWidth)
                    .transition(.move(edge: .trailing))
                }

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

                if showExtensionsSidebar {
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
                                    if dragStartWidthExtensions == nil {
                                        dragStartWidthExtensions = extensionsSidebarWidth
                                    }
                                    let delta = value.translation.width
                                    let newWidth = (dragStartWidthExtensions ?? 720.0) - delta
                                    extensionsSidebarWidth = max(480, min(1200, newWidth))
                                }
                                .onEnded { _ in
                                    dragStartWidthExtensions = nil
                                }
                        )

                    ExtensionsHomeView()
                        .frame(width: extensionsSidebarWidth)
                        .transition(.move(edge: .trailing))
                }

                if showAppDetailsSidebar {
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
                                    if dragStartWidthAppDetails == nil {
                                        dragStartWidthAppDetails = appDetailsSidebarWidth
                                    }
                                    let delta = value.translation.width
                                    let newWidth = (dragStartWidthAppDetails ?? 320.0) - delta
                                    appDetailsSidebarWidth = max(280, min(600, newWidth))
                                }
                                .onEnded { _ in
                                    dragStartWidthAppDetails = nil
                                }
                        )

                    XcodeProjectDetailsSheet()
                        .frame(width: appDetailsSidebarWidth)
                        .transition(.move(edge: .trailing))
                }

                if showInfoProjSidebar, let project = sessionStore.activeProject {
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
                                .onChanged { _ in }
                        )

                    InfoProjView(project: project)
                        .frame(width: 320)
                        .liquidGlass(style: .sidebar, cornerRadius: 16)
                        .padding(8)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }
        .background(
            Button("") {
                activeSheet = .codeSearch
            }
            .keyboardShortcut("p", modifiers: [.option])
            .buttonStyle(.plain)
            .opacity(0)
            .frame(width: 0, height: 0)
        )
        .environment(viewModel)
        .toolbar {
            // No toolbar at all while a full-pane special editor is
            // active (swiftcode.json).
            if !specialEditorActive {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        sessionStore.closeProject()
                    } label: {
                        Label("Close Project", systemImage: "xmark.square")
                    }
                    .help("Close current project")

                    Button {
                        withAnimation(.spring()) {
                            showFileNavigator.toggle()
                            if let session = sessionStore.activeSession {
                                session.showFileNavigator = showFileNavigator
                                sessionStore.saveSession(session)
                            }
                        }
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
                            showArtboardSimulator.toggle()
                            if let session = sessionStore.activeSession {
                                session.showArtboardSimulator = showArtboardSimulator
                                sessionStore.saveSession(session)
                            }
                        }
                    } label: {
                        Image(systemName: "macwindow.on.rectangle")
                            .foregroundColor(showArtboardSimulator ? .accentColor : .secondary)
                    }
                    .help("Toggle Artboard Simulator")

                    Button {
                        withAnimation(.spring()) {
                            showAgentInspector.toggle()
                        }
                    } label: {
                        Image(systemName: "sparkles")
                            .foregroundColor(showAgentInspector ? .accentColor : .secondary)
                    }
                    .help("Toggle AI Agent Inspector")

                    Button {
                        withAnimation(.spring()) {
                            showExtensionsSidebar.toggle()
                        }
                    } label: {
                        Image(systemName: "puzzlepiece")
                            .foregroundColor(showExtensionsSidebar ? .accentColor : .secondary)
                    }
                    .help("Toggle Extensions")

                    BuildToolbarView(viewModel: viewModel.build, projectURL: viewModel.projectURL, editorViewModel: viewModel.editor)
                }
            }
        }
        .sheet(item: $activeSheet) { destination in
            sheetView(for: destination)
        }
        .sheet(isPresented: $showingExportSheet) {
            ExportProjView()
        }
        .sheet(isPresented: Bindable(XcodeBuildAPI.shared).showProjectGenerationUI) {
            BuildingXcodeProject()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ShowExportSheet"))) { _ in
            showingExportSheet = true
        }
        .onAppear {
            if let session = sessionStore.activeSession {
                showFileNavigator = session.showFileNavigator
                showArtboardSimulator = session.showArtboardSimulator
                showAgentInspector = session.showAgentInspector
                showAppDetailsSidebar = session.showAppDetailsSidebar
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .toolbarToolActivated)) { notification in
            if let toolId = notification.userInfo?["toolID"] as? String {
                if toolId == "studio" || toolId == "sdk_studio" {
                    SDKStudioWindowManager.shared.openStudio()
                } else if toolId == "ai_code_gen" || toolId == "assist_view" || toolId == "runAgent" || toolId == "ai_agent" {
                    withAnimation(.spring()) {
                        showAgentInspector = true
                        if let session = sessionStore.activeSession {
                            session.showAgentInspector = true
                            sessionStore.saveSession(session)
                        }
                    }
                } else if let destination = ToolbarActionManager.shared.destination(for: toolId) {
                    activeSheet = destination
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("OpenStudio"))) { _ in
            SDKStudioWindowManager.shared.openStudio()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("com.swiftcode.openFileInWorkspace"))) { notification in
            if let filePath = notification.userInfo?["filePath"] as? String {
                let url = URL(fileURLWithPath: filePath)
                Task {
                    await viewModel.editor.openFile(url: url)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .specialEditorActive)) { notification in
            let active = notification.userInfo?["active"] as? Bool ?? false
            if active, !specialEditorActive, stashedChrome == nil {
                // Stash exactly what was visible, then hide everything.
                stashedChrome = (showFileNavigator, showArtboardSimulator, showAgentInspector, showAppDetailsSidebar, showInfoProjSidebar)
                withAnimation(.spring()) {
                    showFileNavigator = false
                    showArtboardSimulator = false
                    showAgentInspector = false
                    showAppDetailsSidebar = false
                    showInfoProjSidebar = false
                }
            } else if !active, specialEditorActive, let stashed = stashedChrome {
                withAnimation(.spring()) {
                    showFileNavigator = stashed.fileNavigator
                    showArtboardSimulator = stashed.artboard
                    showAgentInspector = stashed.agent
                    showAppDetailsSidebar = stashed.appDetails
                    showInfoProjSidebar = stashed.infoProj
                }
                stashedChrome = nil
            }
            specialEditorActive = active
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("com.swiftcode.openArtboardSimulator"))) { notification in
            withAnimation(.spring()) {
                showArtboardSimulator = true
                if let session = sessionStore.activeSession {
                    session.showArtboardSimulator = true
                    sessionStore.saveSession(session)
                }
            }
            if let artboardID = notification.userInfo?["artboardID"] as? UUID {
                if let visDoc = DocumentCoordinator.shared.visualUIDocument {
                    visDoc.scene.activeArtboardID = artboardID
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("com.swiftcode.toggleAppDetailsSidebar"))) { _ in
            withAnimation(.spring()) {
                showAppDetailsSidebar.toggle()
                if let session = sessionStore.activeSession {
                    session.showAppDetailsSidebar = showAppDetailsSidebar
                    sessionStore.saveSession(session)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("com.swiftcode.toggleInfoProjSidebar"))) { _ in
            withAnimation(.spring()) {
                showInfoProjSidebar.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("TriggerCodingToolsContextAction"))) { notification in
            let userInfo = notification.userInfo
            let action = userInfo?["action"] as? CodingToolsUI.CodingAction ?? .refactor
            let code = userInfo?["code"] as? String ?? ""
            let range = userInfo?["range"] as? NSRange
            let path = userInfo?["filePath"] as? String ?? sessionStore.activeFileNode?.path ?? "File.swift"

            self.codingToolsAction = action
            self.codingToolsCode = code.isEmpty ? sessionStore.activeFileContent : code
            self.codingToolsRange = range
            self.codingToolsFilePath = path
            self.showCodingToolsModal = true
        }
        .sheet(isPresented: $showCodingToolsModal) {
            CodingToolsUI(
                selectedCode: codingToolsCode.isEmpty ? sessionStore.activeFileContent : codingToolsCode,
                fullFileContent: sessionStore.activeFileContent,
                filePath: codingToolsFilePath.isEmpty ? (sessionStore.activeFileNode?.path ?? "File.swift") : codingToolsFilePath,
                initialAction: codingToolsAction,
                onApplyCode: { newCode in
                    if let range = codingToolsRange, range.length > 0 {
                        let current = sessionStore.activeFileContent as NSString
                        if range.location + range.length <= current.length {
                            let updated = current.replacingCharacters(in: range, with: newCode)
                            sessionStore.activeFileContent = updated
                            sessionStore.saveCurrentFile(content: updated)
                            codingToolsRange = nil
                            codingToolsCode = ""
                            showCodingToolsModal = false
                            return
                        }
                    }
                    sessionStore.activeFileContent = newCode
                    sessionStore.saveCurrentFile(content: newCode)
                    codingToolsRange = nil
                    codingToolsCode = ""
                    showCodingToolsModal = false
                }
            )
            .fixedSize()
            .presentationSizing(.fitted)
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
                case .codingDictionary: CodingDictionaryView()
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
                case .localSimulation: SimulatorPreviewView()
                case .simulatorMain: SimulatorMainView()
                case .searchDocumentation: SearchDocumentationView()
                case .sfSymbolsBrowser: SFSymbolPickerView()
                case .snippetsLibrary:
                    SnippetsLibraryView()
                        .frame(minWidth: 880, maxWidth: 960, minHeight: 520, maxHeight: 600)
                case .codeRefactoring: CodeRefactoringView()
                case .errorDiagnostics: ErrorDiagnosticsView()
                case .codeIntelligence: CodeIntelligenceView()
                case .workspaceProfiles:
                    WorkspaceProfilesView()
                        .frame(minWidth: 880, maxWidth: 960, minHeight: 520, maxHeight: 600)
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

                case .visualUIBuilder:
                    VisualUIBuilderView()
                        .frame(minWidth: 1000, minHeight: 700)

                case .databaseExplorer:
                    DatabaseExplorerView()
                        .frame(minWidth: 1000, minHeight: 700)

                case .projectInspector:
                    ProjectInspectorView()
                        .frame(minWidth: 1000, minHeight: 700)

                case .localizationManager:
                    LocalizationManagerView()
                        .frame(minWidth: 1080, idealWidth: 1200, minHeight: 700, idealHeight: 780)

                case .deviceConnect:
                    DeviceConnectView()
                        .frame(minWidth: 880, maxWidth: 960, minHeight: 520, maxHeight: 600)

                case .virtualization:
                    SCVirtualizationView()

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
