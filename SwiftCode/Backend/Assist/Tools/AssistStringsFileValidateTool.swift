import Foundation

public struct AssistStringsFileValidateTool: AssistTool {
    public let id = "strings_file_validate"
    public let name = "Strings File Validate"
    public let description = "Validates .strings localization files: syntax errors, duplicate keys, and empty values."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Validates a .strings file.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path to the .strings file.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let raw = (input["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return .failure("Missing required parameter: path")
        }
        guard let url = AssistWorkspacePaths.resolve(raw, workspaceRoot: context.workspaceRoot),
              let data = try? Data(contentsOf: url) else {
            return .failure("Cannot read file at: \(raw)")
        }
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? ""
        guard !text.isEmpty else { return .failure("File is empty or undecodable: \(raw)") }
        let entryPattern = try? NSRegularExpression(pattern: #"^\s*"((?:[^"\\]|\\.)*)"\s*=\s*"((?:[^"\\]|\\.)*)"\s*;\s*$"#)
        var seen: Set<String> = []
        var duplicates: [String] = []
        var malformed: [(Int, String)] = []
        var emptyValues: [String] = []
        var validCount = 0
        for (i, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("//") || line.hasPrefix("/*") { continue }
            guard let p = entryPattern,
                  let m = p.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                  let kr = Range(m.range(at: 1), in: line),
                  let vr = Range(m.range(at: 2), in: line) else {
                malformed.append((i + 1, String(line.prefix(100))))
                continue
            }
            validCount += 1
            let key = String(line[kr])
            if seen.contains(key) { duplicates.append(key) } else { seen.insert(key) }
            if String(line[vr]).isEmpty { emptyValues.append(key) }
        }
        var lines = ["Strings validation for \(raw):", "- Valid entries: \(validCount)", "- Duplicate keys: \(duplicates.count)", "- Malformed lines: \(malformed.count)", "- Empty values: \(emptyValues.count)"]
        for d in duplicates.prefix(20) { lines.append("  DUPLICATE: \(d)") }
        for (n, l) in malformed.prefix(20) { lines.append("  MALFORMED line \(n): \(l)") }
        for e in emptyValues.prefix(20) { lines.append("  EMPTY VALUE: \(e)") }
        let ok = duplicates.isEmpty && malformed.isEmpty
        return .success(lines.joined(separator: "\n"), data: [
            "valid": "\(validCount)", "duplicates": "\(duplicates.count)",
            "malformed": "\(malformed.count)", "emptyValues": "\(emptyValues.count)",
            "passed": ok ? "true" : "false"
        ])
    }
}
