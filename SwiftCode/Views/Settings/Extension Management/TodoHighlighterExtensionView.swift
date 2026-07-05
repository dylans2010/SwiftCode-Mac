import SwiftUI

// MARK: - TODO Highlighter Extension View
struct TodoHighlighterExtensionView: View {
    @State private var isEnabled = true
    @State private var keywords = ["TODO", "FIXME", "MARK", "HACK", "WARNING"]
    @State private var showInMinimap = true
    @State private var showBadgeCount = true

    private let presetColors: [(String, Color)] = [
        ("TODO", .blue),
        ("FIXME", .red),
        ("MARK", .green),
        ("HACK", .orange),
        ("WARNING", .yellow),
    ]

    var body: some View {
        Form {
            Section {
                Toggle("Enable TODO Highlighter", isOn: $isEnabled)
                Toggle("Show in Minimap", isOn: $showInMinimap)
                Toggle("Show Badge Count", isOn: $showBadgeCount)
            } header: {
                Label("TODO Highlighter", systemImage: "checkmark.circle.badge.xmark")
            }
            Section {
                ForEach(presetColors, id: \.0) { keyword, color in
                    HStack {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color.opacity(0.8))
                            .frame(width: 8, height: 20)
                        Text(keyword)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.semibold)
                        Spacer()
                        Text("Active")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Keywords & Colors")
            }
            Section {
                Text("Highlights TODO, FIXME, MARK, and HACK comments with color-coded badges. All occurrences appear in the editor minimap and the badge count.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("TODO Highlighter")
        .navigationBarTitleDisplayMode(.inline)
    }
}
