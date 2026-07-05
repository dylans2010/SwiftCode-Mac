import SwiftUI

// MARK: - Python Support Extension View
struct PythonSupportExtensionView: View {
    @State private var isEnabled = true
    @State private var pythonVersion = "3.11"
    @State private var venvPath = ".venv"
    @State private var showTypingHints = true
    @State private var enableDocstrings = true

    private let pythonVersions = ["3.9", "3.10", "3.11", "3.12", "3.13"]

    var body: some View {
        Form {
            Section {
                Toggle("Enable Python Support", isOn: $isEnabled)
                Toggle("Type Annotation Hints", isOn: $showTypingHints)
                Toggle("Docstring Templates", isOn: $enableDocstrings)
            } header: {
                Label("Python Support", systemImage: "scroll")
            }
            Section {
                Picker("Python Version", selection: $pythonVersion) {
                    ForEach(pythonVersions, id: \.self) { v in
                        Text("Python \(v)").tag(v)
                    }
                }
                HStack {
                    Text("Virtual Env Path")
                    Spacer()
                    TextField(".venv", text: $venvPath)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.system(.body, design: .monospaced))
                }
            } header: {
                Text("Interpreter")
            }
            Section {
                Text("Python 3 syntax highlighting, docstring templates (Google, NumPy, reStructuredText styles), and a built-in snippet library for common patterns.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Python Support")
        .navigationBarTitleDisplayMode(.inline)
    }
}
