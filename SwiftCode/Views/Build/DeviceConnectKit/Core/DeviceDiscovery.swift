import Foundation
import OSLog

public actor DeviceDiscovery {
    private static let logger = Logger(subsystem: "com.swiftcode.deviceconnect", category: "DeviceDiscovery")

    private var isDiscovering = false
    private var timer: Task<Void, Never>?

    public init() {}

    public func startContinuousDiscovery(interval: TimeInterval = 10, onDiscover: @escaping @Sendable ([ConnectedDevice]) -> Void) {
        guard !isDiscovering else { return }
        isDiscovering = true

        timer = Task { [interval, onDiscover] in
            while !Task.isCancelled {
                do {
                    let devices = try await DiscoverDevicesCommand().execute()
                    onDiscover(devices)
                } catch {
                    Self.logger.error("Continuous discovery error: \(error.localizedDescription)")
                }

                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    public func stopContinuousDiscovery() {
        timer?.cancel()
        timer = nil
        isDiscovering = false
    }
}
