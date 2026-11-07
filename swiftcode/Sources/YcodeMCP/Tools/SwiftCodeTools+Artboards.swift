import Foundation
import YcodeAssistant
import YcodeIDECore
import YcodePreviews

extension SwiftCodeMCPHost {
    var artboardTools: [MCPTool] {
        let safeMutation = MCPToolAnnotations(readOnly: false, idempotent: true)
        return [
            tool("artboard_compile", "Compile Artboard Preview",
                 "Triggers compilation and preview generation of a custom artboard or the active SwiftUI file.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "identifier": Schema.string("Optional artboard UUID or name to compile. If omitted, compiles active document/artboard."),
                                       "targetView": Schema.string("Optional name of the SwiftUI View or #Preview target to compile.")]),
                 output: Schema.output(["status": Schema.str, "preview_target": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.compileArtboard(call)
            },
            tool("artboard_create", "Create Artboard",
                 "Creates a new artboard in the Visual UI Builder with custom SwiftUI code or standard component layout.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "name": Schema.string("Name of the new artboard (e.g., 'SettingsView', 'ProfileCanvas')."),
                                       "deviceFrame": Schema.string("Target device simulator frame (e.g., 'iPhone 16 Pro', 'iPad Pro'). Defaults to 'iPhone 16 Pro'."),
                                       "sourceCode": Schema.string("Optional custom SwiftUI source code with #Preview to render in this artboard."),
                                       "appearance": Schema.string("Color appearance: 'System', 'Light', or 'Dark'. Defaults to 'System'."),
                                       "isPortrait": Schema.boolean("Orientation: true for portrait, false for landscape. Defaults to true.")],
                                      required: ["name"]),
                 output: Schema.output(["id": Schema.str, "name": Schema.str, "deviceFrame": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.createArtboard(call)
            },
            tool("artboard_delete", "Delete Artboard",
                 "Deletes an artboard from the Visual UI Builder canvas by identifier or name.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "identifier": Schema.string("The UUID or name of the artboard to delete.")],
                                      required: ["identifier"]),
                 output: Schema.output(["id": Schema.str, "name": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.deleteArtboard(call)
            },
            tool("artboard_get", "Get Artboard Details",
                 "Retrieves full configuration, component tree hierarchy, and custom SwiftUI source code for a specified artboard.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "identifier": Schema.string("The name or UUID of the artboard to inspect. If omitted, inspects the active artboard.")]),
                 output: Schema.output(["id": Schema.str, "name": Schema.str, "deviceFrame": Schema.str, "hasCustomSource": Schema.bool])) { h, call in
                try h.getArtboard(call)
            },
            tool("artboard_list", "List Artboards",
                 "Lists all artboards in the active Visual UI Builder workspace, including IDs, device frames, appearance, and component counts.",
                 input: Schema.object(["workspace": Schema.workspace]),
                 output: Schema.output(["artboard_count": Schema.int, "active_artboard_id": Schema.str, "artboards": Schema.anyArray])) { h, call in
                h.listArtboards(call)
            },
            tool("artboard_run_app", "Run Full App",
                 "Builds the active project and runs it directly inside an iOS/macOS simulator, reporting logs and execution status.",
                 input: Schema.object(["workspace": Schema.workspace]),
                 output: Schema.output(["runId": Schema.str, "state": Schema.str, "output": Schema.anyArray]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.runArtboardApp(call)
            },
            tool("artboard_update", "Update Artboard",
                 "Updates an existing artboard's source code, device frame, appearance, or properties.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "identifier": Schema.string("The UUID or name of the artboard to update. Defaults to active artboard."),
                                       "name": Schema.string("New name for the artboard."),
                                       "deviceFrame": Schema.string("New device simulator frame."),
                                       "sourceCode": Schema.string("Updated custom SwiftUI source code."),
                                       "appearance": Schema.string("'System', 'Light', or 'Dark'."),
                                       "isPortrait": Schema.boolean("Orientation: true for portrait, false for landscape.")]),
                 output: Schema.output(["id": Schema.str, "name": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.updateArtboard(call)
            },
            tool("fix_artboards", "Fix Artboards and Visual UI Builder Errors",
                 "Audits the entire Artboards, Visual UI Builder, and Preview subsystem, diagnoses simulator, destination, code signing, and syntax errors, and applies automated repairs until compilation succeeds.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "errorContext": Schema.string("Optional error message or log excerpt that triggered the fix request."),
                                       "scope": Schema.string("Optional repair scope: 'preview', 'full_app', 'all'. Defaults to 'all'.")]),
                 output: Schema.output(["repaired": Schema.bool, "actions_count": Schema.int]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.fixArtboards(call)
            },
        ]
    }

    func artboardIndex(matching identifier: String?) -> Int? {
        if let idStr = identifier, !idStr.isEmpty {
            if let uuid = UUID(uuidString: idStr) {
                return artboards.firstIndex(where: { $0.id == uuid })
            }
            return artboards.firstIndex(where: { $0.name.localizedCaseInsensitiveContains(idStr) })
        }
        if let active = activeArtboardID {
            return artboards.firstIndex(where: { $0.id == active }) ?? artboards.indices.first
        }
        return artboards.indices.first
    }

    func artboardWorkspaceFolder(for call: MCPToolCall) -> URL? {
        guard let session = try? session(for: call) else { return nil }
        return Self.folder(of: session.model)
    }

    func ensureArtboardsLoaded(for folder: URL) {
        guard artboards.isEmpty else { return }
        guard let document = ArtboardStore.load(forWorkspace: folder) else { return }
        artboards = document.artboards
        activeArtboardID = document.activeArtboardID
    }

    public func reloadArtboardsFromStore(workspaceFolder folder: URL) {
        guard let document = ArtboardStore.load(forWorkspace: folder) else {
            artboards = []
            activeArtboardID = nil
            return
        }
        artboards = document.artboards
        activeArtboardID = document.activeArtboardID
    }

    func saveArtboards(for folder: URL?) {
        guard let folder else { return }
        let document = ArtboardDocument(artboards: artboards, activeArtboardID: activeArtboardID)
        try? ArtboardStore.save(document, forWorkspace: folder)
    }

    func compileArtboard(_ call: MCPToolCall) async throws -> MCPToolResult {
        let folder = artboardWorkspaceFolder(for: call)
        if let folder { ensureArtboardsLoaded(for: folder) }
        let identifier = call.string("identifier")
        guard let index = artboardIndex(matching: identifier) else {
            if let active = try await compileActiveFile(call) {
                return active
            }
            throw MCPToolError(identifier == nil
                ? "No artboards currently configured in workspace."
                : "Artboard matching '\(identifier!)' not found. Use 'artboard_list' to view available artboards.")
        }
        let artboard = artboards[index]
        guard let source = artboard.customSwiftUISource, !source.isEmpty else {
            throw MCPToolError("Artboard '\(artboard.name)' has no custom SwiftUI source to compile (the MCP host has no active document to fall back to). Give it source with artboard_update, or render a file's preview with preview_render.")
        }
        try await approveChangeWithoutFile(tool: call.name,
                                           summary: "Compile artboard '\(artboard.name)' (render its preview)",
                                           call: call)
        let result = await compileArtboardRecord(at: index, targetView: call.string("targetView"))
        saveArtboards(for: folder)
        return result
    }

    func renderArtboardSource(at index: Int, targetView: String?) async -> (png: Data?, log: String, succeeded: Bool) {
        let artboard = artboards[index]
        guard let source = artboard.customSwiftUISource, !source.isEmpty else {
            return (nil, "", false)
        }
        return await renderSwiftUISource(source, filename: "\(artboard.name).swift", targetView: targetView)
    }

    func renderSwiftUISource(_ source: String, filename: String, targetView: String?) async -> (png: Data?, log: String, succeeded: Bool) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-artboard-\(UUID().uuidString)")
        let file = dir.appendingPathComponent(filename)
        let out = dir.appendingPathComponent("preview.png")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try source.write(to: file, atomically: true, encoding: .utf8)
        } catch {
            return (nil, "cannot write the artboard source for rendering: \(error.localizedDescription)", false)
        }
        defer { try? FileManager.default.removeItem(at: dir) }
        let starts = [URL(fileURLWithPath: FileManager.default.currentDirectoryPath)]
        let result = (await Task.detached {
            PreviewRenderRunner.render(file: file.path, name: targetView, output: out.path, starts: starts) { _ in }
        }.value)
        switch result {
        case .success(let pngURL):
            guard let data = try? Data(contentsOf: pngURL) else {
                return (nil, "the renderer wrote no image", false)
            }
            return (data, "", true)
        case .failure(let failure):
            let log = failure.description + (failure.log.isEmpty ? "" : "\n" + failure.log)
            return (nil, log, false)
        }
    }

    func compileArtboardRecord(at index: Int, targetView: String?) async -> MCPToolResult {
        let artboard = artboards[index]
        let target = targetView ?? artboard.name
        let render = await renderArtboardSource(at: index, targetView: targetView)
        if render.succeeded, let png = render.png {
            artboards[index].lastCompileError = nil
            let summary = "Artboard compiled successfully.\nHosted View: Ready"
            return MCPToolResult(content: [.imageBlock(png), .textBlock(summary)],
                                 structured: ["status": .string("success"), "preview_target": .string(target)])
        }
        let log = render.log
        artboards[index].lastCompileError = log
        return .error("Artboard preview compilation failed.\nLogs:\n\(log)",
                      structured: ["status": .string("failed"), "preview_target": .string(target)])
    }

    func compileActiveFile(_ call: MCPToolCall) async throws -> MCPToolResult? {
        guard let path = delegate?.mcpHostActiveFilePath(), !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        guard url.pathExtension.lowercased() == "swift" else { return nil }
        let source = delegate?.mcpHostText(ofOpenFile: path) ?? (try? String(contentsOf: url, encoding: .utf8))
        guard let source, !source.isEmpty else { return nil }
        let targetView = call.string("targetView")
        try await approveChangeWithoutFile(tool: call.name,
                                           summary: "Compile active file '\(url.lastPathComponent)' (render its preview)",
                                           call: call)
        let render = await renderSwiftUISource(source, filename: url.lastPathComponent, targetView: targetView)
        if render.succeeded, let png = render.png {
            return MCPToolResult(content: [.imageBlock(png), .textBlock("Artboard compiled successfully.\nHosted View: Ready")],
                                 structured: ["status": .string("success"), "preview_target": .string(targetView ?? url.deletingPathExtension().lastPathComponent)])
        }
        return .error("Artboard preview compilation failed.\nLogs:\n\(render.log)",
                      structured: ["status": .string("failed"), "preview_target": .string(targetView ?? url.deletingPathExtension().lastPathComponent)])
    }

    func createArtboard(_ call: MCPToolCall) async throws -> MCPToolResult {
        let rawName = try call.require("name")
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw MCPToolError("Parameter 'name' is required.") }
        let deviceFrame = call.string("deviceFrame") ?? "iPhone 16 Pro"
        let sourceCode = call.string("sourceCode")
        let appearance = call.string("appearance") ?? "System"
        let isPortrait = call.bool("isPortrait") ?? true
        let folder = artboardWorkspaceFolder(for: call)
        if let folder { ensureArtboardsLoaded(for: folder) }
        try await approveChangeWithoutFile(tool: call.name,
                                           summary: "Create artboard '\(name)' with frame '\(deviceFrame)'",
                                           call: call)
        let artboard = ArtboardRecord(id: UUID(), name: name, deviceFrame: deviceFrame,
                                      customSwiftUISource: sourceCode, appearance: appearance,
                                      isPortrait: isPortrait,
                                      rootNode: ArtboardRecord.defaultRoot(name: name))
        artboards.append(artboard)
        activeArtboardID = artboard.id
        saveArtboards(for: folder)
        return .structured(["id": .string(artboard.id.uuidString), "name": .string(name),
                            "deviceFrame": .string(deviceFrame)],
                           summary: "Successfully created artboard '\(name)' (ID: \(artboard.id.uuidString)) with frame '\(deviceFrame)'.")
    }

    func deleteArtboard(_ call: MCPToolCall) async throws -> MCPToolResult {
        let folder = artboardWorkspaceFolder(for: call)
        if let folder { ensureArtboardsLoaded(for: folder) }
        guard !artboards.isEmpty else {
            throw MCPToolError("No artboards currently configured in workspace.")
        }
        let idStr = try call.require("identifier")
        guard let index = artboardIndex(matching: idStr) else {
            throw MCPToolError("No artboard found matching '\(idStr)'.")
        }
        let artboard = artboards[index]
        if artboard.name == "Default" {
            throw MCPToolError("The 'Default' artboard cannot be deleted as it is the workspace canvas root.")
        }
        try await approveChangeWithoutFile(tool: call.name,
                                           summary: "Delete artboard '\(artboard.name)'",
                                           call: call)
        artboards.remove(at: index)
        if activeArtboardID == artboard.id {
            activeArtboardID = artboards.first?.id
        }
        saveArtboards(for: folder)
        return .structured(["id": .string(artboard.id.uuidString), "name": .string(artboard.name)],
                           summary: "Artboard '\(artboard.name)' (ID: \(artboard.id.uuidString)) deleted successfully.")
    }

    func getArtboard(_ call: MCPToolCall) throws -> MCPToolResult {
        let folder = artboardWorkspaceFolder(for: call)
        if let folder { ensureArtboardsLoaded(for: folder) }
        let identifier = call.string("identifier")
        guard let index = artboardIndex(matching: identifier) else {
            throw MCPToolError("Artboard matching '\(identifier ?? "active")' not found. Use 'artboard_list' to view available artboards.")
        }
        let artboard = artboards[index]
        var lines: [String] = []
        lines.append("Artboard: \(artboard.name)")
        lines.append("  ID: \(artboard.id.uuidString)")
        lines.append("  Device Frame: \(artboard.deviceFrame)")
        lines.append("  Appearance: \(artboard.appearance)")
        lines.append("  Orientation: \(artboard.isPortrait ? "Portrait" : "Landscape")")
        lines.append("  Dynamic Type: \(artboard.dynamicTypeSize ?? "Medium")")
        lines.append("  Scale: \(artboard.previewScale ?? 1.0)")
        lines.append("  Safe Areas: \(artboard.showSafeAreas ?? true ? "Visible" : "Hidden")")
        if let error = artboard.lastCompileError {
            lines.append("  Compile Error: \(error)")
        }
        if let source = artboard.customSwiftUISource, !source.isEmpty {
            lines.append("\nCustom SwiftUI Source Code:")
            lines.append("----------------------------")
            lines.append(source)
        } else {
            lines.append("\nComponent Hierarchy:")
            lines.append("--------------------")
            func describe(_ node: ArtboardComponentNode, depth: Int) {
                let flags = (node.isHidden ? " (hidden)" : "") + (node.isLocked ? " (locked)" : "")
                lines.append(String(repeating: "  ", count: depth) + "- [\(node.type.rawValue)] \(node.name)\(flags)")
                for child in node.children { describe(child, depth: depth + 1) }
            }
            describe(artboard.rootNode, depth: 0)
        }
        let hasCustomSource = artboard.customSwiftUISource != nil && !artboard.customSwiftUISource!.isEmpty
        return .structured(["id": .string(artboard.id.uuidString), "name": .string(artboard.name),
                            "deviceFrame": .string(artboard.deviceFrame), "hasCustomSource": .bool(hasCustomSource)],
                           summary: lines.joined(separator: "\n"))
    }

    func listArtboards(_ call: MCPToolCall) -> MCPToolResult {
        let folder = artboardWorkspaceFolder(for: call)
        if let folder { ensureArtboardsLoaded(for: folder) }
        if artboards.isEmpty {
            return .structured(["artboard_count": .int(0), "active_artboard_id": .string(""), "artboards": .array([])],
                               summary: "No artboards currently configured in workspace.")
        }
        var lines: [String] = []
        lines.append("Found \(artboards.count) artboard(s):")
        let list: [AnyJSON] = artboards.enumerated().map { index, board in
            let activeMarker = (board.id == activeArtboardID) ? " [ACTIVE]" : ""
            let hasCustomSource = (board.customSwiftUISource != nil && !board.customSwiftUISource!.isEmpty) ? "custom source" : "component tree"
            lines.append("  \(index + 1). \"\(board.name)\" (ID: \(board.id.uuidString))\(activeMarker)")
            lines.append("     Device Frame: \(board.deviceFrame)")
            lines.append("     Mode: \(hasCustomSource) (Root: \(board.rootType), Children: \(board.childCount))")
            lines.append("     Appearance: \(board.appearance), Orientation: \(board.isPortrait ? "Portrait" : "Landscape")")
            return ["id": .string(board.id.uuidString), "name": .string(board.name),
                    "deviceFrame": .string(board.deviceFrame), "appearance": .string(board.appearance),
                    "isPortrait": .bool(board.isPortrait), "hasCustomSource": .bool(hasCustomSource == "custom source"),
                    "active": .bool(board.id == activeArtboardID)]
        }
        return .structured(["artboard_count": .int(artboards.count),
                            "active_artboard_id": .string(activeArtboardID?.uuidString ?? ""),
                            "artboards": .array(list)],
                           summary: lines.joined(separator: "\n"))
    }

    func runArtboardApp(_ call: MCPToolCall) async throws -> MCPToolResult {
        try await run(call)
    }

    func updateArtboard(_ call: MCPToolCall) async throws -> MCPToolResult {
        let folder = artboardWorkspaceFolder(for: call)
        if let folder { ensureArtboardsLoaded(for: folder) }
        guard !artboards.isEmpty else {
            throw MCPToolError("No artboards currently configured in workspace.")
        }
        let identifier = call.string("identifier")
        guard let index = artboardIndex(matching: identifier) else {
            throw MCPToolError("Artboard not found matching '\(identifier ?? "active")'.")
        }
        var updatedFields: [String] = []
        if let newName = call.string("name") { updatedFields.append("name: '\(newName)'") }
        if let newDevice = call.string("deviceFrame") { updatedFields.append("deviceFrame: '\(newDevice)'") }
        if let newSource = call.string("sourceCode") { updatedFields.append("sourceCode (length: \(newSource.count))") }
        if let appearance = call.string("appearance") { updatedFields.append("appearance: '\(appearance)'") }
        if let isPortrait = call.bool("isPortrait") { updatedFields.append("isPortrait: \(isPortrait)") }
        try await approveChangeWithoutFile(tool: call.name,
                                           summary: "Update artboard '\(artboards[index].name)' (\(updatedFields.joined(separator: ", ")))",
                                           call: call)
        if let newName = call.string("name") { artboards[index].name = newName }
        if let newDevice = call.string("deviceFrame") { artboards[index].deviceFrame = newDevice }
        if let newSource = call.string("sourceCode") {
            artboards[index].customSwiftUISource = newSource
            artboards[index].lastCompileError = nil
        }
        if let appearance = call.string("appearance") { artboards[index].appearance = appearance }
        if let isPortrait = call.bool("isPortrait") { artboards[index].isPortrait = isPortrait }
        let artboard = artboards[index]
        saveArtboards(for: folder)
        return .structured(["id": .string(artboard.id.uuidString), "name": .string(artboard.name)],
                           summary: "Updated artboard '\(artboard.name)': \(updatedFields.joined(separator: ", "))")
    }

    func fixArtboards(_ call: MCPToolCall) async throws -> MCPToolResult {
        let scope = call.string("scope") ?? "all"
        guard ["preview", "full_app", "all"].contains(scope) else {
            throw MCPToolError("Invalid scope: '\(scope)'. Expected 'preview', 'full_app', or 'all'.")
        }
        let folder = artboardWorkspaceFolder(for: call)
        if let folder { ensureArtboardsLoaded(for: folder) }
        try await approveChangeWithoutFile(tool: call.name,
                                           summary: "Audit and repair artboards, previews, and the full-app run (scope: \(scope))",
                                           call: call)
        var actionsTaken: [String] = []

        let appleSims = (await Task.detached { await Self.appleSimulators() }.value)
        let bootedApple = appleSims.filter { $0.state == "Booted" }
        if appleSims.isEmpty {
            actionsTaken.append("Simulator audit: no Apple simulators found (simctl unavailable or none installed)")
        } else {
            actionsTaken.append("Simulator audit: \(appleSims.count) Apple simulator(s), \(bootedApple.count) booted")
        }
        if remoteSimulator?.isConfigured == true {
            actionsTaken.append("SwiftCode Simulator host is configured")
        }

        if scope == "full_app" {
            actionsTaken.append("Full-app clean skipped: use the clean tool for the workspace build")
        } else {
            let cacheDir = ArtboardStore.previewRenderCacheDirectory()
            if FileManager.default.fileExists(atPath: cacheDir.path) {
                try? FileManager.default.removeItem(at: cacheDir)
                actionsTaken.append("Cleared the preview-render cache (\(cacheDir.path)) so the next render rebuilds from scratch")
            } else {
                actionsTaken.append("Preview-render cache already empty — nothing to clear")
            }
        }

        var log = ""
        var verificationSucceeded = true
        if let activeID = activeArtboardID,
           let index = artboards.firstIndex(where: { $0.id == activeID }) {
            let artboard = artboards[index]
            if var source = artboard.customSwiftUISource, !source.isEmpty {
                var modified = false
                if !source.contains("import SwiftUI") {
                    source = "import SwiftUI\n\n" + source
                    modified = true
                    actionsTaken.append("Injected missing 'import SwiftUI' header into artboard '\(artboard.name)'")
                }
                if !source.contains("#Preview") && !source.contains("PreviewProvider") {
                    source += "\n\n#Preview {\n    \(artboard.name)()\n}\n"
                    modified = true
                    actionsTaken.append("Appended missing #Preview macro for '\(artboard.name)'")
                }
                if modified {
                    artboards[index].customSwiftUISource = source
                    artboards[index].lastCompileError = nil
                }
            }
            if artboards[index].customSwiftUISource != nil, !artboards[index].customSwiftUISource!.isEmpty {
                let render = await renderArtboardSource(at: index, targetView: nil)
                log = render.log
                verificationSucceeded = render.succeeded
                if render.succeeded {
                    artboards[index].lastCompileError = nil
                    actionsTaken.append("Recompiled artboard '\(artboard.name)' live preview session")
                } else {
                    artboards[index].lastCompileError = log
                    actionsTaken.append("Recompiled artboard '\(artboard.name)' live preview session (still failing — see logs)")
                }
            }
        } else if let path = delegate?.mcpHostActiveFilePath(), !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            if url.pathExtension.lowercased() == "swift",
               let source = delegate?.mcpHostText(ofOpenFile: path) ?? (try? String(contentsOf: url, encoding: .utf8)),
               !source.isEmpty {
                let render = await renderSwiftUISource(source, filename: url.lastPathComponent, targetView: nil)
                log = render.log
                verificationSucceeded = render.succeeded
                actionsTaken.append(render.succeeded
                    ? "Recompiled active SwiftUI document '\(url.lastPathComponent)' live preview session"
                    : "Recompiled active SwiftUI document '\(url.lastPathComponent)' live preview session (still failing — see logs)")
            }
        }

        let isSuccess = verificationSucceeded
        saveArtboards(for: folder)
        let summary = """
        Fix with Assist completed audit and repairs:
        \(actionsTaken.map { "  • \($0)" }.joined(separator: "\n"))

        Result Status: \(isSuccess ? "Healthy / Resolved" : "Repairs Applied, verifying compiler logs")
        Logs Summary:
        \(String(log.suffix(1000)))
        """
        return .structured(["repaired": .bool(true), "actions_count": .int(actionsTaken.count)], summary: summary)
    }
}

