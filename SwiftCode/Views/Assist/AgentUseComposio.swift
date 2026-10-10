import SwiftUI
import AppKit

@MainActor
public struct AgentUseComposio: View {
    public let metadata: ComposioExecutionMetadata
    @State private var isExpanded = false

    public init(metadata: ComposioExecutionMetadata) {
        self.metadata = metadata
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                // Status icon & SF Symbol
                statusIcon

                // Readable title & tool description
                Text("Composio · \(metadata.toolkit): \(metadata.toolSlug)")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(metadata.success ? Color.primary : (metadata.isExecuting ? Color.primary : Color.red))
                    .lineLimit(1)

                Spacer(minLength: 4)

                if let logId = metadata.logId, !logId.isEmpty {
                    Link(destination: URL(string: "https://dashboard.composio.dev/~/project/logs")!) {
                        HStack(spacing: 3) {
                            Text("Log: \(logId)")
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 7))
                        }
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(Color.accentColor)
                    }
                }

                if metadata.duration > 0 {
                    Text(String(format: "%.1fs", metadata.duration))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
            }

            // Output/result display cleanly as plain secondary monospaced text underneath
            let outputText = displayOutput
            if !outputText.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text(outputText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(isExpanded ? nil : 3)
                        .textSelection(.enabled)

                    if outputText.components(separatedBy: .newlines).count > 3 || outputText.count > 180 {
                        Button {
                            isExpanded.toggle()
                        } label: {
                            Text(isExpanded ? "Show less" : "Show output")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 18)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIcon: some View {
        let symbol = toolkitIcon(for: metadata.toolkit)
        if metadata.isExecuting {
            HStack(spacing: 3) {
                ProgressView()
                    .scaleEffect(0.4)
                    .frame(width: 12, height: 12)
                    .tint(.indigo)
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.indigo)
            }
        } else if metadata.success {
            HStack(spacing: 3) {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.green)
                Image(systemName: symbol)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 3) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.red)
                Image(systemName: symbol)
                    .font(.system(size: 10))
                    .foregroundStyle(Color.red)
            }
        }
    }

    private var displayOutput: String {
        let raw = !metadata.output.isEmpty ? metadata.output : metadata.arguments
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "{}" { return "" }
        return trimmed
    }

    private func toolkitIcon(for toolkit: String) -> String {
        switch toolkit.lowercased() {
        case "github": return "arrow.triangle.branch"
        case "slack": return "bubble.left.and.bubble.right.fill"
        case "googlecalendar", "calendar": return "calendar"
        case "gmail": return "envelope.fill"
        case "linear": return "checklist"
        case "jira": return "list.bullet.rectangle"
        case "notion": return "doc.text.fill"
        default: return "link.badge.plus"
        }
    }
}
