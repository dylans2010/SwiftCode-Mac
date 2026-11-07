import Foundation

public struct AssistCodeCommentExtractTool: AssistTool {
    public let id = "code_comment_extract"
    public let name = "Code Comment Extract"
    public let description = "Extracts documentation comments (/// and /** */) for a symbol or a whole file, with locations."

    public init() {}

    public var capability: ToolCapability { .fileReading }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Extracts doc comments.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative Swift file to extract from."),
                "symbol": JSONSchema(type: "string", description: "Optional: only extract comments attached to this symbol name.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let raw = (input["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return .failure("Missing required parameter: path")
        }
        let symbol = (input["symbol"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = AssistWorkspacePaths.resolve(raw, workspaceRoot: context.workspaceRoot),
              let lines = AssistWorkspaceScan.readLines(url) else {
            return .failure("Cannot read file at: \(raw)")
        }
        var results: [(String, String)] = []
        var pending: [String] = []
        for (i, line) in lines.enumerated() {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("///") {
                pending.append(String(t.dropFirst(3)).trimmingCharacters(in: .whitespaces))
                continue
            }
            if t.hasPrefix("/**") {
                var block = String(t.dropFirst(3))
                if let end = block.range(of: "*/") { block = String(block[..<end.lowerBound]) }
                pending.append(block.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "* ")))
                continue
            }
            if !pending.isEmpty {
                let doc = pending.joined(separator: "\n")
                pending.removeAll()
                if t.isEmpty || t.hasPrefix("//") || t.hasPrefix("@") { continue }
                let name = t.prefix(100).description
                if let symbol, !symbol.isEmpty, !name.contains(symbol) { continue }
                results.append(("\(raw):\(i + 1)", doc + "\n→ " + name))
            } else if !t.isEmpty && !t.hasPrefix("//") {
                pending.removeAll()
            }
        }
        if results.isEmpty {
            return .success("No documentation comments found in \(raw)\(symbol.map { " for '\($0)'" } ?? "").", data: ["count": "0"])
        }
        var out = ["Documentation comments in \(raw) (\(results.count)):"]
        for (loc, doc) in results.prefix(50) {
            out.append("- \(loc):\n  \(doc.replacingOccurrences(of: "\n", with: "\n  "))")
        }
        return .success(out.joined(separator: "\n"), data: ["count": "\(results.count)"])
    }
}
