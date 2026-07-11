import SwiftUI

/// Grid container displaying available quick physical controls (Boot, Shut Down, Restart, Erase, Delete) for the current Simulator.
public struct SimulatorActionsView: View {
    @Environment(SimulatorManager.self) private var simulatorManager
    public let device: SimulatorDevice

    struct ActionItem: Identifiable {
        let id = UUID()
        let type: ActionType
    }

    enum ActionType {
        case togglePower
        case restart
        case erase
    }

    private var actions: [ActionItem] {
        [.init(type: .togglePower), .init(type: .restart), .init(type: .erase)]
    }

    public var body: some View {
        AdaptiveGrid(actions, id: \.id) { item in
            switch item.type {
            case .togglePower:
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
            case .restart:
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
            case .erase:
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
}
