import SwiftUI
import os.log
import YcodeUI

@Observable
@MainActor
final class EnergyImpactMonitorViewModel {
    var thermalStateDescription: String = "Reading…"
    var cpuTimeSeconds: Double?
    var residentMemoryMB: Double?
    var threadCount: Int?
    var unavailableReason: String?

    private let logger = Logger(subsystem: "com.swiftcode.devtools", category: "EnergyImpactMonitor")

    func refresh() {
        #if os(macOS)
        unavailableReason = nil
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermalStateDescription = "Nominal"
        case .fair: thermalStateDescription = "Fair"
        case .serious: thermalStateDescription = "Serious"
        case .critical: thermalStateDescription = "Critical"
        @unknown default: thermalStateDescription = "Unknown"
        }
        cpuTimeSeconds = Self.processCPUTotalSeconds()
        residentMemoryMB = DevToolsSystemMetrics.taskResidentMemoryMB()
        threadCount = DevToolsSystemMetrics.taskThreadCount()
        logger.info("Refreshed energy signals: thermal state \(self.thermalStateDescription), CPU time \(self.cpuTimeSeconds ?? -1) s")
        #else
        thermalStateDescription = "Unavailable on this platform"
        cpuTimeSeconds = nil
        residentMemoryMB = nil
        threadCount = nil
        unavailableReason = "Live energy signals need Mach task_info and ProcessInfo thermal state, which are macOS-only."
        #endif
    }

    #if os(macOS)
    private static func processCPUTotalSeconds() -> Double? {
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
    }
    #endif
}

struct EnergyImpactMonitorDevToolView: View {
    @State private var viewModel = EnergyImpactMonitorViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Real energy signals for this process. macOS exposes no public per-app energy-impact score, so none is shown — only readings the system actually provides.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    Text("Thermal State")
                        .font(.headline)

                    Text(viewModel.thermalStateDescription)
                        .font(.system(.title, design: .rounded))
                        .bold()
                        .foregroundColor(thermalStateColor)

                    if let reason = viewModel.unavailableReason {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .liquidGlass(style: .standard, cornerRadius: 12)

                Divider()

                LabeledContent("Process CPU Time", value: viewModel.cpuTimeSeconds.map { String(format: "%.1f s", $0) } ?? "Unavailable")
                LabeledContent("Resident Memory", value: viewModel.residentMemoryMB.map { String(format: "%.1f MB", $0) } ?? "Unavailable")
                LabeledContent("Live Threads", value: viewModel.threadCount.map(String.init) ?? "Unavailable")

                Button("Recalculate Energy Impact") {
                    viewModel.refresh()
                }
                .buttonStyle(.bordered)
            }
            .padding()
        }
        .navigationTitle("Energy Impact Monitor")
        .onAppear {
            viewModel.refresh()
        }
    }

    private var thermalStateColor: Color {
        switch viewModel.thermalStateDescription {
        case "Nominal": .green
        case "Fair": .orange
        case "Serious", "Critical": .red
        default: .secondary
        }
    }
}
