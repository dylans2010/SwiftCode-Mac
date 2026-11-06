// STAGED PORT — SwiftCode-Legacy `SwiftCode/Backend/Assist/Tools/AssistArtboardCompileTool.swift` (main ab03f681; Dylan's own code, direct port authorised under MIT).
// Staged by migration subagent A3 (Assist systems / tools / execution) — NOT yet landed in the repo.
// Target: SwiftCodeMCP (`swiftcode/Sources/SwiftCodeMCP/Tools/Assist/AssistArtboardCompileTool.swift`).
// Body is Legacy verbatim unless noted under ADAPTATIONS below. No Swift toolchain exists
// in this environment: static checks only — never claim a build passed.
// Audit gap this port closes (claimed-covered-audit):
//   - Active-document fallback: Legacy compiled the active SwiftUI file (or validated the preview pipeline) when no artboard matched; destination throws when the artboard has no custom SwiftUI source and the MCP host has no active document to fall back to.
// ADAPTATIONS: none — verbatim body (imports adjusted only as noted).
// UNRESOLVED DEPENDENCIES (no definition in the destination yet; resolve as the owning ports land):
//   - DocumentCoordinator — other agent (editor-visual-artboards) (`SwiftCode/Core/Editor/DocumentCoordinator.swift`)
//   - PreviewManager — other agent (other) (`SwiftCode/Core/Preview/PreviewManager.swift`)
//   - SwiftViewDetector — UNOWNED (no worklist) (`SwiftCode/Core/Preview/PreviewDiscoveryService.swift`)
//   - ToolCapability — A6 (ALL-MISSING) (`SwiftCode/Backend/Assist/AssistToolRouter.swift`)
//   - ToolRiskLevel — A6 (ALL-MISSING) (`SwiftCode/Backend/Assist/AssistToolRouter.swift`)
// WIRING / REGISTRATION: MCP catalogue: swiftcode/Sources/SwiftCodeMCP/Tools/SwiftCodeTools+Artboards.swift — wire the matching MCP tool handler to this legacy class (or adopt its behaviour); AssistToolRegistry (staged) is the dynamic registry for register/unregister + health + caching once tools land.

import Foundation
import SwiftCodeAssistant

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
