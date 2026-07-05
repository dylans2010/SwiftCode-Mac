import SwiftUI

// MARK: - Swift Formatter Extension View
struct SwiftFormatterExtensionView: View {
    @State private var formatOnSave = true
    @State private var indentWidth = 4
    @State private var useSpaces = true
    @State private var maxLineLength = 120

    var body: some View {
        Form {
            Section {
                Toggle("Format on Save", isOn: $formatOnSave)
                Stepper("Indent Width: \(indentWidth)", value: $indentWidth, in: 2...8)
                Toggle("Use Spaces (not Tabs)", isOn: $useSpaces)
                Stepper("Max Line Length: \(maxLineLength)", value: $maxLineLength, in: 80...200, step: 10)
            } header: {
                Label("Swift Formatter", systemImage: "text.alignleft")
            }
            Section {
                Text("Automatically formats Swift source files using SwiftFormat rules whenever a file is saved. Supports most standard SwiftFormat options.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Swift Formatter")
        .navigationBarTitleDisplayMode(.inline)
    }
}
