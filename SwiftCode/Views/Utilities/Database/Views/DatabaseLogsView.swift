import SwiftUI

struct DatabaseLogsView: View {
    @State private var logs: [String] = [
        "2026-07-31 10:00:00 - Database connection established successfully.",
        "2026-07-31 10:01:15 - Schema synchronization initiated from Default Local SQLite.",
        "2026-07-31 10:01:17 - PRAGMA foreign_keys = ON; successfully executed.",
        "2026-07-31 10:02:40 - Table 'users' schema successfully loaded."
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Operational Logs Stream")
                    .font(.headline)
                Spacer()
                Button("Clear Logs") {
                    logs.removeAll()
                }
            }
            .padding()
            .background(Color.secondary.opacity(0.06))

            Divider()

            List(logs, id: \.self) { log in
                Text(log)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }
        }
    }
}
