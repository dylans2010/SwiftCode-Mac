import Foundation

public struct AssistDocsIndexBuildTool: AssistTool {
    public let id = "docs_index_build"
    public let name = "Docs Index Build"
    public let description = "Builds an index of all Markdown files in the workspace: path, title (first heading), and size."

    public init() {}

    public var capability: ToolCapability { .fileReading }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(type: "object", description: "Indexes Markdown docs.", properties: [:], required: [])
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let root = context.workspaceRoot
        let docs = AssistWorkspaceScan.files(under: root, extensions: ["md", "markdown"])
        if docs.isEmpty {
            return .success("No Markdown files found in the workspace.", data: ["count": "0"])
        }
        var rows: [[String]] = []
        for url in docs.sorted(by: { $0.path < $1.path }) {
            let rel = AssistWorkspacePaths.relative(url, workspaceRoot: root)
            let title = (try? String(contentsOf: url, encoding: .utf8))?
                .components(separatedBy: .newlines)
                .first(where: { $0.hasPrefix("# ") })?
                .replacingOccurrences(of: "# ", with: "")
                .prefix(80).description ?? "(no title)"
            rows.append([rel, title, "\(AssistWorkspaceScan.fileSize(of: url))"])
        }
        let table = AssistTextFormat.markdownTable(headers: ["Path", "Title", "Bytes"], rows: rows)
        return .success("Markdown index (\(docs.count) files):\n\(table)", data: ["count": "\(docs.count)"])
    }
}
