import SwiftUI

@MainActor
struct AddedMCPServersView: View {
    @Bindable var manager: MCPServerManager
    let onEdit: (MCPServer) -> Void
    let onViewTools: (MCPServer) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Table Header Row
            HStack(spacing: 12) {
                Text("Server Name").font(.caption.bold()).frame(width: 150, alignment: .leading)
                Text("Transport").font(.caption.bold()).frame(width: 80, alignment: .leading)
                Text("Status").font(.caption.bold()).frame(width: 100, alignment: .leading)
                Text("Authentication").font(.caption.bold()).frame(width: 120, alignment: .leading)
                Text("Real Tools").font(.caption.bold()).frame(width: 80, alignment: .leading)
                Text("Last Synced").font(.caption.bold()).frame(width: 120, alignment: .leading)
                Spacer()
                Text("Actions").font(.caption.bold()).frame(width: 250, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.08))
            .foregroundStyle(.secondary)

            Divider()

            // Server Rows List
            ForEach(manager.servers) { server in
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        // Display Name
                        VStack(alignment: .leading, spacing: 2) {
                            Text(server.displayName)
                                .font(.body.bold())
                            if server.transport == .stdio {
                                Text(server.executablePath ?? "")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            } else {
                                Text(server.urlString)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: 150, alignment: .leading)

                        // Transport Type
                        Text(server.transport.rawValue.uppercased())
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .frame(width: 80, alignment: .leading)

                        // Connection Status Badge
                        HStack(spacing: 6) {
                            Circle()
                                .fill(statusColor(server.status))
                                .frame(width: 8, height: 8)
                            Text(server.status.rawValue)
                                .font(.caption.bold())
                                .foregroundColor(statusColor(server.status))
                        }
                        .frame(width: 100, alignment: .leading)

                        // Authentication Type
                        Text(server.authType.rawValue)
                            .font(.caption)
                            .frame(width: 120, alignment: .leading)

                        // Tool Count
                        HStack(spacing: 4) {
                            Image(systemName: "hammer.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text("\(server.toolCount)")
                                .font(.system(.caption, design: .monospaced).bold())
                        }
                        .frame(width: 80, alignment: .leading)

                        // Last Refresh
                        Text(server.lastRefresh?.formatted(date: .omitted, time: .shortened) ?? "Never")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(width: 120, alignment: .leading)

                        Spacer()

                        // Interactive Control Actions
                        HStack(spacing: 6) {
                            if server.status == .connected {
                                Button("Disconnect") {
                                    manager.disconnect(server: server)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button("List Tools") {
                                    onViewTools(server)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button {
                                    Task { try? await manager.refreshTools(server: server) }
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help("Refresh server capabilities and tools")
                            } else {
                                Button("Connect") {
                                    Task { try? await manager.connect(server: server) }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(server.status == .connecting)
                            }

                            Button("Edit") {
                                onEdit(server)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button(role: .destructive) {
                                manager.deleteServer(server)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .frame(width: 250, alignment: .trailing)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                    if let lastError = server.lastError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(lastError)
                                .font(.caption)
                                .foregroundColor(.red)
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.06))
                    }

                    Divider()
                }
            }
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    private func statusColor(_ status: MCPServerStatus) -> Color {
        switch status {
        case .disconnected: return .secondary
        case .connecting: return .orange
        case .connected: return .green
        case .failed: return .red
        }
    }
}
