import SwiftUI
import AppKit
import UniformTypeIdentifiers

@MainActor
struct BuildToolbarView: View {
    @State var viewModel: BuildViewModel
    let projectURL: URL
    @Bindable var editorViewModel: EditorViewModel
    @ObservedObject private var toolbarManager = ToolbarManager.shared

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
                    NotificationCenter.default.post(name: .toolbarToolActivated, object: nil, userInfo: ["toolID": "xcode_build_logs"])
                } label: {
                    Label("Run Full App", systemImage: "play.desktopcomputer")
                }

                Button {
                    Task {
                        if let activeDoc = editorViewModel.activeDocument {
                            await editorViewModel.saveActiveDocument()
                            NotificationCenter.default.post(name: .toolbarToolActivated, object: nil, userInfo: ["toolID": "visual_ui_builder"])
                            let (preparedCode, _) = SwiftViewDetector.prepareSourceCode(activeDoc.content, filename: activeDoc.url.path)
                            await PreviewManager.shared.startFreshLivePreviewSession(sourcePath: activeDoc.url.path, sourceCode: preparedCode)
                        }
                    }
                } label: {
                    Label("Live Preview", systemImage: "play.rectangle.on.rectangle")
                }

                Button {
                    NotificationCenter.default.post(name: .toolbarToolActivated, object: nil, userInfo: ["toolID": "deviceConnect"])
                } label: {
                    Label("Device Connect", systemImage: "iphone.badge.play")
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
                    Label("Build Logs", systemImage: "doc.text.fill")
                }

                Button {
                    NotificationCenter.default.post(name: .toolbarToolActivated, object: nil, userInfo: ["toolID": "preview_logs"])
                } label: {
                    Label("Preview Logs", systemImage: "doc.text")
                }

                Button {
                    NotificationCenter.default.post(name: .toolbarToolActivated, object: nil, userInfo: ["toolID": "error_diagnostics"])
                } label: {
                    Label("Project Diagnostics", systemImage: "exclamationmark.triangle")
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
        } label: {
            Label("Actions", systemImage: "swift")
                .foregroundColor(.orange)
        }
        .menuStyle(.borderlessButton)
        .help("Comprehensive Build and Development Actions")
    }

    var body: some View {
        @Bindable var buildManager = self.buildManager
        HStack {
            Spacer()

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

                if let activeDoc = editorViewModel.activeDocument, activeDoc.url.pathExtension.lowercased() == "swift" {
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

                            // 4. Start a brand-new preview session
                            let (preparedCode, _) = SwiftViewDetector.prepareSourceCode(activeDoc.content, filename: activeDoc.url.path)
                            await PreviewManager.shared.startFreshLivePreviewSession(
                                sourcePath: activeDoc.url.path,
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

            Spacer()
        }
        .onAppear {
            buildManager.discoverSchemes(at: projectURL)
        }
        .onChange(of: projectURL) { _, newURL in
            buildManager.discoverSchemes(at: newURL)
        }
    }
}

// MARK: - Toolbar Tool View

@MainActor
struct ToolbarToolView: View {
    let tool: ToolbarTool
    @ObservedObject var toolbarManager: ToolbarManager
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
                        .background(Color.secondary.opacity(0.1))
                        .cornerRadius(6)
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
