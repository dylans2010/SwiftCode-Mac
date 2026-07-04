import Foundation

public struct CreateFileTool: AgentTool {
    public static let identifier = "create_file"
    public let name = "create_file"
    public let description = "Creates a new file with optional content."
    public let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "path": ["type": "string"],
            "content": ["type": "string"]
        ],
        "required": ["path"]
    ]

    public func run(path: String, content: String = "") async throws {
        let url = URL(fileURLWithPath: path)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    public func execute(arguments: [String: Any]) async throws -> String {
        guard let path = arguments["path"] as? String else { throw AgentError.toolError("Missing path") }
        let content = arguments["content"] as? String ?? ""
        try await run(path: path, content: content)
        return "File created successfully at \(path)"
    }
}
