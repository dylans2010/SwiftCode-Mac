import SwiftUI

struct DebugOverlaysView: View {
    @State private var showFrames = false
    @State private var showSafeAreas = false
    @State private var showTaps = false

    var body: some View {
        List {
            Section {
                Toggle("View Frames", isOn: $showFrames)
                Toggle("Show Safe Areas", isOn: $showSafeAreas)
                Toggle("Visualize Touch Targets", isOn: $showTaps)
            } header: {
                Text("UI Overlays")
            } footer: {
                Text("Enabling these will inject debugging layers into the root window.")
            }
        }
        .navigationTitle("Debug Overlays")
    }
}
