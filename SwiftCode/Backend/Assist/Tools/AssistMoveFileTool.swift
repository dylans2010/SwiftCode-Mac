import Foundation

public struct AssistMoveFileTool: AssistTool {
    public let id = "file_move"
    public let name = "Move File"
    public let description = "Moves a file from source to destination path."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Moves a file from a source path to a destination path.",
            properties: [
                "source": JSONSchema(type: "string", description: "Workspace-relative path of the existing file to move."),
                "destination": JSONSchema(type: "string", description: "Workspace-relative destination path.")
            ],
            required: ["source", "destination"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let source = input["source"] as? String else {
            return .failure("Missing required parameter: source")
        }
        guard let destination = input["destination"] as? String else {
            return .failure("Missing required parameter: destination")
        }

        do {
            try context.fileSystem.moveFile(from: source, to: destination)
            return .success("Successfully moved file from \(source) to \(destination)")
        } catch {
            return .failure("Failed to move file: \(error.localizedDescription)")
        }
    }
}
