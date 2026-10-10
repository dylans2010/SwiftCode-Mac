import SwiftUI

@main
struct SwiftCodeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        AgentSystemInitializer.shared.initialize()
        StylingBootstrap.initialize()
        LicenseCatalog.prewarm()
    }

    @State private var sessionStore = ProjectSessionStore.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var codingManager = CodingManager.shared
    @StateObject private var toolbarSettings = ToolbarSettings.shared
    @StateObject private var folderManager = FolderManager.shared
    @StateObject private var codeSuggestionsML = CodeSuggestionsML.shared
    @StateObject private var gistService = GitHubGistService.shared
    @State private var themeVM = ThemeViewModel()

    var body: some Scene {
        WindowGroup {
            StylingBootstrap.configureEnvironment(
                Group {
                    if let activeProject = sessionStore.activeProject {
                        WorkspaceHostView(project: activeProject)
                            .id(activeProject.id)
                    } else {
                        SwiftCodeWelcomeView()
                            .navigationTitle("SwiftCode")
                    }
                }
            )
            .onAppear {
                DispatchQueue.main.async {
                    if let window = NSApplication.shared.windows.first(where: { $0.isVisible }) {
                        window.titleVisibility = .visible
                        window.titlebarAppearsTransparent = false
                        window.standardWindowButton(.closeButton)?.isHidden = false
                        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
                        window.standardWindowButton(.zoomButton)?.isHidden = false
                    }
                }
            }
            .environment(themeVM)
            .environment(sessionStore)
            .environmentObject(settings)
            .environmentObject(toolbarSettings)
            .environmentObject(folderManager)
            .environmentObject(codeSuggestionsML)
            .environmentObject(gistService)
            .onOpenURL { url in
                _ = GitHubOAuth.shared.handleOpenURL(url)
            }
            .task {
                // Ensure the persistent Projects and Models directories exist at launch
                codingManager.ensureProjectsDirectory()
                codingManager.ensureModelsDirectory()
                NotificationManager.shared.requestAuthorizationIfNeeded()
                await OfflineModelDownloader.shared.resumePendingDownloadIfNeeded()
                await AssistModelDiscoveryService.shared.discoverAllModels(forceRefresh: true)

                if CommandLine.arguments.contains("--open-last-project"), let firstProject = sessionStore.projects.first {
                    await sessionStore.openProject(firstProject)
                }
            }
        }
        .commands {
            AppCommands()
        }
    }
}

private struct WorkspaceHostView: View {
    let project: Project
    @State private var viewModel: WorkspaceViewModel

    init(project: Project) {
        self.project = project
        _viewModel = State(wrappedValue: WorkspaceViewModel(projectURL: project.directoryURL))
    }

    var body: some View {
        WorkspaceView(viewModel: viewModel)
            .navigationTitle(project.name)
    }
}
