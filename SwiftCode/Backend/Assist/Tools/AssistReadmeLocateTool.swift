import Foundation

public struct AssistReadmeLocateTool: AssistTool {
    public let id = "readme_locate"
    public let name = "Locate README"
    public let description = "Finds README files in the workspace (any case/extension), reporting each path and its title line."

    public init() {}

    public var capability: ToolCapability { .repositoryDiscovery }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(type: "object", description: "Locates README files.", properties: [:], required: [])
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let root = context.workspaceRoot
        let readmes = AssistWorkspaceScan.files(under: root).filter {
            $0.lastPathComponent.lowercased().hasPrefix("readme")
        }
        if readmes.isEmpty {
            return .failure("No README file found in the workspace.")
        }
        var lines = ["README files found:"]
        for url in readmes.sorted(by: { $0.path < $1.path }) {
            let rel = AssistWorkspacePaths.relative(url, workspaceRoot: root)
            let title = (try? String(contentsOf: url, encoding: .utf8))?
                .components(separatedBy: .newlines)
                .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })?
                .trimmingCharacters(in: .whitespaces) ?? "(unreadable)"
            lines.append("- \(rel): \(title.prefix(120))")
        }
        return .success(lines.joined(separator: "\n"), data: ["count": "\(readmes.count)"])
    }
}
