// Ported from Legacy `SwiftCode/Views/Settings/Extension Management/KotlinSupportExtensionView.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
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

// MARK: - Kotlin Support Extension View
struct KotlinSupportExtensionView: View {
    @State private var isEnabled = true
    @State private var kotlinVersion = "1.9"
    @State private var autoImport = true
    @State private var showCoroutineHints = true

    private let versions = ["1.6", "1.7", "1.8", "1.9", "2.0"]

    var body: some View {
        Form {
            Section {
                Toggle("Enable Kotlin Support", isOn: $isEnabled)
                Toggle("Auto-Import Suggestions", isOn: $autoImport)
                Toggle("Coroutine Hints", isOn: $showCoroutineHints)
            } header: {
                Label("Kotlin Support", systemImage: "chevron.left.forwardslash.chevron.right")
            }
            Section {
                Picker("Kotlin Version", selection: $kotlinVersion) {
                    ForEach(versions, id: \.self) { v in
                        Text("Kotlin \(v)").tag(v)
                    }
                }
            } header: {
                Text("Language Version")
            }
            Section {
                Text("Provides syntax highlighting and basic IntelliSense for Kotlin files (.kt, .kts). Includes coroutine flow hints and standard library auto-imports.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Kotlin Support")
    }
}
