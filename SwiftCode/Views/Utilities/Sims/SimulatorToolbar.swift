import SwiftUI

struct SimulatorToolbar: View {
    @State private var manager = SimulatorManager.shared

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                Button {
                    Task {
                        await manager.refreshAll()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(manager.isRefreshing)

                if manager.isRefreshing {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                }
            }

            Divider()
                .frame(height: 20)

            if let selected = manager.selectedDevice {
                HStack(spacing: 12) {
                    Text(selected.name)
                        .font(.headline)

                    Text(selected.state.rawValue)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(statusColor(for: selected.state).opacity(0.15))
                        .foregroundColor(statusColor(for: selected.state))
                        .cornerRadius(6)
                }

                Spacer()

                HStack(spacing: 8) {
                    if selected.state == .booted {
                        Button {
                            Task {
                                await manager.shutdownSelectedDevice()
                            }
                        } label: {
                            Label("Shutdown", systemImage: "power")
                        }
                    } else {
                        Button {
                            Task {
                                await manager.bootSelectedDevice()
                            }
                        } label: {
                            Label("Boot", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    }

                    Button {
                        Task {
                            await manager.restartSelectedDevice()
                        }
                    } label: {
                        Label("Restart", systemImage: "arrow.clockwise")
                    }
                    .disabled(!selected.state.isRunning)

                    Button {
                        Task {
                            await manager.eraseSelectedDevice()
                        }
                    } label: {
                        Label("Erase", systemImage: "eraser")
                    }
                    .disabled(selected.state == .booted)
                }
            } else {
                Text("Select a simulator in the sidebar to begin")
                    .foregroundColor(.secondary)
                Spacer()
            }
        }
        .padding()
        .background(Color.secondary.opacity(0.05))
    }

    private func statusColor(for state: SimulatorState) -> Color {
        switch state {
        case .booted: return .green
        case .booting: return .orange
        case .shuttingDown: return .blue
        case .shutdown: return .secondary
        case .erasing: return .red
        default: return .secondary
        }
    }
}
