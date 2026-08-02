import Foundation

public struct RuntimeService: Sendable {
    public init() {}

    public func stop(
        deviceUDID: String,
        bundleIdentifier: String
    ) async throws -> Bool {
        return try await StopApplicationCommand().execute(
            deviceUDID: deviceUDID,
            bundleIdentifier: bundleIdentifier
        )
    }
}
