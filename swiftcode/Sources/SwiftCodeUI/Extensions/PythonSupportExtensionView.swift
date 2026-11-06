// Ported from Legacy `SwiftCode/Views/Settings/Extension Management/PythonSupportExtensionView.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
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

// MARK: - Python Support Extension View
struct PythonSupportExtensionView: View {
    @State private var isEnabled = true
    @State private var pythonVersion = "3.11"
    @State private var venvPath = ".venv"
    @State private var showTypingHints = true
    @State private var enableDocstrings = true

    private let pythonVersions = ["3.9", "3.10", "3.11", "3.12", "3.13"]

    var body: some View {
        Form {
            Section {
                Toggle("Enable Python Support", isOn: $isEnabled)
                Toggle("Type Annotation Hints", isOn: $showTypingHints)
                Toggle("Docstring Templates", isOn: $enableDocstrings)
            } header: {
                Label("Python Support", systemImage: "scroll")
            }
            Section {
                Picker("Python Version", selection: $pythonVersion) {
                    ForEach(pythonVersions, id: \.self) { v in
                        Text("Python \(v)").tag(v)
                    }
                }
                HStack {
                    Text("Virtual Env Path")
                    Spacer()
                    TextField(".venv", text: $venvPath)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                        .font(.system(.body, design: .monospaced))
                }
            } header: {
                Text("Interpreter")
            }
            Section {
                Text("Python 3 syntax highlighting, docstring templates (Google, NumPy, reStructuredText styles), and a built-in snippet library for common patterns.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Python Support")
    }
}
