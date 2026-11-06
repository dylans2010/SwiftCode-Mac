// Ported from Legacy `SwiftCode/Views/Settings/Extension Management/MultiCursorExtensionView.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
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
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Multi-Cursor")
    }
}
