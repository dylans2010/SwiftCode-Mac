import Foundation

public struct AssistSymlinkAuditTool: AssistTool {
    public let id = "symlink_audit"
    public let name = "Symlink Audit"
    public let description = "Finds symbolic links under a directory, reporting each target and flagging broken links."

    public init() {}

    public var capability: ToolCapability { .fileReading }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Audits symbolic links.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative directory. Default: workspace root (.).")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let raw = (input["path"] as? String) ?? "."
        guard let url = AssistWorkspacePaths.resolve(raw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Refusing to access path outside the workspace: \(raw)")
        }
        var rows: [(String, String, Bool)] = []
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey], options: []) else {
            return .failure("Cannot enumerate directory: \(raw)")
        }
        while let child = enumerator.nextObject() as? URL {
            let isLink = (try? child.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink ?? false
            if !isLink { continue }
            let target = (try? FileManager.default.destinationOfSymbolicLink(atPath: child.path)) ?? "(unknown)"
            let targetURL = child.deletingLastPathComponent().appendingPathComponent(target)
            let broken = !FileManager.default.fileExists(atPath: target.hasPrefix("/") ? target : targetURL.path)
            rows.append((AssistWorkspacePaths.relative(child, workspaceRoot: context.workspaceRoot), target, broken))
        }
        if rows.isEmpty {
            return .success("No symbolic links under \(raw).", data: ["count": "0", "brokenCount": "0"])
        }
        let broken = rows.filter { $0.2 }.count
        var lines = ["Symbolic links under \(raw) (\(rows.count), \(broken) broken):"]
        lines += rows.sorted { $0.0 < $1.0 }.map { "- \($0.0) -> \($0.1)\($0.2 ? " [BROKEN]" : "")" }
        return .success(lines.joined(separator: "\n"), data: ["count": "\(rows.count)", "brokenCount": "\(broken)"])
    }
}
