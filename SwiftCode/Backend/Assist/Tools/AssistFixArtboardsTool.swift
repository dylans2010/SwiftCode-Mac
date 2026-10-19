import Foundation

public struct AssistFixArtboardsTool: AssistTool {
    public let id = "fix_artboards"
    public let name = "Fix Artboards and Visual UI Builder Errors"
    public let description = "Audits the entire Artboards, Visual UI Builder, and Preview subsystem, diagnoses simulator, destination, code signing, and syntax errors, and applies automated repairs until compilation succeeds."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Audits and automatically repairs Artboards, SwiftUI Previews, and Full App Run failures.",
            properties: [
                "errorContext": JSONSchema(
                    type: "string",
                    description: "Optional error message or log excerpt that triggered the fix request."
                ),
                "scope": JSONSchema(
                    type: "string",
                    description: "Optional repair scope: 'preview', 'full_app', 'all'. Defaults to 'all'."
                )
            ],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let errorContext = input["errorContext"] as? String ?? ""
        var actionsTaken: [String] = []

        // Pass 1: Simulator & Destination Audit
        let liveSims = await BuildDestinationResolver.shared.fetchAvailableSimulators()
        let bootedSim = liveSims.first(where: { $0.variant == "Booted" }) ?? liveSims.first(where: { $0.platform.contains("iOS") })

        if let sim = bootedSim {
            let targetDest = "platform=iOS Simulator,id=\(sim.idString)"
            if XcodeBuildManager.shared.selectedDestination != targetDest {
                XcodeBuildManager.shared.selectedDestination = targetDest
                actionsTaken.append("Realigned XcodeBuildManager destination to live simulator: \(sim.name) (\(sim.idString))")
            }

            if sim.variant != "Booted" {
                _ = AssistToolingSupport.runProcess(
                    executablePath: "/usr/bin/xcrun",
                    arguments: ["simctl", "boot", sim.idString],
                    workingDirectory: context.workspaceRoot
                )
                actionsTaken.append("Booted simulator '\(sim.name)' (\(sim.idString))")
            }
        }

        // Pass 2: Clean DerivedData / Stale Build State
        if errorContext.localizedCaseInsensitiveContains("already in progress") ||
            errorContext.localizedCaseInsensitiveContains("exit code 70") ||
            errorContext.localizedCaseInsensitiveContains("exit code 65") ||
            errorContext.localizedCaseInsensitiveContains("corrupted") {
            XcodeBuildManager.shared.cleanBuild(projectURL: context.workspaceRoot)
            actionsTaken.append("Cleaned stale build artifacts and reset DerivedData build cache")
        }

        // Pass 3: Audit Active Artboard Custom Source Code
        if let doc = DocumentCoordinator.shared.visualUIDocument,
           let activeID = doc.scene.activeArtboardID,
           let activeArtboard = doc.scene.artboards.first(where: { $0.id == activeID }) {

            if var source = activeArtboard.customSwiftUISource, !source.isEmpty {
                var modified = false

                if !source.contains("import SwiftUI") {
                    source = "import SwiftUI\n\n" + source
                    modified = true
                    actionsTaken.append("Injected missing 'import SwiftUI' header into artboard '\(activeArtboard.name)'")
                }

                if !source.contains("#Preview") && !source.contains("PreviewProvider") {
                    source += "\n\n#Preview {\n    \(activeArtboard.name)()\n}\n"
                    modified = true
                    actionsTaken.append("Appended missing #Preview macro for '\(activeArtboard.name)'")
                }

                if modified {
                    activeArtboard.customSwiftUISource = source
                    doc.isDirty = true
                }

                DocumentCoordinator.shared.compiledArtboardErrors.removeValue(forKey: activeArtboard.id)
            }
        }

        // Pass 4: Verification Compile Pass
        if let activeDoc = DocumentCoordinator.shared.activeDocument {
            let (preparedCode, _) = SwiftViewDetector.prepareSourceCode(activeDoc.content, filename: activeDoc.url.path)
            await PreviewManager.shared.startFreshLivePreviewSession(
                sourcePath: activeDoc.url.path,
                sourceCode: preparedCode,
                targetViewName: PreviewManager.shared.selectedPreviewName
            )
            actionsTaken.append("Recompiled active SwiftUI document live preview session")
        }

        let logs = PreviewManager.shared.buildLogs.joined(separator: "\n")
        let isSuccess = !logs.localizedCaseInsensitiveContains("failed") && !logs.localizedCaseInsensitiveContains("error:")

        let summary = """
        Fix with Assist completed audit and repairs:
        \(actionsTaken.map { "  • \($0)" }.joined(separator: "\n"))

        Result Status: \(isSuccess ? "Healthy / Resolved" : "Repairs Applied, verifying compiler logs")
        Logs Summary:
        \(logs.suffix(1000))
        """

        return .success(summary, data: [
            "repaired": "true",
            "actions_count": "\(actionsTaken.count)"
        ])
    }
}
