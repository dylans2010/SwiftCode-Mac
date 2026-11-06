// Ported from SwiftCode-Legacy `SwiftCode/Views/Developer/DebugOverlaysView.swift` (Dylan's own code; direct port authorised under MIT).
// Audit A: MISSING at bc28f653. Static port only — no Swift toolchain here; build verification pending on Dylan's Mac.
import SwiftUI
import SwiftCodeUI

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
        .liquidGlass(style: .subtle, cornerRadius: 12)
        .navigationTitle("Debug Overlays")
    }
}
