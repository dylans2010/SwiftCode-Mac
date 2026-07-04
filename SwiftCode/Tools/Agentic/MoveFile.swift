import Foundation

public struct MoveFileTool {
    public static let identifier = "move_file"

    public func run(sourcePath: String, destinationPath: String) async throws {
        try FileManager.default.moveItem(atPath: sourcePath, toPath: destinationPath)
    }
}
