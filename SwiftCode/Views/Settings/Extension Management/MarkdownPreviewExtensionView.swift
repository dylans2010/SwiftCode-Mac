import SwiftUI

// MARK: - Markdown Preview Extension View
struct MarkdownPreviewExtensionView: View {
    @State private var livePreviewEnabled = true
    @State private var syncScroll = true
    @State private var previewTheme = "github"
    @State private var renderMath = false

    private let themes = ["github", "minimal", "dark", "solarized"]

    var body: some View {
        Form {
            Section {
                Toggle("Live Preview", isOn: $livePreviewEnabled)
                Toggle("Sync Scrolling", isOn: $syncScroll)
                Toggle("Render Math (KaTeX)", isOn: $renderMath)
            } header: {
                Label("Markdown Preview", systemImage: "doc.richtext")
            }
            Section {
                Picker("Preview Theme", selection: $previewTheme) {
                    ForEach(themes, id: \.self) { theme in
                        Text(theme.capitalized).tag(theme)
                    }
                }
            } header: {
                Text("Appearance")
            }
            Section {
                Text("Provides a live side-by-side preview for Markdown files. Supports GFM (GitHub Flavored Markdown), tables, task lists, and optionally KaTeX math rendering.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Markdown Preview")
        .navigationBarTitleDisplayMode(.inline)
    }
}
