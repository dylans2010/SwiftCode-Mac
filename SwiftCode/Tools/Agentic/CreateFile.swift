import Foundation

public struct CreateFileTool {
    public static let identifier = "create_file"

    public func run(path: String, content: String = "") async throws {
        let url = URL(fileURLWithPath: path)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
