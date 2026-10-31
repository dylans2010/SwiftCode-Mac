import SwiftUI

@main
struct SwiftCodeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        if CommandLine.arguments.contains("--run-assist-tests") {
            Task { @MainActor in
                let report = await AssistRuntimeTestSuite.shared.runAllTests()
                print("========================================")
                print("ASSIST V3 RUNTIME TEST SUITE REPORT")
                print("Total: \(report.totalTests), Passed: \(report.passedTests), Failed: \(report.failedTests)")
                for r in report.results {
                    print("[\(r.passed ? "PASS" : "FAIL")] \(r.testName) (\(String(format: "%.3f", r.duration))s): \(r.message)")
                }
                print("========================================")
                fflush(stdout)
                exit(report.allPassed ? 0 : 1)
            }
        }
        AgentSystemInitializer.shared.initialize()
        StylingBootstrap.initialize()
        LicenseCatalog.prewarm()
        // SwiftCode SDK host bootstrap (one-time, idempotent): registers the
        // built-in view openers on the main actor before any extension can
        // call `ui.openView`. Failures are logged, not thrown, by the bootstrap.
        Task { await SDKBootstrap.bootstrapIfNeeded() }
    }

    @State private var sessionStore = ProjectSessionStore.shared
    /// A Finder-opened `.scproj` package awaiting the trust decision.
    @State private var pendingScprojURL: URL?
    /// Error from a Finder open or a trust-alert delete, if any.
    @State private var finderOpenError: String?
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
                            .ignoresSafeArea()
                    }
                }
            )
            .ignoresSafeArea()
            .onAppear {
                DispatchQueue.main.async {
                    if let window = NSApplication.shared.windows.first(where: { $0.isVisible && !($0 is NSPanel) }) {
                        if sessionStore.activeProject != nil {
                            window.isOpaque = true
                            window.backgroundColor = nil
                            window.showsResizeIndicator = true
                            window.isMovableByWindowBackground = false
                            window.titleVisibility = .hidden
                            window.titlebarAppearsTransparent = true
                            window.titlebarSeparatorStyle = .none
                            window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
                            window.collectionBehavior.insert(.fullScreenPrimary)
                            window.minSize = NSSize(width: 900, height: 600)
                            window.maxSize = NSSize(width: 10000, height: 10000)
                            if let titlebarView = window.standardWindowButton(.closeButton)?.superview {
                                titlebarView.isHidden = false
                            }
                            window.standardWindowButton(.closeButton)?.isHidden = false
                            window.standardWindowButton(.miniaturizeButton)?.isHidden = false
                            window.standardWindowButton(.zoomButton)?.isHidden = false
                            if !window.styleMask.contains(.fullScreen) {
                                window.toggleFullScreen(nil)
                            }
                        } else {
                            window.isOpaque = false
                            window.backgroundColor = .clear
                            window.title = ""
                            window.titleVisibility = .hidden
                            window.titlebarAppearsTransparent = true
                            window.titlebarSeparatorStyle = .none
                            window.toolbar = nil
                            window.standardWindowButton(.closeButton)?.isHidden = true
                            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                            window.standardWindowButton(.zoomButton)?.isHidden = true
                            if let titlebarView = window.standardWindowButton(.closeButton)?.superview {
                                titlebarView.isHidden = true
                            }
                        }
                    }
                }
            }
            .onChange(of: sessionStore.activeProject) { _, activeProject in
                DispatchQueue.main.async {
                    if let window = NSApplication.shared.windows.first(where: { $0.isVisible && !($0 is NSPanel) }) {
                        if activeProject != nil {
                            window.isOpaque = true
                            window.backgroundColor = nil
                            window.showsResizeIndicator = true
                            window.isMovableByWindowBackground = false
                            window.titleVisibility = .hidden
                            window.titlebarAppearsTransparent = true
                            window.titlebarSeparatorStyle = .none
                            window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
                            window.collectionBehavior.insert(.fullScreenPrimary)
                            window.minSize = NSSize(width: 900, height: 600)
                            window.maxSize = NSSize(width: 10000, height: 10000)
                            if let titlebarView = window.standardWindowButton(.closeButton)?.superview {
                                titlebarView.isHidden = false
                            }
                            window.standardWindowButton(.closeButton)?.isHidden = false
                            window.standardWindowButton(.miniaturizeButton)?.isHidden = false
                            window.standardWindowButton(.zoomButton)?.isHidden = false
                            if !window.styleMask.contains(.fullScreen) {
                                window.toggleFullScreen(nil)
                            }
                        } else {
                            if window.styleMask.contains(.fullScreen) {
                                window.toggleFullScreen(nil)
                            }
                            window.isOpaque = false
                            window.backgroundColor = .clear
                            window.title = ""
                            window.titleVisibility = .hidden
                            window.titlebarAppearsTransparent = true
                            window.titlebarSeparatorStyle = .none
                            window.toolbar = nil
                            window.standardWindowButton(.closeButton)?.isHidden = true
                            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
                            window.standardWindowButton(.zoomButton)?.isHidden = true
                            if let titlebarView = window.standardWindowButton(.closeButton)?.superview {
                                titlebarView.isHidden = true
                            }
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
                // Finder-opened files arrive here (the app declares
                // .scproj as Owner and .xcodeproj/.xcworkspace as
                // Alternate Viewer in Info.plist). URL schemes keep
                // their existing handlers below.
                if url.isFileURL {
                    handleFinderOpenedFile(url)
                    return
                }
                if url.scheme == "docc" || url.pathExtension.lowercased() == "doccarchive" {
                    DocumentationBrowserWindowManager.shared.openURL(url)
                    return
                }
                if GitHubOAuth.shared.handleOpenURL(url) {
                    return
                }
                if GoogleAccountAuthService.shared.handleOpenURL(url) {
                    return
                }
            }
            .alert(
                "Trust this SwiftCode project?",
                isPresented: Binding(
                    get: { pendingScprojURL != nil },
                    set: { if !$0 { pendingScprojURL = nil } }
                ),
                presenting: pendingScprojURL
            ) { url in
                Button("Trust and Open") {
                    pendingScprojURL = nil
                    ProjectSessionStore.ScprojTrustStore.markTrusted(url)
                    Task {
                        do {
                            let project = try await sessionStore.openScprojPackage(at: url)
                            await sessionStore.openProject(project)
                        } catch {
                            finderOpenError = error.localizedDescription
                        }
                    }
                }
                Button("Delete from Disk", role: .destructive) {
                    pendingScprojURL = nil
                    deleteUntrustedScproj(url)
                }
                Button("Cancel", role: .cancel) {}
            } message: { url in
                // project.json carries no author identity, so the
                // alert names the package and its location instead of
                // inventing an author. Deletion is permanent, by the
                // user's explicit choice at this alert.
                Text("“\(url.lastPathComponent)” at \(url.deletingLastPathComponent().path) was not created by this copy of SwiftCode. SwiftCode projects can run code and tools when opened. Open it only if you trust where it came from — otherwise SwiftCode will permanently delete it from disk.")
            }
            .alert("Couldn't Open File", isPresented: Binding(
                get: { finderOpenError != nil },
                set: { if !$0 { finderOpenError = nil } }
            ), presenting: finderOpenError) { _ in
                Button("OK") {}
            } message: { message in
                Text(message)
            }
            .task {
                // Ensure the persistent Projects and Models directories exist at launch
                codingManager.ensureProjectsDirectory()
                codingManager.ensureModelsDirectory()
                NotificationManager.shared.requestAuthorizationIfNeeded()
                await OfflineModelDownloader.shared.resumePendingDownloadIfNeeded()
                await AssistModelDiscoveryService.shared.discoverAllModels(forceRefresh: true)

                // Initialize the System Index at launch so all AI models (Antigravity, Meta Muse, Cloud, Chat)
                // have instant access to canonical training and system assets from startup.
                await SystemIndexService.shared.ensureReady()

                if CommandLine.arguments.contains("--open-last-project"), let firstProject = sessionStore.projects.first {
                    await sessionStore.openProject(firstProject)
                }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            AppCommands()
        }
    }

    // MARK: - Finder-opened files

    private func handleFinderOpenedFile(_ url: URL) {
        switch url.pathExtension.lowercased() {
        case "scproj":
            // Already trusted once? Open straight away; otherwise
            // the trust alert decides (open, or delete from disk).
            if ProjectSessionStore.ScprojTrustStore.isTrusted(url) {
                Task {
                    do {
                        let project = try await sessionStore.openScprojPackage(at: url)
                        await sessionStore.openProject(project)
                    } catch {
                        finderOpenError = error.localizedDescription
                    }
                }
            } else {
                pendingScprojURL = url
            }
        case "xcodeproj", "xcworkspace":
            // Same path as Open File or Folder in the welcome view:
            // importProject takes the containing directory for a
            // project/workspace bundle, then the project opens.
            Task {
                do {
                    let project = try await sessionStore.importProject(from: url)
                    await sessionStore.openProject(project)
                } catch {
                    finderOpenError = error.localizedDescription
                }
            }
        default:
            break
        }
    }

    /// Deletes an untrusted `.scproj` package from disk, exactly as
    /// the trust alert promises. Also drops it from recents and
    /// forgets any trust grant, so a later copy at the same path is
    /// prompted again instead of opening silently.
    private func deleteUntrustedScproj(_ url: URL) {
        if let existing = sessionStore.projects.first(where: {
            $0.directoryURL.standardizedFileURL.path == url.standardizedFileURL.path
        }) {
            sessionStore.removeProjectFromRecents(existing)
        }
        ProjectSessionStore.ScprojTrustStore.forget(url)
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            finderOpenError = error.localizedDescription
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
            .frame(minWidth: 900, idealWidth: 1400, maxWidth: .infinity, minHeight: 600, idealHeight: 900, maxHeight: .infinity)
            .onAppear {
                DispatchQueue.main.async {
                    configureEditorWindow()
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    configureEditorWindow()
                }
            }
    }

    private func configureEditorWindow() {
        guard let window = NSApplication.shared.windows.first(where: { $0.isVisible && !($0 is NSPanel) }) else { return }
        window.isOpaque = true
        window.backgroundColor = nil
        window.showsResizeIndicator = true
        window.isMovableByWindowBackground = false
        // Titlebar is hidden (see below): the project name lives in the editor jump bar, not a title strip.
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none

        window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView])
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.minSize = NSSize(width: 900, height: 600)
        window.maxSize = NSSize(width: 10000, height: 10000)

        if let titlebarView = window.standardWindowButton(.closeButton)?.superview {
            titlebarView.isHidden = false
        }
        window.standardWindowButton(.closeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isHidden = false

        if !window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        }
    }
}
