// Ported from Legacy `SwiftCode/Views/BuildToolbarView.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged only — not yet merged into swiftcode/Sources. See staging-wire/missing/DISPOSITIONS.md.
// Verbatim except `.liquidGlass(...)` -> thinMaterial (see Adaptive notes).
// BLOCKED references (left intact, owned by other scopes or unaudited):
// RESOLVED by fix W-V2 (and A4 for the toolbar model):
// - ToolbarManager / ToolbarTool (A4, SwiftCodeUI/Window/ToolbarItem.swift);
//   the @ObservedObject uses below are fixed to @State / plain refs because
//   ToolbarManager is @Observable, not ObservableObject.
// - XcodeBuildAPI: exists in SwiftCodeXcodebuild (all methods this view calls).
// - SwiftViewDetector: landed in SwiftCodePreviews (PreviewDiscoveryService).
// - PreviewManager / FullAppRunManager / BuildViewModel: landed by W-V2 in
//   SwiftCodeUI (VisualUIBuilder/PreviewManager.swift, Window/FullAppRunManager.swift,
//   Window/BuildViewModel.swift).
// - DocumentCoordinator / ProjectSessionStore: in SwiftCodeIDECore, imported below.
// - EditorViewModel (SwiftCodeEditorKit), SourceFileDocument, SwiftCodeToolbarDelegate:
//   all exist in production.
// STILL OPEN (not this file): SwiftCodeToolbarDelegate.presentCustomizationPalette()
//   has no handler anywhere (pre-existing; the audit notes it).
// Wiring: WorkspaceWindowController+ToolbarBand is the destination toolbar — this
// view is its SwiftUI pinned-tools strip (Tools Hub / App Details / scheme picker /
// Swift Files menu / Actions menu / pinned tools / Build & Stop).

import SwiftUI
import AppKit
import SwiftCodeBuild
import SwiftCodeEditorKit
import SwiftCodeIDECore
import SwiftCodePreviews
import SwiftCodeXcodebuild
import UniformTypeIdentifiers

@MainActor
struct BuildToolbarView: View {
    @State var viewModel: BuildViewModel
    let projectURL: URL
    @Bindable var editorViewModel: EditorViewModel
    // V2 fix W-V2: ToolbarManager is @Observable, not ObservableObject.
    @State private var toolbarManager = ToolbarManager.shared

    private var buildManager: XcodeBuildManager {
        XcodeBuildManager.shared
    }

    private var openSwiftDocuments: [SourceFileDocument] {
        editorViewModel.openDocuments.filter { $0.url.pathExtension.lowercased() == "swift" }
    }

