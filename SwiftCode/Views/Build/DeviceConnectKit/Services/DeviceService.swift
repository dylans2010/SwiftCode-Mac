import Foundation

public struct DeviceService {
    public init() {}

    public func discover() async throws -> [ConnectedDevice] {
        return try await DiscoverDevicesCommand().execute()
    }
}
