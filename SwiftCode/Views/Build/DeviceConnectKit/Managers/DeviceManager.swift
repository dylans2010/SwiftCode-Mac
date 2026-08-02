import Foundation
import Observation

@Observable
@MainActor
public final class DeviceManager {
    public static let shared = DeviceManager()

    public private(set) var devices: [ConnectedDevice] = []
    public var selectedDevice: ConnectedDevice?
    public var isDiscovering = false

    private let service = DeviceService()

    private init() {}

    public func startDiscovery() async {
        guard !isDiscovering else { return }
        isDiscovering = true

        await DeviceConnectEngine.shared.startDiscovery { [weak self] discovered in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                self.devices = discovered
                // Auto-select first device if none is selected
                if self.selectedDevice == nil, let first = discovered.first {
                    self.selectedDevice = first
                }
            }
        }
    }

    public func stopDiscovery() async {
        await DeviceConnectEngine.shared.stopDiscovery()
        isDiscovering = false
    }

    public func refreshDevices() async {
        do {
            let discovered = try await service.discover()
            self.devices = discovered
            if self.selectedDevice == nil || !discovered.contains(where: { $0.udid == self.selectedDevice?.udid }) {
                self.selectedDevice = discovered.first
            }
        } catch {
            self.devices = []
        }
    }

    public func selectDevice(_ device: ConnectedDevice) {
        self.selectedDevice = device
        // Raise notification
        DeviceConnectNotificationCenter.shared.post(
            name: DeviceConnectNotificationCenter.deviceConnected,
            userInfo: ["device": device]
        )
    }
}
