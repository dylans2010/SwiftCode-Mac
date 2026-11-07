import Foundation

public struct AssistFileTypeBreakdownTool: AssistTool {
    public let id = "file_type_breakdown"
    public let name = "File Type Breakdown"
    public let description = "Breaks down a directory by file extension: file counts and total bytes per type."

    public init() {}

    public var capability: ToolCapability { .fileReading }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Breaks down files by extension.",
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
        var counts: [String: Int] = [:]
        var bytes: [String: Int64] = [:]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return .failure("Cannot enumerate directory: \(raw)")
        }
        while let child = enumerator.nextObject() as? URL {
            let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir { continue }
            let ext = child.pathExtension.lowercased()
            let key = ext.isEmpty ? "(no extension)" : ".\(ext)"
            counts[key, default: 0] += 1
            bytes[key, default: 0] += AssistWorkspaceScan.fileSize(of: child)
        }
        let table = AssistTextFormat.markdownTable(
            headers: ["Extension", "Files", "Bytes"],
            rows: counts.sorted { $0.value > $1.value }.map { [$0.key, "\($0.value)", "\(bytes[$0.key] ?? 0)"] }
        )
        return .success("File type breakdown for \(raw):\n\(table)", data: ["typeCount": "\(counts.count)"])
    }
}
