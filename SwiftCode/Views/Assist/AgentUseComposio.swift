import SwiftUI

@MainActor
public struct AgentUseComposio: View {
    public let metadata: ComposioExecutionMetadata
    @State private var isExpanded = false

    public init(metadata: ComposioExecutionMetadata) {
        self.metadata = metadata
    }

    public var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                // Header row
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: toolkitIcon(for: metadata.toolkit))
                        .font(.headline)
                        .foregroundColor(metadata.success ? .green : (metadata.isExecuting ? .indigo : .red))

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Composio Tool")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)

                            Text(metadata.toolkit.uppercased())
                                .font(.caption.bold())
                                .foregroundColor(.indigo)
                        }

                        HStack(spacing: 4) {
                            Text(metadata.toolSlug)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.primary)

                            Text("api")
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 3))
                        }
                    }

                    Spacer()

                    // Pulse/Execution Status
                    if metadata.isExecuting {
                        HStack(spacing: 5) {
                            ProgressView()
                                .scaleEffect(0.4)
                            Text("RUNNING")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.indigo)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.indigo.opacity(0.12), in: Capsule())
                    } else if metadata.success {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                            Text("SUCCESS")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.12), in: Capsule())
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                            Text("FAILED")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundColor(.red)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(0.12), in: Capsule())
                    }
                }

                // Log ID and Latency Bar
                HStack(spacing: 12) {
                    if let logId = metadata.logId, !logId.isEmpty {
                        Link(destination: URL(string: "https://dashboard.composio.dev/~/project/logs")!) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.text.magnifyingglass")
                                Text("Log: \(logId)")
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 8))
                            }
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.accentColor)
                        }
                    }

                    if metadata.duration > 0 {
                        Text(String(format: "%.2fs", metadata.duration))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Expand / Collapse Details Button
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(isExpanded ? "Hide Details" : "Show Details")
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        }
                        .font(.caption2.bold())
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                // Output / Arguments View
                if isExpanded {
                    Divider()

                    if metadata.arguments != "{}" && !metadata.arguments.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Arguments:")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)

                            Text(metadata.arguments)
                                .font(.system(size: 11, design: .monospaced))
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Response:")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)

                            Spacer()

                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(metadata.output, forType: .string)
                            } label: {
                                Label("Copy", systemImage: "doc.on.doc")
                                    .font(.caption2)
                            }
                            .buttonStyle(.plain)
                        }

                        ScrollView {
                            Text(metadata.output)
                                .font(.system(size: 11, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .frame(maxHeight: 180)
                        .padding(8)
                        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            .padding(10)
        }
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
