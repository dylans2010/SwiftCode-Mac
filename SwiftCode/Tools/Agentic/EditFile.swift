import Foundation

public struct EditFileTool: AgentTool {
    public static let identifier = "edit_file"
    public let name = "edit_file"
    public let description = "Performs search-and-replace edits on a file."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "path": ["type": "string"],
            "edits": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "search": ["type": "string"],
                        "replace": ["type": "string"]
                    ],
                    "required": ["search", "replace"]
                ]
            ]
        ],
        "required": ["path", "edits"]
    ]

    public func run(path: String, edits: [[String: String]]) async throws {
        var content = try String(contentsOfFile: path, encoding: .utf8)
        for edit in edits {
            if let search = edit["search"], let replace = edit["replace"] {
                content = content.replacingOccurrences(of: search, with: replace)
            }
        }
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let path = arguments["path"] as? String,
              let edits = arguments["edits"] as? [[String: String]] else {
            throw AgentError.toolError("Missing path or edits")
        }
        try await run(path: path, edits: edits)
        return "File \(path) edited successfully"
    }
}
