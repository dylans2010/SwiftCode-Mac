import Foundation

public struct ParseMarkdownTool {
    public static let identifier = "parse_markdown"

    public func run(markdown: String) async throws -> String {
        return "Parsed Markdown (simulated)"
    }
}
