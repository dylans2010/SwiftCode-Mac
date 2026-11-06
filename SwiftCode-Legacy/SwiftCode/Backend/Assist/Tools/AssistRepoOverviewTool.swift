import Foundation

public struct AssistRepoOverviewTool: AssistTool {
    public let id = "repo_overview"
    public let name = "Repository Overview"
    public let description = "Summarizes the workspace repository: file counts by language, directory breadth, README/license presence, and largest files."

    public init() {}

    public var capability: ToolCapability { .repositoryDiscovery }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Summarizes the workspace repository.",
            properties: [
                "topLanguages": JSONSchema(type: "integer", description: "How many top languages to report. Default 8.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let root = context.workspaceRoot
        let topN = max(1, min(20, (input["topLanguages"] as? Int) ?? 8))
        let files = AssistWorkspaceScan.files(under: root)
        var byExt: [String: Int] = [:]
        var totalBytes: Int64 = 0
        var largest: [(String, Int64)] = []
        for url in files {
            let ext = url.pathExtension.lowercased()
            let key = ext.isEmpty ? "(no extension)" : ext
            byExt[key, default: 0] += 1
            let size = AssistWorkspaceScan.fileSize(of: url)
            totalBytes += size
            largest.append((AssistWorkspacePaths.relative(url, workspaceRoot: root), size))
        }
        largest.sort { $0.1 > $1.1 }
        let fm = FileManager.default
        let readme = ["README.md", "README.markdown", "README.txt", "Readme.md", "readme.md"].first {
            fm.fileExists(atPath: root.appendingPathComponent($0).path)
        }
        let license = ["LICENSE", "LICENSE.md", "LICENSE.txt", "LICENCE", "COPYING"].first {
            fm.fileExists(atPath: root.appendingPathComponent($0).path)
        }
        var lines: [String] = []
        lines.append("Repository overview for \(root.lastPathComponent):")
        lines.append("- Total files: \(files.count)")
        lines.append("- Total size: \(totalBytes) bytes")
        lines.append("- README: \(readme ?? "not found")")
        lines.append("- License: \(license ?? "not found")")
        lines.append("- Top languages/extensions:")
        for (ext, count) in byExt.sorted(by: { $0.value > $1.value }).prefix(topN) {
            lines.append("  - .\(ext): \(count) files")
        }
        lines.append("- Largest files:")
        for (path, size) in largest.prefix(5) {
            lines.append("  - \(path) (\(size) bytes)")
        }
        return .success(lines.joined(separator: "\n"), data: [
            "fileCount": "\(files.count)",
            "totalBytes": "\(totalBytes)",
            "readme": readme ?? "",
            "license": license ?? ""
        ])
    }
}
