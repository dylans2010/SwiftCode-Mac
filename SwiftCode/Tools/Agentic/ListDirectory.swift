import Foundation

public struct ListDirectoryTool {
    public static let identifier = "list_directory"

    public func run(path: String) async throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path)
    }
}
