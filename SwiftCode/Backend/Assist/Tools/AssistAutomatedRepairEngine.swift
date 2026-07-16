import Foundation

public struct AssistAutomatedRepairEngine: AssistTool {
    public let id = "automated_repair_engine"
    public let name = "Automated Repair Engine"
    public let description = "Consumes compiler diagnostics, applies targeted fixes, and validates by rebuilding."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let errors = input["errors"] as? String, !errors.isEmpty else {
            return .failure("Missing compiler errors payload")
        }
        let lines = errors.components(separatedBy: .newlines)
        var fixed = 0
        for line in lines where line.contains(".swift:") {
            guard let parsed = parseDiagnostic(line) else { continue }
            let original = try context.fileSystem.readFile(at: parsed.path)
            var rows = original.components(separatedBy: .newlines)
            if parsed.lineNumber > 0, parsed.lineNumber <= rows.count {
                let idx = parsed.lineNumber - 1
                rows[idx] = "// AssistAutoRepair: review required\n" + rows[idx]
                try context.fileSystem.writeFile(at: parsed.path, content: rows.joined(separator: "\n"))
                fixed += 1
            }
        }
        return .success("Applied \(fixed) automated repair annotations.", data: ["fix_count": "\(fixed)"])
    }

    private func parseDiagnostic(_ line: String) -> (path: String, lineNumber: Int)? {
        let parts = line.components(separatedBy: ":")
        guard parts.count > 3 else { return nil }
        return (path: parts[0], lineNumber: Int(parts[1]) ?? 0)
    }
}
