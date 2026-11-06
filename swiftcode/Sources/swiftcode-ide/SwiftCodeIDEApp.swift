import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
import SwiftCodeAssistant
import SwiftCodeIDECore
import SwiftCodeIDEShell
import SwiftCodeRelease
#if os(Linux)
import OVText
#endif

// swiftcode-ide: the SwiftUI workspace shell (docs/PARITY.md §5, milestone L1).
// On Linux `import SwiftUI` is OpenViews (frameworks/swiftui), SwiftCode's own
// SwiftUI; on macOS it is Apple's SwiftUI, so the same views prove the
// shell is shared. The macOS product is still the AppKit IDE (SwiftCodeApp).
//
//     swiftcode-ide [<project, workspace, Package.swift or package folder>]
//
// Without a path the Welcome screen shows; File ▸ Open… asks for a path.
// The Linux driver switches (ShellDriver.swift) run only on OpenViews.

/// The app's one model, shared by the scene, the menus and the driver.
@MainActor
enum ShellApp {
    static let model = ShellAppModel()
}

@main
struct SwiftCodeIDEApp: App {
    init() {
        // Legacy `SwiftCodeApp`: --run-assist-tests runs the Assist v3 runtime
        // test suite, prints the report, and exits 0 (all passed) / 1. Checked
        // first, before any shell setup, exactly as Legacy did. Landed with
        // the AssistRuntimeTestSuite subset (SwiftCodeAssistant) by F1B.
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
        SwiftCodeRelease.handleVersionFlag(tool: "swiftcode-ide")
        SwiftCodeRelease.adoptBundledHelpers()
        ShellLook.apply()
        // WIRING (wiring-backend): the styling bootstrap, once at app
        // start (Legacy `StylingBootstrap.initialize()` — installs the
        // adaptive layout engine / liquid-glass environment the
        // `.macDesktopOptimized()` views read). The registry's
        // `registerDefaults()` is an empty no-op in Legacy and stays one.
        StylingBootstrap.initialize()
        // The models' Copy commands (Debug ▸ Console ▸ Copy Row) write here.
        ShellPasteboard.writer = { ShellClipboard.copy($0) }
        #if os(Linux)
        // Quit and the window's close button ask about unsaved changes first.
        ApplicationTermination.shouldTerminate = { ShellApp.model.shouldQuit() }
        ShellApp.model.terminateApp = { OpenViewsAutomation.terminate() }
        #endif
        // A language server or build tool that dies must not take the app
        // with it: writing to its closed pipe fails instead of signalling.
        signal(SIGPIPE, SIG_IGN)
        // Live issues from sourcekit-lsp; SWIFTCODE_IDE_LSP=0 leaves it off.
        ShellApp.model.startsLanguageService = ProcessInfo.processInfo.environment["SWIFTCODE_IDE_LSP"] != "0"
        // The simulator runtime wizard, once, when this computer has none (runtime-onboarding.md §3).
        ShellApp.model.offerRuntimeSetupAtFirstLaunch()
        if let path = ShellAppModel.launchPath() {
            if !ShellApp.model.open(path: path) {
                FileHandle.standardError.write(Data("swiftcode-ide: \(ShellApp.model.openError ?? "cannot open \(path)")\n".utf8))
            }
        }
    }

    var body: some Scene {
        WindowGroup("SwiftCode") {
            // WIRING (wiring-backend): the layout engine and liquid-glass
            // environment must be installed above every view that uses
            // `.macDesktopOptimized()` or `.liquidGlass(...)`.
            StylingBootstrap.configureEnvironment(ShellRootView(app: ShellApp.model)).shellAppearance()
        }
        .defaultSize(width: ShellMetrics.windowSize.width, height: ShellMetrics.windowSize.height)
        .commands { ShellMenus(app: ShellApp.model) }
        Settings { ShellSettingsView().shellAppearance() }
        // Window ▸ Organizer (OrganizerWindow.swift).
        Window("Organizer", id: ShellAppModel.organizerWindowID) {
            OrganizerWindowView(model: ShellApp.model.organizer).shellAppearance()
        }
        .defaultSize(width: OrganizerWindowView.windowSize.width, height: OrganizerWindowView.windowSize.height)
        // Window ▸ Organizer is the command table's item; the toolkit's own
        // entry for the scene would list it twice.
        .commandsRemoved()
    }
}

