import Foundation

public struct WriteFileTool {
    public static let identifier = "write_file"

    public func run(path: String, content: String) async throws {
        let url = URL(fileURLWithPath: path)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }
}
