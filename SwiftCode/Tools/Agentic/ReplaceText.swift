import Foundation

public struct ReplaceTextTool: AgentTool {
    public static let identifier = "replace_text"
    public let name = "replace_text"
    public let description = "Replaces text in a file."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "path": ["type": "string"] as [String: any Sendable],
            "target": ["type": "string"] as [String: any Sendable],
            "replacement": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["path", "target", "replacement"]
    ]

    public func run(path: String, target: String, replacement: String) async throws {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        let newContent = content.replacingOccurrences(of: target, with: replacement)
        try newContent.write(toFile: path, atomically: true, encoding: .utf8)
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let path = arguments["path"] as? String,
              let target = arguments["target"] as? String,
              let replacement = arguments["replacement"] as? String else {
            throw AgentError.toolError("Missing path, target, or replacement")
        }
        try await run(path: path, target: target, replacement: replacement)
        return "Successfully replaced text in \(path)"
    }
}