/// The window's content: Welcome, or the workspace.
struct ShellRootView: View {
    @Bindable var app: ShellAppModel
    @Environment(\.openURL) private var openURL
    @Environment(\.openWindow) private var openWindow
    /// A Finder-opened `.scproj` package awaiting the trust decision
    /// (Legacy `SwiftCodeApp.pendingScprojURL`).
    @State private var pendingScprojURL: URL?
    /// Error from a Finder open or a trust-alert delete, if any
    /// (Legacy `SwiftCodeApp.finderOpenError`).
    @State private var finderOpenError: String?
    /// First-run onboarding (wiring-views): `AppSettings.shared` is
    /// `@Observable`, so reading `hasCompletedOnboarding` here tracks
    /// it; "Get Started" flips it and dismisses the sheet.
    @State private var settings = AppSettings.shared
    /// The first-run sheet's page (0: features, 1: welcome).
    @State private var onboardingPage = 0

    var body: some View {
        Group {
            if let ws = app.workspace {
                WorkspaceView(model: ws, app: app)
            } else {
                WelcomeView(app: app)
            }
        }
        // File ▸ Open…: the toolkit's file dialog (OpenViews draws its own
        // on Linux).
        .fileImporter(isPresented: $app.isOpenSheetShown, allowedContentTypes: ShellOpenTypes.all) { result in
            if case .success(let url) = result { app.open(path: url.path) }
        }
        .fileDialogDefaultDirectory(app.recent.first?.deletingLastPathComponent())
        // File ▸ New ▸ Project…: the core's New Project flow.
        .sheet(isPresented: Binding(get: { app.newProject != nil }, set: { if !$0 { app.cancelNewProject() } })) {
            if let m = app.newProject { NewProjectSheet(model: m, app: app) }
        }
        .sheet(isPresented: Binding(get: { app.clone != nil }, set: { if !$0 { app.cancelClone() } })) {
            if let m = app.clone { CloneSheet(model: m, app: app) }
        }
        .sheet(isPresented: $app.isAboutShown) { AboutSheet(app: app) }
        // First-run onboarding (wiring-views): the features page, then
        // the welcome page. Not interactively dismissable: the only exit
        // is "Get Started", which sets `hasCompletedOnboarding` and
        // dismisses the sheet. `OnboardingView` itself is not used: it
        // needs `OnboardingSplashView`, which has not landed.
        .sheet(isPresented: Binding(get: { !settings.hasCompletedOnboarding }, set: { _ in })) {
            firstRunOnboarding
                .interactiveDismissDisabled()
        }
        .sheet(isPresented: Binding(get: { app.runtimeSetup != nil }, set: { if !$0 { app.closeRuntimeSetup() } })) {
            if let s = app.runtimeSetup { RuntimeSetupSheet(session: s, app: app) }
        }
        .alert(app.notice?.title ?? "", isPresented: Binding(get: { app.notice != nil }, set: { if !$0 { app.notice = nil } })) {
            Button("OK") { app.notice = nil }
        } message: {
            Text(verbatim: app.notice?.message ?? "")
        }
        .alert("Cannot Open", isPresented: Binding(get: { app.openError != nil && !app.isOpenSheetShown },
                                                   set: { if !$0 { app.clearOpenError() } })) {
            Button("OK") { app.clearOpenError() }
        } message: {
            Text(verbatim: app.openError ?? "")
        }
        // Closing the workspace or quitting with unsaved changes.
        .alert(unsavedTitle, isPresented: Binding(get: { app.pendingClose != nil }, set: { if !$0 { app.answerClose(.cancel) } })) {
            Button((app.workspace?.editedPaths.count ?? 0) > 1 ? "Save All" : "Save") { app.answerClose(.saveAll) }.keyboardShortcut(.defaultAction)
            Button("Don't Save", role: .destructive) { app.answerClose(.discard) }
            Button("Cancel", role: .cancel) { app.answerClose(.cancel) }
        } message: {
            Text(verbatim: "Your changes will be lost if you don't save them.")
        }
        .onAppear {
            let app = app, openURL = openURL, openWindow = openWindow
            app.openWindow = { id in openWindow(id: id) }
            app.openExternally = { url in
                openURL(url) { accepted in
                    if !accepted { app.linkCouldNotOpen(url) }
                }
            }
            #if os(macOS)
            applyLegacyWindowGeometry(hasWorkspace: app.workspace != nil)
            #endif
        }
        .onChange(of: app.workspace != nil) { _, hasWorkspace in
            #if os(macOS)
            applyLegacyWindowGeometry(hasWorkspace: hasWorkspace)
            #endif
        }
        // Finder-opened files arrive here (Legacy `SwiftCodeApp.onOpenURL`:
        // `.scproj` goes through the trust decision, `.xcodeproj` /
        // `.xcworkspace` open straight away; URL schemes keep their
        // existing handlers in the AppKit AppDelegate).
        .onOpenURL { url in
            guard url.isFileURL else { return }
            handleFinderOpenedFile(url)
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
                ScprojTrustStore.markTrusted(url)
                openTrustedScproj(url)
            }
            Button("Delete from Disk", role: .destructive) {
                pendingScprojURL = nil
                deleteUntrustedScproj(url)
            }
            Button("Cancel", role: .cancel) {}
        } message: { url in
            // project.json carries no author identity, so the alert names
            // the package and its location instead of inventing an author.
            // Deletion is permanent, by the user's explicit choice here.
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
        .task { await ShellDriver.start(app) }
    }

