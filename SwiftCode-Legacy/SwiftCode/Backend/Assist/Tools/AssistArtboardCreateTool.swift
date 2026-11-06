import Foundation

public struct AssistArtboardCreateTool: AssistTool {
    public let id = "artboard_create"
    public let name = "Create Artboard"
    public let description = "Creates a new artboard in the Visual UI Builder with custom SwiftUI code or standard component layout."

    public init() {}

    public var capability: ToolCapability { .fileModification }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Creates a new artboard in the active document.",
            properties: [
                "name": JSONSchema(type: "string", description: "Name of the new artboard (e.g., 'SettingsView', 'ProfileCanvas')."),
                "deviceFrame": JSONSchema(type: "string", description: "Target device simulator frame (e.g., 'iPhone 16 Pro', 'iPad Pro'). Defaults to 'iPhone 16 Pro'."),
                "sourceCode": JSONSchema(type: "string", description: "Optional custom SwiftUI source code with #Preview to render in this artboard."),
                "appearance": JSONSchema(type: "string", description: "Color appearance: 'System', 'Light', or 'Dark'. Defaults to 'System'."),
                "isPortrait": JSONSchema(type: "boolean", description: "Orientation: true for portrait, false for landscape. Defaults to true.")
            ],
            required: ["name"]
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        guard let name = input["name"] as? String, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("Parameter 'name' is required.")
        }

        let doc = DocumentCoordinator.shared.visualUIDocument ?? VisualUIDocument()
        if DocumentCoordinator.shared.visualUIDocument == nil {
            DocumentCoordinator.shared.visualUIDocument = doc
        }

        let deviceFrame = input["deviceFrame"] as? String ?? "iPhone 16 Pro"
        let sourceCode = input["sourceCode"] as? String
        let appearance = input["appearance"] as? String ?? "System"
        let isPortrait = input["isPortrait"] as? Bool ?? true

        let rootNode = VisualComponentNode(type: .vStack, name: "\(name) Root")
        let artboard = VisualUIArtboard(
            name: name,
            deviceFrame: deviceFrame,
            rootNode: rootNode,
            customSwiftUISource: sourceCode,
            appearance: appearance,
            isPortrait: isPortrait
        )

        doc.checkpoint()
        doc.scene.artboards.append(artboard)
        doc.scene.activeArtboardID = artboard.id
        doc.isDirty = true

        return .success("Successfully created artboard '\(name)' (ID: \(artboard.id.uuidString)) with frame '\(deviceFrame)'.", data: [
            "id": artboard.id.uuidString,
            "name": name,
            "deviceFrame": deviceFrame
        ])
    }
}
