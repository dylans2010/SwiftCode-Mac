import SwiftUI

// MARK: - Snippet Library Extension View
struct SnippetLibraryExtensionView: View {
    @State private var tabExpansionEnabled = true
    @State private var showSuggestionsInline = true

    private let builtInSnippets = [
        ("swiftui-view", "SwiftUI View"),
        ("init", "Memberwise Initializer"),
        ("guard-let", "Guard Let Binding"),
        ("async-func", "Async/Await Function"),
        ("protocol-ext", "Protocol Extension"),
        ("combine-sink", "Combine Sink"),
    ]

    var body: some View {
        Form {
            Section {
                Toggle("Tab Expansion", isOn: $tabExpansionEnabled)
                Toggle("Inline Suggestions", isOn: $showSuggestionsInline)
            } header: {
                Label("Snippet Library", systemImage: "doc.text.below.ecg")
            }
            Section {
                ForEach(builtInSnippets, id: \.0) { trigger, name in
                    HStack {
                        Text(trigger)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.accentColor)
                        Spacer()
                        Text(name)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                }
            } header: {
                Text("Built-in Snippets")
            } footer: {
                Text("Type the trigger and press Tab to expand.")
            }
            Section {
                Text("Manage and insert reusable code snippets with tab-expansion. Add your own snippets from the editor context menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Snippet Library")
        .navigationBarTitleDisplayMode(.inline)
    }
}
