// Ported from Legacy `SwiftCode/Views/Settings/Extension Management/NordThemeExtensionView.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
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

// MARK: - Nord Theme Extension View
struct NordThemeExtensionView: View {
    @State private var isActive = false
    @State private var variant = "dark"

    private let swatches: [(String, Color)] = [
        ("Polar Night", Color(red: 0.18, green: 0.20, blue: 0.25)),
        ("Snow Storm", Color(red: 0.93, green: 0.94, blue: 0.96)),
        ("Frost Blue", Color(red: 0.53, green: 0.75, blue: 0.82)),
        ("Aurora Green", Color(red: 0.64, green: 0.74, blue: 0.55)),
        ("Aurora Red", Color(red: 0.75, green: 0.38, blue: 0.42)),
        ("Aurora Purple", Color(red: 0.71, green: 0.56, blue: 0.75)),
    ]

    var body: some View {
        Form {
            Section {
                Toggle("Set as Active Theme", isOn: $isActive)
                Picker("Variant", selection: $variant) {
                    Text("Dark").tag("dark")
                    Text("Light").tag("light")
                }
                .pickerStyle(.segmented)
            } header: {
                Label("Nord Theme", systemImage: "snowflake")
            }
            Section {
                ForEach(swatches, id: \.0) { name, color in
                    HStack {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(color)
                            .frame(width: 24, height: 24)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                        Text(name)
                        Spacer()
                    }
                }
            } header: {
                Text("Color Palette")
            }
            Section {
                Text("The popular Nord arctic color palette for comfortable night coding. Features cool blue tones derived from the arctic landscape.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Nord Theme")
    }
}