public enum ArtboardComponentType: String, Codable, CaseIterable, Sendable {
    case vStack = "VStack"
    case hStack = "HStack"
    case zStack = "ZStack"
    case group = "Group"
    case form = "Form"
    case list = "List"
    case scrollView = "ScrollView"
    case grid = "Grid"
    case lazyVGrid = "LazyVGrid"
    case lazyHGrid = "LazyHGrid"
    case navigationStack = "NavigationStack"
    case navigationSplitView = "NavigationSplitView"
    case tabView = "TabView"
    case text = "Text"
    case button = "Button"
    case label = "Label"
    case image = "Image"
    case asyncImage = "AsyncImage"
    case toggle = "Toggle"
    case picker = "Picker"
    case slider = "Slider"
    case stepper = "Stepper"
    case progressView = "ProgressView"
    case textField = "TextField"
    case secureField = "SecureField"
    case divider = "Divider"
    case spacer = "Spacer"
    case groupBox = "GroupBox"
    case canvas = "Canvas"
    case charts = "Charts"
    case map = "Map"
    case videoPlayer = "VideoPlayer"
    case webView = "WebView"
    case sfSymbol = "SF Symbol"
    case disclosureGroup = "DisclosureGroup"
    case contentUnavailableView = "ContentUnavailableView"
    case viewThatFits = "ViewThatFits"
    case anyLayout = "AnyLayout"
    case timelineView = "TimelineView"
    case gauge = "Gauge"
    case photosPicker = "PhotosPicker"
    case shareLink = "ShareLink"
    case menu = "Menu"
    case contextMenu = "ContextMenu"
    case toolbar = "Toolbar"
    case toolbarItem = "ToolbarItem"
    case searchable = "Searchable"
    case inspector = "Inspector"
    case safeAreaInset = "SafeAreaInset"
    case scrollViewReader = "ScrollViewReader"
    case matchedGeometryEffect = "MatchedGeometryEffect"
    case phaseAnimator = "PhaseAnimator"
    case keyframeAnimator = "KeyframeAnimator"
    case meshGradient = "MeshGradient"
    case swiftData = "SwiftData"
    case observation = "Observation"
    case accessibility = "Accessibility"

