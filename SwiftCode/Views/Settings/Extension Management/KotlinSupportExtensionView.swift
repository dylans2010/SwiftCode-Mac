import SwiftUI

// MARK: - Kotlin Support Extension View
struct KotlinSupportExtensionView: View {
    @State private var isEnabled = true
    @State private var kotlinVersion = "1.9"
    @State private var autoImport = true
    @State private var showCoroutineHints = true

    private let versions = ["1.6", "1.7", "1.8", "1.9", "2.0"]

    var body: some View {
        Form {
            Section {
                Toggle("Enable Kotlin Support", isOn: $isEnabled)
                Toggle("Auto-Import Suggestions", isOn: $autoImport)
                Toggle("Coroutine Hints", isOn: $showCoroutineHints)
            } header: {
                Label("Kotlin Support", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            Section {
                Picker("Kotlin Version", selection: $kotlinVersion) {
                    ForEach(versions, id: \.self) { v in
                        Text("Kotlin \(v)").tag(v)
                    }
                }
            } header: {
                Text("Language Version")
            }
            Section {
                Text("Provides syntax highlighting and basic IntelliSense for Kotlin files (.kt, .kts). Includes coroutine flow hints and standard library auto-imports.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Kotlin Support")
        .navigationBarTitleDisplayMode(.inline)
    }
}
