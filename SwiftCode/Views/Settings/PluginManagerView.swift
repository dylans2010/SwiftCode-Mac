import SwiftUI

// MARK: - Plugin Manager View

struct PluginManagerView: View {
    @StateObject private var pluginManager = PluginManager.shared
    @State private var showInstallHelp = false
    @State private var showCreateView = false

    var body: some View {
        NavigationStack {
            Group {
                if pluginManager.isLoading {
                    ProgressView("Scanning Plugins…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if pluginManager.plugins.isEmpty {
                    emptyState
                } else {
                    pluginList
                }
            }
            .navigationTitle("Plugin Manager")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button {
                            showCreateView = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .foregroundStyle(.orange)

                        Button("Refresh") {
                            Task { await pluginManager.scanPlugins() }
                        }
                        .foregroundStyle(.orange)
                    }
                }
            }
            .sheet(isPresented: $showCreateView) {
                PluginCodeCreateView()
            }
            .alert("Install Plugin", isPresented: $showInstallHelp) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Copy a plugin folder containing a plugin.json manifest into the Plugins directory in the app's Documents folder.")
            }
        }
    }

    // MARK: - Plugin List

    private var pluginList: some View {
        List {
            ForEach(pluginManager.plugins) { plugin in
                PluginRowView(plugin: plugin) {
                    pluginManager.togglePlugin(plugin)
                } onUninstall: {
                    try? pluginManager.uninstallPlugin(plugin)
                }
            }

            Section {
                Button {
                    showInstallHelp = true
                } label: {
                    Label("How to Install a Plugin", systemImage: "questionmark.circle")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "puzzlepiece.extension")
                .font(.system(size: 52))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("No Plugins Installed")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.primary)
            Text("Add plugins by placing a plugin folder with a plugin.json manifest in the Plugins directory.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                showInstallHelp = true
            } label: {
                Label("Learn More", systemImage: "questionmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    ScrollView(.horizontal, showsIndicators: false) {
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
                    }
                }
            }

            Spacer()

            Toggle("", isOn: .constant(plugin.isEnabled))
                .labelsHidden()
                .tint(.orange)
                .onTapGesture { onToggle() }
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                showUninstallConfirm = true
            } label: {
                Label("Uninstall", systemImage: "trash")
            }
        }
        .confirmationDialog("Uninstall \(plugin.name)?", isPresented: $showUninstallConfirm, titleVisibility: .visible) {
            Button("Uninstall", role: .destructive) { onUninstall() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove the plugin from SwiftCode, are you sure?.")
        }
    }
}
