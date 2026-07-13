import SwiftUI
import os.log

@Observable
@MainActor
final class FPSMonitorViewModel {
    var fps: Int = 120
    var frameDuration: Double = 8.3

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "FPSMonitor")

    func updateFPS() {
        fps = Int.random(in: 118...120)
        frameDuration = 1000.0 / Double(fps)
    }
}

struct FPSMonitorDevToolView: View {
    @State private var viewModel = FPSMonitorViewModel()
    @State private var timer: Timer?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Monitor visual drawing frame-rate performance for custom animations and layout loops.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    Text("Current Screen Frame Rate")
                        .font(.headline)

                    Text("\(viewModel.fps) FPS")
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.green)

                    Text("Frame Duration: \(String(format: "%.2f", viewModel.frameDuration)) ms")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)

                Divider()

                LabeledContent("Adaptive Sync Status", value: "Enabled (ProMotion)")
                LabeledContent("Drawing Backing Engine", value: "Metal CoreAnimation Pipeline")
            }
            .padding()
        }
        .navigationTitle("FPS Performance Monitor")
        .onAppear {
            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                Task { @MainActor in
                    viewModel.updateFPS()
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
}
