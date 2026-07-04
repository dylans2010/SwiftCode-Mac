import Foundation

public struct EditFileTool: AgentTool {
    public static let identifier = "edit_file"
    public let name = "edit_file"
    public let description = "Performs search-and-replace edits on a file."
    public let schema: [String: JSON] = [
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

    public func execute(arguments: [String: JSON]) async throws -> String {
        guard case .string(let path) = arguments["path"],
              case .array(let editsJSON) = arguments["edits"] else {
            throw AgentError.toolError("Missing path or edits")
        }

        var edits: [[String: String]] = []
        for editJSON in editsJSON {
            if case .object(let obj) = editJSON,
               case .string(let search) = obj["search"],
               case .string(let replace) = obj["replace"] {
                edits.append(["search": search, "replace": replace])
            }
        }

        try await run(path: path, edits: edits)
        return "File \(path) edited successfully"
    }
}
