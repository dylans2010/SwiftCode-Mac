import Foundation
import CryptoKit

public struct AssistFindDuplicateFilesTool: AssistTool {
    public let id = "find_duplicate_files"
    public let name = "Find Duplicate Files"
    public let description = "Finds byte-identical duplicate files under a directory using SHA-256 content hashing."

    public init() {}

    public var capability: ToolCapability { .fileReading }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Finds duplicate files by content hash.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative directory. Default: workspace root (.)."),
                "minSize": JSONSchema(type: "integer", description: "Ignore files smaller than this many bytes. Default 1.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let raw = (input["path"] as? String) ?? "."
        let minSize = max(0, (input["minSize"] as? Int) ?? 1)
        guard let url = AssistWorkspacePaths.resolve(raw, workspaceRoot: context.workspaceRoot) else {
            return .failure("Refusing to access path outside the workspace: \(raw)")
        }
        var bySize: [Int64: [URL]] = [:]
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return .failure("Cannot enumerate directory: \(raw)")
        }
        while let child = enumerator.nextObject() as? URL {
            let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir { continue }
            let size = AssistWorkspaceScan.fileSize(of: child)
            if size >= Int64(minSize) { bySize[size, default: []].append(child) }
        }
        var groups: [[String]] = []
        for (_, urls) in bySize where urls.count > 1 {
            var byHash: [String: [URL]] = [:]
            for u in urls {
                if let h = Self.sha256(of: u) { byHash[h, default: []].append(u) }
            }
            for (_, dupes) in byHash where dupes.count > 1 {
                groups.append(dupes.map { AssistWorkspacePaths.relative($0, workspaceRoot: context.workspaceRoot) }.sorted())
            }
        }
        if groups.isEmpty {
            return .success("No duplicate files found under \(raw).", data: ["groupCount": "0"])
        }
        var lines = ["Duplicate file groups (\(groups.count)):"]
        for group in groups.sorted(by: { $0.first ?? "" < $1.first ?? "" }).prefix(50) {
            lines.append("- " + group.joined(separator: ", "))
        }
        return .success(lines.joined(separator: "\n"), data: ["groupCount": "\(groups.count)"])
    }

    private static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
