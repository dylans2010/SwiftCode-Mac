import Foundation

public struct ReadMultipleFilesTool: AgentTool {
    public static let identifier = "read_multiple_files"
    public let name = "read_multiple_files"
    public let description = "Reads the content of multiple files."
    public let schema: [String: JSON] = [
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

    public func execute(arguments: [String: JSON]) async throws -> String {
        guard case .array(let pathsJSON) = arguments["paths"] else { throw AgentError.toolError("Missing paths array") }

        let paths = pathsJSON.compactMap { (item: JSON) -> String? in
            if case .string(let s) = item { return s }
            return nil
        }

        let results = try await run(paths: paths)

        var output = ""
        for (path, content) in results {
            output += "--- FILE: \(path) ---\n\(content)\n\n"
        }
        return output
    }
}
