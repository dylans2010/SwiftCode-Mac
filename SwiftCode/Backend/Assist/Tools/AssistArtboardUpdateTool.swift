import Foundation

public struct AssistArtboardUpdateTool: AssistTool {
    public let id = "artboard_update"
    public let name = "Update Artboard"
    public let description = "Updates an existing artboard's source code, device frame, appearance, or properties."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Updates an existing artboard.",
            properties: [
                "identifier": JSONSchema(type: "string", description: "The UUID or name of the artboard to update. Defaults to active artboard."),
                "name": JSONSchema(type: "string", description: "New name for the artboard."),
                "deviceFrame": JSONSchema(type: "string", description: "New device simulator frame."),
                "sourceCode": JSONSchema(type: "string", description: "Updated custom SwiftUI source code."),
                "appearance": JSONSchema(type: "string", description: "'System', 'Light', or 'Dark'."),
                "isPortrait": JSONSchema(type: "boolean", description: "Orientation: true for portrait, false for landscape.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let doc = DocumentCoordinator.shared.visualUIDocument else {
            return .failure("No active VisualUIDocument found.")
        }

        let identifier = input["identifier"] as? String
        let target: VisualUIArtboard?
        if let idStr = identifier, !idStr.isEmpty {
            if let uuid = UUID(uuidString: idStr) {
                target = doc.scene.artboards.first(where: { $0.id == uuid })
            } else {
                target = doc.scene.artboards.first(where: { $0.name.localizedCaseInsensitiveContains(idStr) })
            }
        } else {
            if let activeID = doc.scene.activeArtboardID {
                target = doc.scene.artboards.first(where: { $0.id == activeID })
            } else {
                target = doc.scene.artboards.first
            }
        }

        guard let artboard = target else {
            return .failure("Artboard not found matching '\(identifier ?? "active")'.")
        }

        doc.checkpoint()

        var updatedFields: [String] = []

        if let newName = input["name"] as? String {
            artboard.name = newName
            updatedFields.append("name: '\(newName)'")
        }
        if let newDevice = input["deviceFrame"] as? String {
            artboard.deviceFrame = newDevice
            updatedFields.append("deviceFrame: '\(newDevice)'")
        }
        if let newSource = input["sourceCode"] as? String {
            artboard.customSwiftUISource = newSource
            DocumentCoordinator.shared.compiledArtboardErrors.removeValue(forKey: artboard.id)
            updatedFields.append("sourceCode (length: \(newSource.count))")
        }
        if let appearance = input["appearance"] as? String {
            artboard.appearance = appearance
            updatedFields.append("appearance: '\(appearance)'")
        }
        if let isPortrait = input["isPortrait"] as? Bool {
            artboard.isPortrait = isPortrait
            updatedFields.append("isPortrait: \(isPortrait)")
        }

        doc.isDirty = true

        return .success("Updated artboard '\(artboard.name)': \(updatedFields.joined(separator: ", "))", data: [
            "id": artboard.id.uuidString,
            "name": artboard.name
        ])
    }
}

@MainActor
