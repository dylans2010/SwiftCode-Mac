import Foundation

public struct AssistDependencyGraphTool: AssistTool {
    public let id = "dependency_graph"
    public let name = "Dependency Graph"
    public let description = "Generates a graph of project dependencies."

    public init() {}

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let root = AssistToolingSupport.resolvePath(input["path"] as? String, workspaceRoot: context.workspaceRoot)
        // Scan common source directories if root is base
        let files = AssistToolingSupport.enumeratedFiles(at: root, allowedExtensions: ["swift"], maxFileSize: 300_000)

        var nodes = Set<String>()
        var edges: [String] = []

        // Extract imports using regex
        let importRegex = try? NSRegularExpression(pattern: "^\\s*import\\s+([A-Za-z0-9_\\.]+)", options: [.anchorsMatchLines])

        for file in files {
            guard let content = AssistToolingSupport.readText(file), let importRegex else { continue }
            let source = AssistToolingSupport.relativePath(for: file, workspaceRoot: context.workspaceRoot)
            nodes.insert(source)

            let nsRange = NSRange(location: 0, length: content.utf16.count)
            let matches = importRegex.matches(in: content, options: [], range: nsRange)

            for match in matches {
                guard match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: content) else { continue }
                let module = String(content[r])
                nodes.insert(module)
                edges.append("\(source) -> \(module)")
            }
        }

        let resultData = [
            "node_count": "\(nodes.count)",
            "edge_count": "\(edges.count)",
            "nodes": nodes.sorted().joined(separator: ", "),
            "edges": edges.sorted().joined(separator: "\n")
        ]

        return .success("Dependency graph generated for \(files.count) files.", data: resultData)
    }
}