    public var systemIcon: String {
        switch self {
        case .vStack: return "arrow.down.to.line"
        case .hStack: return "arrow.right.to.line"
        case .zStack: return "square.stack.3d.down.right"
        case .group: return "square.dashed"
        case .form: return "doc.text"
        case .list: return "list.bullet"
        case .scrollView: return "scroll"
        case .grid: return "grid"
        case .lazyVGrid: return "grid.circle"
        case .lazyHGrid: return "grid.circle.fill"
        case .navigationStack: return "list.bullet.indent"
        case .navigationSplitView: return "sidebar.left"
        case .tabView: return "square.grid.3x1.below.line"
        case .text: return "text.alignleft"
        case .button: return "hand.point.up.left.fill"
        case .label: return "tag"
        case .image: return "photo"
        case .asyncImage: return "arrow.clockwise.icloud"
        case .toggle: return "switch.2"
        case .picker: return "filemenu.and.selection"
        case .slider: return "slider.horizontal.3"
        case .stepper: return "plusminus"
        case .progressView: return "circle.dotted"
        case .textField: return "character.cursor.ibackground"
        case .secureField: return "key"
        case .divider: return "minus"
        case .spacer: return "arrow.up.and.down.and.arrow.left.and.right"
        case .groupBox: return "square.grid.2x1"
        case .canvas: return "paintbrush"
        case .charts: return "chart.bar"
        case .map: return "map"
        case .videoPlayer: return "play.tv"
        case .webView: return "globe"
        case .sfSymbol: return "sparkles"
        case .disclosureGroup: return "chevron.right.circle"
        case .contentUnavailableView: return "exclamationmark.triangle"
        case .viewThatFits: return "arrow.up.right.and.arrow.down.left.rectangle"
        case .anyLayout: return "square.on.square"
        case .timelineView: return "hourglass"
        case .gauge: return "gauge"
        case .photosPicker: return "photo.on.rectangle"
        case .shareLink: return "square.and.arrow.up"
        case .menu: return "ellipsis.rectangle"
        case .contextMenu: return "contextualmenu.and.cursorarrow"
        case .toolbar: return "macwindow.navigationbar"
        case .toolbarItem: return "plus"
        case .searchable: return "magnifyingglass"
        case .inspector: return "sidebar.right"
        case .safeAreaInset: return "square.bottomthird.filled"
        case .scrollViewReader: return "scroll.fill"
        case .matchedGeometryEffect: return "sparkles.rectangle.stack"
        case .phaseAnimator: return "play.square.stack"
        case .keyframeAnimator: return "key.and.lock"
        case .meshGradient: return "square.stack.3d.up.fill"
        case .swiftData: return "cylinder.split.1x2"
        case .observation: return "eye"
        case .accessibility: return "figure.roll"
        }
    }

