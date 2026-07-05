import SwiftUI

// MARK: - AI Refactor Extension View
struct AIRefactorExtensionView: View {
    @State private var isEnabled = true
    @State private var suggestionMode = "inline"
    @State private var autoSuggest = false
    @State private var showDiff = true

    var body: some View {
        Form {
            Section {
                Toggle("Enable AI Refactor", isOn: $isEnabled)
                Toggle("Auto-Suggest Refactors", isOn: $autoSuggest)
                Toggle("Show Diff Before Applying", isOn: $showDiff)
            } header: {
                Label("AI Refactor", systemImage: "wand.and.sparkles")
            }
            Section {
                Picker("Suggestion Mode", selection: $suggestionMode) {
                    Text("Inline (lightbulb menu)").tag("inline")
                    Text("Side Panel").tag("panel")
                    Text("Command Palette").tag("command")
                }
            } header: {
                Text("Display")
            }
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Extract Method", systemImage: "arrow.up.doc")
                    Label("Rename Symbol", systemImage: "pencil.line")
                    Label("Restructure Conditionals", systemImage: "arrow.triangle.branch")
                    Label("Convert to Async/Await", systemImage: "clock.arrow.2.circlepath")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } header: {
                Text("Available Refactors")
            }
            Section {
                Text("AI-powered refactoring suggestions: extract method, rename, restructure conditionals, and convert callback-style code to async/await.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("AI Refactor")
        .navigationBarTitleDisplayMode(.inline)
    }
}