    @ViewBuilder
    private var openSwiftFilesMenu: some View {
        if !openSwiftDocuments.isEmpty {
            Menu {
                ForEach(openSwiftDocuments) { document in
                    Button {
                        editorViewModel.activeDocument = document
                        editorViewModel.selectedTabID = document.id
                    } label: {
                        Label(document.url.lastPathComponent, systemImage: "swift")
                    }

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(document.url.path, forType: .string)
                    } label: {
                        Label("Copy Path", systemImage: "doc.on.doc")
                    }

                    Button {
                        NSWorkspace.shared.selectFile(document.url.path, inFileViewerRootedAtPath: document.url.deletingLastPathComponent().path)
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                    }

                    Divider()
                }
            } label: {
                Label("Swift Files", systemImage: "swift")
            }
            .menuStyle(.borderlessButton)
            .help("Open Swift files and file actions")
        }
    }

    @ViewBuilder
    private var swiftActionsMenu: some View {
        Menu {
            Section("Build & Run") {
                Button {
                    Task {
                        NotificationCenter.default.post(name: .toolbarToolActivated, object: nil, userInfo: ["toolID": "xcode_build_logs"])
                        _ = await XcodeBuildAPI.shared.buildProject()
                    }
                } label: {
                    Label("Build", systemImage: "play.fill")
                }

                Button {
                    NotificationCenter.default.post(name: .toolbarToolActivated, object: nil, userInfo: ["toolID": "deviceConnect"])
                } label: {
                    Label("Device Connect", systemImage: "iphone.badge.play")
                }
            }

            Section("Preview & Simulation") {
                Button {
                    Task {
                        if let docURL = editorViewModel.activeDocument?.fileURL {
                            await editorViewModel.saveActiveDocument()
                            NotificationCenter.default.post(name: .toolbarToolActivated, object: nil, userInfo: ["toolID": "visual_ui_builder"])
                            // Saved just above, so disk content is the editor text here.
                            // (W-V2: SourceFileDocument has no `content`/`url` members in
                            // production — the document-model reconciliation is
                            // coordinator-owned; fileURL + disk read is the equivalent.)
                            let content = (try? String(contentsOf: docURL, encoding: .utf8)) ?? ""
                            let (preparedCode, _) = SwiftViewDetector.prepareSourceCode(content, filename: docURL.path)
                            await PreviewManager.shared.startFreshLivePreviewSession(sourcePath: docURL.path, sourceCode: preparedCode)
                        }
                    }
                } label: {
                    Label("Live Preview", systemImage: "play.rectangle.on.rectangle")
                }

                Button {
                    Task {
                        NotificationCenter.default.post(name: .toolbarToolActivated, object: nil, userInfo: ["toolID": "visual_ui_builder"])
                        if let visDoc = DocumentCoordinator.shared.visualUIDocument {
                            let artboard = visDoc.scene.artboards.first(where: { $0.name == "Simulator" }) ?? visDoc.scene.artboards.first
                            if let targetArt = artboard {
                                visDoc.scene.activeArtboardID = targetArt.id
                                let session = PreviewManager.shared.getOrCreateRuntimeSession(for: targetArt.id)
                                // W-V2: startBuildPipeline requires projectDirectory + sourceFile.
                                if let docURL = editorViewModel.activeDocument?.fileURL {
                                    await session.startBuildPipeline(projectDirectory: docURL.deletingLastPathComponent(), sourceFile: docURL, targetViewName: targetArt.name)
                                }
                            }
                        }
                    }
                } label: {
                    Label("Compile Project on Artboard", systemImage: "play.desktopcomputer")
                }

                Button {
                    Task {
                        await PreviewManager.shared.stopAndRestartSession()
                    }
                } label: {
                    Label("Restart Preview Session", systemImage: "arrow.clockwise.circle")
                }

                Button {
                    FullAppRunManager.shared.stopApplication()
                } label: {
                    Label("Stop Runtime", systemImage: "stop.circle")
                }
            }

            Section("Project Maintenance") {
                Button {
                    Task {
                        _ = await XcodeBuildAPI.shared.cleanProject()
                    }
                } label: {
                    Label("Clean Build Folder", systemImage: "trash")
                }

                Button {
                    XcodeBuildAPI.shared.showProjectGenerationUI = true
                } label: {
                    Label("Generate Xcode Project", systemImage: "hammer.circle.fill")
                }

                Button {
                    NotificationCenter.default.post(name: .toolbarToolActivated, object: nil, userInfo: ["toolID": "dependency_manager"])
                } label: {
                    Label("Resolve Packages", systemImage: "shippingbox.fill")
                }

                Button {
                    Task {
                        if let activeProj = ProjectSessionStore.shared.activeProject {
                            ProjectSessionStore.shared.refreshFileTree(for: activeProj)
                        }
                    }
                } label: {
                    Label("Refresh Workspace", systemImage: "arrow.clockwise")
                }

                Button {
                    NotificationCenter.default.post(name: .toolbarToolActivated, object: nil, userInfo: ["toolID": "project_inspector"])
                } label: {
                    Label("Validate Project", systemImage: "checkmark.shield")
                }
            }

            Section("Diagnostics & Logs") {
                Button {
                    NotificationCenter.default.post(name: .toolbarToolActivated, object: nil, userInfo: ["toolID": "xcode_build_logs"])
                } label: {
                    Label("Build Logs & Runtime Logs", systemImage: "doc.text.fill")
                }

                Button {
                    NotificationCenter.default.post(name: .toolbarToolActivated, object: nil, userInfo: ["toolID": "preview_logs"])
                } label: {
                    Label("Preview Logs", systemImage: "doc.text")
                }

                Button {
                    NotificationCenter.default.post(name: .toolbarToolActivated, object: nil, userInfo: ["toolID": "error_diagnostics"])
                } label: {
                    Label("Build Diagnostics", systemImage: "exclamationmark.triangle")
                }

                Button {
                    NotificationCenter.default.post(name: .toolbarToolActivated, object: nil, userInfo: ["toolID": "visual_ui_builder"])
                } label: {
                    Label("Open Preview Inspector", systemImage: "sidebar.right")
                }
            }

            Section("Finder Actions") {
                Button {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: XcodeBuildAPI.shared.determineDerivedDataLocation().path)
                } label: {
                    Label("Open Derived Data", systemImage: "folder")
                }

                Button {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: XcodeBuildAPI.shared.resolveOutputLocation().path)
                } label: {
                    Label("Reveal Build Folder", systemImage: "folder.badge.gearshape")
                }

                Button {
                    NotificationCenter.default.post(name: NSNotification.Name("ShowExportSheet"), object: nil)
                } label: {
                    Label("Export Project...", systemImage: "square.and.arrow.up")
                }

                Button {
                    NotificationCenter.default.post(name: NSNotification.Name("com.swiftcode.toggleAppDetailsSidebar"), object: nil)
                } label: {
                    Label("Project Information", systemImage: "info.circle")
                }
            }

            Section("Toolbar") {
                Button {
                    SwiftCodeToolbarDelegate.presentCustomizationPalette()
                } label: {
                    Label("Customize Toolbar...", systemImage: "slider.horizontal.3")
                }
            }
        } label: {
            Label("Actions", systemImage: "swift")
                .foregroundColor(.orange)
        }
        .menuStyle(.borderlessButton)
        .help("Comprehensive Build and Development Actions")
    }

    var body: some View {
        @Bindable var buildManager = self.buildManager
        HStack(spacing: 12) {
            Button {
                NotificationCenter.default.post(
                    name: .toolbarToolActivated,
                    object: nil,
                    userInfo: ["toolID": "main_tools"]
                )
            } label: {
                Label("Tools Hub", systemImage: "wrench.and.screwdriver.fill")
            }
            .buttonStyle(.bordered)
            .help("Open Workspace Tools Hub")

            Button {
                NotificationCenter.default.post(
                    name: NSNotification.Name("com.swiftcode.toggleAppDetailsSidebar"),
                    object: nil
                )
            } label: {
                Label("App Details", systemImage: "info.circle.fill")
            }
            .buttonStyle(.bordered)
            .help("Toggle App Details Sidebar")

            if isProjectArchiveImported() {
                Button {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("com.swiftcode.toggleInfoProjSidebar"),
                        object: nil
                    )
                } label: {
                    Label("Archive Info", systemImage: "archivebox.circle.fill")
                        .foregroundColor(.pink)
                }
                .buttonStyle(.bordered)
                .help("View SwiftCode Project Archive metadata")
            }

            // W-V2: SourceFileDocument has no `content`/`url` in production; the disk
            // read below can be stale when edits are unsaved — it only gates this button.
            if let docURL = editorViewModel.activeDocument?.fileURL, docURL.pathExtension.lowercased() == "swift", hasLivePreviewComment(content: (try? String(contentsOf: docURL, encoding: .utf8)) ?? "") {
                Button {
                    Task {
                        // 1. Save current editor contents immediately
                        await editorViewModel.saveActiveDocument()

                        // 2. Launch Visual UI Builder immediately
                        NotificationCenter.default.post(
                            name: .toolbarToolActivated,
                            object: nil,
                            userInfo: ["toolID": "visual_ui_builder"]
                        )

                        // 3. Focus the Default Artboard
                        if let visDoc = DocumentCoordinator.shared.visualUIDocument {
                            if let defaultArtboard = visDoc.scene.artboards.first(where: { $0.name == "Default" }) {
                                visDoc.scene.activeArtboardID = defaultArtboard.id
                            }
                        }

                        // 4. Start a brand-new preview session (saved just above, so
                        // disk content is the editor text here — see the W-V2 note above).
                        let content = (try? String(contentsOf: docURL, encoding: .utf8)) ?? ""
                        let (preparedCode, _) = SwiftViewDetector.prepareSourceCode(content, filename: docURL.path)
                        await PreviewManager.shared.startFreshLivePreviewSession(
                            sourcePath: docURL.path,
                            sourceCode: preparedCode
                        )
                    }
                } label: {
                    Label("Live Preview", systemImage: "play.desktopcomputer")
                        .foregroundColor(.purple)
                }
                .buttonStyle(.bordered)
                .help("Launch Live Viewport for the active Swift document")
            }

            // ESSENTIAL ACTIONS: Scheme selector
            if !buildManager.discoveredSchemes.isEmpty {
                Picker("Scheme", selection: $buildManager.selectedScheme) {
                    ForEach(buildManager.discoveredSchemes, id: \.self) { scheme in
                        Text(scheme).tag(scheme as String?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 130)
                .labelsHidden()
                .help("Select Build Scheme")
                .accessibilityLabel("Build Scheme Selector")
            }

            openSwiftFilesMenu
            swiftActionsMenu

            // Pinned & Optional Tools: Only show options that are explicitly pinned (enabled)
            HStack(spacing: 8) {
                ForEach(toolbarManager.enabledTools) { tool in
                    ToolbarToolView(tool: tool, toolbarManager: toolbarManager, buildManager: buildManager)
                }
            }
            .animation(.spring(), value: toolbarManager.enabledTools)

            Divider()
                .frame(height: 16)

            // ESSENTIAL ACTIONS: Build & Stop Buttons
            HStack(spacing: 8) {
                Button(action: {
                    Task {
                        // Automatically open XcodeBuildLogView
                        NotificationCenter.default.post(
                            name: .toolbarToolActivated,
                            object: nil,
                            userInfo: ["toolID": "xcode_build_logs"]
                        )
                        // Trigger build in background
                        await buildManager.runBuild(projectURL: projectURL)
                    }
                }) {
                    Label("Build", systemImage: "play.fill")
                        .foregroundStyle(.green)
                }
                .disabled(buildManager.isBuilding)
                .help("Run Xcodebuild on active project")
                .accessibilityLabel("Start Build")

                Button(action: {
                    buildManager.cancelBuild()
                }) {
                    Label("Stop", systemImage: "stop.fill")
                        .foregroundStyle(.red)
                }
                .disabled(!buildManager.isBuilding)
                .help("Stop active Xcodebuild run")
                .accessibilityLabel("Stop Build")
            }

            if buildManager.isBuilding {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Building in progress")
            }
        }
        .onAppear {
            buildManager.discoverSchemes(at: projectURL)
        }
        .onChange(of: projectURL) { _, newURL in
            buildManager.discoverSchemes(at: newURL)
        }
    }

    private func isProjectArchiveImported() -> Bool {
        guard let project = ProjectSessionStore.shared.activeProject else { return false }
        let manifestURL = project.directoryURL.appendingPathComponent("manifest.json")
        return FileManager.default.fileExists(atPath: manifestURL.path)
    }

    private func hasLivePreviewComment(content: String) -> Bool {
        let lines = content.components(separatedBy: .newlines).prefix(15)
        return lines.contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.contains("//") && trimmed.contains("@SwiftCodeVisualUIBuilderDocument")
        }
    }
}

