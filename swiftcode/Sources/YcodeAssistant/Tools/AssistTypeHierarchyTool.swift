import Foundation

public struct AssistTypeHierarchyTool: AssistTool {
    public let id = "type_hierarchy"
    public let name = "Type Hierarchy"
    public let description = "Maps class/struct/enum/protocol declarations and their inheritance and conformance clauses across Swift sources."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Maps type declarations and inheritance.",
            properties: [
                "type": JSONSchema(type: "string", description: "Optional: focus on one type name and show its ancestors/descendants.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let focus = (input["type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let root = context.workspaceRoot
        var decls: [String: (kind: String, parents: [String], loc: String)] = [:]
        let pattern = try? NSRegularExpression(pattern: #"^\s*(?:public|private|internal|fileprivate|open)?\s*(?:final\s+)?(class|struct|enum|protocol|actor)\s+([A-Za-z_][\w]*)\s*(?::\s*([^\{]+))?"#)
        for url in AssistWorkspaceScan.swiftFiles(under: root) {
            guard let lines = AssistWorkspaceScan.readLines(url) else { continue }
            let rel = AssistWorkspacePaths.relative(url, workspaceRoot: root)
            for (i, line) in lines.enumerated() {
                guard let p = pattern,
                      let m = p.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                      m.numberOfRanges >= 3,
                      let kr = Range(m.range(at: 1), in: line),
                      let nr = Range(m.range(at: 2), in: line) else { continue }
                let kind = String(line[kr]); let name = String(line[nr])
                var parents: [String] = []
                if m.numberOfRanges >= 4, let pr = Range(m.range(at: 3), in: line) {
                    parents = String(line[pr]).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                }
                decls[name] = (kind, parents, "\(rel):\(i + 1)")
            }
        }
        if let focus, !focus.isEmpty {
            guard let d = decls[focus] else {
                return .failure("Type '\(focus)' not found in workspace Swift sources.")
            }
            var lines = ["Type hierarchy for '\(focus)' (\(d.kind)) at \(d.loc):", "Inherits/conforms to:"]
            lines += d.parents.isEmpty ? ["- (none)"] : d.parents.map { "- \($0)" }
            let children = decls.filter { $0.value.parents.contains(focus) }.map { "\($0.key) (\($0.value.kind))" }.sorted()
            lines.append("Subtypes (\(children.count)):")
            lines += children.isEmpty ? ["- (none)"] : children.map { "- \($0)" }
            return .success(lines.joined(separator: "\n"), data: ["type": focus, "childCount": "\(children.count)"])
        }
        var lines = ["Type declarations (\(decls.count) total):"]
        for name in decls.keys.sorted().prefix(200) {
            let d = decls[name]!
            let parents = d.parents.isEmpty ? "" : ": " + d.parents.joined(separator: ", ")
            lines.append("- \(d.kind) \(name)\(parents) — \(d.loc)")
        }
        if decls.count > 200 { lines.append("… [truncated: showing 200 of \(decls.count)]") }
        return .success(lines.joined(separator: "\n"), data: ["typeCount": "\(decls.count)"])
    }
}
