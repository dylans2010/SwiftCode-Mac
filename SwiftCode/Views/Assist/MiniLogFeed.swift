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
        VStack(alignment: .leading, spacing: 4) {
            ForEach(recentLogs) { entry in
                HStack(spacing: 6) {
                    Text("[\(entry.level.rawValue)]")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(color(for: entry.level))

                    Text(entry.message)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.primary.opacity(0.05), lineWidth: 1)
        )
    }

    private func color(for level: AssistLogLevel) -> Color {
        switch level {
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .debug: return .purple
        }
    }
}
