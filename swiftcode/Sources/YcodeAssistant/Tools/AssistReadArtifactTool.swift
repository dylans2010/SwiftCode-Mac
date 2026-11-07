import Foundation

public struct AssistReadArtifactTool: AssistTool {
    public let id = "read_artifact"
    public let name = "Read Artifact"
    public let description = "Reads a Markdown artifact's full content from the native artifact store (truncated at 60k characters)."

    public init() {}

    public var capability: ToolCapability { .fileReading }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Reads an artifact's content.",
            properties: [
                "name": JSONSchema(type: "string", description: "Artifact name (snake_case, .md optional). Example: repository_analysis")
            ],
            required: ["name"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let name = (input["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return .failure("Missing required parameter: name")
        }
        do {
            let (record, content, wasTruncated) = try AssistArtifactStore.shared.readArtifact(
                name: name, workspaceRoot: context.workspaceRoot
            )
            return .success(
                "# \(record.title)\n\n\(content)",
                data: [
                    "filename": record.filename, "title": record.title,
                    "kind": record.kind.rawValue, "truncated": wasTruncated ? "true" : "false",
                    "contentLength": "\(content.count)"
                ]
            )
        } catch let e as AssistArtifactError {
            return .failure(e.localizedDescription)
        } catch {
            return .failure("Failed to read artifact: \(error.localizedDescription)")
        }
    }
}
