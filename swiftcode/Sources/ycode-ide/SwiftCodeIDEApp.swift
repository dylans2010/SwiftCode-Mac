import Foundation
import SwiftUI
#if os(macOS)
import AppKit
#endif
#if canImport(UniformTypeIdentifiers)
import UniformTypeIdentifiers
#endif
import YcodeAssistant
import SwiftCodeGitHub
import YcodeIDECore
import YcodeIDEShell
import YcodeRelease
#if os(Linux)
import OVText
#endif

@MainActor
enum ShellApp {
    static let model = ShellAppModel()
}

@main
struct SwiftCodeIDEApp: App {
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
        SwiftCodeRelease.handleVersionFlag(tool: "swiftcode-ide")
        SwiftCodeRelease.adoptBundledHelpers()
        ShellLook.apply()
        StylingBootstrap.initialize()
        GitHubService.shared.configure(tokenProvider: { defaultSecretStore().readString(SecretAccount.githubToken) })
        ShellPasteboard.writer = { ShellClipboard.copy($0) }
        #if os(Linux)
        ApplicationTermination.shouldTerminate = { ShellApp.model.shouldQuit() }
        ShellApp.model.terminateApp = { OpenViewsAutomation.terminate() }
        #endif
        signal(SIGPIPE, SIG_IGN)
        ShellApp.model.startsLanguageService = ProcessInfo.processInfo.environment["SWIFTCODE_IDE_LSP"] != "0"
        ShellApp.model.offerRuntimeSetupAtFirstLaunch()
        if let path = ShellAppModel.launchPath() {
            if !ShellApp.model.open(path: path) {
                FileHandle.standardError.write(Data("swiftcode-ide: \(ShellApp.model.openError ?? "cannot open \(path)")\n".utf8))
            }
        }
    }

    var body: some Scene {
        WindowGroup("SwiftCode") {
            StylingBootstrap.configureEnvironment(ShellRootView(app: ShellApp.model)).shellAppearance()
        }
        .defaultSize(width: ShellMetrics.windowSize.width, height: ShellMetrics.windowSize.height)
        .commands { ShellMenus(app: ShellApp.model) }
        Settings { ShellSettingsView().shellAppearance() }
        Window("Organizer", id: ShellAppModel.organizerWindowID) {
            OrganizerWindowView(model: ShellApp.model.organizer).shellAppearance()
        }
        .defaultSize(width: OrganizerWindowView.windowSize.width, height: OrganizerWindowView.windowSize.height)
        .commandsRemoved()
    }
}

struct ShellRootView: View {
    @Bindable var app: ShellAppModel
    @Environment(\.openURL) private var openURL
    @Environment(\.openWindow) private var openWindow
    @State private var pendingScprojURL: URL?
    @State private var finderOpenError: String?
    @State private var settings = AppSettings.shared
    @State private var onboardingPage = 0

    var body: some View {
        Group {
            if let ws = app.workspace {
                WorkspaceView(model: ws, app: app)
            } else {
                WelcomeView(app: app)
            }
        }
        .fileImporter(isPresented: $app.isOpenSheetShown, allowedContentTypes: ShellOpenTypes.all) { result in
            if case .success(let url) = result { app.open(path: url.path) }
        }
        .fileDialogDefaultDirectory(app.recent.first?.deletingLastPathComponent())
        .sheet(isPresented: Binding(get: { app.newProject != nil }, set: { if !$0 { app.cancelNewProject() } })) {
            if let m = app.newProject { NewProjectSheet(model: m, app: app) }
        }
        .sheet(isPresented: Binding(get: { app.clone != nil }, set: { if !$0 { app.cancelClone() } })) {
            if let m = app.clone { CloneSheet(model: m, app: app) }
        }
        .sheet(isPresented: $app.isAboutShown) { AboutSheet(app: app) }
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

    private func handleFinderOpenedFile(_ url: URL) {
        switch url.pathExtension.lowercased() {
        case "scproj":
            if ScprojTrustStore.isTrusted(url) {
                openTrustedScproj(url)
            } else {
                pendingScprojURL = url
            }
        case "xcodeproj", "xcworkspace":
            if !app.open(path: url.path) {
                finderOpenError = app.openError ?? "Could not open \(url.lastPathComponent)."
            }
        default:
            break
        }
    }

    private func openTrustedScproj(_ url: URL) {
        if !app.open(path: url.path) {
            finderOpenError = app.openError ?? "Could not open \(url.lastPathComponent)."
        }
    }

    private func deleteUntrustedScproj(_ url: URL) {
        ScprojTrustStore.forget(url)
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            finderOpenError = error.localizedDescription
        }
    }

    #if os(macOS)
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

enum ShellOpenTypes {
    static var all: [UTType] {
        [UTType(filenameExtension: "xcodeproj", conformingTo: .package),
         UTType(filenameExtension: "xcworkspace", conformingTo: .package),
         .swiftSource, .folder].compactMap { $0 }
    }
}

enum ShellMetrics {
    #if os(Linux)
    static let menuBarHeight: CGFloat = 26
    #else
    static let menuBarHeight: CGFloat = 0
    #endif
    static let windowSize = CGSize(width: WorkspaceChrome.windowWidth, height: WorkspaceChrome.windowHeight + menuBarHeight)
}

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
    func shellTarget(_ name: String) -> some View {
        accessibilityIdentifier(name)
    }
}

func symbol(_ name: String) -> Image {
    Image(systemName: name)
}
