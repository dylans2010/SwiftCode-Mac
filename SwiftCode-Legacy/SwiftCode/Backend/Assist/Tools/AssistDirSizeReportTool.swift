import Foundation

public struct AssistDirSizeReportTool: AssistTool {
    public let id = "dir_size_report"
    public let name = "Directory Size Report"
    public let description = "Reports recursive disk usage per immediate subdirectory of a directory, largest first."

    public init() {}

    public var capability: ToolCapability { .fileReading }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Reports subdirectory sizes.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative directory. Default: workspace root (.)."),
                "limit": JSONSchema(type: "integer", description: "Maximum subdirectories. Default 30, max 200.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let raw = (input["path"] as? String) ?? "."
        let limit = max(1, min(200, (input["limit"] as? Int) ?? 30))
        guard let url = AssistWorkspacePaths.resolve(raw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Refusing to access path outside the workspace: \(raw)")
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            return .failure("Not a directory: \(raw)")
        }
        let children = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        var rows: [(String, Int64)] = []
        for child in children {
            let childIsDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            var size: Int64 = 0
            if childIsDir {
                if let enumerator = FileManager.default.enumerator(at: child, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: [.skipsHiddenFiles]) {
                    while let grand = enumerator.nextObject() as? URL {
                        let gIsDir = (try? grand.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                        if !gIsDir { size += AssistWorkspaceScan.fileSize(of: grand) }
                    }
                }
            } else {
                size = AssistWorkspaceScan.fileSize(of: child)
            }
            rows.append((child.lastPathComponent + (childIsDir ? "/" : ""), size))
        }
        rows.sort { $0.1 > $1.1 }
        var lines = ["Directory sizes under \(AssistWorkspacePaths.relative(url, workspaceRoot: context.workspaceRoot)):"]
        for (name, size) in rows.prefix(limit) {
            lines.append(String(format: "- %@ — %lld bytes (%.2f MB)", name, size, Double(size) / 1_048_576.0))
        }
        let total = rows.reduce(0) { $0 + $1.1 }
        return .success(lines.joined(separator: "\n"), data: ["totalBytes": "\(total)", "entryCount": "\(rows.count)"])
    }
}
