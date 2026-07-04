import Foundation

public struct CheckpointCreatorTool {
    public static let identifier = "checkpoint_creator"

    public func run(description: String) async throws -> String {
        return "Checkpoint '\(description)' created"
    }
}
