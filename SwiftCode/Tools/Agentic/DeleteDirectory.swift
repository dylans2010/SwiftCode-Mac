import Foundation

public struct DeleteDirectoryTool {
    public static let identifier = "delete_directory"

    public func run(path: String) async throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.removeItem(at: url)
    }
}
