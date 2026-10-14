import AppKit
import SwiftUI

// MARK: - SDKStudioView
//
// SwiftCode Studio root view — the EXCLUSIVE creation and development hub
// for SwiftCode platform/SDK projects and extensions (spec §13.3).

@MainActor
public struct SDKStudioView: View {
    @State private var selection: SDKStudioSection
    @StateObject private var codeEditorState = SDKCodeEditorState()
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
            SDKStudioProjectsView(
                editorState: codeEditorState,
                onOpenInCodeEditor: { projectURL in
                    openProjectInEditor(projectURL, targetSection: .codeEditor)
                },
                onOpenInManifestEditor: { projectURL in
                    openProjectInEditor(projectURL, targetSection: .manifestEditor)
                }
            )
        case .codeEditor:
            SDKCodeEditorShellView(editorState: codeEditorState)
        case .manifestEditor:
            SDKManifestEditorView(
                manifestFileURL: codeEditorState.projectRootURL?.appendingPathComponent("swiftcode.json"),
                editorState: codeEditorState
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
            AvailableExtensionsView()
        case .assistAccess:
            AssistAccessFormView()
        case .sdk:
            sdkResourcesView
        case .shipExport:
            SDKShipExportView()
        }
    }

    private func openProjectInEditor(_ projectURL: URL, targetSection: SDKStudioSection) {
        let root = projectURL.standardizedFileURL
        codeEditorState.setProjectRoot(root)
        let fm = FileManager.default
        let candidates = [
            root.appendingPathComponent("swiftcode.json"),
            root.appendingPathComponent("src/index.ts"),
            root.appendingPathComponent("App.swift"),
            root.appendingPathComponent("ContentView.swift"),
            root.appendingPathComponent("README.md")
        ]
        for candidate in candidates where fm.fileExists(atPath: candidate.path) {
            _ = try? codeEditorState.openFile(candidate)
        }
        if targetSection == .codeEditor {
            let preferredSource = root.appendingPathComponent("src/index.ts")
            let swiftSource = root.appendingPathComponent("ContentView.swift")
            if fm.fileExists(atPath: preferredSource.path) {
                _ = try? codeEditorState.openFile(preferredSource)
            } else if fm.fileExists(atPath: swiftSource.path) {
                _ = try? codeEditorState.openFile(swiftSource)
            }
        } else if targetSection == .manifestEditor {
            let manifestURL = root.appendingPathComponent("swiftcode.json")
            if fm.fileExists(atPath: manifestURL.path) {
                _ = try? codeEditorState.openFile(manifestURL)
            }
        }
        selection = targetSection
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
                Text("Projects creates and opens apps and extensions. Manifest Editor provides visual and raw editing of swiftcode.json. Code Editor includes snippets, validation, build/run, and diagnostics. Ship & Export packages your extension for distribution.")
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
