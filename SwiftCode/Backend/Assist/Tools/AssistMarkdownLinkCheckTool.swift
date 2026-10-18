import Foundation

public struct AssistMarkdownLinkCheckTool: AssistTool {
    public let id = "markdown_link_check"
    public let name = "Markdown Link Check"
    public let description = "Validates links in Markdown files: internal file links must resolve; reports broken ones."

    public init() {}

    public var capability: ToolCapability { .fileReading }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Checks Markdown links.",
            properties: [
                "path": JSONSchema(type: "string", description: "Optional workspace-relative Markdown file. Omit to check all Markdown files.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let root = context.workspaceRoot
        let raw = (input["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        var targets: [URL] = []
        if let raw, !raw.isEmpty {
            guard let url = AssistWorkspacePaths.resolve(raw, workspaceRoot: root) else {
                return .failure("Refusing to access path outside the workspace: \(raw)")
            }
            targets = [url]
        } else {
            targets = AssistWorkspaceScan.files(under: root, extensions: ["md", "markdown"])
        }
        let linkPattern = try? NSRegularExpression(pattern: #"\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)"#)
        var checked = 0
        var broken: [String] = []
        for url in targets {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let rel = AssistWorkspacePaths.relative(url, workspaceRoot: root)
            let matches = linkPattern?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
            for m in matches {
                guard let r = Range(m.range(at: 2), in: text) else { continue }
                var dest = String(text[r])
                // Skip anchors-only, absolute URLs, and mailto:.
                if dest.hasPrefix("#") || dest.contains("://") || dest.hasPrefix("mailto:") { continue }
                // Strip anchor.
                if let hash = dest.firstIndex(of: "#") { dest = String(dest[..<hash]) }
                if dest.isEmpty { continue }
                checked += 1
                let base = url.deletingLastPathComponent()
                let candidate = URL(fileURLWithPath: dest, relativeTo: base).standardized
                let candidatePath = candidate.path
                let rootPath = root.standardized.path
                let inside = candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
                if !inside || !FileManager.default.fileExists(atPath: candidatePath) {
                    broken.append("\(rel): [\(dest)]")
                    if broken.count > 200 { break }
                }
            }
            if broken.count > 200 { break }
        }
        if broken.isEmpty {
            return .success("All \(checked) internal links resolve.", data: ["checked": "\(checked)", "broken": "0"])
        }
        var lines = ["Broken internal links (\(broken.count) of \(checked) checked):"]
        lines += broken.map { "- \($0)" }
        return .success(lines.joined(separator: "\n"), data: ["checked": "\(checked)", "broken": "\(broken.count)"])
    }
}
