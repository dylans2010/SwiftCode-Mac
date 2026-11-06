import Foundation

public struct AssistArtboardCompileTool: AssistTool {
    public let id = "artboard_compile"
    public let name = "Compile Artboard Preview"
    public let description = "Triggers compilation and preview generation of a custom artboard or the active SwiftUI file."

    public init() {}

    public var capability: ToolCapability { .compilation }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Compiles an artboard or active SwiftUI document for live preview.",
            properties: [
                "identifier": JSONSchema(type: "string", description: "Optional artboard UUID or name to compile. If omitted, compiles active document/artboard."),
                "targetView": JSONSchema(type: "string", description: "Optional name of the SwiftUI View or #Preview target to compile.")
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let identifier = input["identifier"] as? String
        let targetView = input["targetView"] as? String

        if let doc = DocumentCoordinator.shared.visualUIDocument,
           let idStr = identifier,
           let artboard = doc.scene.artboards.first(where: { $0.id.uuidString == idStr || $0.name.localizedCaseInsensitiveContains(idStr) }) {
            doc.scene.activeArtboardID = artboard.id

            if let source = artboard.customSwiftUISource, !source.isEmpty {
                let (preparedCode, _) = SwiftViewDetector.prepareSourceCode(source, filename: "\(artboard.name).swift")
                await PreviewManager.shared.startFreshLivePreviewSession(
                    sourcePath: "\(artboard.name).swift",
                    sourceCode: preparedCode,
                    targetViewName: targetView ?? artboard.name
                )
            }
        } else if let activeDoc = DocumentCoordinator.shared.activeDocument {
            let (preparedCode, _) = SwiftViewDetector.prepareSourceCode(activeDoc.content, filename: activeDoc.url.path)
            await PreviewManager.shared.startFreshLivePreviewSession(
                sourcePath: activeDoc.url.path,
                sourceCode: preparedCode,
                targetViewName: targetView ?? PreviewManager.shared.selectedPreviewName
            )
        } else {
            try await PreviewManager.shared.validatePreviewBuildPipeline()
        }

        let logs = PreviewManager.shared.buildLogs.joined(separator: "\n")
        let isFailed = logs.localizedCaseInsensitiveContains("failed") || logs.localizedCaseInsensitiveContains("error:")
        let hosted = PreviewManager.shared.hostedView != nil

        if isFailed && !hosted {
            return .failure("Artboard preview compilation failed.\nLogs:\n\(logs)")
        } else {
            return .success("Artboard compiled successfully.\nHosted View: \(hosted ? "Ready" : "Building")\nLogs:\n\(logs.suffix(1000))", data: [
                "status": hosted ? "success" : "in_progress",
                "preview_target": PreviewManager.shared.selectedPreviewName ?? ""
            ])
        }
    }
}
