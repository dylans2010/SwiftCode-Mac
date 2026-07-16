import Foundation

public struct AssistInsertCodeBlockTool: AssistTool {
    public let id = "code_insert"
    public let name = "Insert Code Block"
    public let description = "Inserts a block of code at a specific line or before/after a symbol."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String else {
            return .failure("Missing required parameter: path")
        }
        guard let code = input["code"] as? String else {
            return .failure("Missing required parameter: code")
        }

        do {
            let content = try context.fileSystem.readFile(at: path)
            let insertionMode = (input["mode"] as? String ?? "line").lowercased()
            let updated: String

            switch insertionMode {
            case "before":
                guard let pattern = input["pattern"] as? String else {
                    return .failure("Missing required parameter for before mode: pattern")
                }
                updated = AssistCodeFunctions.insertBefore(in: content, pattern: pattern, insert: code)
            case "after":
                guard let pattern = input["pattern"] as? String else {
                    return .failure("Missing required parameter for after mode: pattern")
                }
                updated = AssistCodeFunctions.insertAfter(in: content, pattern: pattern, insert: code)
            default:
                let lineNumber = max(1, Int(input["line"] as? String ?? "1") ?? 1)
                var lines = content.components(separatedBy: .newlines)
                let insertIndex = min(lineNumber - 1, lines.count)
                lines.insert(contentsOf: code.components(separatedBy: .newlines), at: insertIndex)
                updated = lines.joined(separator: "\n")
            }

            try context.fileSystem.writeFile(at: path, content: updated)
            return .success("Code block inserted into \(path)")
        } catch {
            return .failure("Failed to insert code into \(path): \(error.localizedDescription)")
        }
    }
}
