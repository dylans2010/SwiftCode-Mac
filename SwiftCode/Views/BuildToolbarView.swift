import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct BuildToolbarView: View {
    @State var viewModel: BuildViewModel
    let projectURL: URL
    @ObservedObject private var toolbarManager = ToolbarManager.shared

    private var buildManager: XcodeBuildManager {
        XcodeBuildManager.shared
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
