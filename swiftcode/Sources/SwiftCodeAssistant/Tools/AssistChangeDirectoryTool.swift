import Foundation

/// Native `cd` equivalent. Changes the session working directory used by
/// subsequent filesystem operations and by `use_terminal` (when it omits
/// `workingDirectory`). Implemented through the session working-directory
/// store + `AssistFileSystem.currentDirectory` — NOT a shell `cd`, which
/// would die with its one-shot shell process and never persist.
///
/// Semantics: `path` resolves against the current directory (`.` = no-op,
/// `..` = parent). The target must exist, be a directory, and stay inside
/// the workspace root. `..` past the root is an error, not a silent clamp.
/// On failure the working directory is left unchanged.
public struct AssistChangeDirectoryTool: AssistTool {
    public let id = "dir_cd"
    public let name = "Change Directory"
    public let description = "Changes the session working directory (native cd equivalent). Subsequent plain relative paths resolve against it; use_terminal defaults to it when workingDirectory is omitted. Validates existence, directory-ness, and workspace containment."

    public init() {}

    public var capability: ToolCapability { .fileReading }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Changes the session working directory. Path resolves against the current directory; '..' past the workspace root is an error.",
            properties: [
                "path": JSONSchema(type: "string", description: "Directory to change to, relative to the current directory (or workspace-root-relative with a leading '/').")
            ],
            required: ["path"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let path = input["path"] as? String, !path.isEmpty else {
            return .failure("Missing required parameter: path")
        }
        do {
            let previous = context.fileSystem.currentDirectory
            let target = try context.fileSystem.setCurrentDirectory(path)
            // Persist for subsequent messages in this session; the context
            // builder re-applies it when the context is rebuilt.
            AssistWorkingDirectoryStore.shared.setCurrentDirectory(target, for: context.sessionId)
            // Listing for orientation, like a shell that prints the new cwd.
            let contents = (try? context.fileSystem.listDirectory(at: "."))?.sorted() ?? []
            return .success("Working directory changed to \(target.path)", data: [
                "path": target.path,
                "previousPath": previous.path,
                "contents": contents.joined(separator: "\n"),
                "count": "\(contents.count)"
            ])
        } catch {
            return .failure("Failed to change directory to \(path): \(error.localizedDescription)")
        }
    }
}

/// Native `pwd` equivalent. Reports the session working directory.
public struct AssistPrintWorkingDirectoryTool: AssistTool {
    public let id = "dir_pwd"
    public let name = "Print Working Directory"
    public let description = "Reports the session working directory (native pwd equivalent)."

    public init() {}

    public var capability: ToolCapability { .fileReading }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Reports the session working directory. No parameters.",
            properties: [:],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let current = context.fileSystem.currentDirectory
        return .success("Working directory: \(current.path)", data: ["path": current.path])
    }
}
