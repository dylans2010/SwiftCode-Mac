import Foundation

public struct AssistArtboardListTool: AssistTool {
    public let id = "artboard_list"
    public let name = "List Artboards"
    public let description = "Lists all artboards in the active Visual UI Builder workspace, including IDs, device frames, appearance, and component counts."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Lists all artboards in the current document.",
            properties: [:],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let doc = DocumentCoordinator.shared.visualUIDocument ?? VisualUIDocument()
        if DocumentCoordinator.shared.visualUIDocument == nil {
            DocumentCoordinator.shared.visualUIDocument = doc
        }

        let artboards = doc.scene.artboards
        if artboards.isEmpty {
            return .success("No artboards currently configured in workspace.", data: ["artboard_count": "0"])
        }

        var lines: [String] = []
        lines.append("Found \(artboards.count) artboard(s):")

        for (index, board) in artboards.enumerated() {
            let activeMarker = (board.id == doc.scene.activeArtboardID) ? " [ACTIVE]" : ""
            let hasCustomSource = (board.customSwiftUISource != nil && !board.customSwiftUISource!.isEmpty) ? "custom source" : "component tree"
            let childCount = board.rootNode.children.count
            lines.append("  \(index + 1). \"\(board.name)\" (ID: \(board.id.uuidString))\(activeMarker)")
            lines.append("     Device Frame: \(board.deviceFrame)")
            lines.append("     Mode: \(hasCustomSource) (Root: \(board.rootNode.type.rawValue), Children: \(childCount))")
            lines.append("     Appearance: \(board.appearance ?? "System"), Orientation: \(board.isPortrait == false ? "Landscape" : "Portrait")")
        }

        return .success(lines.joined(separator: "\n"), data: [
            "artboard_count": "\(artboards.count)",
            "active_artboard_id": doc.scene.activeArtboardID?.uuidString ?? ""
        ])
    }
}

@MainActor
