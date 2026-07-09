import SwiftUI

struct WorkspaceView: View {
    @State var viewModel: WorkspaceViewModel
    @Environment(ThemeViewModel.self) var themeVM
    @EnvironmentObject private var projectManager: ProjectManager
    @State private var showInspector = false

    // Feature sheet states
    @State private var activeSheet: ToolbarActionManager.SheetDestination?
    @State private var showingExportSheet = false

    var body: some View {
        AdaptivePage {
            AdaptiveEditorPage {
                ProjectNavigatorView(viewModel: viewModel.projectTree)
            } content: {
                EditorTextView(workspaceViewModel: viewModel)
            } inspector: {
                InspectorPanelView(workspaceViewModel: viewModel)
            }
        }
        .environment(viewModel)
        .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        projectManager.closeProject()
                    } label: {
                        Label("Close Project", systemImage: "xmark.square")
                    }
                    .help("Close current project")

                    BuildToolbarView(viewModel: viewModel.build, projectURL: viewModel.projectURL)

                    Button {
                        showInspector.toggle()
                    } label: {
                        Label("Inspector", systemImage: "sidebar.right")
                    }
                    .help("Toggle Inspector (⌘⌥I)")
                }

                ToolbarItemGroup(placement: .secondaryAction) {
                    ControlGroup {
                        Button {
                            activeSheet = .codeSearch
                        } label: {
                            Label("Search", systemImage: "magnifyingglass")
                        }
                        .help("Global Search")

                        Button {
                            activeSheet = .settings
                        } label: {
                            Label("Settings", systemImage: "gear")
                        }
                        .help("Settings")
                    }

                    Menu {
                        Section("Project") {
                            Button("Gists") { activeSheet = .gistManager }
                            Button("Deployments") { activeSheet = .deployments }
                            Button("Collaboration") { activeSheet = .collaboration }
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
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                }
            }
            .inspector(isPresented: $showInspector) {
                InspectorPanelView(workspaceViewModel: viewModel)
                    .inspectorColumnWidth(min: 250, ideal: 300)
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
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ToggleInspector"))) { _ in
                showInspector.toggle()
            }
            .background(Color(hex: themeVM.currentTheme.background))
            .foregroundStyle(Color(hex: themeVM.currentTheme.foreground))
            .navigationBarBackButtonHidden(true)
    }

    @ViewBuilder
    private func sheetView(for destination: ToolbarActionManager.SheetDestination) -> some View {
        let project = projectManager.activeProject ?? Project(name: "Untitled")
        let owner = project.githubRepo?.split(separator: "/").first.map(String.init) ?? ""
        let repo = project.githubRepo?.split(separator: "/").last.map(String.init) ?? ""

        AdaptiveSheet {
            NavigationStack {
                Group {
                    switch destination {
                case .codeSearch: CodeSearchView()
                case .settings: GeneralSettingsView()
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
}

struct InspectorPanelView: View {
    let workspaceViewModel: WorkspaceViewModel
    @State private var selection: InspectorTab = .outline

    enum InspectorTab: String, CaseIterable, Identifiable {
        case outline = "list.bullet.indent"
        case settings = "slider.horizontal.3"
        case metrics = "chart.bar"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Tab", selection: $selection) {
                ForEach(InspectorTab.allCases) { tab in
                    Image(systemName: tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            switch selection {
            case .outline:
                SymbolOutlineView()
            case .settings:
                MinimapSettingsView()
            case .metrics:
                CodeMetricsDashboardView()
            }
        }
    }
}
