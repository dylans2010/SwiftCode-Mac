import SwiftUI

struct BackgroundTaskMonitorView: View {
    let tasks = [
        BackgroundTaskInfo(name: "GitHub Sync", status: "Running", start: Date().addingTimeInterval(-300)),
        BackgroundTaskInfo(name: "Cache Cleanup", status: "Scheduled", start: nil),
        BackgroundTaskInfo(name: "Index Refresher", status: "Completed", start: Date().addingTimeInterval(-3600))
    ]

    var body: some View {
        List(tasks) { task in
            HStack {
                VStack(alignment: .leading) {
                    Text(task.name)
                        .font(.headline)
                    if let start = task.start {
                        Text("Started: \(start, style: .time)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Waiting...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(task.status)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor(task.status).opacity(0.2), in: Capsule())
                    .foregroundStyle(statusColor(task.status))
            }
            .listRowBackground(Color.white.opacity(0.05))
        }
        .navigationTitle("Background Tasks")
        .background(Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea())
    }

    private func statusColor(_ status: String) -> Color {
        switch status {
        case "Running": return .blue
        case "Scheduled": return .yellow
        case "Completed": return .green
        default: return .secondary
        }
    }
}

struct BackgroundTaskInfo: Identifiable {
    let id = UUID()
    let name: String
    let status: String
    let start: Date?
}
