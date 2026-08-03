import SwiftUI

@main
struct SwiftCodeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        OfflineModelDownloader.shared.registerBackgroundTask()
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
    @State private var authManager = AuthManager.shared

    var body: some Scene {
        WindowGroup {
            StylingBootstrap.configureEnvironment(
                Group {
                    if authManager.isLoading {
                        VStack(spacing: 16) {
                            ProgressView()
                                .controlSize(.large)
                            Text("Restoring active cloud session...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(NSColor.windowBackgroundColor))
                    } else if !authManager.isAuthenticated {
                        CloudAuthViews(isGate: true, onSuccess: {
                            Task {
                                await CloudManager.shared.initialize()
                            }
                        })
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(NSColor.windowBackgroundColor))
                    } else if let activeProject = sessionStore.activeProject {
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
                        window.titleVisibility = .hidden
                        window.titlebarAppearsTransparent = true
                        window.standardWindowButton(.closeButton)?.isHidden = true
                        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                        window.standardWindowButton(.zoomButton)?.isHidden = true
                        if !window.styleMask.contains(.fullSizeContentView) {
                            window.styleMask.insert(.fullSizeContentView)
                        }
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

                // Restore session on launch and initialize cloud
                await authManager.restoreSession()
                if authManager.isAuthenticated {
                    await CloudManager.shared.initialize()
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
