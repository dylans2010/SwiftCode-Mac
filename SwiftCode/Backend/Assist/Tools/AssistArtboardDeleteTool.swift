import Foundation

public struct AssistArtboardDeleteTool: AssistTool {
    public let id = "artboard_delete"
    public let name = "Delete Artboard"
    public let description = "Deletes an artboard from the Visual UI Builder canvas by identifier or name."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Deletes an artboard.",
            properties: [
                "identifier": JSONSchema(type: "string", description: "The UUID or name of the artboard to delete.")
            ],
            required: ["identifier"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let doc = DocumentCoordinator.shared.visualUIDocument else {
            return .failure("No active VisualUIDocument found.")
        }
        guard let idStr = input["identifier"] as? String, !idStr.isEmpty else {
            return .failure("Parameter 'identifier' is required.")
        }

        let targetIndex: Int?
        if let uuid = UUID(uuidString: idStr) {
            targetIndex = doc.scene.artboards.firstIndex(where: { $0.id == uuid })
        } else {
            targetIndex = doc.scene.artboards.firstIndex(where: { $0.name.localizedCaseInsensitiveContains(idStr) })
        }

        guard let index = targetIndex else {
            return .failure("No artboard found matching '\(idStr)'.")
        }

        let artboard = doc.scene.artboards[index]
        if artboard.name == "Default" {
            return .failure("The 'Default' artboard cannot be deleted as it is the workspace canvas root.")
        }

        doc.checkpoint()
        let deleted = doc.scene.artboards.remove(at: index)
        if doc.scene.activeArtboardID == deleted.id {
            doc.scene.activeArtboardID = doc.scene.artboards.first?.id
        }
        doc.isDirty = true

        return .success("Artboard '\(deleted.name)' (ID: \(deleted.id.uuidString)) deleted successfully.")
    }
}

@MainActor
