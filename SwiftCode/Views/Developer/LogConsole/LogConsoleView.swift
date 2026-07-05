import SwiftUI

struct LogConsoleView: View {
    @StateObject private var logger = InternalLoggingManager.shared
    @State private var searchText = ""

    var filteredLogs: [LogEntry] {
        if searchText.isEmpty {
            return logger.logs
        }
        return logger.logs.filter { $0.message.localizedCaseInsensitiveContains(searchText) || $0.category.rawValue.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            List(filteredLogs.reversed()) { log in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(log.category.rawValue)
                            .font(.caption.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(categoryColor(log.category).opacity(0.2))
                            .foregroundStyle(categoryColor(log.category))
                            .clipShape(RoundedRectangle(cornerRadius: 4))

                        Spacer()

                        Text(log.timestamp, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text(log.message)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
                .padding(.vertical, 4)
            }
            .listStyle(.plain)
        }
        .navigationTitle("Log Console")
        .searchable(text: $searchText, prompt: "Filter logs")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    logger.clearLogs()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
            }
        }
    }

    private func categoryColor(_ category: LogCategory) -> Color {
        switch category {
        case .networking: return .blue
        case .githubAPI: return .purple
        case .deployments: return .green
        case .aiProcessing: return .orange
        case .storeKit: return .yellow
        case .extensions: return .cyan
        case .buildSystem: return .red
        }
    }
}
