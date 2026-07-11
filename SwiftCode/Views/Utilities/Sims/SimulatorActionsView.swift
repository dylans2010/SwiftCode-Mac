import SwiftUI

/// Grid container displaying available quick physical controls (Boot, Shut Down, Restart, Erase, Delete) for the current Simulator.
public struct SimulatorActionsView: View {
    @Environment(SimulatorManager.self) private var simulatorManager
    public let device: SimulatorDevice

    public var body: some View {
        AdaptiveGrid(horizontalSpacing: 12, verticalSpacing: 12) {
            // Boot / Shut Down Button
            if device.state == .shutdown {
                Button(action: {
                    Task {
                        await simulatorManager.bootDevice(udid: device.udid)
                    }
                }) {
                    VStack(spacing: 8) {
                        Image(systemName: "play.fill")
                            .font(.title2)
                        Text("Boot Simulator")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity, minHeight: 65)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            } else {
                Button(action: {
                    Task {
                        await simulatorManager.shutdownDevice(udid: device.udid)
                    }
                }) {
                    VStack(spacing: 8) {
                        Image(systemName: "square.fill")
                            .font(.title2)
                        Text("Shut Down")
                            .fontWeight(.medium)
                    }
                    .frame(maxWidth: .infinity, minHeight: 65)
                }
                .buttonStyle(.bordered)
            }

            // Restart Button
            Button(action: {
                Task {
                    await simulatorManager.shutdownDevice(udid: device.udid)
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    await simulatorManager.bootDevice(udid: device.udid)
                }
            }) {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise.circle")
                        .font(.title2)
                    Text("Restart")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity, minHeight: 65)
            }
            .buttonStyle(.bordered)

            // Erase Button
            Button(action: {
                Task {
                    await simulatorManager.eraseDevice(udid: device.udid)
                }
            }) {
                VStack(spacing: 8) {
                    Image(systemName: "eraser.fill")
                        .font(.title2)
                    Text("Erase Data")
                        .fontWeight(.medium)
                }
                .frame(maxWidth: .infinity, minHeight: 65)
            }
            .buttonStyle(.bordered)
        }
    }
}
