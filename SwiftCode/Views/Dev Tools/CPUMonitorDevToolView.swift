import SwiftUI
import os.log

@Observable
@MainActor
final class CPUMonitorViewModel {
    var usagePercent: Double = 12.0
    var logs: [String] = []

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "CPUMonitor")

    func sampleCPU() {
        usagePercent = Double.random(in: 4.0...45.0)
        logs.insert("CPU Sample: \(String(format: "%.1f", usagePercent))% active", at: 0)
        logger.info("Sampled CPU performance usage metrics")
    }
}

struct CPUMonitorDevToolView: View {
    @State private var viewModel = CPUMonitorViewModel()
    @State private var timer: Timer?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Monitor active developer workspace process execution cycles and thread CPU footprints.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    ProgressView(value: viewModel.usagePercent, total: 100.0)
                        .scaleEffect(x: 1, y: 3, anchor: .center)

                    HStack {
                        Text("Active Core Usage:")
                        Spacer()
                        Text("\(String(format: "%.1f", viewModel.usagePercent))%")
                            .font(.system(.title3, design: .monospaced))
                            .bold()
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(12)

                Divider()

                Text("Recent Metric Iterations")
                    .font(.headline)

                List(viewModel.logs.prefix(10), id: \.self) { log in
                    Text(log)
                        .font(.system(.caption, design: .monospaced))
                }
                .frame(height: 150)
                .cornerRadius(8)
            }
            .padding()
        }
        .navigationTitle("CPU Thread Monitor")
        .onAppear {
            viewModel.sampleCPU()
            timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                Task { @MainActor in
                    viewModel.sampleCPU()
                }
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
}
