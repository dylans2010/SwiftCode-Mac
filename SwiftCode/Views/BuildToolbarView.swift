import SwiftUI

@MainActor
struct BuildToolbarView: View {
    @State var viewModel: BuildViewModel
    let projectURL: URL

    @State private var selectedConfiguration = "Debug"
    @State private var selectedDestination = "generic/platform=iOS Simulator"

    @ObservedObject private var toolbarSettings = ToolbarSettings.shared

    private var buildManager: XcodeBuildManager {
        XcodeBuildManager.shared
    }

    var body: some View {
        HStack(spacing: 8) {
            // Build Button
            Button(action: {
                Task {
                    // Automatically open XcodeBuildLogView
                    NotificationCenter.default.post(
                        name: .toolbarToolActivated,
                        object: nil,
                        userInfo: ["toolID": "xcode_build_logs"]
                    )
                    // Trigger build in background
                    await buildManager.runBuild(
                        projectURL: projectURL,
                        scheme: buildManager.selectedScheme,
                        configuration: selectedConfiguration,
                        destination: selectedDestination
                    )
                }
            }) {
                Label("Build", systemImage: "play.fill")
            }
            .disabled(buildManager.isBuilding)
            .help("Run xcodebuild on active project")

            // Stop Button
            Button(action: {
                buildManager.cancelBuild()
            }) {
                Label("Stop", systemImage: "stop.fill")
            }
            .disabled(!buildManager.isBuilding)
            .help("Stop active build run")

            if buildManager.isBuilding {
                ProgressView()
                    .controlSize(.small)
            }

            Divider()
                .frame(height: 16)

            // Dynamic Scheme Picker
            if !buildManager.availableSchemes.isEmpty {
                Picker("Scheme", selection: Bindable(buildManager).selectedScheme) {
                    ForEach(buildManager.availableSchemes, id: \.self) { scheme in
                        Text(scheme).tag(scheme as String?)
                    }
                }
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 130)
                .help("Select Build Scheme")
            }

            // Configuration Picker
            Picker("Config", selection: $selectedConfiguration) {
                Text("Debug").tag("Debug")
                Text("Release").tag("Release")
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(width: 85)
            .help("Select Build Configuration")

            Divider()
                .frame(height: 16)

            // Pinned Tools Row
            HStack(spacing: 6) {
                ForEach(toolbarSettings.pinnedTools, id: \.self) { toolId in
                    let info = toolInfo(for: toolId)
                    Button(action: { activateTool(toolId) }) {
                        HStack(spacing: 4) {
                            Image(systemName: info.icon)
                            Text(info.name)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .onTapGesture(count: 2) {
                        toolbarSettings.unpinTool(id: toolId)
                    }
                    .onDrag {
                        NSItemProvider(object: toolId as NSString)
                    }
                    .onDrop(of: [.text], delegate: PinnedToolDropDelegate(item: toolId, manager: toolbarSettings))
                    .contextMenu {
                        Button(role: .destructive) {
                            toolbarSettings.unpinTool(id: toolId)
                        } label: {
                            Label("Remove Pin", systemImage: "pin.slash")
                        }
                    }
                }
            }
            .animation(.spring(response: 0.3), value: toolbarSettings.pinnedTools)

            if !toolbarSettings.pinnedTools.isEmpty {
                Button(action: { toolbarSettings.restorePinnedDefaults() }) {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.plain)
                .help("Restore default pinned tools")
            }
        }
        .onAppear {
            Task {
                _ = await buildManager.discoverSchemes(in: projectURL)
            }
        }
        .onChange(of: projectURL) { _, newURL in
            Task {
                _ = await buildManager.discoverSchemes(in: newURL)
            }
        }
    }

    // MARK: - Helpers

    private func activateTool(_ toolId: String) {
        if toolId == "ai_code_gen" {
            NotificationCenter.default.post(
                name: .toolbarToolActivated,
                object: nil,
                userInfo: ["toolID": "ai_code_gen"]
            )
        } else {
            NotificationCenter.default.post(
                name: .toolbarToolActivated,
                object: nil,
                userInfo: ["toolID": toolId]
            )
        }
    }

    private func toolInfo(for toolId: String) -> (name: String, icon: String) {
        if let found = ToolbarManager.defaultTools.first(where: { $0.id == toolId }) {
            return (found.name, found.icon)
        }
        return (toolId.replacingOccurrences(of: "_", with: " ").capitalized, "cube.fill")
    }
}

// MARK: - Drag & Drop Delegate

struct PinnedToolDropDelegate: DropDelegate {
    let item: String
    @ObservedObject var manager: ToolbarSettings

    func performDrop(info: DropInfo) -> Bool {
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let provider = info.itemProviders(for: [.text]).first else { return }
        provider.loadObject(ofClass: NSString.self) { string, _ in
            guard let draggedId = string as? String else { return }
            if draggedId != item {
                DispatchQueue.main.async {
                    if let from = manager.pinnedTools.firstIndex(of: draggedId),
                       let to = manager.pinnedTools.firstIndex(of: item) {
                        manager.pinnedTools.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
                    }
                }
            }
        }
    }
}