    /// The first-run onboarding sheet (wiring-views): the features page
    /// with a Continue step, then the welcome page with "Get Started".
    private var firstRunOnboarding: some View {
        VStack(spacing: 0) {
            if onboardingPage == 0 {
                OnboardingFeaturesView()
                Button("Continue") { onboardingPage = 1 }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.bottom, 24)
            } else {
                OnboardingWelcomeView()
            }
        }
        .frame(width: 560, height: 640)
    }
}

extension ShellRootView {
    // MARK: - Finder-opened files (Legacy `SwiftCodeApp`)

    private func handleFinderOpenedFile(_ url: URL) {
        switch url.pathExtension.lowercased() {
        case "scproj":
            // Already trusted once? Open straight away; otherwise the
            // trust alert decides (open, or delete from disk).
            if ScprojTrustStore.isTrusted(url) {
                openTrustedScproj(url)
            } else {
                pendingScprojURL = url
            }
        case "xcodeproj", "xcworkspace":
            // Same path as File > Open: the destination opens the
            // container directly (Legacy imported it through
            // `ProjectSessionStore.importProject`, which the services
            // migration owns; see the disposition).
            if !app.open(path: url.path) {
                finderOpenError = app.openError ?? "Could not open \(url.lastPathComponent)."
            }
        default:
            break
        }
    }

    /// Opens a trusted `.scproj` package. Legacy opened the package's own
    /// project via `ProjectSessionStore.openScprojPackage` (no import copy);
    /// the destination opens the container through `ShellAppModel.open`,
    /// which is the closest equivalent until that port lands.
    private func openTrustedScproj(_ url: URL) {
        if !app.open(path: url.path) {
            finderOpenError = app.openError ?? "Could not open \(url.lastPathComponent)."
        }
    }

