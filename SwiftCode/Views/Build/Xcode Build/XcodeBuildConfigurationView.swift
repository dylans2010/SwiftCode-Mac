import SwiftUI

@MainActor
struct XcodeBuildConfigurationView: View {
    @State private var xcodeBuildPath = ""
    @State private var toolchainPath = "Loading..."
    @State private var validationMessage = ""
    @State private var isValid = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Toolchain Configuration") {
                    HStack {
                        TextField("xcodebuild executable path:", text: $xcodeBuildPath)
                            .textFieldStyle(.roundedBorder)

                        Button("Detect Default") {
                            xcodeBuildPath = "/usr/bin/xcodebuild"
                            validate()
                        }
                    }

                    HStack {
                        Text("Active Developer Path:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(toolchainPath)
                            .font(.caption.monospaced())
                    }
                }

                Section("Validation Status") {
                    HStack {
                        Image(systemName: isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(isValid ? .green : .red)
                        Text(validationMessage)
                            .font(.body)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Build Configuration Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Settings") {
                        XcodeBuildManager.shared.setXcodeBuildPath(xcodeBuildPath)
                        dismiss()
                    }
                    .disabled(xcodeBuildPath.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                xcodeBuildPath = XcodeBuildManager.shared.getXcodeBuildPath()
                validate()
                Task {
                    toolchainPath = await XcodeBuildManager.shared.getActiveToolchain()
                }
            }
            .onChange(of: xcodeBuildPath) { _, _ in
                validate()
            }
        }
        .frame(minWidth: 400, idealWidth: 450, maxWidth: 600, minHeight: 250, idealHeight: 280, maxHeight: 400)
    }

    private func validate() {
        if XcodeBuildManager.shared.validatePath(xcodeBuildPath) {
            isValid = true
            validationMessage = "xcodebuild found and is executable."
        } else {
            isValid = false
            validationMessage = "Path is invalid or not executable. Default is /usr/bin/xcodebuild."
        }
    }
}
