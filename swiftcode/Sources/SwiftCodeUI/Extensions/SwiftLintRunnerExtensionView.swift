// Ported from Legacy `SwiftCode/Views/Settings/Extension Management/SwiftLintRunnerExtensionView.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
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

// MARK: - SwiftLint Runner Extension View
struct SwiftLintRunnerExtensionView: View {
    @State private var lintOnType = true
    @State private var showGutterIcons = true
    @State private var treatWarningsAsErrors = false
    @State private var configPath = ".swiftlint.yml"

    var body: some View {
        Form {
            Section {
                Toggle("Lint While Typing", isOn: $lintOnType)
                Toggle("Show Gutter Icons", isOn: $showGutterIcons)
                Toggle("Treat Warnings as Errors", isOn: $treatWarningsAsErrors)
            } header: {
                Label("SwiftLint Runner", systemImage: "exclamationmark.triangle")
            }
            Section {
                HStack {
                    Text("Config File")
                    Spacer()
                    TextField(".swiftlint.yml", text: $configPath)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.system(.body, design: .monospaced))
                }
            } header: {
                Text("Configuration")
            }
            Section {
                Text("Runs SwiftLint inline and surfaces warnings and errors in the editor gutter. Respects your project's .swiftlint.yml configuration file.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } header: {
                Text("About")
            }
        }
        .navigationTitle("SwiftLint Runner")
    }
}
