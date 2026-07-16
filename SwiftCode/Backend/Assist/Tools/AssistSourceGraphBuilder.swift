import Foundation

public struct AssistSourceGraphBuilder: AssistTool {
    public let id = "source_graph_builder"
    public let name = "Source Graph Builder"
    public let description = "Parses Swift files and returns dependency and symbol relationship graph data."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let root = AssistToolingSupport.resolvePath(input["path"] as? String, workspaceRoot: context.workspaceRoot)
        guard FileManager.default.fileExists(atPath: root.path) else {
            return .failure("Path does not exist: \(root.path)")
        }

        let files = AssistToolingSupport.enumeratedFiles(at: root, allowedExtensions: ["swift"], maxFileSize: 800_000)
        var nodes = Set<String>()
        var imports = Set<String>()
        var relationships: [String] = []

        let symbolRegex = try NSRegularExpression(pattern: "\\b(class|struct|enum|protocol|func)\\s+([A-Za-z_][A-Za-z0-9_]*)", options: [])
        let typeUseRegex = try NSRegularExpression(pattern: "\\b([A-Z][A-Za-z0-9_]*)\\b", options: [])
        let importRegex = try NSRegularExpression(pattern: "^\\s*import\\s+([A-Za-z0-9_\\.]+)", options: [.anchorsMatchLines])

        for file in files {
            guard let content = AssistToolingSupport.readText(file) else { continue }
            let rel = AssistToolingSupport.relativePath(for: file, workspaceRoot: context.workspaceRoot)
            nodes.insert(rel)
            let range = NSRange(location: 0, length: content.utf16.count)

            let symbolMatches = symbolRegex.matches(in: content, options: [], range: range)
            var fileSymbols: [String] = []
            for match in symbolMatches {
                guard let kindRange = Range(match.range(at: 1), in: content),
                      let nameRange = Range(match.range(at: 2), in: content) else { continue }
                let symbol = "\(content[kindRange]):\(content[nameRange])"
                nodes.insert(symbol)
                relationships.append("\(rel) -> \(symbol)")
                fileSymbols.append(String(content[nameRange]))
            }

            for match in importRegex.matches(in: content, options: [], range: range) {
                guard let importRange = Range(match.range(at: 1), in: content) else { continue }
                let module = String(content[importRange])
                imports.insert(module)
                nodes.insert("module:\(module)")
                relationships.append("\(rel) -> module:\(module)")
            }

            for match in typeUseRegex.matches(in: content, options: [], range: range) {
                guard let r = Range(match.range(at: 1), in: content) else { continue }
                let usedType = String(content[r])
                if fileSymbols.contains(usedType) { continue }
                relationships.append("\(rel) -> type:\(usedType)")
            }
        }

        return .success(
            "Built source graph for \(files.count) Swift files.",
            data: [
                "file_count": "\(files.count)",
                "node_count": "\(nodes.count)",
                "relationship_count": "\(relationships.count)",
                "imports": imports.sorted().joined(separator: ","),
                "relationships": relationships.prefix(2000).joined(separator: "\n")
            ]
        )
    }
}
