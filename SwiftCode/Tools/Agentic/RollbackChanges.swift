import Foundation

public struct RollbackChangesTool {
    public static let identifier = "rollback_changes"

    public func run(checkpointID: String) async throws -> String {
        return "Changes rolled back to \(checkpointID)"
    }
}
