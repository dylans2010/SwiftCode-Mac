import Foundation

public struct SigningService {
    public init() {}

    public func validateIdentities() async throws -> [String] {
        return try await SigningValidationCommand().execute()
    }
}
