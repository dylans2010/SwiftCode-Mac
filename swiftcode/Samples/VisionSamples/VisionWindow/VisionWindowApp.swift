// SwiftCode's visionOS sample 1 (visionos.md §10.21): a SwiftUI window with a
// button, a counter and a toggle. Logs through os.Logger, subsystem
// org.swiftcode.samples, so a guest log stream shows what happened.
import os
import SwiftUI

let log = Logger(subsystem: "org.swiftcode.samples", category: "window")

@main
struct VisionWindowApp: App {
    var body: some Scene {
        WindowGroup {
            WindowView()
        }
    }
}

struct WindowView: View {
    @State private var taps = 0
    @State private var on = true

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "cube.transparent")
                .font(.system(size: 64))
            Text("SwiftCode sample: SwiftUI window")
                .font(.largeTitle)
            Text("Taps: \(taps)")
                .font(.title)
            Button("Tap me") {
                taps += 1
                log.notice("swiftcode-sample: window tap \(self.taps)")
            }
            Toggle("A toggle", isOn: $on)
                .frame(width: 320)
        }
        .padding(48)
        .onAppear { log.notice("swiftcode-sample: window appeared") }
    }
}
