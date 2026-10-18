import Foundation

public struct AssistProjectStructureMapTool: AssistTool {
    public let id = "project_structure_map"
    public let name = "Project Structure Map"
    public let description = "Builds a machine-readable map of the project: top-level directories with file counts and the Xcode target layout parsed from the .pbxproj when present."

    public init() {}

    public var capability: ToolCapability { .repositoryDiscovery }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Builds a machine-readable project structure map.",
            properties: [
                "maxDepth": JSONSchema(type: "integer", description: "Directory depth to map. Default 2, max 4.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let root = context.workspaceRoot
        let maxDepth = max(1, min(4, (input["maxDepth"] as? Int) ?? 2))
        var dirCounts: [String: Int] = [:]
        var dirBytes: [String: Int64] = [:]
        for url in AssistWorkspaceScan.files(under: root) {
            let rel = AssistWorkspacePaths.relative(url, workspaceRoot: root)
            let parts = rel.split(separator: "/").map(String.init)
            guard parts.count > 1 else { continue }
            for depth in 1...min(maxDepth, parts.count - 1) {
                let dir = parts.prefix(depth).joined(separator: "/")
                dirCounts[dir, default: 0] += 1
                dirBytes[dir, default: 0] += AssistWorkspaceScan.fileSize(of: url)
            }
        }
        var targets: [String] = []
        if let pbxproj = AssistWorkspaceScan.findPbxproj(in: root),
           let text = try? String(contentsOf: pbxproj, encoding: .utf8),
           let pattern = try? NSRegularExpression(pattern: #"/\* (\w[\w ]*) \*/ = \{\s*isa = PBXNativeTarget;"#) {
            targets = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { m -> String? in
                guard let r = Range(m.range(at: 1), in: text) else { return nil }
                return String(text[r])
            }.sorted()
        }
        var lines = ["Project structure map (depth \(maxDepth)):"]
        for dir in dirCounts.keys.sorted() {
            lines.append("- \(dir)/ — \(dirCounts[dir] ?? 0) files, \(dirBytes[dir] ?? 0) bytes")
        }
        if !targets.isEmpty {
            lines.append("Xcode targets: \(targets.joined(separator: ", "))")
        }
        return .success(lines.joined(separator: "\n"), data: [
            "directoryCount": "\(dirCounts.count)",
            "targets": targets.joined(separator: ",")
        ])
    }
}
