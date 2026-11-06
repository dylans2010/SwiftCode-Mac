import Foundation
import SwiftUI
import YcodeExtensions
import YcodeSDK
import YcodeSDKStudio

// MARK: - SDKStudioSection
//
// Legacy: `SwiftCode/SDK/Studio/SDKStudioSection.swift` (spec §13.3).
// Raw values are the exact display names; `Identifiable` (id = rawValue)
// lets the Studio view drive a sidebar selection directly.

enum SDKStudioSection: String, CaseIterable, Identifiable {
    case projects = "Projects"
    case codeEditor = "Code Editor"
    case manifestEditor = "Manifest Editor"
    case extensions = "Extensions"
    case apiKeys = "API Keys"
    case security = "Security"
    case logs = "Logs"
    case installedExtensions = "Installed"
    case assistAccess = "Assist Access"
    case sdk = "SDK & Downloads"
    case shipExport = "Ship & Export"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .projects: return "folder"
        case .codeEditor: return "chevron.left.forwardslash.chevron.right"
        case .manifestEditor: return "doc.badge.gearshape"
        case .extensions: return "puzzlepiece.extension"
        case .apiKeys: return "key"
        case .security: return "lock.shield"
        case .logs: return "doc.text"
        case .installedExtensions: return "app.badge"
        case .assistAccess: return "person.badge.key"
        case .sdk: return "shippingbox"
        case .shipExport: return "square.and.arrow.up"
        }
    }
}

// MARK: - SDKStudioCodeEditorSection
//
// Legacy: `SwiftCode/SDK/Studio/CodeEditor/SDKStudioCodeEditorSection.swift`.
// Kept for compatibility: anything addressing the section by its stable
// string id ("codeEditor") keeps working unchanged.

struct SDKStudioCodeEditorSection: Identifiable, Sendable, Hashable {
    var id: String { "codeEditor" }
    var title: String { "Code Editor" }
    var systemImage: String { "chevron.left.forwardslash.chevron.right" }

    init() {}
}

// MARK: - SDKStudioWindowManager
//
// Legacy: `SwiftCode/SDK/Studio/SDKStudioWindowManager.swift` — a
// singleton owning one `NSWindow` hosting `SDKStudioView` through
// `NSHostingController`, remembering the last section in UserDefaults.
//
// Ycode deviation: `ycode-ide` views are pure SwiftUI (no AppKit in this
// target — see the other views in this directory), so this manager is the
// section-persistence + presentation state. The macOS AppKit shell
// (YcodeUI/YcodeApp) hosts `SDKStudioView` in its own window and drives
// it through `openStudio(section:)` / `closeStudio()`; the remembered
// section and open flag use Legacy's exact UserDefaults keys.

@MainActor
@Observable
final class SDKStudioWindowManager {
    static let shared = SDKStudioWindowManager()

    private static let lastSectionKey = "com.swiftcode.sdk.studio.lastSection"
    private static let studioIsOpenKey = "com.swiftcode.sdk.studio.isOpen"

    private(set) var currentSection: SDKStudioSection = .projects
    private(set) var isStudioOpen: Bool = false

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Self.lastSectionKey),
           let section = SDKStudioSection(rawValue: raw) {
            self.currentSection = section
        }
        self.isStudioOpen = UserDefaults.standard.bool(forKey: Self.studioIsOpenKey)
    }

    func updateSection(_ section: SDKStudioSection) {
        currentSection = section
        UserDefaults.standard.set(section.rawValue, forKey: Self.lastSectionKey)
    }

    func openStudio() {
        openStudio(section: currentSection)
    }

    func openStudio(section: SDKStudioSection) {
        updateSection(section)
        isStudioOpen = true
        UserDefaults.standard.set(true, forKey: Self.studioIsOpenKey)
    }

    func closeStudio() {
        isStudioOpen = false
        UserDefaults.standard.set(false, forKey: Self.studioIsOpenKey)
    }
}

// MARK: - Shared Studio chrome
//
// `ContentUnavailableView` and `GroupBox` do not exist in OpenViews
// (the Linux SwiftUI), so Studio uses these two small stand-ins. They
// render the same content on Apple's SwiftUI too.

struct SDKStudioEmptyState: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage).font(.title)
            Text(title).font(.headline)
            Text(description)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct SDKStudioGroupBox<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - SDKStudioView
//
// Legacy: `SwiftCode/SDK/Studio/Views/SDKStudioView.swift` — the Studio
// root: sidebar over the eleven sections, a shared `SDKCodeEditorState`,
// an "Install SDK" toolbar button, the first-launch installer sheet, and
// the SDK & Downloads resources section.

@MainActor
struct SDKStudioView: View {
    @State private var selection: SDKStudioSection?
    @State private var editorState = SDKCodeEditorState()
    @State private var showSDKFirstLaunchInstaller = false
    @State private var resourceError: String?
    @State private var installer = SDKStudioInstallerHost()

    init(initialSection: SDKStudioSection = SDKStudioWindowManager.shared.currentSection) {
        _selection = State(initialValue: initialSection)
    }

