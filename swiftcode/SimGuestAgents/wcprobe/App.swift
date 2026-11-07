import SwiftUI

@main
struct WCProbeApp: App {
    init() { Probe.shared.start() }

    var body: some Scene {
        WindowGroup {
            #if os(watchOS)
            List {
                Button("Primary action") { Probe.shared.primaryAction() }
                    .handGestureShortcut(.primaryAction)
                ForEach(1...60, id: \.self) { n in
                    Text(n == 1 ? "WCProbe watch" : "Row \(n)")
                }
            }
            .onScrollGeometryChange(for: Double.self, of: { Double($0.contentOffset.y) }) { _, y in
                Probe.shared.scrolled(to: y)
            }
            #else
            Text("WCProbe " + Probe.shared.role)
            #endif
        }
    }
}
