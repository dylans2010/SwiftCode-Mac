import AppKit
import SwiftUI

// MARK: - SDKStudioView
//
// SwiftCode Studio root view — the EXCLUSIVE creation hub for SwiftCode
// platform/SDK projects and extensions (spec §13.3 "Exclusive Project
// Creation Boundary").
//
// Per the spec, Studio is the ONLY UI surface where users may create
// projects targeting the SwiftCode platform and extensions using the
// SwiftCode SDK. The main code-editor UI is restricted to editing,
// navigating, and viewing existing files; creation templates, new-project
// wizards, and platform scaffolding MUST NOT appear in the main editor's
// file/menu interfaces. Selecting "New SwiftCode Project" or "New
// Extension" in the main editor is required to redirect here via
// `SDKStudioWindowManager.shared.openStudio(section: .projects)` (or
// `.extensions`).
//
// IMPORTANT APP-SURGERY NOTE: rerouting the main editor's menus to
// `SDKStudioWindowManager` is a separate task and is NOT part of this
// file. Tracked in `SwiftCode/SDK/Studio/agent_notes.md`.
//
// Shell only: the six detail panes are built in parallel and referenced
// here, never redefined:
//   - `SDKStudioProjectsView`   (project & extension generation wizards)
//   - `SDKStudioExtensionsView` (lifecycle console + manifest inspector)
//   - `SDKStudioAPIKeysView`    (developer API key management)
//   - `SDKSecurityManagerView`  (use.Security sensitive-value manager)
//   - `SDKStudioLogsView`       (dual logging inspector: user + developer)
//   - `SDKCodeEditorShellView`  (Studio code editor: navigator, tabs,
//                                console, find bar, snippet browser)
//   - `AvailableExtensionsView`  (installed extensions/apps browser: run
//                                contributed commands, enable/disable,
//                                uninstall — spec §7)
//   - `AssistAccessFormView`     (Assist access application form + pending
//                                queue: approve/deny grants the key-bound
//                                Assist entitlement — spec §10)
//
// Native macOS SwiftUI (`NavigationSplitView`), macOS 15, Swift 6.
//
// `SDKStudioView` is explicitly `@MainActor`: Swift 6 removed the old
// implicit `@MainActor` inference from `@StateObject`, so views that own
// `@MainActor`-isolated state (like `SDKCodeEditorShellView`) must be
// `@MainActor` themselves, and this view constructs them.

@MainActor
public struct SDKStudioView: View {
    @State private var selection: SDKStudioSection
    @State private var showSDKFirstLaunchInstaller = false
    @State private var resourceError: String?

    public init(initialSection: SDKStudioSection = .projects) {
        _selection = State(initialValue: initialSection)
    }

    public var body: some View {
        NavigationSplitView {
            List(SDKStudioSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 220)
            .navigationTitle("Studio")
        } detail: {
            NavigationStack {
                studioDetailView(for: selection)
            }
            .id(selection)
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
        // First-launch SDK installer (spec §5): prompts once per the
        // persisted choice in `SDKStudioFirstLaunchChoice`. Declining
        // leaves Studio fully usable — nothing here is gated on install.
        .sheet(isPresented: $showSDKFirstLaunchInstaller) {
            SDKFirstLaunchInstallerView()
        }
        .task {
            if SDKStudioFirstLaunchChoice.shouldPrompt() {
                showSDKFirstLaunchInstaller = true
            }
        }
    }

    @ViewBuilder
    private func studioDetailView(for section: SDKStudioSection) -> some View {
        switch section {
        case .projects:
            SDKStudioProjectsView()
        case .extensions:
            SDKStudioExtensionsView()
        case .apiKeys:
            SDKStudioAPIKeysView()
        case .security:
            SDKSecurityManagerView()
        case .logs:
            SDKStudioLogsView()
        case .codeEditor:
            SDKCodeEditorShellView()
        case .installedExtensions:
            AvailableExtensionsView()
        case .assistAccess:
            AssistAccessFormView()
        case .sdk:
            sdkResourcesView
        case .shipExport:
            SDKShipExportView()
        }
    }

    private var sdkResourcesView: some View {
        Form {
            Section("SwiftCode SDK \(SDKInstaller.expectedVersion)") {
                Text("Install the SDK to build extensions, or save the bundled npm package for an offline installation. Node.js is required.")
                Text(SDKInstaller.defaultPrefix.path)
                    .font(.callout.monospaced())
                    .textSelection(.enabled)
                Button("Install or Repair SDK…") { showSDKFirstLaunchInstaller = true }
                Button("Save SDK Package…") { saveSDKPackage() }
                Text("The installer checks the pinned GitHub release and falls back to the bundled package if the remote download is unavailable or incomplete.")
                    .foregroundStyle(.secondary)
            }
            Section("Documentation & Tools") {
                Button("Open SDK Documentation") {
                    guard let docs = Bundle.main.resourceURL?.appendingPathComponent("SwiftCodeSDK/Documentation"),
                          FileManager.default.fileExists(atPath: docs.path) else {
                        resourceError = "SDK documentation is missing from this app build."
                        return
                    }
                    NSWorkspace.shared.open(docs)
                }
                Text("Projects creates apps and extensions. Extensions includes Manifest and Grants inspectors. Code Editor includes snippets, build/run and the console. Ship & Export packages your extension for distribution.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func saveSDKPackage() {
        guard let source = SDKInstaller.defaultBundledFallbackURL() else {
            resourceError = "The bundled SDK package is missing. Use the GitHub download or install a complete SwiftCode build."
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "swiftcode-sdk-\(SDKInstaller.expectedVersion).tgz"
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try Data(contentsOf: source).write(to: destination, options: .atomic)
        } catch {
            resourceError = error.localizedDescription
        }
    }
}
