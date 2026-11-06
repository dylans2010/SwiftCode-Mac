// SnippetLibraryExtensionView.swift
//
// Ported from Legacy `SwiftCode/Views/Settings/Extension Management/SnippetLibraryExtensionView.swift` (SwiftCode-Mac migration, Views/UI worklist).
// Worklist verdict: PARTIAL.
// Missing behaviour ported: legacy built-in snippet set (swiftui-view, init, guard-let, async-func, protocol-ext, combine-sink); tab-expansion and inline-suggestion toggles
// Static port only — no Swift toolchain here; build verification pending on Dylan's Mac.
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
                            .foregroundStyle(Color.accentColor)
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
                    .padding(10)
                    .liquidGlass(style: .subtle, cornerRadius: 8)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Snippet Library")
    }
}
