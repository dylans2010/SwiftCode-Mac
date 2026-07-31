import SwiftUI

struct DatabaseLogsView: View {
    @State private var historyItems: [QueryHistoryItem] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Operational Logs Stream")
                    .font(.headline)
                Spacer()
                Button("Clear Logs") {
                    DatabaseHistoryService.shared.clearHistory()
                    loadLogs()
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.06))

            Divider()

            if historyItems.isEmpty {
                ContentUnavailableView("No logs recorded", systemImage: "doc.text", description: Text("Execute SQL statements or apply templates to generate logs."))
            } else {
                List(historyItems) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(item.timestamp, style: .date)
                            Text(item.timestamp, style: .time)
                            Spacer()
                            Text(item.status)
                                .font(.caption.bold())
                                .foregroundColor(item.status == "SUCCESS" ? .green : .red)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)

                        Text(item.sql)
                            .font(.system(.body, design: .monospaced))
                            .padding(4)
                            .background(Color.secondary.opacity(0.05))

                        if let errMsg = item.errorMessage {
                            Text("Error: \(errMsg)")
                                .font(.caption)
                                .foregroundColor(.red)
                        } else {
                            Text("Execution Time: \(String(format: "%.1f", item.executionTimeMs)) ms | Rows Affected: \(item.rowsAffected)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .onAppear {
            loadLogs()
        }
    }

    private func loadLogs() {
        historyItems = DatabaseHistoryService.shared.fetchHistory()
    }
}
