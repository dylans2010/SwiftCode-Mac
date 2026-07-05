import SwiftUI

// MARK: - DocC Generator Extension View
struct DocCGeneratorExtensionView: View {
    @State private var isEnabled = true
    @State private var autoBuildOnSave = false
    @State private var outputPath = ".build/plugins/Swift-DocC"
    @State private var enableInheritedDocs = true
    @State private var minAccessLevel = "public"

    private let accessLevels = ["public", "internal", "private"]

    var body: some View {
        Form {
            Section {
                Toggle("Enable DocC Generator", isOn: $isEnabled)
                Toggle("Auto-Build on Save", isOn: $autoBuildOnSave)
                Toggle("Inherited Documentation", isOn: $enableInheritedDocs)
            } header: {
                Label("DocC Generator", systemImage: "books.vertical.fill")
            }
            Section {
                HStack {
                    Text("Output Path")
                    Spacer()
                    TextField(".build/plugins/Swift-DocC", text: $outputPath)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.system(.caption, design: .monospaced))
                }
                Picker("Minimum Access Level", selection: $minAccessLevel) {
                    ForEach(accessLevels, id: \.self) { level in
                        Text(level.capitalized).tag(level)
                    }
                }
            } header: {
                Text("Output Settings")
            }
            Section {
                Text("Build and preview Apple DocC documentation directly in the IDE. Generates a static documentation catalog that can be hosted or submitted with your package.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("DocC Generator")
        .navigationBarTitleDisplayMode(.inline)
    }
}
