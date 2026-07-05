import SwiftUI

// MARK: - Multi-Cursor Extension View
struct MultiCursorExtensionView: View {
    @State private var isEnabled = true
    @State private var highlightMatchingWords = true
    @State private var addCursorOnClick = false

    private let shortcuts = [
        ("Add Cursor Above", "⌥↑"),
        ("Add Cursor Below", "⌥↓"),
        ("Select All Occurrences", "⌘⇧L"),
        ("Add Next Occurrence", "⌘D"),
        ("Column Selection", "⌥⇧Drag"),
    ]

    var body: some View {
        Form {
            Section {
                Toggle("Enable Multi-Cursor", isOn: $isEnabled)
                Toggle("Highlight Matching Words", isOn: $highlightMatchingWords)
                Toggle("Add Cursor on ⌥-Click", isOn: $addCursorOnClick)
            } header: {
                Label("Multi-Cursor", systemImage: "cursorarrow.rays")
            }
            Section {
                ForEach(shortcuts, id: \.0) { action, shortcut in
                    HStack {
                        Text(action)
                        Spacer()
                        Text(shortcut)
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Keyboard Shortcuts")
            }
            Section {
                Text("Edit multiple locations simultaneously with multi-cursor support. Add cursors above/below, select all occurrences of a word, or use column selection mode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Multi-Cursor")
        .navigationBarTitleDisplayMode(.inline)
    }
}
