import Foundation

public struct ReadFileTool {
    public static let identifier = "read_file"

    public func run(path: String) async throws -> String {
        let url = URL(fileURLWithPath: path)
        return try String(contentsOf: url, encoding: .utf8)
    }
}
