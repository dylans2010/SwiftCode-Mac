import Foundation

public struct ReadIssuesTool {
    public static let identifier = "read_issues"

    public func run(repository: String) async throws -> String {
        return "List of issues for \(repository)"
    }
}
