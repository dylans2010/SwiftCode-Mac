import SwiftUI

/// Panel managing Design Tokens, Color Palettes, Typography managers, SF Symbols collections, and Gradients.
public struct VisualUIAssetsPanel: View {
    @Bindable var document: VisualUIDocument

    // Predefined color presets
    private let colorTokens = [
        ("Classic Blue", "#007AFF"),
        ("Apple Green", "#34C759"),
        ("Sunset Orange", "#FF9500"),
        ("Vibrant Pink", "#FF2D55"),
        ("Warm Purple", "#AF52DE"),
        ("Solid Black", "#000000"),
        ("Clean White", "#FFFFFF")
    ]

    // Predefined typography presets
    private let typographyTokens = [
        ("Large Title", "System Bold 34"),
        ("Title 1", "System Semibold 28"),
        ("Headline", "System Bold 17"),
        ("Body", "System Regular 17"),
        ("Subhead", "System Regular 15"),
        ("Footnote", "System Regular 13")
    ]

    public var body: some View {
        VStack(spacing: 0) {
            Text("DESIGN TOKENS & ASSETS")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Color Palettes section
                    GroupBox("Color Palette Manager") {
                        VStack(spacing: 8) {
                            ForEach(colorTokens, id: \.0) { token in
                                HStack {
                                    Circle()
                                        .fill(Color(hex: token.1))
                                        .frame(width: 20, height: 20)
                                        .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1))

                                    Text(token.0)
                                        .font(.subheadline)
                                    Spacer()
                                    Text(token.1)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    applyColorToSelection(token.1)
                                }
                            }
                        }
                    }

                    // Typography section
                    GroupBox("Typography Presets") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(typographyTokens, id: \.0) { token in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(token.0)
                                        .font(.subheadline.bold())
                                    Text(token.1)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    applyTypographyToSelection(token.0)
                                }
                                Divider()
                            }
                        }
                    }
                }
                .padding(8)
            }
        }
    }

    private func applyColorToSelection(_ hex: String) {
        guard let selectedID = document.scene.selectedNodeIDs.first,
              let node = document.scene.findNode(byID: selectedID) else { return }
        document.checkpoint()
        node.properties["foregroundColor"] = hex
        VisualUISettings.shared.addLog("Applied color token \(hex) to selection \(node.name)")
    }

    private func applyTypographyToSelection(_ name: String) {
        guard let selectedID = document.scene.selectedNodeIDs.first,
              let node = document.scene.findNode(byID: selectedID) else { return }
        document.checkpoint()
        node.properties["fontPreset"] = name
        VisualUISettings.shared.addLog("Applied typography token \(name) to selection \(node.name)")
    }
}
