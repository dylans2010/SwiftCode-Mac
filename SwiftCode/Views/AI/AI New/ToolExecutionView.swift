import SwiftUI

struct ToolExecutionView: View {
    @ObservedObject private var logger = AgentLogger.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Tools Executed")
                    .font(.headline)
                Spacer()
                Text("\(logger.toolLogs.count) Calls")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if logger.toolLogs.isEmpty {
                Text("No Tools Executed Yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(logger.toolLogs.suffix(5).reversed()) { entry in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: "wrench.and.screwdriver.fill")
                                        .font(.caption2)
                                    Text(entry.toolName)
                                        .font(.caption.bold())
                                }

                                Text(sourceName(entry.source))
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(sourceColor(entry.source).opacity(0.2))
                                    .foregroundColor(sourceColor(entry.source))
                                    .cornerRadius(4)

                                Text(formatArgs(entry.arguments))
                                    .font(.system(size: 9, design: .monospaced))
                                    .lineLimit(1)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                            .frame(width: 150)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    private func sourceName(_ source: ToolSource) -> String {
        source.rawValue.uppercased()
    }

    private func sourceColor(_ source: ToolSource) -> Color {
        switch source {
        case .core: return .blue
        case .skill: return .purple
        case .connection: return .orange
        case .plugin: return .green
        }
    }

    private func formatArgs(_ args: [String: Any]) -> String {
        return args.map { "\($0.key): \($0.value)" }.joined(separator: ", ")
    }
}
