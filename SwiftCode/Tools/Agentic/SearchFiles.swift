import Foundation

public struct SearchFilesTool: AgentTool {
    public static let identifier = "search_files"
    public let name = "search_files"
    public let description = "Searches for files matching a pattern in a directory."
    public let schema: [String: JSON] = [
        "type": "object",
        "properties": [
            "directory": ["type": "string"],
            "pattern": ["type": "string"]
        ],
        "required": ["directory", "pattern"]
    ]

    public func run(directory: String, pattern: String) async throws -> [String] {
        let url = URL(fileURLWithPath: directory)
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])

        var results: [String] = []
        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.lastPathComponent.contains(pattern) {
                results.append(fileURL.path)
            }
        }
        return results
    }

    public func execute(arguments: [String: JSON]) async throws -> String {
        guard case .string(let directory) = arguments["directory"],
              case .string(let pattern) = arguments["pattern"] else {
            throw AgentError.toolError("Missing directory or pattern")
        }
        let results = try await run(directory: directory, pattern: pattern)
        return results.joined(separator: "\n")
    }
}
