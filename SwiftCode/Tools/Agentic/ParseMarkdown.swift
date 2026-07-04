import Foundation

public struct ParseMarkdownTool: AgentTool {
    public static let identifier = "parse_markdown"
    public let name = "parse_markdown"
    public let description = "Parses a Markdown string."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "markdown": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["markdown"]
    ]

    public func run(markdown: String) async throws -> String {
        return "Parsed Markdown (simulated)"
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let markdown = arguments["markdown"] as? String else {
            throw AgentError.toolError("Missing markdown")
        }
        return try await run(markdown: markdown)
    }
}
