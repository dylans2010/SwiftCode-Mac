import Foundation

public struct RenameFileTool {
    public static let identifier = "rename_file"

    public func run(oldPath: String, newPath: String) async throws {
        try FileManager.default.moveItem(atPath: oldPath, toPath: newPath)
    }
}
