import SwiftUI

struct APILatencyTrackerView: View {
    @StateObject private var loggingManager = InternalLoggingManager.shared

    var body: some View {
        List {
            if loggingManager.networkLogs.isEmpty {
                Text("No network activity recorded.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(uniqueEndpoints, id: \.path) { metric in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(metric.path)
                                .font(.headline)
                            Text("Average Latency (\(metric.count) calls)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(metric.avgLatency * 1000))ms")
                            .font(.body.monospaced())
                            .foregroundStyle(latencyColor(Int(metric.avgLatency * 1000)))
                    }
                    .listRowBackground(Color.white.opacity(0.05))
                }
            }
        }
        .navigationTitle("API Latency")
        .background(Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea())
    }

    private var uniqueEndpoints: [EndpointMetric] {
        let logs = loggingManager.networkLogs
        let grouped = Dictionary(grouping: logs) { log -> String in
            let url = URL(string: log.url)
            return url?.path ?? log.url
        }

        return grouped.map { (path, logs) in
            let durations = logs.compactMap { $0.duration }
            let avg = durations.isEmpty ? 0 : durations.reduce(0, +) / Double(durations.count)
            return EndpointMetric(path: path, avgLatency: avg, count: logs.count)
        }.sorted { $0.avgLatency > $1.avgLatency }
    }

    private func latencyColor(_ ms: Int) -> Color {
        if ms < 200 { return .green }
        if ms < 1000 { return .yellow }
        return .red
    }
}

struct EndpointMetric {
    let path: String
    let avgLatency: Double
    let count: Int
}
