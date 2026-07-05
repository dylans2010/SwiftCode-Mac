import SwiftUI

// MARK: - JSON Formatter Extension View
struct JSONFormatterExtensionView: View {
    @State private var formatOnSave = true
    @State private var indentStyle = "spaces"
    @State private var indentSize = 2
    @State private var sortKeys = false
    @State private var collapseByDefault = false

    var body: some View {
        Form {
            Section {
                Toggle("Format on Save", isOn: $formatOnSave)
                Toggle("Sort Keys Alphabetically", isOn: $sortKeys)
                Toggle("Collapse Nodes by Default", isOn: $collapseByDefault)
            } header: {
                Label("JSON Formatter", systemImage: "curlybraces")
            }
            Section {
                Picker("Indent Style", selection: $indentStyle) {
                    Text("Spaces").tag("spaces")
                    Text("Tabs").tag("tabs")
                }
                .pickerStyle(.segmented)
                Stepper("Indent Size: \(indentSize)", value: $indentSize, in: 1...8)
            } header: {
                Text("Formatting")
            }
            Section {
                Text("Pretty-prints and validates JSON files with collapsible nodes. Highlights syntax errors and provides inline validation as you type.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("JSON Formatter")
        .navigationBarTitleDisplayMode(.inline)
    }
}
