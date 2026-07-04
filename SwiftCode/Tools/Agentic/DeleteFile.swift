import Foundation

public struct DeleteFileTool {
    public static let identifier = "delete_file"

    public func run(path: String) async throws {
        let url = URL(fileURLWithPath: path)
        try FileManager.default.removeItem(at: url)
    }
}
