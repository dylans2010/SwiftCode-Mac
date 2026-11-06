// Ported from Legacy `SwiftCode/Views/Settings/Extension Management/DocCGeneratorExtensionView.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
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

// MARK: - Documentation Generator Extension View
struct DocCGeneratorExtensionView: View {
    @State private var isEnabled = true
    @State private var autoBuildOnSave = false
    @State private var outputPath = ".build/plugins/Swift-DocC"
    @State private var enableInheritedDocs = true
    @State private var minAccessLevel = "public"

    private let accessLevels = ["public", "internal", "private"]

    var body: some View {
        Form {
            Section {
                Toggle("Enable Documentation Generator", isOn: $isEnabled)
                Toggle("Auto-Build on Save", isOn: $autoBuildOnSave)
                Toggle("Inherited Documentation", isOn: $enableInheritedDocs)
            } header: {
                Label("Documentation Generator", systemImage: "books.vertical.fill")
            }
            Section {
                HStack {
                    Text("Output Path")
                    Spacer()
                    TextField("Output path", text: $outputPath)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.system(.caption, design: .monospaced))
                }
                Picker("Minimum Access Level", selection: $minAccessLevel) {
                    ForEach(accessLevels, id: \.self) { level in
                        Text(level.capitalized).tag(level)
                    }
                }
            } header: {
                Text("Output Settings")
            }
            Section {
                Text("Build and preview Apple documentation directly in the IDE. Generates a static documentation catalog that can be hosted or submitted with your package.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Documentation Generator")
    }
}
