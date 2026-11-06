// Ported from Legacy `SwiftCode/Views/Settings/Extension Management/RustSupportExtensionView.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
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

// MARK: - Rust Support Extension View
struct RustSupportExtensionView: View {
    @State private var isEnabled = true
    @State private var edition = "2021"
    @State private var clippyEnabled = true
    @State private var showLifetimeHints = true
    @State private var showOwnershipHints = true

    private let editions = ["2015", "2018", "2021"]

    var body: some View {
        Form {
            Section {
                Toggle("Enable Rust Support", isOn: $isEnabled)
                Toggle("Clippy Linting", isOn: $clippyEnabled)
                Toggle("Ownership Hints", isOn: $showOwnershipHints)
                Toggle("Lifetime Hints", isOn: $showLifetimeHints)
            } header: {
                Label("Rust Support", systemImage: "gearshape.2.fill")
            }
            Section {
                Picker("Edition", selection: $edition) {
                    ForEach(editions, id: \.self) { e in
                        Text("Rust \(e)").tag(e)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Language Edition")
            }
            Section {
                Text("Rust syntax highlighting with ownership and lifetime annotations. Integrates Clippy for idiomatic code suggestions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Rust Support")
    }
}
