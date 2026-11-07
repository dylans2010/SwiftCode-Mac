import Foundation

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
            AssistWorkingDirectoryStore.shared.setCurrentDirectory(target, for: context.sessionId)
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
