import Foundation

public struct FindTextTool: AgentTool {
    public static let identifier = "find_text"
    public let name = "find_text"
    public let description = "Searches for text in a directory."
    public let schema: [String: any Sendable] = [
        "type": "object",
        "properties": [
            "directory": ["type": "string"] as [String: any Sendable],
            "text": ["type": "string"] as [String: any Sendable]
        ] as [String: any Sendable],
        "required": ["directory", "text"]
    ]

    public func run(directory: String, text: String) async throws -> [String: [Int]] {
        let url = URL(fileURLWithPath: directory)
        let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])

        var results: [String: [Int]] = [:]
        while let fileURL = enumerator?.nextObject() as? URL {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            let lines = content.components(separatedBy: .newlines)
            var matchingLines: [Int] = []
            for (index, line) in lines.enumerated() {
                if line.contains(text) {
                    matchingLines.append(index + 1)
                }
            }
            if !matchingLines.isEmpty {
                results[fileURL.path] = matchingLines
            }
        }
        return results
    }

    public func execute(arguments: [String: any Sendable]) async throws -> String {
        guard let directory = arguments["directory"] as? String,
              let text = arguments["text"] as? String else {
            throw AgentError.toolError("Missing directory or text")
        }
        let results = try await run(directory: directory, text: text)
        if results.isEmpty {
            return "No matches found."
        }
        return results.map { "\($0.key): \($0.value.map(String.init).joined(separator: ", "))" }.joined(separator: "\n")
    }
}
