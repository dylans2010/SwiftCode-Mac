import Foundation

public struct ReadEnvironmentVariablesTool {
    public static let identifier = "read_environment_variables"

    public func run() async throws -> [String: String] {
        return ProcessInfo.processInfo.environment
    }
}