    public var isContainer: Bool {
        switch self {
        case .vStack, .hStack, .zStack, .group, .form, .list, .scrollView, .grid,
             .lazyVGrid, .lazyHGrid, .navigationStack, .navigationSplitView, .tabView,
             .groupBox, .disclosureGroup, .viewThatFits, .anyLayout, .scrollViewReader,
             .menu, .contextMenu, .toolbar, .inspector, .safeAreaInset:
            return true
        default:
            return false
        }
    }
}

public struct ArtboardComponentNode: Sendable, Codable, Equatable, Identifiable {
    public var id: UUID
    public var type: ArtboardComponentType
    public var name: String
    public var children: [ArtboardComponentNode]
    public var properties: [String: String]
    public var isLocked: Bool
    public var isHidden: Bool

    public init(id: UUID = UUID(), type: ArtboardComponentType, name: String? = nil,
                children: [ArtboardComponentNode] = [], properties: [String: String] = [:],
                isLocked: Bool = false, isHidden: Bool = false) {
        self.id = id
        self.type = type
        self.name = name ?? type.rawValue
        self.children = children
        self.properties = properties
        self.isLocked = isLocked
        self.isHidden = isHidden
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        let rawType = (try? c.decode(String.self, forKey: .type)) ?? ArtboardComponentType.vStack.rawValue
        type = ArtboardComponentType(rawValue: rawType) ?? .vStack
        name = (try? c.decode(String.self, forKey: .name)) ?? type.rawValue
        children = (try? c.decode([ArtboardComponentNode].self, forKey: .children)) ?? []
        properties = (try? c.decode([String: String].self, forKey: .properties)) ?? [:]
        isLocked = (try? c.decode(Bool.self, forKey: .isLocked)) ?? false
        isHidden = (try? c.decode(Bool.self, forKey: .isHidden)) ?? false
    }

