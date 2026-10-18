import Foundation

public struct AssistFileMetadataTool: AssistTool {
    public let id = "file_metadata"
    public let name = "File Metadata"
    public let description = "Returns size, dates, permissions, type, and directory status for a file or directory inside the workspace."

    public init() {}

    public var capability: ToolCapability { .fileReading }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Returns size, dates, permissions, type, and directory status for a file or directory inside the workspace.",
            properties: [
                "path": JSONSchema(type: "string", description: "Workspace-relative path of the file or directory.")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let rawPath = (input["path"] as? String), !rawPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("Missing required parameter: path")
        }
        guard let url = resolveWorkspacePath(rawPath, workspaceRoot: context.workspaceRoot) else {
            return .failure("Refusing to access path outside the workspace: \(rawPath)")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            return .failure("No file or directory at path: \(rawPath)")
        }

        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            return .failure("Failed to read metadata for \(rawPath): \(error.localizedDescription)")
        }

        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let creation = (attributes[.creationDate] as? Date).map { formatter.string(from: $0) } ?? ""
        let modification = (attributes[.modificationDate] as? Date).map { formatter.string(from: $0) } ?? ""
        let permissionsValue = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
        let permissionsOctal = String(permissionsValue, radix: 8)
        let fileType = (attributes[.type] as? FileAttributeType)?.rawValue ?? "unknown"
        let isDirString = isDirectory.boolValue ? "true" : "false"
        let relative = relativePath(url, workspaceRoot: context.workspaceRoot)

        let output = """
        Metadata for \(relative):
        - File name: \(url.lastPathComponent)
        - Extension: \(url.pathExtension.isEmpty ? "(none)" : url.pathExtension)
        - Is directory: \(isDirString)
        - File type: \(fileType)
        - Size: \(size) bytes
        - Created: \(creation.isEmpty ? "(unknown)" : creation)
        - Modified: \(modification.isEmpty ? "(unknown)" : modification)
        - Permissions (octal): \(permissionsOctal)
        """
        return .success(output, data: [
            "path": relative,
            "fileName": url.lastPathComponent,
            "extension": url.pathExtension,
            "isDirectory": isDirString,
            "fileType": fileType,
            "size": "\(size)",
            "creationDate": creation,
            "modificationDate": modification,
            "permissions": permissionsOctal,
            "permissionsOctal": permissionsOctal
        ])
    }

    private func resolveWorkspacePath(_ raw: String, workspaceRoot: URL) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("\0"), !trimmed.hasPrefix("~"), !trimmed.contains("..") else {
            return nil
        }
        let rootPath = workspaceRoot.standardized.path
        let candidate: URL
        if trimmed.hasPrefix("/") {
            candidate = URL(fileURLWithPath: trimmed).standardized
        } else {
            candidate = workspaceRoot.appendingPathComponent(trimmed).standardized
        }
        let candidatePath = candidate.path
        guard candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/") else {
            return nil
        }
        return candidate
    }

    private func relativePath(_ url: URL, workspaceRoot: URL) -> String {
        let rootPath = workspaceRoot.standardized.path
        let path = url.standardized.path
        if path == rootPath { return "." }
        if path.hasPrefix(rootPath + "/") {
            return String(path.dropFirst(rootPath.count + 1))
        }
        return path
    }
}
