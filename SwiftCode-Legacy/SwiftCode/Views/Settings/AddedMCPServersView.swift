import SwiftUI

@MainActor
struct AddedMCPServersView: View {
    @Bindable var manager: MCPServerManager
    let onEdit: (MCPServer) -> Void
    let onViewTools: (MCPServer) -> Void

    var body: some View {
        VStack(spacing: 16) {
            ForEach(manager.servers) { server in
                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        // Server Header with Status Badge
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: server.transport == .stdio ? "terminal.fill" : "globe")
                                .font(.title2)
                                .foregroundColor(server.status == .connected ? .green : .secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 8) {
                                    Text(server.displayName)
                                        .font(.headline)
                                        .foregroundStyle(.primary)

                                    // Transport Badge
                                    Text(server.transport.rawValue.uppercased())
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.secondary.opacity(0.12), in: Capsule())
                                        .foregroundStyle(.secondary)
                                }

                                Text("Last Refresh: \(server.lastRefresh?.formatted(date: .omitted, time: .shortened) ?? "Never")")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            // Status Indicator Badge
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(statusColor(server.status))
                                    .frame(width: 8, height: 8)
                                Text(server.status.rawValue.uppercased())
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(statusColor(server.status))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(statusColor(server.status).opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                        }

                        Divider()

                        // Metadata Information Section
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: server.transport == .stdio ? "folder.fill" : "link")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                                    .frame(width: 14)

                                Text(server.transport == .stdio ? (server.executablePath ?? "No path configured") : server.urlString)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            HStack(spacing: 16) {
                                // Auth Badge
                                HStack(spacing: 4) {
                                    Image(systemName: "lock.shield.fill")
                                        .font(.caption2)
                                        .foregroundColor(.blue)
                                    Text("Auth: \(server.authType.rawValue)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                // Tool Count Badge
                                HStack(spacing: 4) {
                                    Image(systemName: "hammer.fill")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                    Text("\(server.toolCount) Tools Available")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        // Inline error banner if any
                        if let lastError = server.lastError {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                Text(lastError)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .lineLimit(2)
                                Spacer()
                            }
                            .padding(8)
                            .background(Color.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                        }

                        Divider()

                        // Actions controls panel
                        HStack(spacing: 10) {
                            if server.status == .connected {
                                Button(action: {
                                    manager.disconnect(server: server)
                                }) {
                                    Label("Disconnect", systemImage: "bolt.slash.fill")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)

                                Button(action: {
                                    onViewTools(server)
                                }) {
                                    Label("Browse Tools", systemImage: "hammer.fill")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)

                                Button {
                                    Task { try? await manager.refreshTools(server: server) }
                                } label: {
                                    Image(systemName: "arrow.clockwise")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.regular)
                                .help("Refresh server capabilities and tools")
                            } else {
                                Button(action: {
                                    Task { try? await manager.connect(server: server) }
                                }) {
                                    HStack {
                                        if server.status == .connecting {
                                            ProgressView().scaleEffect(0.5).padding(.trailing, 4)
                                        } else {
                                            Image(systemName: "bolt.fill")
                                        }
                                        Text(server.status == .connecting ? "Connecting..." : "Connect Server")
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.regular)
                                .disabled(server.status == .connecting)
                            }

                            Spacer()

                            Button(action: {
                                onEdit(server)
                            }) {
                                Label("Edit", systemImage: "pencil")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)

                            Button(role: .destructive) {
                                manager.deleteServer(server)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.regular)
                        }
                    }
                    .padding(4)
                }
                .groupBoxStyle(ModernGroupBoxStyle())
            }
        }
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
