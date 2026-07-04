import Foundation

public struct ReplaceTextTool {
    public static let identifier = "replace_text"

    public func run(path: String, target: String, replacement: String) async throws {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let newContent = content.replacingOccurrences(of: target, with: replacement)
        try newContent.write(toFile: path, atomically: true, encoding: .utf8)
    }
}
