import Foundation

public struct AssistExecutableFilesScanTool: AssistTool {
    public let id = "executable_files_scan"
    public let name = "Executable Files Scan"
    public let description = "Lists files with the executable bit set under a directory — a hygiene check for accidental +x bits in repos."

    public init() {}

    public var capability: ToolCapability { .fileReading }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Scans for executable files.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative directory. Default: workspace root (.)."),
                "limit": JSONSchema(type: "integer", description: "Maximum results. Default 100, max 1000.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let raw = (input["path"] as? String) ?? "."
        let limit = max(1, min(1000, (input["limit"] as? Int) ?? 100))
        guard let url = AssistWorkspacePaths.resolve(raw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Refusing to access path outside the workspace: \(raw)")
        }
        var hits: [String] = []
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return .failure("Cannot enumerate directory: \(raw)")
        }
        while let child = enumerator.nextObject() as? URL, hits.count < limit {
            let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir { continue }
            if FileManager.default.isExecutableFile(atPath: child.path) {
                hits.append(AssistWorkspacePaths.relative(child, workspaceRoot: context.workspaceRoot))
            }
        }
        if hits.isEmpty {
            return .success("No executable files under \(raw).", data: ["count": "0"])
        }
        return .success("Executable files under \(raw) (\(hits.count)):\n" + hits.sorted().map { "- \($0)" }.joined(separator: "\n"),
                        data: ["count": "\(hits.count)"])
    }
}
