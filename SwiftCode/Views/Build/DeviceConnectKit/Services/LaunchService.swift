import Foundation

public struct LaunchService {
    public init() {}

    public func launch(
        deviceUDID: String,
        bundleIdentifier: String
    ) async throws -> Int32? {
        return try await LaunchApplicationCommand().execute(
            deviceUDID: deviceUDID,
            bundleIdentifier: bundleIdentifier
        )
    }
}
