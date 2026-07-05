import SwiftUI

struct ExtensionMarketplaceView: View {
    @StateObject private var extensionManager = ExtensionManager.shared

    var body: some View {
        AdvancedToolScreen(title: "Extension Marketplace") {
            AdvancedToolCard(title: "Available Extensions", subtitle: "Install and enable integrations") {
                ForEach(extensionManager.getAllAvailableExtensions()) { ext in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(ext.name).font(.headline)
                            Spacer()
                            Toggle("Enabled", isOn: Binding(get: { ext.isEnabled }, set: { _ in extensionManager.toggleExtension(ext) }))
                                .labelsHidden()
                        }

                        Text(ext.description).font(.subheadline)
                        HStack {
                            Button(ext.isInstalled ? "Remove" : "Install") {
                                if ext.isInstalled {
                                    try? extensionManager.uninstallExtension(ext)
                                } else {
                                    extensionManager.downloadExtension(ext)
                                }
                            }
                            .buttonStyle(.bordered)
                            Text(ext.category.rawValue).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Divider()
                }
            }
        }
    }
}