    public func duplicated() -> ArtboardComponentNode {
        ArtboardComponentNode(id: UUID(), type: type, name: "\(name) Copy",
                              children: children.map { $0.duplicated() },
                              properties: properties, isLocked: isLocked, isHidden: isHidden)
    }

    public func node(id: UUID) -> ArtboardComponentNode? {
        if self.id == id { return self }
        for child in children { if let found = child.node(id: id) { return found } }
        return nil
    }

    public func updateNode(id: UUID, _ update: (inout ArtboardComponentNode) -> Void) -> ArtboardComponentNode {
        var copy = self
        if copy.id == id {
            update(&copy)
            return copy
        }
        copy.children = copy.children.map { $0.updateNode(id: id, update) }
        return copy
    }

    public func removeNode(id: UUID) -> ArtboardComponentNode {
        var copy = self
        copy.children = copy.children.filter { $0.id != id }.map { $0.removeNode(id: id) }
        return copy
    }

    public func addChild(_ child: ArtboardComponentNode, to id: UUID) -> ArtboardComponentNode {
        var copy = self
        if copy.id == id {
            copy.children.append(child)
            return copy
        }
        copy.children = copy.children.map { $0.addChild(child, to: id) }
        return copy
    }
}

public struct ArtboardRecord: Sendable, Codable {
    public var id: UUID
    public var name: String
    public var deviceFrame: String
    public var rootNode: ArtboardComponentNode
    public var customSwiftUISource: String?
    public var appearance: String
    public var isPortrait: Bool
    public var dynamicTypeSize: String?
    public var previewScale: Double?
    public var showSafeAreas: Bool?
    public var lastCompileError: String?

