import SwiftUI

struct APIInspectorView: View {
    @StateObject private var logger = InternalLoggingManager.shared

    var body: some View {
        List(logger.networkLogs.reversed()) { log in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(log.method)
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.2))
                        .foregroundStyle(.blue)
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    Text(log.url)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer()

                    if let code = log.statusCode {
                        Text("\(code)")
                            .font(.caption.bold())
                            .foregroundStyle(code < 400 ? .green : .red)
                    }
                }

                HStack {
                    if let duration = log.duration {
                        Label(String(format: "%.2fms", duration * 1000), systemImage: "timer")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(log.timestamp, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("API Inspector")
        .toolbar {
            Button("Clear") {
                logger.clearLogs()
            }
        }
        .overlay {
            if logger.networkLogs.isEmpty {
                ContentUnavailableView("No Network Traffic", systemImage: "network", description: Text("Network requests will appear here in real-time."))
            }
        }
    }
}
