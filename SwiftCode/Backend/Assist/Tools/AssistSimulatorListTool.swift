import Foundation

public struct AssistSimulatorListTool: AssistTool {
    public let id = "simulator_list"
    public let name = "List Simulators"
    public let description = "Lists available iOS/tvOS/watchOS simulators with runtime, state, and UDID via simctl."

    public init() {}

    public var capability: ToolCapability { .diagnostics }
    public var riskLevel: ToolRiskLevel { .safeRead }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Lists available simulators. No parameters.",
            properties: [:],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let xcrunPath = "/usr/bin/xcrun"
        guard FileManager.default.fileExists(atPath: xcrunPath) else {
            return .failure("xcrun not found at /usr/bin/xcrun. Install Xcode command line tools first.")
        }
        let (exitCode, stdout, stderr) = runProcess(
            executablePath: xcrunPath,
            arguments: ["simctl", "list", "devices", "-j"],
            workingDirectory: context.workspaceRoot
        )
        guard exitCode == 0 else {
            return .failure("simctl list failed (exit \(exitCode)): \(stderr.trimmingCharacters(in: .whitespacesAndNewlines).suffix(1000))")
        }
        guard let data = stdout.data(using: .utf8),
              let top = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devicesByRuntime = top["devices"] as? [String: Any] else {
            return .failure("Could not parse simctl JSON output.")
        }

        var lines: [String] = []
        var total = 0
        var available = 0
        var booted = 0
        for runtime in devicesByRuntime.keys.sorted() {
            guard let devices = devicesByRuntime[runtime] as? [[String: Any]] else { continue }
            lines.append("Runtime: \(runtime)")
            for device in devices.sorted(by: { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }) {
                let name = device["name"] as? String ?? "(unknown)"
                let udid = device["udid"] as? String ?? "(unknown)"
                let state = device["state"] as? String ?? "(unknown)"
                let isAvailable = device["isAvailable"] as? Bool ?? false
                total += 1
                if isAvailable { available += 1 }
                if state == "Booted" { booted += 1 }
                lines.append("  \(name) (\(udid)) - \(state) - available: \(isAvailable ? "yes" : "no")")
            }
        }
        if total == 0 {
            return .failure("No simulators found. No runtimes or devices are installed.")
        }
        let output = "Simulators: \(total) device(s) across \(devicesByRuntime.keys.count) runtime(s), \(available) available, \(booted) booted.\n" + lines.joined(separator: "\n")
        return .success(output, data: [
            "device_count": "\(total)",
            "runtime_count": "\(devicesByRuntime.keys.count)",
            "available_count": "\(available)",
            "booted_count": "\(booted)"
        ])
    }

    private func runProcess(executablePath: String, arguments: [String], workingDirectory: URL?) -> (exitCode: Int32, stdout: String, stderr: String) {
        AssistToolingSupport.runProcess(executablePath: executablePath, arguments: arguments, workingDirectory: workingDirectory)
    }
}

// MARK: - Artboard Subsystem Tools

@MainActor
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

@MainActor
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

@MainActor
public struct AssistArtboardRunAppTool: AssistTool {
    public let id = "artboard_run_app"
    public let name = "Run Full App"
    public let description = "Builds the active project and runs it directly inside an iOS/macOS simulator, reporting logs and execution status."

    public init() {}

    public var capability: ToolCapability { .compilation }
    public var riskLevel: ToolRiskLevel { .safeMutation }

    public var parametersSchema: JSONSchema {
        JSONSchema(
            type: "object",
            description: "Builds and runs the full app on the target simulator.",
            properties: [:],
            required: []
        )
    }

    public func execute(input: [String: Any], context: AssistContext) async throws -> AssistToolResult {
        let runManager = FullAppRunManager.shared
        if runManager.isRunning {
            return .failure("An application execution run is already in progress.")
        }

        await runManager.runFullApp()

        let logs = runManager.runLogs.joined(separator: "\n")
        let isFailed = logs.localizedCaseInsensitiveContains("failed") || logs.localizedCaseInsensitiveContains("error:")

        if isFailed {
            return .failure("Full app run failed.\nStep: \(runManager.currentStep)\nLogs:\n\(logs.suffix(2000))")
        } else {
            return .success("Full application compiled and launched successfully.\nDuration: \(String(format: "%.1fs", runManager.buildDuration))\nLogs:\n\(logs.suffix(1000))", data: [
                "duration": "\(runManager.buildDuration)",
                "step": runManager.currentStep
            ])
        }
    }
}

@MainActor
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
