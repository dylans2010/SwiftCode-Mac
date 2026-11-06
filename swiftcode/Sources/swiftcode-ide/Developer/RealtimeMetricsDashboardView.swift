// Ported from SwiftCode-Legacy `SwiftCode/Views/Developer/RealtimeMetricsDashboardView.swift` (Dylan's own code; direct port authorised under MIT).
// Audit A: MISSING at bc28f653. Static port only — no Swift toolchain here; build verification pending on Dylan's Mac.
//
// CLEANUP (2026-11-06, C23): Legacy's six tiles were hardcoded —
// "Active Users 1,240", "Request Rate 45/s", "Error Rate 0.2%",
// "Avg Latency 142ms", "Storage Used 1.4 GB", "Memory Peak 512 MB".
// There is no backend behind this IDE for active users, request rate,
// error rate or latency, so those server metrics are deleted, not
// re-seeded. What remains is local-only and live, refreshed every 2 s:
// host CPU load and this process's resident memory and thread count
// (DevToolsSystemMetrics, real Mach readings) and disk used on the home
// volume (real FileManager filesystem attributes). A reading that is
// unavailable shows "—" instead of an invented number.
import SwiftUI
import SwiftCodeUI

struct RealtimeMetricsDashboardView: View {
    @State private var cpuLoad: Double?
    @State private var residentMemoryMB: Double?
    @State private var threadCount: Int?
    @State private var diskUsedBytes: Int64?

    @State private var timer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Live local metrics for this machine and process. This IDE has no backend, so there are no server metrics here — no active users, request rate, error rate or latency.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 16) {
                    MetricTile(title: "Host CPU Load", value: cpuLoad.map { String(format: "%.1f%%", $0) } ?? "—", icon: "cpu", color: .blue)
                    MetricTile(title: "App Memory (Resident)", value: residentMemoryMB.map { String(format: "%.1f MB", $0) } ?? "—", icon: "memorychip", color: .pink)
                    MetricTile(title: "Active Threads", value: threadCount.map(String.init) ?? "—", icon: "arrow.up.right.circle.fill", color: .green)
                    MetricTile(title: "Disk Used (Home Volume)", value: diskUsedBytes.map { DevToolsDiskUsage.formatted($0) } ?? "—", icon: "hdd.fill", color: .teal)
                }
            }
            .padding()
        }
        .liquidGlass(style: .subtle, cornerRadius: 12)
        .navigationTitle("Metrics Dashboard")
        .background(Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea())
        .onReceive(timer) { _ in
            refresh()
        }
        .onAppear {
            refresh()
        }
    }

    private func refresh() {
        cpuLoad = DevToolsSystemMetrics.hostCPULoadPercent()
        residentMemoryMB = DevToolsSystemMetrics.taskResidentMemoryMB()
        threadCount = DevToolsSystemMetrics.taskThreadCount()
        diskUsedBytes = Self.volumeUsedBytes()
    }

    /// Used bytes on the volume containing the user's home directory,
    /// from live filesystem attributes. Nil when unreadable.
    private static func volumeUsedBytes() -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let size = (attributes[.systemSize] as? NSNumber)?.int64Value,
              let free = (attributes[.systemFreeSize] as? NSNumber)?.int64Value else { return nil }
        return size - free
    }
}

struct MetricTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 4) {
                Text(value)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 16))
    }
}