// MARK: - Toolbar Tool View

@MainActor
struct ToolbarToolView: View {
    let tool: ToolbarTool
    // V2 fix W-V2: @Observable types are held as plain refs when passed in.
    var toolbarManager: ToolbarManager
    @Bindable var buildManager: XcodeBuildManager

    var body: some View {
        Group {
            if tool.id == "config_selector" {
                Picker("Config", selection: $buildManager.selectedConfiguration) {
                    ForEach(buildManager.availableConfigurations, id: \.self) { config in
                        Text(config).tag(config)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 100)
                .labelsHidden()
                .help("Select Build Configuration")
                .accessibilityLabel("Build Configuration Selector")
            } else if tool.id == "destination_selector" {
                Picker("Destination", selection: $buildManager.selectedDestination) {
                    ForEach(buildManager.availableDestinations, id: \.self) { dest in
                        Text(dest.replacingOccurrences(of: "generic/platform=", with: "")).tag(dest)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)
                .labelsHidden()
                .help("Select Build Destination")
                .accessibilityLabel("Build Destination Selector")
            } else {
                Button {
                    NotificationCenter.default.post(
                        name: .toolbarToolActivated,
                        object: nil,
                        userInfo: ["toolID": tool.id]
                    )
                } label: {
                    Image(systemName: tool.icon)
                        .font(.system(size: 13))
                        .padding(6)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(tool.name)
                .accessibilityLabel(tool.name)
            }
        }
        .contextMenu {
            Button(role: .destructive) {
                withAnimation {
                    toolbarManager.toggleTool(id: tool.id)
                }
            } label: {
                Label("Remove Pin", systemImage: "pin.slash")
            }

            Button {
                withAnimation {
                    toolbarManager.resetToDefaults()
                }
            } label: {
                Text("Restore Defaults")
            }
        }
        .onDrag {
            NSItemProvider(object: tool.id as NSString)
        }
        .onDrop(of: [.text], delegate: PinnedToolDropDelegate(tool: tool, manager: toolbarManager))
    }
}

// MARK: - Pinned Tool Drop Delegate

struct PinnedToolDropDelegate: DropDelegate {
    let tool: ToolbarTool
    let manager: ToolbarManager

    func performDrop(info: DropInfo) -> Bool {
        true
    }

    func dropEntered(info: DropInfo) {
        guard let provider = info.itemProviders(for: [.text]).first else { return }

        provider.loadObject(ofClass: NSString.self) { item, error in
            guard let idString = item as? String else { return }

            Task { @MainActor in
                guard idString != tool.id else { return }

                let enabledTools = manager.enabledTools
                guard let sourceIndex = enabledTools.firstIndex(where: { $0.id == idString }),
                      let destinationIndex = enabledTools.firstIndex(where: { $0.id == tool.id }) else {
                    return
                }

                if sourceIndex != destinationIndex {
                    withAnimation {
                        manager.moveTool(from: IndexSet(integer: sourceIndex), to: destinationIndex > sourceIndex ? destinationIndex + 1 : destinationIndex)
                    }
                }
            }
        }
    }
}

