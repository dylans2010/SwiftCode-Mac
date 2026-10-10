import Foundation

public struct AssistReadFileTool: AssistTool {
    public let id = "file_read"
    public let name = "Read File"
    public let description = "Reads the content of a file at the specified path."

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Reads the content of a file at the specified path.",
            properties: [
                "path": JSONSchema(type: "string", description: "The relative path to the file from the workspace root.")
            ],
            required: ["path"]
        )
    }

    public init() {}

    public var capability: ToolCapability { .fileReading }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard var path = (input["path"] ?? input["filePath"] ?? input["file_path"] ?? input["targetFile"] ?? input["file"]) as? String else {
            return .failure("Missing required parameter: path")
        }

        let workspacePrefix = context.workspaceRoot.path
        if !workspacePrefix.isEmpty && path.hasPrefix(workspacePrefix) {
            path = String(path.dropFirst(workspacePrefix.count))
        }
        while path.hasPrefix("/") {
            path = String(path.dropFirst())
        }

        do {
            let content = try context.fileSystem.readFile(at: path)
            return .success("Successfully read file: \(path)", data: ["content": content])
        } catch {
            return .failure("Failed to read file at \(path): \(error.localizedDescription)")
        }
    }
}
