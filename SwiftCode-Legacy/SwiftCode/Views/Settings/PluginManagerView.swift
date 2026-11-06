import SwiftUI

// MARK: - Plugin Manager View

struct PluginManagerView: View {
    @StateObject private var pluginManager = PluginManager.shared
    @State private var showInstallHelp = false
    @State private var showCreateView = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 1. Installed Plugins GroupBox
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("Installed Plugins", systemImage: "cpu")
                                .font(.headline)
                                .foregroundColor(.orange)
                            Spacer()

                            HStack(spacing: 12) {
                                Button {
                                    showCreateView = true
                                } label: {
                                    Label("Create Plugin", systemImage: "plus")
                                }
                                .buttonStyle(.bordered)
                                .tint(.orange)

                                Button {
                                    Task { await pluginManager.scanPlugins() }
                                } label: {
                                    Label("Refresh", systemImage: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)
                                .tint(.orange)
                            }
                        }

                        if pluginManager.isLoading {
                            HStack {
                                ProgressView()
                                    .padding(.trailing, 8)
                                Text("Scanning Plugins…")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 24)
                        } else if pluginManager.plugins.isEmpty {
                            emptyState
                        } else {
                            VStack(spacing: 12) {
                                ForEach(pluginManager.plugins) { plugin in
                                    PluginRowView(plugin: plugin) {
                                        pluginManager.togglePlugin(plugin)
                                    } onUninstall: {
                                        try? pluginManager.uninstallPlugin(plugin)
                                    }
                                    .padding()
                                    .background(Color.primary.opacity(0.04))
                                    .cornerRadius(10)
                                }
                            }
                        }
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())

                // 2. Guide / How to Install GroupBox
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Label("How to Install Plugins", systemImage: "questionmark.circle")
                                .font(.headline)
                                .foregroundColor(.blue)
                            Spacer()
                        }

                        Text("Copy a plugin folder containing a plugin.json manifest into the Plugins directory in the app's Documents folder. SwiftCode will automatically detect and list them.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineSpacing(4)

                        Button("Learn More") {
                            showInstallHelp = true
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
            .padding(24)
        }
        .navigationTitle("Plugin Manager")
        .sheet(isPresented: $showCreateView) {
            PluginCodeCreateView()
        }
        .alert("Install Plugin", isPresented: $showInstallHelp) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Copy a plugin folder containing a plugin.json manifest into the Plugins directory in the app's Documents folder.")
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 44))
                .foregroundStyle(.secondary.opacity(0.5))
                .padding()
                .background(Circle().fill(Color.primary.opacity(0.03)))

            Text("No Plugins Installed")
                .font(.headline)
                .foregroundStyle(.primary)

            Text("Add plugins by placing a plugin folder with a plugin.json manifest in the Plugins directory.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }
}

// MARK: - Plugin Row

private struct PluginRowView: View {
    let plugin: PluginManifest
    let onToggle: () -> Void
    let onUninstall: () -> Void

    @State private var showUninstallConfirm = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "puzzlepiece.extension.fill")
                .font(.title3)
                .foregroundStyle(plugin.isEnabled ? .orange : .secondary)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(plugin.name)
                        .font(.subheadline.weight(.semibold))
                    Text("v\(plugin.version)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.secondary.opacity(0.15), in: Capsule())
                }
                Text(plugin.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                if !plugin.capabilities.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(plugin.capabilities, id: \.self) { cap in
                            Text(cap.rawValue)
                                .font(.caption2)
                                .foregroundStyle(.blue)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.12), in: Capsule())
                        }
                    }
                    .padding(.top, 2)
                }
            }

            Spacer()

            HStack(spacing: 12) {
                Toggle("", isOn: .constant(plugin.isEnabled))
                    .labelsHidden()
                    .tint(.orange)
                    .onTapGesture { onToggle() }

                Button(role: .destructive) {
                    showUninstallConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
                .help("Uninstall Plugin")
            }
        }
        .padding(.vertical, 4)
        .confirmationDialog("Uninstall \(plugin.name)?", isPresented: $showUninstallConfirm, titleVisibility: .visible) {
            Button("Uninstall", role: .destructive) { onUninstall() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove the plugin from SwiftCode, are you sure?.")
        }
    }
}
