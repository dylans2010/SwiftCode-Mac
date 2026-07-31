import SwiftUI

/// Panel configuring transitions, animation timelines, timing curves, spring values, and interactive states.
public struct VisualUIAnimationsPanel: View {
    @Bindable var document: VisualUIDocument

    // Custom animation presets
    private let curves = ["Spring", "EaseInOut", "EaseIn", "EaseOut", "Linear"]
    private let transitions = ["None", "Opacity", "Slide", "Scale", "Move"]

    public var body: some View {
        VStack(spacing: 0) {
            Text("ANIMATION TIMELINE & CURVES")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)

            Divider()

            if let selectedID = document.scene.selectedNodeIDs.first,
               let node = document.scene.findNode(byID: selectedID) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Configure Animation for '\(node.name)'")
                            .font(.subheadline.bold())

                        // Timing curve picker
                        GroupBox("Timing Curve") {
                            VStack(spacing: 10) {
                                Picker("Curve:", selection: Binding(
                                    get: { node.properties["animationCurve"] ?? "Spring" },
                                    set: { node.properties["animationCurve"] = $0 }
                                )) {
                                    ForEach(curves, id: \.self) { curve in
                                        Text(curve).tag(curve)
                                    }
                                }

                                HStack {
                                    Text("Duration:")
                                    Spacer()
                                    TextField("0.3", text: Binding(
                                        get: { node.properties["animationDuration"] ?? "0.3" },
                                        set: { node.properties["animationDuration"] = $0 }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 60)
                                }

                                HStack {
                                    Text("Delay:")
                                    Spacer()
                                    TextField("0.0", text: Binding(
                                        get: { node.properties["animationDelay"] ?? "0.0" },
                                        set: { node.properties["animationDelay"] = $0 }
                                    ))
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 60)
                                }
                            }
                        }

                        // Transitions preset
                        GroupBox("Transition Preset") {
                            VStack(spacing: 10) {
                                Picker("Transition:", selection: Binding(
                                    get: { node.properties["transitionPreset"] ?? "None" },
                                    set: { node.properties["transitionPreset"] = $0 }
                                )) {
                                    ForEach(transitions, id: \.self) { transition in
                                        Text(transition).tag(transition)
                                    }
                                }
                            }
                        }

                        // Playback Control Simulation
                        Button {
                            VisualUISettings.shared.addLog("Triggered simulated transition preview for \(node.name).")
                        } label: {
                            Label("Preview Transition", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }
                    .padding(8)
                }
            } else {
                ContentUnavailableView {
                    Label("No Element Selected", systemImage: "play.circle")
                } description: {
                    Text("Select a component to configure its entry transitions and animations.")
                }
            }
        }
    }
}
