import Foundation

public struct AssistFileBackupTool: AssistTool {
    public let id = "file_backup"
    public let name = "File Backup"
    public let description = "Backs up a workspace file to .assist_temp/backups/<name>.<timestamp>.bak before a risky edit."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Backs up a file.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative file to back up.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let raw = (input["path"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return .failure("Missing required parameter: path")
        }
        guard let url = AssistWorkspacePaths.resolve(raw, workspaceRoot: context.workspaceRoot),
              FileManager.default.fileExists(atPath: url.path) else {
            return .failure("No file at path: \(raw)")
        }
        let fm = FileManager.default
        let backups = context.workspaceRoot.appendingPathComponent(".assist_temp/backups", isDirectory: true)
        do {
            try fm.createDirectory(at: backups, withIntermediateDirectories: true)
        } catch {
            return .failure("Cannot create backup directory: \(error.localizedDescription)")
        }
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let backupName = url.lastPathComponent + "." + stamp + ".bak"
        let backupURL = backups.appendingPathComponent(backupName)
        do {
            try fm.copyItem(at: url, to: backupURL)
        } catch {
            return .failure("Backup failed: \(error.localizedDescription)")
        }
        // Verify byte count matches.
        let srcSize = AssistWorkspaceScan.fileSize(of: url)
        let dstSize = AssistWorkspaceScan.fileSize(of: backupURL)
        guard srcSize == dstSize else {
            try? fm.removeItem(at: backupURL)
            return .failure("Backup verification failed (size mismatch); backup removed.")
        }
        let rel = ".assist_temp/backups/\(backupName)"
        return .success("Backed up \(raw) to \(rel) (\(srcSize) bytes).", data: [
            "source": raw, "backup": rel, "bytes": "\(srcSize)"
        ], filesChanged: [rel])
    }
}
