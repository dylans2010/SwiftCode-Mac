import SwiftUI
import os.log

@Observable
@MainActor
final class BatteryStatusViewModel {
    var level: Double = 100.0
    var isCharging: Bool = true
    var timeRemaining: String = "Calculating..."

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "BatteryStatus")

    func refreshStatus() {
        // macOS Battery Status retrieval simulation
        level = 85.0
        isCharging = false
        timeRemaining = "4 hours, 20 minutes"
        logger.info("Refreshed system battery status values")
    }
}

struct BatteryStatusDevToolView: View {
    @State private var viewModel = BatteryStatusViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Inspect macOS battery power sources, current charge level, and charging rates.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .center, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.primary, lineWidth: 3)
                            .frame(width: 140, height: 70)

                        HStack(spacing: 0) {
                            Rectangle()
                                .fill(viewModel.level > 20 ? Color.green : Color.red)
                                .frame(width: CGFloat(viewModel.level) * 1.2, height: 56)
                            Spacer(minLength: 0)
                        }
                        .frame(width: 120, height: 56)
                        .clipped()

                        Text("\(Int(viewModel.level))%")
                            .font(.system(.title3, design: .monospaced))
                            .bold()
                            .foregroundColor(.primary)
                    }

                    HStack {
                        Image(systemName: viewModel.isCharging ? "bolt.fill" : "bolt.slash.fill")
                        Text(viewModel.isCharging ? "Charging Mode Enabled" : "Discharging on Battery Power")
                            .font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)

                Divider()

                LabeledContent("Time Remaining", value: viewModel.timeRemaining)
                LabeledContent("Source Type", value: "Internal Mac Battery")
                LabeledContent("Condition", value: "Normal / Healthy")

                Button("Refresh Status") {
                    viewModel.refreshStatus()
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .navigationTitle("Battery Status Monitor")
        .onAppear {
            viewModel.refreshStatus()
        }
    }
}
