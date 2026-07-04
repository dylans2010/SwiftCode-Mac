import Foundation

public struct ReadMultipleFilesTool: AgentTool {
    public static let identifier = "read_multiple_files"
    public let name = "read_multiple_files"
    public let description = "Reads the content of multiple files."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": ["paths": ["type": "array", "items": ["type": "string"]]],
        "required": ["paths"]
    ]

    public func run(paths: [String]) async throws -> [String: String] {
        var results: [String: String] = [:]
        for path in paths {
            let url = URL(fileURLWithPath: path)
            results[path] = try String(contentsOf: url, encoding: .utf8)
        }
        return results
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let paths = arguments["paths"] as? [String] else { throw AgentError.toolError("Missing paths array") }
        let results = try await run(paths: paths)

        var output = ""
        for (path, content) in results {
            output += "--- FILE: \(path) ---\n\(content)\n\n"
        }
        return output
    }
}
