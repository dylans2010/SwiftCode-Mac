import SwiftUI

struct AIModelDebuggerView: View {
    @StateObject private var logger = InternalLoggingManager.shared

    var aiLogs: [LogEntry] {
        logger.logs.filter { $0.category == .aiProcessing }
    }

    var body: some View {
        List {
            if aiLogs.isEmpty {
                ContentUnavailableView("No AI Activity", systemImage: "brain", description: Text("AI processing logs will appear here."))
            } else {
                ForEach(aiLogs.reversed()) { log in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(log.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Text(log.message)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("AI Model Debugger")
        .toolbar {
            Button("Clear") {
                logger.clearLogs()
            }
        }
    }
}
