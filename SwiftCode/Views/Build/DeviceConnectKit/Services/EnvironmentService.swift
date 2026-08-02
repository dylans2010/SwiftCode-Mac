import Foundation

public struct EnvironmentService: Sendable {
    public init() {}

    public func validate() async throws -> DeviceEnvironment {
        return try await ValidateEnvironmentCommand().execute()
    }
}
