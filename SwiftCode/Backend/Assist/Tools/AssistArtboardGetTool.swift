import Foundation

public struct AssistArtboardGetTool: AssistTool {
    public let id = "artboard_get"
    public let name = "Get Artboard Details"
    public let description = "Retrieves full configuration, component tree hierarchy, and custom SwiftUI source code for a specified artboard."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Retrieves details of an artboard by identifier or name.",
            properties: [
                "identifier": JSONSchema(
                    type: "string",
                    description: "The name or UUID of the artboard to inspect. If omitted, inspects the active artboard."
                )
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let doc = DocumentCoordinator.shared.visualUIDocument ?? VisualUIDocument()
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
            return .failure("Artboard matching '\(identifier ?? "active")' not found. Use 'artboard_list' to view available artboards.")
        }

        var lines: [String] = []
        lines.append("Artboard: \(artboard.name)")
        lines.append("  ID: \(artboard.id.uuidString)")
        lines.append("  Device Frame: \(artboard.deviceFrame)")
        lines.append("  Appearance: \(artboard.appearance ?? "System")")
        lines.append("  Orientation: \(artboard.isPortrait == false ? "Landscape" : "Portrait")")
        lines.append("  Dynamic Type: \(artboard.dynamicTypeSize ?? "Medium")")
        lines.append("  Scale: \(artboard.previewScale ?? 1.0)")
        lines.append("  Safe Areas: \(artboard.showSafeAreas ?? true ? "Visible" : "Hidden")")

        if let error = DocumentCoordinator.shared.compiledArtboardErrors[artboard.id] {
            lines.append("  Compile Error: \(error)")
        }

        if let source = artboard.customSwiftUISource, !source.isEmpty {
            lines.append("\nCustom SwiftUI Source Code:")
            lines.append("----------------------------")
            lines.append(source)
        } else {
            lines.append("\nComponent Hierarchy:")
            lines.append("--------------------")
            describeNode(artboard.rootNode, indent: 0, into: &lines)
        }

        return .success(lines.joined(separator: "\n"), data: [
            "id": artboard.id.uuidString,
            "name": artboard.name,
            "deviceFrame": artboard.deviceFrame,
            "hasCustomSource": (artboard.customSwiftUISource != nil && !artboard.customSwiftUISource!.isEmpty) ? "true" : "false"
        ])
    }

    private func describeNode(_ node: VisualComponentNode, indent: Int, into lines: inout [String]) {
        let prefix = String(repeating: "  ", count: indent)
        var propDesc: [String] = []
        if let txt = node.properties["textValue"] { propDesc.append("text: \"\(txt)\"") }
        if let sym = node.properties["sfSymbolName"] { propDesc.append("symbol: \"\(sym)\"") }
        let propStr = propDesc.isEmpty ? "" : " (\(propDesc.joined(separator: ", ")))"
        lines.append("\(prefix)- [\(node.type.rawValue)] \(node.name)\(propStr)")
        for child in node.children {
            describeNode(child, indent: indent + 1, into: &lines)
        }
    }
}

@MainActor
