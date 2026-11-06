// Ported from Legacy `SwiftCode/Views/Settings/Extension Management/DarkProThemeExtensionView.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
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

// MARK: - Dark Pro Theme Extension View
struct DarkProThemeExtensionView: View {
    @State private var isActive = false

    private let swatches: [(String, Color)] = [
        ("Background", Color(red: 0.12, green: 0.12, blue: 0.12)),
        ("Foreground", Color(red: 0.85, green: 0.85, blue: 0.85)),
        ("Keywords", Color(red: 0.34, green: 0.61, blue: 0.87)),
        ("Strings", Color(red: 0.81, green: 0.52, blue: 0.35)),
        ("Comments", Color(red: 0.40, green: 0.62, blue: 0.40)),
        ("Functions", Color(red: 0.86, green: 0.86, blue: 0.56)),
    ]

    var body: some View {
        Form {
            Section {
                Toggle("Set as Active Theme", isOn: $isActive)
            } header: {
                Label("Dark Pro Theme", systemImage: "moon.stars.fill")
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
                Text("A professional dark theme inspired by VS Code Dark+. Optimized for long coding sessions with carefully tuned contrast ratios.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Dark Pro Theme")
    }
}
