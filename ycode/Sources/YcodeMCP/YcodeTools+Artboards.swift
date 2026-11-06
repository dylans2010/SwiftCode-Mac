import Foundation
import YcodeAssistant
import YcodeIDECore
import YcodePreviews

/// The ported Legacy Artboards tools (Wave 5).
///
/// Behaviour source: Legacy's `AssistArtboardCompileTool`,
/// `AssistArtboardCreateTool`, `AssistArtboardDeleteTool`,
/// `AssistArtboardGetTool`, `AssistArtboardListTool`,
/// `AssistArtboardRunAppTool`, `AssistArtboardUpdateTool` and
/// `AssistFixArtboardsTool` (Dylan's own code, ported under MIT).
/// The 8 IDs below were verified live from the Legacy registry
/// (`registerAllTools` + each tool's `id`).
///
/// Conventions, following Waves 1–4:
///
/// * Schemas are Legacy's `parametersSchema` verbatim, plus the
///   `workspace` parameter Wave 1 adds to every tool. Descriptions
///   are Legacy's verbatim. Structured data keeps Legacy's keys,
///   with typed JSON values (integers and booleans) the way Ycode's
///   other tools do — Legacy's string-only map is not reproduced.
/// * Risk → annotations follows the catalogue §1.3 table:
///   `safeRead` → read-only/idempotent, `writes: false`;
///   `safeMutation` → `readOnly: false, idempotent: true`,
///   `writes: true`. Every mutation goes through the approval gate
///   (`approveChangeWithoutFile`, the Wave 4 shape for non-text
///   operations) before it runs; the server's read-only policy
///   refuses the `writes: true` tools before that.
/// * Ycode has no Artboards system (the destination audit verified
///   `Artboard` occurs 0 times in destination source), so the tools
///   map onto the closest seams instead of building a parallel
///   system: the artboard record lives in-memory on the host (as
///   Legacy's lived in-memory in `DocumentCoordinator`'s
///   `VisualUIDocument` — there is no artboard file format in
///   either), and compiling an artboard renders its custom SwiftUI
///   source through `YcodePreviews` (`PreviewRenderRunner`, the
///   `preview_render` engine). There is no Visual UI Builder
///   component model in Ycode, so a created artboard's component
///   tree is the single root node Legacy's create tool makes (a
///   `vStack` named `"<name> Root"` with no children).
///
/// Implemented (8): `artboard_compile`, `artboard_create`,
/// `artboard_delete`, `artboard_get`, `artboard_list`,
/// `artboard_run_app`, `artboard_update`, `fix_artboards`.
///
/// Deliberate deviations from Legacy, recorded here:
///
/// * `artboard_compile` renders the artboard's custom source with
///   `PreviewRenderRunner` (a headless PNG via the open SwiftUI
///   port), not Legacy's live `PreviewManager` session: there is no
///   live preview host in the MCP server. An artboard with no
///   custom source cannot be compiled: Legacy fell back to the
///   active document, and the MCP host has no active document
///   (the delegate only exposes an open file's text by path, not
///   which file is open), so it fails naming `preview_render` as
///   the alternative. The `targetView` default differs too:
///   Legacy defaulted it to the artboard name; Ycode renders the
///   first `#Preview` unless `targetView` names one, because an
///   unnamed `#Preview` is called `Preview`, not the artboard
///   name (`PreviewDiscovery`).
/// * `artboard_run_app` delegates to the existing `run` tool: it
///   builds the scheme and runs it on this computer or, for a
///   Ycode Simulator destination, on the remote simulator. Legacy
///   ran the full app on an Apple simulator via
///   `FullAppRunManager`; Ycode has no Apple-simulator run
///   destination, so an Apple-simulator run is not available here.
/// * `fix_artboards` ports passes 3 (source repair) and 4
///   (recompile) for real; pass 1 (simulator/destination audit)
///   is audit-only — Ycode has no `XcodeBuildManager` destination
///   to realign and the fix tool does not boot a simulator on its
///   own (`simulator_boot` does that); pass 2 (DerivedData clean)
///   has no Ycode equivalent and is reported, not performed (use
///   the `clean` tool for the workspace build). The `scope`
///   parameter is validated (`preview`, `full_app`, `all`) where
///   Legacy accepted any value and ignored it.
/// * Artboards are host-scoped and in-memory: they are not
///   persisted to disk and do not survive a server restart, and
///   they are not scoped per workspace. A fresh server starts with
///   no artboards (Legacy's fresh `VisualUIDocument` likewise
///   started empty apart from its `Default` canvas root, which
///   Ycode does not seed — but the `Default` deletion guard is
///   kept: an artboard named `Default` cannot be deleted).
/// * `artboard_get` has no compile-error store to read beyond the
///   last `artboard_compile` failure for that artboard
///   (`lastCompileError`), where Legacy read
///   `DocumentCoordinator.compiledArtboardErrors`.
///
/// Wiring (coordinator): add `artboardTools` to `installTools()` in
/// `YcodeTools.swift` (`server.tools = … + artboardTools +
/// simulatorTools`).
extension YcodeMCPHost {
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
                 output: Schema.output(["artboard_count": Schema.int, "active_artboard_id": Schema.str, "artboards": Schema.anyArray])) { h, _ in
                h.listArtboards()
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

    // MARK: - Lookup

    /// Legacy's lookup: a UUID matches by id, anything else matches
    /// the first artboard whose name contains it (case-insensitive).
    /// No identifier means the active artboard, else the first.
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

    // MARK: - `artboard_compile`

    func compileArtboard(_ call: MCPToolCall) async throws -> MCPToolResult {
        let identifier = call.string("identifier")
        guard let index = artboardIndex(matching: identifier) else {
            throw MCPToolError(identifier == nil
                ? "No artboards currently configured in workspace."
                : "Artboard matching '\(identifier!)' not found. Use 'artboard_list' to view available artboards.")
        }
        let artboard = artboards[index]
        guard let source = artboard.customSwiftUISource, !source.isEmpty else {
            throw MCPToolError("Artboard '\(artboard.name)' has no custom SwiftUI source to compile (the MCP host has no active document to fall back to). Give it source with artboard_update, or render a file's preview with preview_render.")
        }
        // Compiling starts a preview render: a mutation of preview
        // state, so it goes through the approval gate first.
        try await approveChangeWithoutFile(tool: call.name,
                                           summary: "Compile artboard '\(artboard.name)' (render its preview)",
                                           call: call)
        return await compileArtboardRecord(at: index, targetView: call.string("targetView"))
    }

    /// Renders one artboard's custom source to a PNG through
    /// `YcodePreviews` and reports Legacy's success/failure shape.
    /// Returns the PNG data on success (nil + the log on failure).
    func renderArtboardSource(at index: Int, targetView: String?) async -> (png: Data?, log: String, succeeded: Bool) {
        let artboard = artboards[index]
        guard let source = artboard.customSwiftUISource, !source.isEmpty else {
            return (nil, "", false)
        }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ycode-artboard-\(UUID().uuidString)")
        let file = dir.appendingPathComponent("\(artboard.name).swift")
        let out = dir.appendingPathComponent("preview.png")
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try source.write(to: file, atomically: true, encoding: .utf8)
        } catch {
            return (nil, "cannot write the artboard source for rendering: \(error.localizedDescription)", false)
        }
        defer { try? FileManager.default.removeItem(at: dir) }
        let starts = [URL(fileURLWithPath: FileManager.default.currentDirectoryPath)]
        let result = await Task.detached {
            PreviewRenderRunner.render(file: file.path, name: targetView, output: out.path, starts: starts) { _ in }
        }.value
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

    // MARK: - `artboard_create`

    func createArtboard(_ call: MCPToolCall) async throws -> MCPToolResult {
        let rawName = try call.require("name")
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw MCPToolError("Parameter 'name' is required.") }
        let deviceFrame = call.string("deviceFrame") ?? "iPhone 16 Pro"
        let sourceCode = call.string("sourceCode")
        let appearance = call.string("appearance") ?? "System"
        let isPortrait = call.bool("isPortrait") ?? true
        try await approveChangeWithoutFile(tool: call.name,
                                           summary: "Create artboard '\(name)' with frame '\(deviceFrame)'",
                                           call: call)
        // Legacy's root node: a vStack named "<name> Root", no children.
        let artboard = ArtboardRecord(id: UUID(), name: name, deviceFrame: deviceFrame,
                                      customSwiftUISource: sourceCode, appearance: appearance,
                                      isPortrait: isPortrait, rootType: "vStack",
                                      rootName: "\(name) Root", childCount: 0)
        artboards.append(artboard)
        activeArtboardID = artboard.id
        return .structured(["id": .string(artboard.id.uuidString), "name": .string(name),
                            "deviceFrame": .string(deviceFrame)],
                           summary: "Successfully created artboard '\(name)' (ID: \(artboard.id.uuidString)) with frame '\(deviceFrame)'.")
    }

    // MARK: - `artboard_delete`

    func deleteArtboard(_ call: MCPToolCall) async throws -> MCPToolResult {
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
        return .structured(["id": .string(artboard.id.uuidString), "name": .string(artboard.name)],
                           summary: "Artboard '\(artboard.name)' (ID: \(artboard.id.uuidString)) deleted successfully.")
    }

    // MARK: - `artboard_get`

    func getArtboard(_ call: MCPToolCall) throws -> MCPToolResult {
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
            lines.append("- [\(artboard.rootType)] \(artboard.rootName)")
        }
        let hasCustomSource = artboard.customSwiftUISource != nil && !artboard.customSwiftUISource!.isEmpty
        return .structured(["id": .string(artboard.id.uuidString), "name": .string(artboard.name),
                            "deviceFrame": .string(artboard.deviceFrame), "hasCustomSource": .bool(hasCustomSource)],
                           summary: lines.joined(separator: "\n"))
    }

    // MARK: - `artboard_list`

    func listArtboards() -> MCPToolResult {
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

    // MARK: - `artboard_run_app`

    /// Builds the scheme and runs it, through the existing `run`
    /// tool: on this computer, or on the Ycode Simulator when the
    /// destination is one. Legacy ran on an Apple simulator; Ycode
    /// has no Apple-simulator run destination.
    func runArtboardApp(_ call: MCPToolCall) async throws -> MCPToolResult {
        try await run(call)
    }

    // MARK: - `artboard_update`

    func updateArtboard(_ call: MCPToolCall) async throws -> MCPToolResult {
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
        return .structured(["id": .string(artboard.id.uuidString), "name": .string(artboard.name)],
                           summary: "Updated artboard '\(artboard.name)': \(updatedFields.joined(separator: ", "))")
    }

    // MARK: - `fix_artboards`

    func fixArtboards(_ call: MCPToolCall) async throws -> MCPToolResult {
        let errorContext = call.string("errorContext") ?? ""
        let scope = call.string("scope") ?? "all"
        guard ["preview", "full_app", "all"].contains(scope) else {
            throw MCPToolError("Invalid scope: '\(scope)'. Expected 'preview', 'full_app', or 'all'.")
        }
        try await approveChangeWithoutFile(tool: call.name,
                                           summary: "Audit and repair artboards, previews, and the full-app run (scope: \(scope))",
                                           call: call)
        var actionsTaken: [String] = []

        // Pass 1: Simulator & Destination Audit (audit-only in
        // Ycode — no XcodeBuildManager destination to realign, and
        // this tool does not boot a simulator on its own).
        let appleSims = await Task.detached { Self.appleSimulators() }.value
        let bootedApple = appleSims.filter { $0.state == "Booted" }
        if appleSims.isEmpty {
            actionsTaken.append("Simulator audit: no Apple simulators found (simctl unavailable or none installed)")
        } else {
            actionsTaken.append("Simulator audit: \(appleSims.count) Apple simulator(s), \(bootedApple.count) booted")
        }
        if remoteSimulator?.isConfigured == true {
            actionsTaken.append("Ycode Simulator host is configured")
        }

        // Pass 2: Clean DerivedData / Stale Build State — no Ycode
        // equivalent. Report it instead of pretending to clean.
        if errorContext.localizedCaseInsensitiveContains("already in progress")
            || errorContext.localizedCaseInsensitiveContains("exit code 70")
            || errorContext.localizedCaseInsensitiveContains("exit code 65")
            || errorContext.localizedCaseInsensitiveContains("corrupted") {
            actionsTaken.append("Stale-build clean skipped: Ycode has no DerivedData cache to clean (use the clean tool for the workspace build)")
        }

        // Pass 3: Audit Active Artboard Custom Source Code.
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
            // Pass 4: Verification Compile Pass (the active artboard
            // only — Ycode has no active document to recompile).
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
        }

        // Legacy judged success from the build log's wording; the
        // headless render's log may carry neither "failed" nor
        // "error:" when it fails (e.g. no Swift toolchain), so the
        // render outcome itself decides. No compile ran means
        // nothing failed, which Legacy also counted as healthy.
        let isSuccess = verificationSucceeded
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

/// One artboard. Ycode has no Visual UI Builder component model, so
/// the component tree is the single root node Legacy's create tool
/// makes; `childCount` stays 0 until a component model exists.
struct ArtboardRecord: Sendable {
    var id: UUID
    var name: String
    var deviceFrame: String
    var customSwiftUISource: String?
    var appearance: String
    var isPortrait: Bool
    var dynamicTypeSize: String?
    var previewScale: Double?
    var showSafeAreas: Bool?
    var rootType: String
    var rootName: String
    var childCount: Int
    var lastCompileError: String?

    init(id: UUID, name: String, deviceFrame: String, customSwiftUISource: String?,
         appearance: String, isPortrait: Bool, rootType: String, rootName: String, childCount: Int) {
        self.id = id
        self.name = name
        self.deviceFrame = deviceFrame
        self.customSwiftUISource = customSwiftUISource
        self.appearance = appearance
        self.isPortrait = isPortrait
        self.dynamicTypeSize = nil
        self.previewScale = nil
        self.showSafeAreas = nil
        self.rootType = rootType
        self.rootName = rootName
        self.childCount = childCount
        self.lastCompileError = nil
    }
}
