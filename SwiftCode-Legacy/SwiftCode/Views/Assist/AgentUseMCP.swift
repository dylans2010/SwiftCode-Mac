import SwiftUI

@MainActor
public struct AgentUseMCP: View {
    public let metadata: MCPExecutionMetadata
    @State private var isExpanded = false

    public init(metadata: MCPExecutionMetadata) {
        self.metadata = metadata
    }

    public var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                // Header row
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "network.badge.shield.half.filled")
                        .font(.headline)
                        .foregroundColor(metadata.success ? .green : (metadata.isExecuting ? .orange : .red))

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("MCP Execution")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)

                            Text(metadata.serverName)
                                .font(.caption.bold())
                                .foregroundColor(.accentColor)
                        }

                        HStack(spacing: 4) {
                            Text(metadata.toolName)
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(.primary)

                            Text("tool")
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
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.orange.opacity(0.12), in: Capsule())
                    } else if metadata.success {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text("COMPLETED")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.green)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.green.opacity(0.12), in: Capsule())
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                                .font(.caption)
                            Text("FAILED")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.red)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.red.opacity(0.12), in: Capsule())
                    }
                }

                Divider()

                // Info Grid: Duration, Timestamp
                HStack(spacing: 20) {
                    Label {
                        Text(metadata.timestamp.formatted(date: .omitted, time: .shortened))
                            .font(.caption)
                    } icon: {
                        Image(systemName: "clock")
                            .foregroundColor(.secondary)
                    }

                    Label {
                        Text(String(format: "%.2f s", metadata.duration))
                            .font(.caption)
                    } icon: {
                        Image(systemName: "hourglass")
                            .foregroundColor(.secondary)
                    }
                }
                .foregroundColor(.secondary)

                // Arguments / Request Summary
                VStack(alignment: .leading, spacing: 4) {
                    Text("ARGUMENTS PAYLOAD")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)

                    Text(metadata.arguments)
                        .font(.system(size: 10, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.12))
                        .cornerRadius(6)
                        .textSelection(.enabled)
                }

                // Output / Response Summary
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(metadata.success ? "MCP EXECUTION RESULT" : "EXECUTION OUTPUT / ERRORS")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)

                        Spacer()

                        Button(action: { isExpanded.toggle() }) {
                            Text(isExpanded ? "Collapse" : "Expand Full Output")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(.accentColor)
                    }

                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(metadata.output)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(isExpanded ? nil : 5)
                            .padding(10)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.15))
                    .cornerRadius(6)
                    .textSelection(.enabled)
                }
            }
            .padding(8)
        }
        .groupBoxStyle(ModernGroupBoxStyle())
        .padding(.horizontal, 12)
        .transition(.asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity),
            removal: .opacity
        ))
    }
}
