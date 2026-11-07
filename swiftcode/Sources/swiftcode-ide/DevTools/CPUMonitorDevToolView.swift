import SwiftUI
import SwiftCodeUI
import os.log

@Observable
@MainActor
final class CPUMonitorViewModel {
    var usagePercent: Double?
    var hostLoadPercent: Double?
    var threadCount: Int?
    var residentMemoryMB: Double?
    var logs: [String] = []
    var unavailableReason: String?

    private var previousSample: (cpuSeconds: Double, date: Date)?
    private var didLogUnavailable = false

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "CPUMonitor")

    func sampleCPU() {
        let now = Date()
        hostLoadPercent = DevToolsSystemMetrics.hostCPULoadPercent()
        threadCount = DevToolsSystemMetrics.taskThreadCount()
        residentMemoryMB = DevToolsSystemMetrics.taskResidentMemoryMB()

        guard let totalCPUSeconds = Self.processCPUTotalSeconds() else {
            unavailableReason = "CPU sampling needs Mach task_info, which is macOS-only."
            if !didLogUnavailable {
                didLogUnavailable = true
                logs.insert("CPU sampling unavailable on this platform.", at: 0)
                logger.info("CPU sampling unavailable: task_info returned no reading")
            }
            return
        }
        unavailableReason = nil

        if let previous = previousSample {
            let cpuDelta = totalCPUSeconds - previous.cpuSeconds
            let wallDelta = now.timeIntervalSince(previous.date)
            let cores = Double(ProcessInfo.processInfo.processorCount)
            if wallDelta > 0, cores > 0, cpuDelta >= 0 {
                let percent = cpuDelta / wallDelta / cores * 100
                usagePercent = min(100, max(0, percent))
                let stamp = DateFormatter.localizedString(from: now, dateStyle: .none, timeStyle: .medium)
                logs.insert("CPU Sample: \(String(format: "%.1f", usagePercent ?? 0))% process · \(hostLoadPercent.map { String(format: "%.1f", $0) } ?? "—")% host — \(stamp)", at: 0)
                logger.info("Sampled CPU performance usage metrics")
            }
        }
        previousSample = (cpuSeconds: totalCPUSeconds, date: now)
    }

    private static func processCPUTotalSeconds() -> Double? {
        #if os(macOS)
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard kerr == KERN_SUCCESS else { return nil }
        let user = Double(info.user_time.seconds) + Double(info.user_time.microseconds) / 1_000_000
        let system = Double(info.system_time.seconds) + Double(info.system_time.microseconds) / 1_000_000
        return user + system
        #else
        return nil
        #endif
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
                    ProgressView(value: viewModel.usagePercent ?? 0, total: 100.0)
                        .scaleEffect(x: 1, y: 3, anchor: .center)

                    HStack {
                        Text("Process CPU (share of all cores):")
                        Spacer()
                        Text(viewModel.usagePercent.map { "\(String(format: "%.1f", $0))%" } ?? "—")
                            .font(.system(.title3, design: .monospaced))
                            .bold()
                    }

                    if let reason = viewModel.unavailableReason {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .liquidGlass(style: .standard, cornerRadius: 12)

                Divider()

                LabeledContent("Host CPU Load", value: viewModel.hostLoadPercent.map { String(format: "%.1f%%", $0) } ?? "Unavailable")
                LabeledContent("Live Threads", value: viewModel.threadCount.map(String.init) ?? "Unavailable")
                LabeledContent("Resident Memory", value: viewModel.residentMemoryMB.map { String(format: "%.1f MB", $0) } ?? "Unavailable")

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
