// Ported from Legacy (Dylan's own SwiftCode code, MIT-authorised direct port):
//   SwiftCode/Views/Utilities/Database/Views/DatabaseLogsView.swift
//   (Legacy main ab03f681)
//
// Destination: SwiftCodeUI/Database/DatabaseLogsView.swift.
//
// Adaptations (behaviour preserved unless noted):
// * Legacy's `QueryHistoryItem` is the destination's
//   `DatabaseQueryHistoryItem` (SwiftCodeIDECore/Model/Database/
//   DatabaseHistory.swift — same fields, renamed with the Database
//   prefix). `DatabaseHistoryService.shared.fetchHistory()` /
//   `.clearHistory()` exist in the destination with the same signatures.
// * Legacy's `.liquidGlass(style: .subtle, cornerRadius: 0)` view
//   modifier has no destination equivalent — SwiftCode draws no glass
//   of its own making (see ModernGroupBoxStyle.swift in this target) —
//   so the header row keeps its `.padding()` and drops the modifier.
//   Nothing else about the layout changes.
// * `import SwiftCodeIDECore` added for the history types (SwiftCodeUI
//   already depends on SwiftCodeIDECore).

import SwiftUI
import SwiftCodeIDECore

struct DatabaseLogsView: View {
    @State private var historyItems: [DatabaseQueryHistoryItem] = []

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
