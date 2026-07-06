import SwiftUI

@main
struct SwiftCodeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        OfflineModelDownloader.shared.registerBackgroundTask()
        AgentSystemInitializer.shared.initialize()
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
            HomeView()
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
