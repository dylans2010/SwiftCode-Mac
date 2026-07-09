import SwiftUI

@main
struct SwiftCodeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        Task {
            do {
                try await Bootstrapper.shared.bootstrap()
            } catch {
                print("Kernel Bootstrap failed: \(error)")
            }
        }
        OfflineModelDownloader.shared.registerBackgroundTask()
        AgentSystemInitializer.shared.initialize()
        StylingBootstrap.initialize()
    }

    @StateObject private var projectManager = ProjectManager.shared
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
                    if let activeProject = projectManager.activeProject {
                        WorkspaceView(viewModel: WorkspaceViewModel(projectURL: activeProject.directoryURL))
                            .navigationTitle(activeProject.name)
                    } else {
                        HomeView()
                            .navigationTitle("SwiftCode")
                    }
                }
            )
            .environment(themeVM)
            .environmentObject(projectManager)
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
            }
        }
        .commands {
            AppCommands()
        }
    }
}
