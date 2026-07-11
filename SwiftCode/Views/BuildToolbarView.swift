import SwiftUI

@MainActor
struct BuildToolbarView: View {
    @State var viewModel: BuildViewModel
    let projectURL: URL
    @ObservedObject private var toolbarManager = ToolbarManager.shared

    private var buildManager: XcodeBuildManager {
        XcodeBuildManager.shared
    }

    var body: some View {
        HStack(spacing: 12) {
            // Dynamic scheme selector
            if !buildManager.discoveredSchemes.isEmpty {
                Picker("Scheme", selection: Bindable(buildManager).selectedScheme) {
                    ForEach(buildManager.discoveredSchemes, id: \.self) { scheme in
                        Text(scheme).tag(scheme as String?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 130)
                .labelsHidden()
                .help("Select Build Scheme")
            }

            // Configuration selector
            Picker("Config", selection: Bindable(buildManager).selectedConfiguration) {
                ForEach(buildManager.availableConfigurations, id: \.self) { config in
                    Text(config).tag(config)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 90)
            .labelsHidden()
            .help("Select Build Configuration")

            // Destination selector
            Picker("Destination", selection: Bindable(buildManager).selectedDestination) {
                ForEach(buildManager.availableDestinations, id: \.self) { dest in
                    Text(dest.replacingOccurrences(of: "generic/platform=", with: "")).tag(dest)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 140)
            .labelsHidden()
            .help("Select Build Destination")

            Divider()
                .frame(height: 16)

            // Pinned Tools
            HStack(spacing: 6) {
                ForEach(toolbarManager.enabledTools) { tool in
                    Button {
                        NotificationCenter.default.post(
                            name: .toolbarToolActivated,
                            object: nil,
                            userInfo: ["toolID": tool.id]
                        )
                    } label: {
                        Image(systemName: tool.icon)
                            .font(.system(size: 13))
                            .padding(4)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help(tool.name)
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
            .animation(.spring(), value: toolbarManager.enabledTools)

            Divider()
                .frame(height: 16)

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
            }
            .disabled(buildManager.isBuilding)
            .help("Run Xcodebuild on active project")

            Button(action: {
                buildManager.cancelBuild()
            }) {
                Label("Stop", systemImage: "stop.fill")
            }
            .disabled(!buildManager.isBuilding)
            .help("Stop active Xcodebuild run")

            if buildManager.isBuilding {
                ProgressView()
                    .controlSize(.small)
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

struct PinnedToolDropDelegate: DropDelegate {
    let tool: ToolbarTool
    let manager: ToolbarManager

    func performDrop(info: DropInfo) -> Bool {
        return true
    }

    func dropEntered(info: DropInfo) {
        guard let provider = info.itemProviders(for: [.text]).first else { return }
        _ = provider.loadObject(ofClass: NSString.self) { string, error in
            if let draggedId = string as? String {
                Task { @MainActor in
                    if let sourceIndex = manager.tools.firstIndex(where: { $0.id == draggedId }),
                       let destinationIndex = manager.tools.firstIndex(where: { $0.id == tool.id }) {
                        if sourceIndex != destinationIndex {
                            manager.tools.swapAt(sourceIndex, destinationIndex)
                            // Persist swaps
                            if let data = try? JSONEncoder().encode(manager.tools) {
                                UserDefaults.standard.set(data, forKey: "com.swiftcode.toolbarTools")
                            }
                        }
                    }
                }
            }
        }
    }
}
