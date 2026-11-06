// Ported from Legacy `SwiftCode/Views/Settings/Extension Management/GoSupportExtensionView.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
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

// MARK: - Go Support Extension View
struct GoSupportExtensionView: View {
    @State private var isEnabled = true
    @State private var gofmtOnSave = true
    @State private var goVersion = "1.22"
    @State private var enableModules = true

    private let goVersions = ["1.20", "1.21", "1.22", "1.23"]

    var body: some View {
        Form {
            Section {
                Toggle("Enable Go Support", isOn: $isEnabled)
                Toggle("gofmt on Save", isOn: $gofmtOnSave)
                Toggle("Go Modules (go.mod)", isOn: $enableModules)
            } header: {
                Label("Go Support", systemImage: "arrow.trianglehead.2.counterclockwise.rotate.90")
            }
            Section {
                Picker("Go Version", selection: $goVersion) {
                    ForEach(goVersions, id: \.self) { v in
                        Text("Go \(v)").tag(v)
                    }
                }
            } header: {
                Text("Toolchain")
            }
            Section {
                Text("Go syntax highlighting and gofmt integration. Automatically formats Go files on save and provides go.mod-aware import resolution.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Go Support")
    }
}
