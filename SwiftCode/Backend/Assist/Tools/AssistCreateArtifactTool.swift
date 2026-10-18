import Foundation

public struct AssistCreateArtifactTool: AssistTool {
    public let id = "create_artifact"
    public let name = "Create Artifact"
    public let description = "Creates (or updates/appends) a Markdown artifact in the native artifact store at .assist_temp/artifacts/<name>.md. The single way to produce durable deliverables."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Creates a Markdown artifact.",
            properties: [
                "name": JSONSchema(type: "string", description: "Artifact name, snake_case (.md added automatically). Example: repository_analysis"),
                "content": JSONSchema(type: "string", description: "Full Markdown document content."),
                "description": JSONSchema(type: "string", description: "One-line description shown in the artifact list. Default: first meaningful line."),
                "mode": JSONSchema(type: "string", description: "create (default) | update | append.")
            ],
            required: ["name", "content"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let name = (input["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return .failure("Missing required parameter: name")
        }
        guard let content = input["content"] as? String, !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("Missing required parameter: content (must be non-empty Markdown)")
        }
        let description = (input["description"] as? String) ?? ""
        let modeRaw = ((input["mode"] as? String) ?? "create").lowercased()
        let mode: AssistArtifactMode
        switch modeRaw {
        case "create": mode = .create
        case "update": mode = .update
        case "append": mode = .append
        default: return .failure("Invalid mode '\(modeRaw)'. Use create, update, or append.")
        }
        do {
            let record = try AssistArtifactStore.shared.createArtifact(
                name: name, content: content, description: description,
                mode: mode, workspaceRoot: context.workspaceRoot
            )
            return .success(
                "Artifact '\(record.title)' saved (\(modeRaw)) at \(record.relativePath).",
                data: [
                    "filename": record.filename, "title": record.title,
                    "relativePath": record.relativePath, "mode": modeRaw,
                    "contentLength": "\(content.count)"
                ],
                filesChanged: [record.relativePath]
            )
        } catch let e as AssistArtifactError {
            return .failure(e.localizedDescription)
        } catch {
            return .failure("Failed to create artifact: \(error.localizedDescription)")
        }
    }
}
