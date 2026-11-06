import SwiftUI

// MARK: - Extensions settings (persisted via ExtV2Storage)

public struct ExtensionSettingsView: View {
    @ObservedObject private var manager = ExtV2Manager.shared
    @State private var savedMessage: String?

    public init() {}

    public var body: some View {
        Form {
            Section("Registry") {
                TextField("Registry base URL", text: $manager.settings.registryBaseURL)
                    .textFieldStyle(.roundedBorder)
                Toggle("Allow prerelease versions", isOn: $manager.settings.allowPrerelease)
                Toggle("Check for updates automatically", isOn: $manager.settings.autoUpdate)
            }
            Section("Runtime") {
                TextField("Node executable path (optional)", text: Binding(
                    get: { manager.settings.nodeExecutablePath ?? "" },
                    set: { manager.settings.nodeExecutablePath = $0.isEmpty ? nil : $0 }))
                    .textFieldStyle(.roundedBorder)
                Text("Leave empty to use the Node.js found on PATH (/opt/homebrew/bin/node, /usr/local/bin/node, /usr/bin/node). VS Code extensions cannot run without Node.js.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Maintenance") {
                Button("Register sample native plugin") {
                    manager.registerSamplePlugin()
                    savedMessage = "Sample native plugin registered."
                }
                Button("Clean stale install staging") {
                    manager.storage.cleanStaleStaging()
                    savedMessage = "Staging cleaned."
                }
                Button("Clear diagnostics") {
                    ExtV2DiagnosticsService.shared.clear()
                    savedMessage = "Diagnostics cleared."
                }
            }
            Button("Save settings") {
                manager.saveSettings()
                savedMessage = "Settings saved."
            }
            .buttonStyle(.borderedProminent)
            if let savedMessage {
                Text(savedMessage).font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}
