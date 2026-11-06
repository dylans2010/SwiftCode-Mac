// Ported from Legacy `SwiftCode/Views/Settings/Extension Management/TodoHighlighterExtensionView.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged only — not yet merged into swiftcode/Sources. See staging-wire/missing/DISPOSITIONS.md.
// Verbatim except `.liquidGlass(...)` -> thinMaterial (see Adaptive notes).
// Self-contained v1 extension settings form. All toggles/pickers are local @State
// in Legacy (no backend calls) — preserved as-is; there is no destination backend
// for these yet (no Go/Kotlin/Python/Rust/TypeScript language support, no
// multi-cursor engine, no DocC generator, no SwiftLint runner, no TODO highlighter,
// and the v2 theme system has 4 built-ins without these palettes).
// Wiring: the Extensions v2 console (ExtensionsPanelViewController) should present
// these as the extension's settings view; theme views' "Set as Active Theme" toggle
// needs a theme-activation hook in the v2 theme system when one exists.

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
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } header: {
                Text("About")
            }
        }
        .navigationTitle("TODO Highlighter")
    }
}
