import SwiftUI

struct SimulatorActionsView: View {
    let device: SimulatorDevice
    @State private var manager = SimulatorManager.shared
    @State private var showingConfirmErase = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Quick Actions", systemImage: "bolt.circle")
                        .font(.headline)
                        .foregroundColor(.yellow)
                    Spacer()
                }

                Divider()

                HStack(spacing: 12) {
                    if device.state == .booted {
                        Button {
                            Task {
                                await manager.shutdownSelectedDevice()
                            }
                        } label: {
                            Label("Shutdown", systemImage: "power")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    } else {
                        Button {
                            Task {
                                await manager.bootSelectedDevice()
                            }
                        } label: {
                            Label("Boot", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
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
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(!device.state.isRunning)

                    Button {
                        showingConfirmErase = true
                    } label: {
                        Label("Erase", systemImage: "eraser")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(device.state == .booted)
                }
                .controlSize(.large)
            }
            .padding()
            .confirmationDialog(
                "Are you sure you want to erase '\(device.name)'?",
                isPresented: $showingConfirmErase,
                titleVisibility: .visible
            ) {
                Button("Erase Contents and Settings", role: .destructive) {
                    Task {
                        await manager.eraseSelectedDevice()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("All installed applications and persistent user data will be permanently deleted.")
            }
        }
        .groupBoxStyle(ModernGroupBoxStyle())
    }
}