    public var rootType: String { rootNode.type.rawValue }
    public var rootName: String { rootNode.name }
    public var childCount: Int { rootNode.children.count }

    enum CodingKeys: String, CodingKey {
        case id, name, deviceFrame, rootNode, customSwiftUISource, appearance,
             isPortrait, dynamicTypeSize, previewScale, showSafeAreas
    }

    public init(id: UUID = UUID(), name: String, deviceFrame: String = "iPhone 16 Pro",
                customSwiftUISource: String? = nil, appearance: String = "System",
                isPortrait: Bool = true, rootNode: ArtboardComponentNode,
                dynamicTypeSize: String? = nil, previewScale: Double? = nil,
                showSafeAreas: Bool? = nil) {
        self.id = id
        self.name = name
        self.deviceFrame = deviceFrame
        self.rootNode = rootNode
        self.customSwiftUISource = customSwiftUISource
        self.appearance = appearance
        self.isPortrait = isPortrait
        self.dynamicTypeSize = dynamicTypeSize
        self.previewScale = previewScale
        self.showSafeAreas = showSafeAreas
        self.lastCompileError = nil
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(UUID.self, forKey: .id)) ?? UUID()
        name = (try? c.decode(String.self, forKey: .name)) ?? "Untitled"
        deviceFrame = (try? c.decode(String.self, forKey: .deviceFrame)) ?? "iPhone 16 Pro"
        rootNode = (try? c.decode(ArtboardComponentNode.self, forKey: .rootNode))
            ?? ArtboardComponentNode(type: .vStack, name: "Root")
        customSwiftUISource = try? c.decodeIfPresent(String.self, forKey: .customSwiftUISource) ?? nil
        appearance = (try? c.decode(String.self, forKey: .appearance)) ?? "System"
        isPortrait = (try? c.decode(Bool.self, forKey: .isPortrait)) ?? true
        dynamicTypeSize = try? c.decodeIfPresent(String.self, forKey: .dynamicTypeSize) ?? nil
        previewScale = try? c.decodeIfPresent(Double.self, forKey: .previewScale) ?? nil
        showSafeAreas = try? c.decodeIfPresent(Bool.self, forKey: .showSafeAreas) ?? nil
        lastCompileError = nil
    }

    public static func defaultRoot(name: String) -> ArtboardComponentNode {
        ArtboardComponentNode(type: .vStack, name: "\(name) Root")
    }
}

