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
            // ESSENTIAL ACTIONS: Scheme selector
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
                .accessibilityLabel("Build Scheme Selector")
            }

            // Pinned & Optional Tools
            HStack(spacing: 8) {
                ForEach(toolbarManager.enabledTools) { tool in
                    Group {
                        if tool.id == "config_selector" {
                            Picker("Config", selection: Bindable(buildManager).selectedConfiguration) {
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
                            Picker("Destination", selection: Bindable(buildManager).selectedDestination) {
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
