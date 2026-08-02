import SwiftUI

public struct PreviewLogsView: View {
    @State private var diagnostics = PreviewDiagnostics.shared

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            // Header/Toolbar
            HStack {
                Label("Preview Engine Diagnostics Console", systemImage: "terminal")
                    .font(.headline)

                Spacer()

                Button(action: {
                    diagnostics.clearLogs()
                }) {
                    Label("Clear Logs", systemImage: "trash")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.secondary)
                .disabled(diagnostics.logs.isEmpty)
            }
            .padding()
            .background(Color(.windowBackground))

            Divider()

            if diagnostics.logs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "terminal")
                        .font(.system(size: 36))
                        .foregroundColor(.secondary)
                    Text("No Preview Diagnostics Recorded")
                        .font(.headline)
                        .foregroundColor(.secondary)
                    Text("The logs console captures real-time compilation, rendering, and loading events from the preview engine pipeline.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.windowBackground))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(diagnostics.logs) { log in
                            HStack(alignment: .top, spacing: 8) {
                                // Timestamp
                                Text(formattedTime(log.timestamp))
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundColor(.secondary)

                                // Category Tag
                                Text("[\(log.category.uppercased())]")
                                    .font(.system(.caption, design: .monospaced))
                                    .bold()
                                    .foregroundColor(categoryColor(log.category))
                                    .frame(width: 80, alignment: .leading)

                                // Message
                                Text(log.message)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(.vertical, 12)
                }
                .background(Color(.windowBackground))
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    private func formattedTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }

    private func categoryColor(_ category: String) -> Color {
        switch category.lowercased() {
        case "error":
            return .red
        case "compile":
            return .orange
        case "render":
            return .blue
        case "cache":
            return .green
        case "state":
            return .purple
        default:
            return .secondary
        }
    }
}
