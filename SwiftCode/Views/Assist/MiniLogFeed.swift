import SwiftUI

public struct MiniLogFeed: View {
    @ObservedObject public var logger: AssistLogger

    public init(logger: AssistLogger) {
        self.logger = logger
    }

    private var recentLogs: [AssistLogEntry] {
        Array(logger.logs.suffix(3))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(recentLogs) { entry in
                HStack(spacing: 4) {
                    Text("[\(entry.level.rawValue)]")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(color(for: entry.level))

                    Text(entry.message)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    private func color(for level: AssistLogLevel) -> Color {
        switch level {
        case .info: return .secondary
        case .warning: return .orange
        case .error: return .red
        case .debug: return .secondary
        }
    }
}
