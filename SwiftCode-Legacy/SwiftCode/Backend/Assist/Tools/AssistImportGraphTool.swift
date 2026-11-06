import Foundation

public struct AssistImportGraphTool: AssistTool {
    public let id = "import_graph"
    public let name = "Import Graph"
    public let description = "Builds a file-level import graph: which modules each source file imports, and which files import a given module."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Builds a file-level import graph.",
            properties: [
                "module": JSONSchema(type: "string", description: "Optional: only show files importing this module."),
                "limit": JSONSchema(type: "integer", description: "Maximum files to report. Default 200.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let module = (input["module"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = max(1, min(2000, (input["limit"] as? Int) ?? 200))
        let root = context.workspaceRoot
        let importPattern = try? NSRegularExpression(pattern: #"^\s*import\s+([A-Za-z_][\w.]*)"#)
        var edges: [(file: String, module: String)] = []
        var moduleCounts: [String: Int] = [:]
        for url in AssistWorkspaceScan.files(under: root, extensions: AssistWorkspaceScan.sourceExts) {
            guard let lines = AssistWorkspaceScan.readLines(url) else { continue }
            let rel = AssistWorkspacePaths.relative(url, workspaceRoot: root)
            for line in lines {
                guard let m = importPattern?.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                      let r = Range(m.range(at: 1), in: line) else { continue }
                let mod = String(line[r])
                if let module, mod != module { continue }
                edges.append((rel, mod))
                moduleCounts[mod, default: 0] += 1
            }
        }
        if let module {
            let files = Array(Set(edges.map { $0.file })).sorted()
            var lines = ["Files importing '\(module)' (\(files.count)):"]
            lines += files.prefix(limit).map { "- \($0)" }
            return .success(lines.joined(separator: "\n"), data: ["module": module, "fileCount": "\(files.count)"])
        }
        var lines = ["Most-imported modules:"]
        for (mod, count) in moduleCounts.sorted(by: { $0.value > $1.value }).prefix(30) {
            lines.append("- \(mod): \(count) files")
        }
        lines.append("Import edges (\(edges.count) total, showing \(min(limit, edges.count))):")
        lines += edges.prefix(limit).map { "- \($0.file) -> \($0.module)" }
        return .success(lines.joined(separator: "\n"), data: ["edgeCount": "\(edges.count)", "moduleCount": "\(moduleCounts.count)"])
    }
}