public struct ArtboardDocument: Sendable, Codable {
    public var version: Int
    public var artboards: [ArtboardRecord]
    public var activeArtboardID: UUID?
    public var framework: String
    public var zoomScale: Double
    public var panOffsetX: Double
    public var panOffsetY: Double

    public init(version: Int = 1, artboards: [ArtboardRecord] = [], activeArtboardID: UUID? = nil,
                framework: String = "SwiftUI", zoomScale: Double = 1.0,
                panOffsetX: Double = 0, panOffsetY: Double = 0) {
        self.version = version
        self.artboards = artboards
        self.activeArtboardID = activeArtboardID
        self.framework = framework
        self.zoomScale = zoomScale
        self.panOffsetX = panOffsetX
        self.panOffsetY = panOffsetY
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        artboards = (try? c.decode([ArtboardRecord].self, forKey: .artboards)) ?? []
        activeArtboardID = try? c.decodeIfPresent(UUID.self, forKey: .activeArtboardID) ?? nil
        framework = (try? c.decode(String.self, forKey: .framework)) ?? "SwiftUI"
        zoomScale = (try? c.decode(Double.self, forKey: .zoomScale)) ?? 1.0
        panOffsetX = (try? c.decode(Double.self, forKey: .panOffsetX)) ?? 0
        panOffsetY = (try? c.decode(Double.self, forKey: .panOffsetY)) ?? 0
    }
}

public enum ArtboardStore {
    public static func documentURL(forWorkspace folder: URL) -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support
            .appendingPathComponent("SwiftCode", isDirectory: true)
            .appendingPathComponent("Artboards", isDirectory: true)
            .appendingPathComponent(filenameKey(forWorkspace: folder) + ".swiftcode-artboard")
    }

    public static func filenameKey(forWorkspace folder: URL) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in folder.standardizedFileURL.path.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }

    public static func load(forWorkspace folder: URL) -> ArtboardDocument? {
        guard let data = try? Data(contentsOf: documentURL(forWorkspace: folder)) else { return nil }
        return try? JSONDecoder().decode(ArtboardDocument.self, from: data)
    }

    public static func save(_ document: ArtboardDocument, forWorkspace folder: URL) throws {
        let url = documentURL(forWorkspace: folder)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: url, options: .atomic)
    }

    public static func previewRenderCacheDirectory(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        let base = environment["XDG_CACHE_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache")
        return base.appendingPathComponent("swiftcode/preview-render")
    }
}
