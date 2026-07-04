import Foundation

public struct CreateDirectoryTool {
    public static let identifier = "create_directory"

    public func run(path: String) async throws {
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }
}
