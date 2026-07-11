import SwiftUI

/// Top-level control bar offering standard boot, shutdown, and simulator operations.
public struct SimulatorToolbar: View {
    @Environment(SimulatorManager.self) private var simulatorManager
    @State private var showingCreationSheet = false

    public var body: some View {
        HStack {
            if let device = simulatorManager.selectedDevice {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(device.name)
                            .font(.headline)

                        Text(device.state.rawValue)
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1.5)
                            .background(device.state == .booted ? Color.green.opacity(0.15) : Color.gray.opacity(0.15))
                            .foregroundStyle(device.state == .booted ? .green : .secondary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    Text(device.udid)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Actions Group
                HStack(spacing: 8) {
                    if device.state == .shutdown {
                        Button(action: {
                            Task {
                                await simulatorManager.bootDevice(udid: device.udid)
                            }
                        }) {
                            Label("Boot", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                    } else {
                        Button(action: {
                            Task {
                                await simulatorManager.shutdownDevice(udid: device.udid)
                            }
                        }) {
                            Label("Shut Down", systemImage: "square.fill")
                        }
                        .buttonStyle(.bordered)
                    }

                    Menu {
                        Button(role: .destructive) {
                            Task {
                                await simulatorManager.eraseDevice(udid: device.udid)
                            }
                        } label: {
                            Label("Erase All Data...", systemImage: "eraser.fill")
                        }

                        Button(role: .destructive) {
                            Task {
                                await simulatorManager.deleteDevice(udid: device.udid)
                            }
                        } label: {
                            Label("Delete Device Permanently...", systemImage: "trash.fill")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.pullDown)
                    .frame(width: 40)
                }
            } else {
                Text("Select a device in the sidebar to get started.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            Divider()
                .frame(height: 16)
                .padding(.horizontal, 4)

            Button(action: {
                showingCreationSheet = true
            }) {
                Label("New Device", systemImage: "plus")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showingCreationSheet) {
            SimulatorCreationView()
        }
    }
}
