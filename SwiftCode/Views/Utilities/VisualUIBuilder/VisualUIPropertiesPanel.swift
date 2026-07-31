import SwiftUI

/// Advanced visual properties sub-panel displaying gradient editors, material managers, shadow presets, and borders.
public struct VisualUIPropertiesPanel: View {
    @Bindable var document: VisualUIDocument

    @State private var borderStroke = 1.0
    @State private var shadowRadius = 4.0
    @State private var selectedMaterial = "Thin"
    @State private var selectedGradient = "Linear"

    public var body: some View {
        VStack(spacing: 0) {
            Text("ADVANCED MODIFIERS")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)

            Divider()

            if let selectedID = document.scene.selectedNodeIDs.first,
               let node = document.scene.findNode(byID: selectedID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Border Editor
                        GroupBox("Border Editor") {
                            VStack {
                                Slider(value: $borderStroke, in: 0...10, step: 1) {
                                    Text("Border Stroke: \(Int(borderStroke))px")
                                }
                                .onChange(of: borderStroke) { _, newValue in
                                    document.checkpoint()
                                    node.properties["borderWidth"] = "\(Int(newValue))"
                                }
                            }
                        }

                        // Shadow Editor
                        GroupBox("Shadow & Elevation") {
                            VStack {
                                Slider(value: $shadowRadius, in: 0...20) {
                                    Text("Shadow Radius: \(Int(shadowRadius))")
                                }
                                .onChange(of: shadowRadius) { _, newValue in
                                    document.checkpoint()
                                    node.properties["shadowRadius"] = "\(Int(newValue))"
                                }
                            }
                        }

                        // Gradient Editor
                        GroupBox("Gradient Designer") {
                            Picker("Gradient Style", selection: $selectedGradient) {
                                Text("None").tag("None")
                                Text("Linear").tag("Linear")
                                Text("Radial").tag("Radial")
                                Text("Angular").tag("Angular")
                            }
                            .onChange(of: selectedGradient) { _, newValue in
                                document.checkpoint()
                                node.properties["gradientStyle"] = newValue
                            }
                        }

                        // Material presets
                        GroupBox("Material & Blur Overrides") {
                            Picker("Material Theme", selection: $selectedMaterial) {
                                Text("None").tag("None")
                                Text("UltraThin").tag("UltraThin")
                                Text("Thin").tag("Thin")
                                Text("Regular").tag("Regular")
                                Text("Thick").tag("Thick")
                            }
                            .onChange(of: selectedMaterial) { _, newValue in
                                document.checkpoint()
                                node.properties["materialTheme"] = newValue
                            }
                        }
                    }
                    .padding(8)
                }
            } else {
                ContentUnavailableView {
                    Label("No Component Selected", systemImage: "slider.horizontal.3")
                }
            }
        }
    }
}
