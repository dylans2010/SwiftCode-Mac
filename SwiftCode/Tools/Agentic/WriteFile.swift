import Foundation

public struct WriteFileTool: AgentTool {
    public static let identifier = "write_file"
    public let name = "write_file"
    public let description = "Writes content to a file."
    public let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "path": ["type": "string"],
            "content": ["type": "string"]
        ],
        "required": ["path", "content"]
    ]

    public func run(path: String, content: String) async throws {
        let url = URL(fileURLWithPath: path)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    public func execute(arguments: [String: Any]) async throws -> String {
        guard let path = arguments["path"] as? String, let content = arguments["content"] as? String else {
            throw AgentError.toolError("Missing path or content")
        }
        try await run(path: path, content: content)
        return "File written successfully"
    }
}
