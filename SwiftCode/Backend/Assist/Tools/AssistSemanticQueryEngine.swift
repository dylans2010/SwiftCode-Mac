import Foundation

public struct AssistSemanticQueryEngine: AssistTool {
    public let id = "semantic_query_engine"
    public let name = "Semantic Source Query Engine"
    public let description = "Performs semantic search for symbols, SwiftUI views, models, and services with usage context."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let query = (input["query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else {
            return .failure("Missing required parameter: query")
        }

        let scopePath = input["path"] as? String
        let scope = AssistToolingSupport.resolvePath(scopePath, workspaceRoot: context.workspaceRoot)
        let files = AssistToolingSupport.enumeratedFiles(at: scope, allowedExtensions: ["swift"], maxFileSize: 800_000)

        var hits: [String] = []
        let q = query.lowercased()
        for file in files {
            guard let content = AssistToolingSupport.readText(file) else { continue }
            let lines = content.components(separatedBy: .newlines)
            for (idx, line) in lines.enumerated() {
                let lc = line.lowercased()
                let isSemanticClass = (q == "view" && line.contains(": View")) ||
                (q == "model" && (line.contains("struct") || line.contains("class")) && (lc.contains("model") || lc.contains("viewmodel"))) ||
                (q == "service" && lc.contains("service"))
                if lc.contains(q) || isSemanticClass {
                    let start = max(0, idx - 1)
                    let end = min(lines.count - 1, idx + 1)
                    let snippet = (start...end).map { "\($0 + 1): \(lines[$0])" }.joined(separator: " | ")
                    hits.append("\(AssistToolingSupport.relativePath(for: file, workspaceRoot: context.workspaceRoot))::\(idx + 1)::\(snippet)")
                }
            }
        }

        return .success("Semantic query returned \(hits.count) matches.", data: ["matches": hits.prefix(1500).joined(separator: "\n")])
    }
}