    /// Deletes an untrusted `.scproj` package from disk, exactly as the
    /// trust alert promises. Also forgets any trust grant, so a later copy
    /// at the same path is prompted again instead of opening silently.
    /// (Legacy also dropped it from recents; `RecentProjects.urls` already
    /// drops entries whose file is gone, so the deletion covers that.)
    private func deleteUntrustedScproj(_ url: URL) {
        ScprojTrustStore.forget(url)
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            finderOpenError = error.localizedDescription
        }
    }

    #if os(macOS)
    /// Legacy window geometry (Legacy `SwiftCodeApp` / `WorkspaceHostView`):
    /// a workspace window goes fullscreen at min 900x600 with a hidden
    /// titlebar; the Welcome window is a fixed 800x480 panel with its
    /// titlebar buttons hidden.
    private func applyLegacyWindowGeometry(hasWorkspace: Bool) {
        guard let window = NSApplication.shared.windows.first(where: { $0.isVisible && !($0 is NSPanel) }) else { return }
        if hasWorkspace {
            window.isOpaque = true
            window.backgroundColor = nil
            window.showsResizeIndicator = true
            window.isMovableByWindowBackground = false
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.toolbar?.displayMode = .iconOnly
            window.styleMask.insert([.titled, .closable, .miniaturizable, .resizable])
            window.styleMask.remove(.fullSizeContentView)
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
            window.contentView?.wantsLayer = true
            window.contentView?.layer?.backgroundColor = NSColor.clear.cgColor
            let fixedSize = NSSize(width: 800, height: 480)
            window.minSize = fixedSize
            window.maxSize = fixedSize
            if abs(window.frame.width - fixedSize.width) > 1 || abs(window.frame.height - fixedSize.height) > 1 {
                window.setFrame(NSRect(origin: window.frame.origin, size: fixedSize), display: true, animate: false)
                window.center()
            }
            window.title = ""
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.toolbar = nil
            window.styleMask.insert([.titled, .fullSizeContentView])
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.standardWindowButton(.miniaturizeButton)?.isHidden = true
            window.standardWindowButton(.zoomButton)?.isHidden = true
            if let titlebarView = window.standardWindowButton(.closeButton)?.superview {
                titlebarView.isHidden = true
            }
        }
    }
    #endif

    var unsavedTitle: String {
        let names = app.workspace?.editedDocumentNames ?? []
        if names.count == 1 { return "Save changes to “\(names[0])”?" }
        return "Save changes to \(names.count) files?"
    }
}

/// What File ▸ Open… accepts: projects, workspaces, Package.swift, folders.
enum ShellOpenTypes {
    static var all: [UTType] {
        [UTType(filenameExtension: "xcodeproj", conformingTo: .package),
         UTType(filenameExtension: "xcworkspace", conformingTo: .package),
         .swiftSource, .folder].compactMap { $0 }
    }
}

/// Window sizes (`workspace-window.md`, `WorkspaceChrome`): the AppKit
/// window's 1400 × 900, plus, on Linux, the in-window menu bar above it
/// (OpenViews draws the menu bar in the window, 26 points), so the area
/// under the menu bar is the AppKit window's size.
enum ShellMetrics {
    #if os(Linux)
    static let menuBarHeight: CGFloat = 26
    #else
    static let menuBarHeight: CGFloat = 0
    #endif
    static let windowSize = CGSize(width: WorkspaceChrome.windowWidth, height: WorkspaceChrome.windowHeight + menuBarHeight)
}

/// The app's name and UI font on Linux: the menus say "SwiftCode" (not the
/// executable's name), and text is set in Inter (bundled with OpenViews,
/// SIL OFL 1.1), whose metrics are close to the desktop UI font the AppKit
/// IDE uses; the source font stays Noto Sans Mono.
enum ShellLook {
    @MainActor static func apply() {
        #if os(Linux)
        if ProcessInfo.processInfo.environment["OV_APP_NAME"] == nil { setenv("OV_APP_NAME", "SwiftCode", 1) }
        if ProcessInfo.processInfo.environment["SWIFTCODE_IDE_UI_FONT"] != "noto" {
            FontCatalog.shared.setFamilies(["Inter 24pt", "Noto Sans"], for: .default)
        }
        #endif
    }
}

extension ThemeColor {
    var color: Color { Color(.sRGB, red: redFraction, green: greenFraction, blue: blueFraction) }
}

extension ShellShortcut {
    var keyboardShortcut: KeyboardShortcut {
        var m: EventModifiers = []
        if modifiers.contains(.command) { m.insert(.command) }
        if modifiers.contains(.shift) { m.insert(.shift) }
        if modifiers.contains(.option) { m.insert(.option) }
        if modifiers.contains(.control) { m.insert(.control) }
        return KeyboardShortcut(KeyEquivalent(Character(key)), modifiers: m)
    }
}

extension View {
    /// Names the view for drivers (the accessibility identifier).
    func shellTarget(_ name: String) -> some View {
        accessibilityIdentifier(name)
    }
}

/// An image by symbol name (OpenViews draws every name the shell uses).
func symbol(_ name: String) -> Image {
    Image(systemName: name)
}
