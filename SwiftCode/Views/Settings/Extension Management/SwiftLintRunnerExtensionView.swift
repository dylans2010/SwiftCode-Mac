import SwiftUI

// MARK: - SwiftLint Runner Extension View
struct SwiftLintRunnerExtensionView: View {
    @State private var lintOnType = true
    @State private var showGutterIcons = true
    @State private var treatWarningsAsErrors = false
    @State private var configPath = ".swiftlint.yml"

    var body: some View {
        Form {
            Section {
                Toggle("Lint While Typing", isOn: $lintOnType)
                Toggle("Show Gutter Icons", isOn: $showGutterIcons)
                Toggle("Treat Warnings as Errors", isOn: $treatWarningsAsErrors)
            } header: {
                Label("SwiftLint Runner", systemImage: "exclamationmark.triangle")
            }
            Section {
                HStack {
                    Text("Config File")
                    Spacer()
                    TextField(".swiftlint.yml", text: $configPath)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.system(.body, design: .monospaced))
                }
            } header: {
                Text("Configuration")
            }
            Section {
                Text("Runs SwiftLint inline and surfaces warnings and errors in the editor gutter. Respects your project's .swiftlint.yml configuration file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("SwiftLint Runner")
        .navigationBarTitleDisplayMode(.inline)
    }
}
