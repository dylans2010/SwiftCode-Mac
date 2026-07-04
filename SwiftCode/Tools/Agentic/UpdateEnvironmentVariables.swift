import Foundation

public struct UpdateEnvironmentVariablesTool {
    public static let identifier = "update_environment_variables"

    public func run(variables: [String: String]) async throws {
        for (key, value) in variables {
            setenv(key, value, 1)
        }
    }
}
