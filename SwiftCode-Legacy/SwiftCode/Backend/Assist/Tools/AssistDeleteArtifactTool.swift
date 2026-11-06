import Foundation

public struct AssistDeleteArtifactTool: AssistTool {
    public let id = "delete_artifact"
    public let name = "Delete Artifact"
    public let description = "Permanently deletes a Markdown artifact from the native artifact store. agent_notes.md is protected and cannot be deleted."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .potentiallyDestructive }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Deletes an artifact permanently.",
            properties: [
                "name": JSONSchema(type: "string", description: "Artifact name (snake_case, .md optional)."),
                "confirm": JSONSchema(type: "boolean", description: "Must be true to delete. Safety interlock.")
            ],
            required: ["name", "confirm"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let name = (input["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return .failure("Missing required parameter: name")
        }
        guard (input["confirm"] as? Bool) == true else {
            return .failure("Deletion requires confirm: true. The artifact was NOT deleted.")
        }
        do {
            let filename = try AssistArtifactStore.shared.deleteArtifact(name: name, workspaceRoot: context.workspaceRoot)
            return .success("Artifact '\(filename)' deleted permanently.", data: ["filename": filename])
        } catch let e as AssistArtifactError {
            return .failure(e.localizedDescription)
        } catch {
            return .failure("Failed to delete artifact: \(error.localizedDescription)")
        }
    }
}
