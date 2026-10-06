import Foundation

public struct AssistSearchTool: AssistTool {
    public let id = "search_text"
    public let name = "Search Text"
    public let description = "Searches for text across files in the project sandbox."

    public init() {}

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Searches for text across files in the project workspace.",
            properties: [
                "pattern": JSONSchema(type: "string", description: "The exact substring or query string to search for."),
                "path": JSONSchema(type: "string", description: "Optional subdirectory path scope.")
            ],
            required: ["pattern"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let pattern = input["pattern"] as? String else {
            return .failure("Missing required parameter: pattern")
        }

        do {
            let results = try AssistSearchFunctions.searchText(in: context.workspaceRoot, pattern: pattern, isRegex: false)
            let formattedResults = results.map { (url, matches) in
                let relativePath = url.path.replacingOccurrences(of: context.workspaceRoot.path + "/", with: "")
                return "\(relativePath):\n" + matches.joined(separator: "\n")
            }.joined(separator: "\n\n")

            return .success("Search results for '\(pattern)':", data: ["results": formattedResults])
        } catch {
            return .failure("Search failed: \(error.localizedDescription)")
        }
    }
}