    var body: some View {
        NavigationSplitView {
            List(SDKStudioSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .navigationTitle("Studio")
        } detail: {
            NavigationStack {
                studioDetailView(for: selection ?? .projects)
            }
            .id(selection ?? .projects)
        }
        .onChange(of: selection) { _, newSection in
            guard let newSection else { return }
            SDKStudioWindowManager.shared.updateSection(newSection)
        }
        .navigationTitle("SwiftCode Studio")
        .toolbar {
            Button("Install SDK", systemImage: "arrow.down.circle") {
                showSDKFirstLaunchInstaller = true
            }
        }
        .alert("SDK Resource Unavailable", isPresented: Binding(
            get: { resourceError != nil },
            set: { if !$0 { resourceError = nil } }
        )) {
            Button("OK", role: .cancel) { resourceError = nil }
        } message: {
            Text(resourceError ?? "")
        }
        .sheet(isPresented: $showSDKFirstLaunchInstaller) {
            SDKFirstLaunchInstallerView(installer: installer)
        }
        .task {
            if SDKStudioFirstLaunchChoice.shouldPrompt(sdkInstalled: installerInspectOK()) {
                showSDKFirstLaunchInstaller = true
            }
        }
    }

    private func installerInspectOK() -> Bool {
        if case .ok = installer.inspect() { return true }
        return false
    }

    @ViewBuilder
    private func studioDetailView(for section: SDKStudioSection) -> some View {
        switch section {
        case .projects:
            SDKStudioProjectsView(
                editorState: editorState,
                onOpenInCodeEditor: { projectURL in
                    openProjectInEditor(projectURL, targetSection: .codeEditor)
                },
                onOpenInManifestEditor: { projectURL in
                    openProjectInEditor(projectURL, targetSection: .manifestEditor)
                }
            )
        case .codeEditor:
            SDKCodeEditorShellView(editorState: editorState)
        case .manifestEditor:
            SDKManifestEditorView(
                manifestFileURL: editorState.projectRootURL?.appendingPathComponent("swiftcode.json"),
                editorState: editorState
            )
        case .extensions:
            SDKStudioExtensionsView()
        case .apiKeys:
            SDKStudioAPIKeysView()
        case .security:
            SDKSecurityManagerView()
        case .logs:
            SDKStudioLogsView()
        case .installedExtensions:
            SDKAvailableExtensionsView()
        case .assistAccess:
            SDKAssistAccessFormView()
        case .sdk:
            sdkResourcesView
        case .shipExport:
            SDKShipExportView(editorState: editorState)
        }
    }

    private func openProjectInEditor(_ projectURL: URL, targetSection: SDKStudioSection) {
        let root = projectURL.standardizedFileURL
        editorState.setProjectRoot(root)
        let fm = FileManager.default
        let candidates = [
            root.appendingPathComponent("swiftcode.json"),
            root.appendingPathComponent("src/index.ts"),
            root.appendingPathComponent("App.swift"),
            root.appendingPathComponent("ContentView.swift"),
            root.appendingPathComponent("README.md"),
        ]
        for candidate in candidates where fm.fileExists(atPath: candidate.path) {
            _ = try? editorState.openFile(candidate)
        }
        if targetSection == .codeEditor {
            let preferredSource = root.appendingPathComponent("src/index.ts")
            let swiftSource = root.appendingPathComponent("ContentView.swift")
            if fm.fileExists(atPath: preferredSource.path) {
                _ = try? editorState.openFile(preferredSource)
            } else if fm.fileExists(atPath: swiftSource.path) {
                _ = try? editorState.openFile(swiftSource)
            }
        } else if targetSection == .manifestEditor {
            let manifestURL = root.appendingPathComponent("swiftcode.json")
            if fm.fileExists(atPath: manifestURL.path) {
                _ = try? editorState.openFile(manifestURL)
            }
        }
        selection = targetSection
    }

    private var sdkResourcesView: some View {
        Form {
            Section("SwiftCode SDK \(SDKVersion.current.description)") {
                Text("Install the SDK to build extensions, or save the bundled npm package for an offline installation. Node.js is required.")
                Text(type(of: installer).defaultPrefix.path)
                    .font(.callout.monospaced())
                    .padding(6)
                Button("Install or Repair SDK…") { showSDKFirstLaunchInstaller = true }
                switch installer.inspect() {
                case .ok(let version):
                    Text("SDK \(version) is installed.")
                        .foregroundStyle(.secondary)
                case .notInstalled:
                    Text("The SDK is not installed yet. Use “Install or Repair SDK…” to install it.")
                        .foregroundStyle(.secondary)
                case .versionMismatch(let found, let expected):
                    Text("Installed SDK \(found) does not match expected \(expected).")
                        .foregroundStyle(.secondary)
                case .error(let message):
                    Text(message).foregroundStyle(.secondary)
                }
                Text("The installer checks the pinned GitHub release and falls back to the bundled package if the remote download is unavailable or incomplete.")
                    .foregroundStyle(.secondary)
            }
            Section("Documentation & Tools") {
                Text("Projects creates and opens apps and extensions. Manifest Editor provides visual and raw editing of swiftcode.json. Code Editor includes snippets, validation, build/run, and diagnostics. Ship & Export packages your extension for distribution.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
