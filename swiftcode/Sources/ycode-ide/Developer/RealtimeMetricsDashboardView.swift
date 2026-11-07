import SwiftUI
import YcodeUI

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
