import SwiftUI

struct NetworkInspectorView: View {
    @StateObject private var logger = InternalLoggingManager.shared

    var body: some View {
        List(logger.networkLogs) { log in
            VStack(alignment: .leading) {
                HStack {
                    Text(log.method)
                        .font(.caption.bold())
                    Text(log.url)
                        .font(.caption)
                        .lineLimit(1)
                }
                HStack {
                    if let code = log.statusCode {
                        Text("\(code)")
                            .foregroundColor(code < 400 ? .green : .red)
                    }
                    if let duration = log.duration {
                        Text(String(format: "%.2fms", duration * 1000))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text(log.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Network Inspector")
        .toolbar {
            Button("Clear") {
                logger.clearLogs()
            }
        }
    }
}
