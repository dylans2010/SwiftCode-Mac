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

    // Dashboard State & Layout customization
    @State private var searchQuery = ""
    @State private var selectedCategory = "All"

    // Custom storage for tools state
    @State private var pinnedToolIDs: Set<String> = []
    @State private var favoritedToolIDs: Set<String> = []
    @State private var hiddenToolIDs: Set<String> = []
    @State private var toolsOrder: [String] = []

    // Static baseline definition of all tools
    private let allAvailableTools: [WorkspaceTool] = [
        WorkspaceTool(id: "build_settings", name: "Xcode Build Settings", description: "Manage optimization levels, target SDKs, and build parameters.", iconName: "gearshape.2.fill", colorHex: "#34C759", category: "Build & Deploy", destination: "xcodeBuildSettings"),
        WorkspaceTool(id: "build_logs", name: "Xcode Build Logs", description: "Stream compile warnings, errors, and live build output.", iconName: "doc.text.fill", colorHex: "#FF9500", category: "Build & Deploy", destination: "xcodeBuildLogs"),
        WorkspaceTool(id: "ipa_builder", name: "IPA Packaging Suite", description: "Pack built iOS apps into IPA containers from SwiftCode without Xcode UI.", iconName: "shippingbox.fill", colorHex: "#AF52DE", category: "Build & Deploy", destination: "ipaBuild"),
        WorkspaceTool(id: "dependency_manager", name: "Dependency Manager", description: "Search, import, and manage local or remote Swift packages.", iconName: "puzzlepiece.extension.fill", colorHex: "#007AFF", category: "Utilities", destination: "dependencyManager"),
        WorkspaceTool(id: "deployments", name: "Deployments Console", description: "Trigger production deployments to Netlify, Vercel, and GitHub Pages.", iconName: "cloud.fill", colorHex: "#5AC8FA", category: "Build & Deploy", destination: "deployments"),
        WorkspaceTool(id: "source_control", name: "Source Control", description: "Inspect Git history, commits, stashes, merges, and conflicts.", iconName: "square.stack.3d.down.right.fill", colorHex: "#4CD964", category: "Git & CI", destination: "sourceControl"),
        WorkspaceTool(id: "ci_build", name: "CI Visual Workflows", description: "Create and monitor GitHub Actions workflow runners visually.", iconName: "play.circle.fill", colorHex: "#5856D6", category: "Git & CI", destination: "ciBuild"),
        WorkspaceTool(id: "simulator_main", name: "Simulator & Previews", description: "Simulate devices, manage simulators, and inspect preview screens.", iconName: "iphone", colorHex: "#FF2D55", category: "Utilities", destination: "simulatorMain"),
        WorkspaceTool(id: "personal_documentation", name: "Personal Documentation", description: "Access personal markdown wikis, notes, and local code references.", iconName: "book.fill", colorHex: "#A2845E", category: "Utilities", destination: "personalDocumentation"),
        WorkspaceTool(id: "dev_tools", name: "Developer utility bundle", description: "JSON formatters, base64 encoders, regex checkers, and JWT tools.", iconName: "wrench.and.screwdriver.fill", colorHex: "#FF3B30", category: "Utilities", destination: "devTools"),
        WorkspaceTool(id: "collaboration", name: "Live Collaboration", description: "Coordinate real-time coding sessions with team members.", iconName: "person.2.fill", colorHex: "#34C759", category: "Utilities", destination: "collaboration"),
        WorkspaceTool(id: "sf_symbols", name: "SF Symbols Browser", description: "Search and copy native SF Symbol identifiers.", iconName: "sparkles", colorHex: "#FFCC00", category: "Utilities", destination: "sfSymbolsBrowser"),
        WorkspaceTool(id: "extension_marketplace", name: "Extension Marketplace", description: "Browse and install community tools, themes, and extensions.", iconName: "bag.fill", colorHex: "#AF52DE", category: "Utilities", destination: "extensionMarketplace"),
        WorkspaceTool(id: "crash_log_analyzer", name: "Crash Log Analyzer", description: "Analyze production crash logs and trace symbolic memory leaks.", iconName: "doc.richtext.fill", colorHex: "#FF3B30", category: "Utilities", destination: "crashLogAnalyzer"),
        WorkspaceTool(id: "project_dependency_graph", name: "Project Dependency Graph", description: "Render internal project file import mapping and graphs.", iconName: "network", colorHex: "#007AFF", category: "Utilities", destination: "projectDependencyGraph"),
        WorkspaceTool(id: "workspace_profiles", name: "Workspace Profiles", description: "Create, edit, duplicate, and switch between workspace setting profiles.", iconName: "person.crop.square.fill.and.at.rectangle.fill", colorHex: "#34C759", category: "Utilities", destination: "workspaceProfiles"),
        WorkspaceTool(id: "snippets_library", name: "Snippets Library", description: "Store, tag, categorize, and quickly insert code snippet templates with live syntax highlighting.", iconName: "curlybraces", colorHex: "#FF9500", category: "Utilities", destination: "snippetsLibrary")
    ]

    var body: some View {
        AdaptivePage {
            HStack(spacing: 0) {
                // Sidebar remains visible on the left to navigate files
                FileNavigatorSidebarView(viewModel: viewModel.projectTree)
                    .frame(minWidth: 200, idealWidth: 240, maxWidth: 320)

                Divider()

                // Center Tools Dashboard View
                VStack(spacing: 0) {
                    // Header Area
                    dashboardHeaderView
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .background(.ultraThinMaterial)

                    Divider()

                    // Scrollable Grid of interactive tools
                    ScrollView {
                        VStack(spacing: 24) {
                            // Search and Category Selector
                            searchAndCategoryFiltersView

                            // Pinned Section
                            let pinnedTools = filteredToolsList().filter { pinnedToolIDs.contains($0.id) }
                            if !pinnedTools.isEmpty {
                                dashboardSection(title: "Pinned Tools", systemImage: "pin.fill", tools: pinnedTools, color: .orange)
                            }

                            // Main Tools List Section
                            let remainingTools = filteredToolsList().filter { !pinnedToolIDs.contains($0.id) }
                            if !remainingTools.isEmpty {
                                dashboardSection(title: "Active Tools", systemImage: "squares.shape.squares.of.four", tools: remainingTools, color: .blue)
                            } else if pinnedTools.isEmpty {
                                ContentUnavailableView(
                                    "No Tools Match Criteria",
                                    systemImage: "wrench.and.screwdriver",
                                    description: Text("Try clearing your search query or choosing another category filter.")
                                )
                                .padding(.top, 40)
                            }

                            // Hidden Tools Management Shelf
                            let hiddenTools = allAvailableTools.filter { hiddenToolIDs.contains($0.id) }
                            if !hiddenTools.isEmpty {
                                hiddenToolsShelfView(hiddenTools: hiddenTools)
                            }
                        }
                        .padding(24)
                    }
                    .background(Color(hex: themeVM.currentTheme.background))
                }
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
        .onAppear {
            loadDashboardState()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    sessionStore.closeProject()
                } label: {
                    Label("Close Project", systemImage: "xmark.square")
                }
                .help("Close current project")

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

                BuildToolbarView(viewModel: viewModel.build, projectURL: viewModel.projectURL)
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

    // MARK: - Dashboard Layout Parts

    private var dashboardHeaderView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(sessionStore.activeProject?.name ?? "SwiftCode")
                        .font(.title2.bold())
                        .foregroundStyle(.primary)

                    Text("WORKSPACE")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.accentColor.opacity(0.12))
                        .foregroundStyle(Color.accentColor)
                        .cornerRadius(4)
                }
                Text("Manage project specifications, build tools, dependency packages, and CI runs.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()

            Button {
                showingExportSheet = true
            } label: {
                Label("Export (.scproj)", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
        }
    }

    private var searchAndCategoryFiltersView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // Search Input Field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Search workspace tools...", text: $searchQuery)
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()

                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

                Spacer()
            }

            // Category Filter Pills
            HStack(spacing: 8) {
                let categories = ["All", "Favorites", "Pinned", "Build & Deploy", "Git & CI", "Utilities"]
                ForEach(categories, id: \.self) { cat in
                    Button {
                        selectedCategory = cat
                    } label: {
                        Text(cat)
                            .font(.subheadline)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(selectedCategory == cat ? Color.accentColor : Color.secondary.opacity(0.1), in: Capsule())
                            .foregroundStyle(selectedCategory == cat ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
        }
    }

    @ViewBuilder
    private func dashboardSection(title: String, systemImage: String, tools: [WorkspaceTool], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .foregroundStyle(color)
                Text(title)
                    .font(.headline.bold())
                Spacer()
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280))], spacing: 16) {
                ForEach(tools) { tool in
                    toolCardView(tool: tool)
                }
            }
        }
    }

    private func toolCardView(tool: WorkspaceTool) -> some View {
        let isFav = favoritedToolIDs.contains(tool.id)
        let isPinned = pinnedToolIDs.contains(tool.id)

        return GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(hex: tool.colorHex).opacity(0.12))
                            .frame(width: 36, height: 32)
                        Image(systemName: tool.iconName)
                            .font(.title3)
                            .foregroundStyle(Color(hex: tool.colorHex))
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(tool.name)
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                        Text(tool.category.uppercased())
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Card Options controls
                    HStack(spacing: 8) {
                        Button {
                            toggleFavorite(tool.id)
                        } label: {
                            Image(systemName: isFav ? "star.fill" : "star")
                                .foregroundStyle(isFav ? .yellow : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(isFav ? "Remove Favorite" : "Favorite")

                        Button {
                            togglePin(tool.id)
                        } label: {
                            Image(systemName: isPinned ? "pin.fill" : "pin")
                                .foregroundStyle(isPinned ? .orange : .secondary)
                        }
                        .buttonStyle(.plain)
                        .help(isPinned ? "Unpin Tool" : "Pin Tool")

                        Button {
                            hideTool(tool.id)
                        } label: {
                            Image(systemName: "eye.slash")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Hide Tool")
                    }
                }

                Text(tool.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    launchTool(tool)
                } label: {
                    HStack {
                        Text("Open Tool")
                        Spacer()
                        Image(systemName: "arrow.right.circle.fill")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(4)
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }

    private func hiddenToolsShelfView(hiddenTools: [WorkspaceTool]) -> some View {
        GroupBox {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Spacer()
                        Button("Restore All Hidden Tools") {
                            withAnimation(.spring()) {
                                hiddenToolIDs.removeAll()
                                saveDashboardState()
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(.top, 4)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 10) {
                        ForEach(hiddenTools) { tool in
                            HStack {
                                Image(systemName: tool.iconName)
                                    .foregroundStyle(Color(hex: tool.colorHex))
                                Text(tool.name)
                                    .font(.caption.bold())
                                Spacer()
                                Button("Restore") {
                                    withAnimation(.spring()) {
                                        hiddenToolIDs.remove(tool.id)
                                        saveDashboardState()
                                    }
                                }
                                .buttonStyle(.plain)
                                .font(.caption2)
                                .foregroundStyle(Color.accentColor)
                            }
                            .padding(8)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "eye.slash.fill")
                        .foregroundStyle(.secondary)
                    Text("Hidden Tools Management (\(hiddenTools.count))")
                        .font(.headline)
                    Spacer()
                }
            }
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }

    // MARK: - Dashboard Operations

    private func filteredToolsList() -> [WorkspaceTool] {
        var list = allAvailableTools.filter { !hiddenToolIDs.contains($0.id) }

        if !searchQuery.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(searchQuery) || $0.description.localizedCaseInsensitiveContains(searchQuery) }
        }

        switch selectedCategory {
        case "Favorites":
            return list.filter { favoritedToolIDs.contains($0.id) }
        case "Pinned":
            return list.filter { pinnedToolIDs.contains($0.id) }
        case "All":
            return list
        default:
            return list.filter { $0.category == selectedCategory }
        }
    }

    private func launchTool(_ tool: WorkspaceTool) {
        if let dest = ToolbarActionManager.SheetDestination(rawValue: tool.destination) {
            activeSheet = dest
        }
    }

    private func toggleFavorite(_ id: String) {
        withAnimation(.spring()) {
            if favoritedToolIDs.contains(id) {
                favoritedToolIDs.remove(id)
            } else {
                favoritedToolIDs.insert(id)
            }
            saveDashboardState()
        }
    }

    private func togglePin(_ id: String) {
        withAnimation(.spring()) {
            if pinnedToolIDs.contains(id) {
                pinnedToolIDs.remove(id)
            } else {
                pinnedToolIDs.insert(id)
            }
            saveDashboardState()
        }
    }

    private func hideTool(_ id: String) {
        withAnimation(.spring()) {
            hiddenToolIDs.insert(id)
            saveDashboardState()
        }
    }

    // MARK: - Persistence Helpers

    private func loadDashboardState() {
        if let favs = UserDefaults.standard.stringArray(forKey: "com.swiftcode.dashboard.favorites") {
            favoritedToolIDs = Set(favs)
        }
        if let pins = UserDefaults.standard.stringArray(forKey: "com.swiftcode.dashboard.pinned") {
            pinnedToolIDs = Set(pins)
        }
        if let hidden = UserDefaults.standard.stringArray(forKey: "com.swiftcode.dashboard.hidden") {
            hiddenToolIDs = Set(hidden)
        }
    }

    private func saveDashboardState() {
        UserDefaults.standard.set(Array(favoritedToolIDs), forKey: "com.swiftcode.dashboard.favorites")
        UserDefaults.standard.set(Array(pinnedToolIDs), forKey: "com.swiftcode.dashboard.pinned")
        UserDefaults.standard.set(Array(hiddenToolIDs), forKey: "com.swiftcode.dashboard.hidden")
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
                        .frame(minWidth: 800, minHeight: 600)

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
