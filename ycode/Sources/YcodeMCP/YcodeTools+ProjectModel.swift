import Foundation
import YcodeIDECore
import YcodeProject

/// The ported Legacy project-model / pbxproj tool family (Wave 7,
/// slice B).
///
/// Behaviour source: Legacy's `AssistCreateNewAppTool`,
/// `AssistGenerateXcodeprojTool` (in `AssistBuildProjectTool.swift`),
/// `AssistPbxprojLintTool`, `AssistProjectBuildSettingsTool`,
/// `AssistProjectCapabilitiesTool`, `AssistDiffTool`,
/// `AssistProjectMutationController`, `AssistRestoreSnapshotTool`,
/// `AssistProjectSchemeListTool`, `AssistSnapshotProjectTool`,
/// `AssistProjectStructureMapTool`, `AssistProjectTargetAddTool`,
/// `AssistProjectTargetListTool`, `AssistSchemeTestPlanListTool`,
/// `AssistTargetDependenciesListTool`, `AssistTargetSourceListTool`,
/// `AssistWorkspaceSettingsReadTool`, `AssistXcodeBuildSettingsTool`
/// and `AssistXcodeSchemeTool` (Dylan's own code, ported under MIT).
/// The behaviour contract is
/// `~/SwiftCode-Migration-Workspace/scratch/wave7-slice-b-spec.md`.
///
/// Conventions, following Waves 1–6:
///
/// * Schemas are Legacy's `parametersSchema` verbatim, plus the
///   `workspace` parameter every Ycode tool carries. Legacy's
///   parameter-name aliases are NOT supported: Ycode's argument
///   validation rejects unknown arguments before the handler runs.
///   The two tool-name aliases in this slice, `xcode_scheme` →
///   `xcode_scheme_manager` and `build_settings` →
///   `xcode_build_settings_inspector` (Legacy's `AssistToolRegistry`
///   alias table), live in `MCPServer.toolAliases`, which the
///   coordinator owns — they are not added here.
/// * Structured data keeps Legacy's keys, with typed JSON values
///   (integers, booleans) the way Ycode's other tools do — Legacy's
///   string-only map is not reproduced. Tools whose Legacy result
///   carries no data return a plain text result instead.
/// * Paths resolve through the session resolvers
///   (`resolveFileReadingPath`, `fileReadingRelativePath`) and never
///   escape the workspace, with the deviations documented in the
///   spec: `create_new_app` confines the new project to the
///   workspace (Legacy wrote to `~/Documents` or an arbitrary
///   absolute path), and `projectLocation` is resolved with the
///   strict `resolve(_:in:)` so an outside absolute path fails
///   instead of being silently reinterpreted.
/// * The project model is Ycode's own (`YcodeProject`): pbxproj
///   reads go through `PBXProj` parsing, edits through its typed
///   mutations (`setBuildSetting`, `addFileReference`,
///   `addBuildFile`, `removeFileReference`, `addTarget`,
///   `addSourceGroup`), serialised with `PBXProjWriter`. No tool
///   edits pbxproj text by line or regex insertion, and no
///   parallel project model is built.
/// * No `xcodebuild` is spawned anywhere in this slice. Legacy's
///   scheme/target/settings reads ran it (macOS-only); this port
///   reads the same facts from the parsed pbxproj and the
///   session's own model (`WorkspaceModel.schemeNames`). Build
///   setting values are the values as written in the pbxproj
///   (project-level merged with target-level, target wins); no
///   xcconfig is followed and no `$(…)` macro is expanded.
/// * Approval gating: the seven writing tools
///   (`create_new_app`, `generate_xcodeproj`,
///   `project_build_settings`, `project_capabilities`,
///   `project_mutation_controller`, `project_snapshot`,
///   `project_target_add`) plus `project_restore` are
///   `writes: true`. Project-file edits go through `commit()` /
///   `approve()`; `project_snapshot` / `project_restore` use an
///   explicit `MCPChange` + `approve()` per call (the snapshot
///   store is outside the workspace, so `commit()` does not
///   apply). `project_restore` is `potentiallyDestructive`.
///   There is no Autopilot bypass.
/// * `generate_xcodeproj` never installs xcodegen: Legacy
///   installed it via Homebrew without a prompt when missing;
///   this port fails with Legacy's message instead. It is also
///   `writes: true` (Legacy marked it `execution`) because
///   `xcodegen generate` writes a `.xcodeproj` bundle into the
///   workspace, so a read-only server must refuse it.
/// * Snapshots live in Application Support `YcodeSnapshots/`
///   (Legacy's `AssistSnapshots/` layout, renamed for Ycode).
///   `project_snapshot` is `writes: true` although Legacy marked
///   it `safeRead`, because it writes a whole-tree copy to disk.
/// * `project_target_add` registers its target properly
///   (`PBXProj.addTarget`: targets list, product reference,
///   configuration list, source group). Legacy inserted the
///   blocks as text but never registered the target, leaving an
///   orphan; the port does not reproduce that defect.
/// * `project_mutation_controller`'s `remove` removes matching
///   `PBXFileReference` objects through the model instead of
///   deleting every line containing the file string (Legacy's
///   line filter could delete unrelated lines).
///
/// Wiring: this array is NOT added to `installTools()` here —
/// `YcodeTools.swift` is owned by the coordinator, which adds
/// `+ projectModelTools` to the chain.
extension YcodeMCPHost {
    var projectModelTools: [MCPTool] {
        let safeMutation = MCPToolAnnotations(readOnly: false, idempotent: true)
        let destructive = MCPToolAnnotations(readOnly: false, destructive: true)
        return [
            tool("create_new_app", "Create New App",
                 "Creates a new native application project from user specifications or autonomous request parameters.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "appName": Schema.string("Display name of the application (e.g. My Notes)."),
                                       "bundleIdentifier": Schema.string("Reverse domain bundle identifier (e.g. com.example.mynotes)."),
                                       "version": Schema.string("Marketing version number (e.g. 1.0)."),
                                       "build": Schema.string("Build number (e.g. 1)."),
                                       "platform": Schema.string("Target platform: macOS, iOS, iPadOS, watchOS, or visionOS."),
                                       "projectLocation": Schema.string("Absolute file URL path where the project directory should be generated."),
                                       "applicationDescription": Schema.string("Natural language description or feature specification of the application."),
                                       "uiPreferences": Schema.anyObject,
                                       "architecturePreferences": Schema.string("Preferred software architecture pattern (e.g. MVVM, TCA, Observable Stores)."),
                                       "additionalRequirements": Schema.string("Any extra technical requirements or constraints."),
                                       "overwriteExistingMetadata": Schema.boolean("Whether to overwrite existing project metadata if an active project exists.")],
                                      required: ["appName", "applicationDescription"]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.projectModelCreateNewApp(call)
            },
            tool("generate_xcodeproj", "Generate Xcode Project",
                 "Generates .xcodeproj files from an XcodeGen project.yml spec. Installs XcodeGen automatically if missing. Runs in the background without a terminal approval prompt.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "spec": Schema.string("Workspace-relative path to the XcodeGen spec file. Default is 'project.yml'."),
                                       "useCache": Schema.string("'true' to pass --use-cache to xcodegen. Default is 'false'.")]),
                 output: Schema.output(["spec": Schema.str, "projects": Schema.str, "duration": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.projectModelGenerateXcodeproj(call)
            },
            tool("pbxproj_lint", "pbxproj Lint",
                 "Lints the .pbxproj: file references pointing at missing files, duplicate paths, and build files with dangling file references.",
                 input: Schema.object(["workspace": Schema.workspace]),
                 output: Schema.output(["fileRefCount": Schema.int, "missingCount": Schema.int, "duplicateCount": Schema.int,
                                        "danglingCount": Schema.int, "clean": Schema.bool])) { h, call in
                try h.projectModelPbxprojLint(call)
            },
            tool("project_build_settings", "Build Settings",
                 "Reads Xcode build settings with xcodebuild, or sets one build setting key in the project's pbxproj.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "action": Schema.string("read or set. Default: read."),
                                       "target": Schema.string("Optional target name for read or set."),
                                       "configuration": Schema.string("Build configuration, e.g. Debug or Release. Default: Debug."),
                                       "key": Schema.string("Build setting key. Required for set; optional filter for read."),
                                       "value": Schema.string("New value for the key. Required for set.")]),
                 // No output schema: read-all, read-one and set return
                 // different key sets, and Schema.output requires every
                 // listed property.
                 annotations: safeMutation, writes: true) { h, call in
                try await h.projectModelProjectBuildSettings(call)
            },
            tool("project_capabilities", "Capabilities",
                 "Lists app capabilities from entitlements and pbxproj, or enables/disables one capability by editing the entitlements plist.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "action": Schema.string("list, enable, or disable. Default: list."),
                                       "capability": Schema.string("Capability name for enable/disable: push, icloud, appGroups, appSandbox, keychain, network.")]),
                 // No output schema: list and enable/disable return
                 // different key sets, and Schema.output requires every
                 // listed property.
                 annotations: safeMutation, writes: true) { h, call in
                try await h.projectModelProjectCapabilities(call)
            },
            tool("project_diff", "Diff Project",
                 "Compares the working tree with Git HEAD, returning real unified diffs and modified files.",
                 input: Schema.object(["workspace": Schema.workspace]),
                 output: Schema.output(["diff": Schema.str, "branch": Schema.str, "staged_count": Schema.int, "unstaged_count": Schema.int])) { h, call in
                try h.projectModelProjectDiff(call)
            },
            tool("project_mutation_controller", "Xcode Project Mutation Controller",
                 "Adds/removes file references in the user's project.pbxproj, resolving groups and build phases from the target project.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "action": Schema.string("One of 'add', 'remove', or 'repair'."),
                                       "projectFile": Schema.string("Workspace-relative path to project.pbxproj. Defaults to the project.pbxproj of the project found in the workspace root."),
                                       "filePath": Schema.string("Workspace-relative file path. Required for 'add' and 'remove'.")],
                                      required: ["action"]),
                 output: Schema.output(["project": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.projectModelProjectMutationController(call)
            },
            tool("project_restore", "Restore Snapshot",
                 "Restores the project to a previously saved state.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "snapshot_id": Schema.string("Snapshot identifier from project_snapshot or project_changelog.")],
                                      required: ["snapshot_id"]),
                 annotations: destructive, writes: true) { h, call in
                try await h.projectModelProjectRestore(call)
            },
            tool("project_scheme_list", "List Schemes",
                 "Lists the Xcode schemes available for the user's project or workspace.",
                 input: Schema.object(["workspace": Schema.workspace]),
                 output: Schema.output(["schemes": Schema.str, "count": Schema.int, "project": Schema.str])) { h, call in
                try h.projectModelProjectSchemeList(call)
            },
            tool("project_snapshot", "Snapshot Project",
                 "Creates a full snapshot of the current project state.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "message": Schema.string("Label stored on the snapshot. Default: \"Manual Snapshot\".")]),
                 output: Schema.output(["snapshot_id": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.projectModelProjectSnapshot(call)
            },
            tool("project_structure_map", "Project Structure Map",
                 "Builds a machine-readable map of the project: top-level directories with file counts and the Xcode target layout parsed from the .pbxproj when present.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "maxDepth": Schema.integer("Directory depth to map. Default 2, max 4.")]),
                 output: Schema.output(["directoryCount": Schema.int, "targets": Schema.str])) { h, call in
                try h.projectModelProjectStructureMap(call)
            },
            tool("project_target_add", "Add Target",
                 "Adds a new Xcode target: creates a source directory with a real Swift file and inserts PBXNativeTarget blocks into project.pbxproj.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "targetName": Schema.string("Name of the new target. Letters, digits, underscore, hyphen only."),
                                       "type": Schema.string("Target type: app, framework, or test. Default: app."),
                                       "bundleId": Schema.string("Optional bundle identifier for the new target.")],
                                      required: ["targetName"]),
                 output: Schema.output(["targetName": Schema.str, "type": Schema.str, "targetId": Schema.str, "sourceDirectory": Schema.str]),
                 annotations: safeMutation, writes: true) { h, call in
                try await h.projectModelProjectTargetAdd(call)
            },
            tool("project_target_list", "List Targets",
                 "Lists the Xcode targets in the user's project by scanning project.pbxproj and xcodebuild output.",
                 input: Schema.object(["workspace": Schema.workspace]),
                 output: Schema.output(["targets": Schema.str, "count": Schema.int, "sources": Schema.str])) { h, call in
                try h.projectModelProjectTargetList(call)
            },
            tool("scheme_test_plan_list", "Scheme Test Plan List",
                 "Finds .xctestplan files in the workspace and lists the test targets each plan covers.",
                 input: Schema.object(["workspace": Schema.workspace]),
                 output: Schema.output(["count": Schema.int])) { h, call in
                try h.projectModelSchemeTestPlanList(call)
            },
            tool("target_dependencies_list", "Target Dependencies List",
                 "Lists Xcode target-to-target dependencies parsed from the project's .pbxproj.",
                 input: Schema.object(["workspace": Schema.workspace]),
                 output: Schema.output(["targetCount": Schema.int, "edgeCount": Schema.int])) { h, call in
                try h.projectModelTargetDependenciesList(call)
            },
            tool("target_source_list", "Target Source List",
                 "Lists the source files compiled into a given Xcode target (Compile Sources build phase), resolved from the .pbxproj.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "target": Schema.string("Target name. If omitted, lists sources for every target (truncated per target)."),
                                       "limit": Schema.integer("Maximum files per target. Default 200.")]),
                 output: Schema.output(["targetCount": Schema.int])) { h, call in
                try h.projectModelTargetSourceList(call)
            },
            tool("workspace_settings_read", "Workspace Settings Read",
                 "Reads Xcode workspace/shared settings (.xcsettings plists): build system, derived-data location, and IDE workspace checks.",
                 input: Schema.object(["workspace": Schema.workspace]),
                 output: Schema.output(["count": Schema.int])) { h, call in
                try h.projectModelWorkspaceSettingsRead(call)
            },
            tool("xcode_build_settings_inspector", "Xcode Build Settings Inspector",
                 "Inspects and extracts active build configuration settings, flags, and paths via xcodebuild.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "target": Schema.string("Optional target name to query build settings for."),
                                       "settingKey": Schema.string("Optional specific build setting key to extract (e.g. PRODUCT_BUNDLE_IDENTIFIER, SWIFT_VERSION).")])) { h, call in
                try h.projectModelXcodeBuildSettingsInspector(call)
            },
            tool("xcode_scheme_manager", "Xcode Scheme & Build Configuration Manager",
                 "Inspects, lists, and queries Xcode schemes, targets, and build configurations in the workspace.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "action": Schema.string("Action: 'list_schemes', 'inspect_scheme'."),
                                       "schemeName": Schema.string("Scheme name to inspect (for 'inspect_scheme').")],
                                      required: ["action"])) { h, call in
                try h.projectModelXcodeSchemeManager(call)
            },
        ]
    }
}

extension YcodeMCPHost {
    // MARK: - Shared helpers (project model)

    /// Top-level directories Legacy's workspace scan skips, checked
    /// against the first path component exactly as
    /// `AssistWorkspaceScan.files` does.
    nonisolated static let projectModelSkippedDirs: Set<String> = [
        ".git", ".build", "build", "DerivedData", ".swiftpm",
        "Pods", "Carthage", "node_modules", ".venv",
    ]

    /// The first `project.pbxproj` under the root, in sorted-path
    /// order (Legacy took the first in enumerator order, which is
    /// unspecified; sorted-first is deterministic).
    nonisolated static func projectModelFindPbxproj(in root: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return nil
        }
        var found: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "pbxproj" {
            found.append(url)
        }
        return found.sorted { $0.path < $1.path }.first
    }

    /// Every `project.pbxproj` at depth ≤ 4, Legacy's
    /// `project_target_list` scan.
    nonisolated static func projectModelFindPBXProjURLs(in root: URL) -> [URL] {
        var results: [URL] = []
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return results
        }
        var depthByURL: [URL: Int] = [root: 0]
        for case let url as URL in enumerator {
            let parent = url.deletingLastPathComponent()
            let depth = (depthByURL[parent] ?? 0) + 1
            depthByURL[url] = depth
            if depth > 4 { enumerator.skipDescendants(); continue }
            if url.lastPathComponent == "project.pbxproj" { results.append(url) }
        }
        return results.sorted { $0.path < $1.path }
    }

    /// The top-level `.xcworkspace` (preferred) or `.xcodeproj` in
    /// the workspace root, Legacy's `locateProject`.
    nonisolated static func projectModelTopLevelProject(in root: URL) -> URL? {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return nil
        }
        let workspaces = entries.filter { $0.pathExtension == "xcworkspace" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        if let ws = workspaces.first { return ws }
        let projects = entries.filter { $0.pathExtension == "xcodeproj" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
        return projects.first
    }

    /// Reads and parses a pbxproj, returning the model and its text.
    nonisolated static func projectModelLoadPBXProj(at url: URL) throws -> (PBXProj, String) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw MCPToolError("Failed to read project.pbxproj.")
        }
        do {
            return (try PBXProj(parsing: text), text)
        } catch {
            throw MCPToolError("Failed to read project.pbxproj.")
        }
    }

    /// Files under the root with Legacy's `AssistWorkspaceScan.files`
    /// semantics: hidden files skipped, top-level skipped dirs
    /// skipped, optional extension filter, 20,000-file cap.
    nonisolated static func projectModelScanFiles(under root: URL, extensions: Set<String>? = nil, maxFiles: Int = 20000) -> [URL] {
        var results: [URL] = []
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else {
            return results
        }
        let rootPath = root.standardized.path
        while let url = enumerator.nextObject() as? URL, results.count < maxFiles {
            let rel = url.standardized.path.replacingOccurrences(of: rootPath + "/", with: "")
            if projectModelSkippedDirs.contains(rel.split(separator: "/").first.map(String.init) ?? "") { continue }
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir { continue }
            if let exts = extensions, !exts.contains(url.pathExtension.lowercased()) { continue }
            results.append(url)
        }
        return results
    }

    nonisolated static func projectModelFileSize(of url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }

    /// A build-setting value as a string: plain strings as-is,
    /// arrays space-joined (as `xcodebuild -showBuildSettings`
    /// renders them).
    nonisolated static func projectModelSettingString(_ value: PlistValue?) -> String? {
        guard let value else { return nil }
        if let s = value.string { return s }
        if let a = value.array { return a.compactMap(\.string).joined(separator: " ") }
        return nil
    }

    /// The settings of one configuration: project-level first,
    /// target-level overriding. Returns the merged map, whether the
    /// named target was found, and whether any configuration block
    /// with that name exists.
    nonisolated static func projectModelMergedSettings(_ proj: PBXProj, targetName: String?, configuration: String) -> (settings: [String: String], targetFound: Bool, configFound: Bool) {
        var merged: [String: String] = [:]
        var configFound = false
        func absorb(listID: String?) {
            for c in proj.buildConfigurations(listID: listID) where c.string("name") == configuration {
                configFound = true
                if let settings = c["buildSettings"]?.dictionary {
                    for key in settings.keys {
                        if let value = projectModelSettingString(settings[key]) { merged[key] = value }
                    }
                }
            }
        }
        absorb(listID: proj.project?.string("buildConfigurationList"))
        var targetFound = targetName == nil
        if let targetName, !targetName.isEmpty {
            if let target = proj.targets.first(where: { $0.string("name") == targetName }) {
                targetFound = true
                absorb(listID: target.string("buildConfigurationList"))
            }
        }
        return (merged, targetFound, configFound)
    }

    /// The project's default configuration name (its list's
    /// `defaultConfigurationName`, else `Debug`).
    nonisolated static func projectModelDefaultConfiguration(_ proj: PBXProj) -> String {
        if let list = proj.project?.string("buildConfigurationList"),
           let name = proj[list]?.string("defaultConfigurationName"), !name.isEmpty {
            return name
        }
        return "Debug"
    }

    /// The full path of a `PBXGroup` from the main group down
    /// (`path`, falling back to `name`), following the parent
    /// chain. Synchronised folders are not groups and are not
    /// followed (Legacy's resolver only matched `PBXGroup`).
    nonisolated static func projectModelGroupPaths(_ proj: PBXProj) -> [String: String] {
        var parentOf: [String: String] = [:]
        var groups: [String: PBXObject] = [:]
        for obj in proj.objects.values where obj.isa == "PBXGroup" {
            groups[obj.id] = obj
            for child in obj.references("children") where groups[child] != nil || proj[child]?.isa == "PBXGroup" {
                parentOf[child] = obj.id
            }
        }
        var out: [String: String] = [:]
        for (id, group) in groups {
            var components: [String] = []
            var current: String? = id
            var guardCount = 0
            while let c = current, let g = groups[c], guardCount < 64 {
                guardCount += 1
                if let pc = g.string("path") ?? g.string("name"), !pc.isEmpty { components.append(pc) }
                current = parentOf[c]
            }
            out[id] = components.reversed().joined(separator: "/")
        }
        return out
    }

    /// Legacy's `groupID(forFileDirectory:)`: the group whose
    /// resolved directory exactly matches `fileDir`, else the
    /// deepest path-prefix match. Nil when nothing matches.
    nonisolated static func projectModelGroupID(forFileDirectory fileDir: String, in proj: PBXProj) -> String? {
        let paths = projectModelGroupPaths(proj)
        guard !paths.isEmpty else { return nil }
        let normalized = fileDir.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var best: (id: String, depth: Int)?
        for (id, p) in paths {
            guard !p.isEmpty else { continue }
            if p == normalized { return id }
            if normalized.hasPrefix(p + "/") {
                if best == nil || p.count > best!.depth { best = (id, p.count) }
            }
        }
        return best?.id
    }

    /// The first `PBXSourcesBuildPhase` in project-target order
    /// (Legacy took the first `/* Sources */` phase in file order).
    nonisolated static func projectModelSourcesPhaseID(in proj: PBXProj) -> String? {
        for target in proj.targets {
            for phase in proj.buildPhases(ofTarget: target.id) where phase.isa == "PBXSourcesBuildPhase" {
                return phase.id
            }
        }
        return nil
    }

    /// The snapshot store: Application Support `YcodeSnapshots/`
    /// (Legacy's `AssistSnapshots/` layout, renamed for Ycode).
    nonisolated static func projectModelSnapshotsDirectory() throws -> URL {
        let appSupport = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let dir = appSupport.appendingPathComponent("YcodeSnapshots", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    /// The `.xcodeproj` name (without extension) for a pbxproj URL.
    nonisolated static func projectModelProjectName(for pbxURL: URL) -> String {
        pbxURL.deletingLastPathComponent().deletingPathExtension().lastPathComponent
    }

    /// Legacy's `isValidSettingKey`: `[A-Za-z0-9_]+`, no `..`,
    /// newline, `;`, `{` or `}`.
    nonisolated static func projectModelIsValidSettingKey(_ key: String) -> Bool {
        guard !key.isEmpty else { return false }
        if key.contains("..") || key.contains("\n") || key.contains("\r") || key.contains(";") || key.contains("{") || key.contains("}") {
            return false
        }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_")
        return key.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    nonisolated static func projectModelIsValidTargetName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 64, !name.contains(".."), !name.contains("/") else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")
        return name.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    nonisolated static func projectModelIsValidBundleId(_ id: String) -> Bool {
        guard !id.isEmpty, !id.contains(" ") else { return false }
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-.")
        return id.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Reads a plist dictionary, or nil when the file is not a
    /// valid plist dictionary.
    nonisolated static func projectModelReadPlist(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        var format = PropertyListSerialization.PropertyListFormat.xml
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: &format) else { return nil }
        return plist as? [String: Any]
    }

    nonisolated static func projectModelPlistXML(_ dict: [String: Any]) -> String? {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

extension YcodeMCPHost {
    // MARK: - Read-only tools

    func projectModelPbxprojLint(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        guard let pbxproj = Self.projectModelFindPbxproj(in: root),
              let text = try? String(contentsOf: pbxproj, encoding: .utf8) else {
            throw MCPToolError("No .pbxproj found in the workspace.")
        }
        let projectDir = pbxproj.deletingLastPathComponent().deletingLastPathComponent()
        var fileRefPaths: [String: String] = [:]
        if let p = try? NSRegularExpression(pattern: #"([0-9A-F]{24}) /\* (.+?) \*/ = \{isa = PBXFileReference;[^}]*?path = ([^;]+);"#, options: [.dotMatchesLineSeparators]) {
            for m in p.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let r1 = Range(m.range(at: 1), in: text), let r3 = Range(m.range(at: 3), in: text) else { continue }
                fileRefPaths[String(text[r1])] = String(text[r3]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        var missing: [String] = []
        var seenPaths: Set<String> = []
        var duplicates: [String] = []
        for (id, path) in fileRefPaths.sorted(by: { $0.value < $1.value }) {
            if seenPaths.contains(path) { duplicates.append("\(path) (ref \(id))") }
            seenPaths.insert(path)
            if !path.hasPrefix("/") {
                let candidate = projectDir.appendingPathComponent(path).standardized
                if !FileManager.default.fileExists(atPath: candidate.path) {
                    missing.append("\(path) (ref \(id))")
                }
            }
            if missing.count > 200 { break }
        }
        var dangling: [String] = []
        if let p = try? NSRegularExpression(pattern: #"fileRef = ([0-9A-F]{24}) /\* (.+?) \*/;"#) {
            for m in p.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let r1 = Range(m.range(at: 1), in: text), let r2 = Range(m.range(at: 2), in: text) else { continue }
                if fileRefPaths[String(text[r1])] == nil {
                    dangling.append("\(String(text[r2])) (fileRef \(String(text[r1])))")
                    if dangling.count > 100 { break }
                }
            }
        }
        var lines = ["pbxproj lint for \(pbxproj.lastPathComponent):"]
        lines.append("- File references: \(fileRefPaths.count)")
        lines.append("- Missing files on disk: \(missing.count)")
        lines += missing.sorted().prefix(30).map { "  MISSING: \($0)" }
        lines.append("- Duplicate paths: \(duplicates.count)")
        lines += duplicates.sorted().prefix(20).map { "  DUPLICATE: \($0)" }
        lines.append("- Dangling build-file refs: \(dangling.count)")
        lines += dangling.sorted().prefix(20).map { "  DANGLING: \($0)" }
        let clean = missing.isEmpty && duplicates.isEmpty && dangling.isEmpty
        return .structured(["fileRefCount": .int(fileRefPaths.count), "missingCount": .int(missing.count),
                            "duplicateCount": .int(duplicates.count), "danglingCount": .int(dangling.count),
                            "clean": .bool(clean)],
                           summary: lines.joined(separator: "\n"))
    }

    func projectModelProjectDiff(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let status: GitRunOutput
        do {
            status = try Self.runGit(["status", "--porcelain"], in: root)
        } catch {
            throw MCPToolError("Diff inspection failed: \(error.localizedDescription)")
        }
        guard status.status == 0 else {
            let detail = status.combined.trimmingCharacters(in: .whitespacesAndNewlines)
            throw MCPToolError("Diff inspection failed: \(detail.isEmpty ? "git status exited with status \(status.status)" : detail)")
        }
        var branch = ""
        if let current = try? Self.runGit(["branch", "--show-current"], in: root), current.status == 0 {
            branch = current.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if branch.isEmpty,
           let rev = try? Self.runGit(["rev-parse", "--abbrev-ref", "HEAD"], in: root), rev.status == 0 {
            branch = rev.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if branch.isEmpty || branch == "HEAD" { branch = "(detached)" }
        var staged = 0
        var unstaged = 0
        var modifiedFiles: [String] = []
        for line in status.stdout.components(separatedBy: "\n") where line.count >= 3 {
            let x = line[line.startIndex]
            let y = line[line.index(after: line.startIndex)]
            if x != " " && x != "?" { staged += 1 }
            if y != " " { unstaged += 1 }
            var path = String(line.dropFirst(3))
            if let arrow = path.range(of: " -> ") { path = String(path[arrow.upperBound...]) }
            modifiedFiles.append((path as NSString).lastPathComponent)
        }
        let diff: GitRunOutput
        do {
            diff = try Self.runGit(["diff", "HEAD"], in: root)
        } catch {
            throw MCPToolError("Diff inspection failed: \(error.localizedDescription)")
        }
        guard diff.status == 0 else {
            let detail = diff.combined.trimmingCharacters(in: .whitespacesAndNewlines)
            throw MCPToolError("Diff inspection failed: \(detail.isEmpty ? "git diff exited with status \(diff.status)" : detail)")
        }
        let hunks = diff.stdout.components(separatedBy: "\n").filter { $0.hasPrefix("@@") }.count
        if diff.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && modifiedFiles.isEmpty {
            return .structured(["diff": .string(""), "branch": .string(branch), "staged_count": .int(0), "unstaged_count": .int(0)],
                               summary: "No changes detected. Working tree is clean.")
        }
        let formattedDiff = diff.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let summary = "Git Status on branch '\(branch)': \(staged) staged, \(unstaged) unstaged, \(hunks) diff hunks.\n\n\(formattedDiff)"
        return .structured(["diff": .string(formattedDiff), "branch": .string(branch),
                            "staged_count": .int(staged), "unstaged_count": .int(unstaged)],
                           summary: summary)
    }

    func projectModelProjectSchemeList(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        guard s.model.kind != .package else {
            throw MCPToolError("No .xcodeproj or .xcworkspace found at the top level of the workspace.")
        }
        let schemes = s.model.schemeNames
        return .structured(["schemes": .string(schemes.joined(separator: ",")), "count": .int(schemes.count),
                            "project": .string(s.model.url.lastPathComponent)],
                           summary: "Found \(schemes.count) scheme(s): \(schemes.joined(separator: ", "))")
    }

    func projectModelProjectStructureMap(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let maxDepth = max(1, min(4, call.int("maxDepth") ?? call.arguments["maxDepth"]?.string.flatMap(Int.init) ?? 2))
        var dirCounts: [String: Int] = [:]
        var dirBytes: [String: Int64] = [:]
        for url in Self.projectModelScanFiles(under: root) {
            let rel = Self.relativePath(url.path, root: root.path)
            let parts = rel.split(separator: "/").map(String.init)
            guard parts.count > 1 else { continue }
            for depth in 1...min(maxDepth, parts.count - 1) {
                let dir = parts.prefix(depth).joined(separator: "/")
                dirCounts[dir, default: 0] += 1
                dirBytes[dir, default: 0] += Self.projectModelFileSize(of: url)
            }
        }
        var targets: [String] = []
        if let pbxproj = Self.projectModelFindPbxproj(in: root),
           let (proj, _) = try? Self.projectModelLoadPBXProj(at: pbxproj) {
            targets = proj.targets.compactMap { $0.string("name") }.sorted()
        }
        var lines = ["Project structure map (depth \(maxDepth)):"]
        for dir in dirCounts.keys.sorted() {
            lines.append("- \(dir)/ — \(dirCounts[dir] ?? 0) files, \(dirBytes[dir] ?? 0) bytes")
        }
        if !targets.isEmpty {
            lines.append("Xcode targets: \(targets.joined(separator: ", "))")
        }
        return .structured(["directoryCount": .int(dirCounts.count), "targets": .string(targets.joined(separator: ","))],
                           summary: lines.joined(separator: "\n"))
    }

    func projectModelProjectTargetList(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        var targets = Set<String>()
        var sources: [String] = []
        for pbxURL in Self.projectModelFindPBXProjURLs(in: root) {
            guard let (proj, _) = try? Self.projectModelLoadPBXProj(at: pbxURL) else { continue }
            let scanned = proj.targets.compactMap { $0.string("name") }
            if !scanned.isEmpty {
                targets.formUnion(scanned)
                sources.append(pbxURL.lastPathComponent)
            }
        }
        let sorted = targets.sorted()
        guard !sorted.isEmpty else {
            throw MCPToolError("No Xcode targets found. No .xcodeproj with a project.pbxproj was located in the workspace.")
        }
        return .structured(["targets": .string(sorted.joined(separator: ",")), "count": .int(sorted.count),
                            "sources": .string(sources.joined(separator: ","))],
                           summary: "Found \(sorted.count) target(s): \(sorted.joined(separator: ", "))")
    }

    func projectModelSchemeTestPlanList(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            throw MCPToolError("Cannot enumerate workspace.")
        }
        var plans: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "xctestplan" {
            plans.append(url)
        }
        if plans.isEmpty {
            return .structured(["count": .int(0)], summary: "No .xctestplan files found in the workspace.")
        }
        var lines = ["Test plans (\(plans.count)):"]
        for url in plans.sorted(by: { $0.path < $1.path }) {
            let rel = fileReadingRelativePath(of: url, in: s)
            var detail = ""
            if let data = try? Data(contentsOf: url),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let targets = json["testTargets"] as? [[String: Any]] {
                let names = targets.compactMap { $0["target"] as? [String: Any] }.compactMap { $0["name"] as? String }
                detail = names.isEmpty ? "" : " — targets: " + names.joined(separator: ", ")
            }
            lines.append("- \(rel)\(detail)")
        }
        return .structured(["count": .int(plans.count)], summary: lines.joined(separator: "\n"))
    }

    func projectModelTargetDependenciesList(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        guard let pbxproj = Self.projectModelFindPbxproj(in: root),
              let (proj, _) = try? Self.projectModelLoadPBXProj(at: pbxproj) else {
            throw MCPToolError("No .pbxproj found in the workspace.")
        }
        let targetNames = Dictionary(uniqueKeysWithValues: proj.targets.compactMap { t -> (String, String)? in
            guard let name = t.string("name") else { return nil }
            return (t.id, name)
        })
        guard !targetNames.isEmpty else {
            throw MCPToolError("No PBXNativeTarget entries parsed from the pbxproj.")
        }
        var depToTarget: [String: String] = [:]
        for obj in proj.objects.values where obj.isa == "PBXTargetDependency" {
            if let target = obj.string("target") { depToTarget[obj.id] = target }
        }
        var lines = ["Target dependencies:"]
        var edgeCount = 0
        for target in proj.targets {
            guard let name = target.string("name") else { continue }
            let depNames = target.references("dependencies").compactMap { depToTarget[$0] }.compactMap { targetNames[$0] }.sorted()
            edgeCount += depNames.count
            lines.append("- \(name): \(depNames.isEmpty ? "(no target dependencies)" : depNames.joined(separator: ", "))")
        }
        return .structured(["targetCount": .int(targetNames.count), "edgeCount": .int(edgeCount)],
                           summary: lines.joined(separator: "\n"))
    }

    func projectModelTargetSourceList(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let wanted = call.string("target")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let limit = max(1, min(2000, call.int("limit") ?? call.arguments["limit"]?.string.flatMap(Int.init) ?? 200))
        guard let pbxproj = Self.projectModelFindPbxproj(in: root),
              let (proj, _) = try? Self.projectModelLoadPBXProj(at: pbxproj) else {
            throw MCPToolError("No .pbxproj found in the workspace.")
        }
        var targetSources: [(String, [String])] = []
        for target in proj.targets {
            guard let name = target.string("name") else { continue }
            if let wanted, !wanted.isEmpty, name != wanted { continue }
            var sources: [String] = []
            for phase in proj.buildPhases(ofTarget: target.id) where phase.isa == "PBXSourcesBuildPhase" {
                for buildFileID in phase.references("files") {
                    guard let ref = proj.fileReference(ofBuildFile: buildFileID),
                          let path = ref.string("path") else { continue }
                    sources.append(path)
                }
            }
            targetSources.append((name, sources.sorted()))
        }
        guard !targetSources.isEmpty else {
            if let wanted, !wanted.isEmpty {
                throw MCPToolError("Target '\(wanted)' not found in the pbxproj.")
            }
            throw MCPToolError("No target source phases parsed from the pbxproj.")
        }
        var lines = ["Target sources:"]
        for (name, sources) in targetSources {
            lines.append("- \(name) (\(sources.count) files):")
            lines += sources.prefix(limit).map { "    \($0)" }
            if sources.count > limit { lines.append("    … [truncated: showing \(limit) of \(sources.count)]") }
        }
        return .structured(["targetCount": .int(targetSources.count)], summary: lines.joined(separator: "\n"))
    }

    func projectModelWorkspaceSettingsRead(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let settingsFiles = Self.projectModelScanFiles(under: root, extensions: ["xcsettings"])
        if settingsFiles.isEmpty {
            return .structured(["count": .int(0)], summary: "No .xcsettings files found (default Xcode workspace settings apply).")
        }
        var lines = ["Workspace settings files (\(settingsFiles.count)):"]
        for url in settingsFiles.sorted(by: { $0.path < $1.path }) {
            let rel = fileReadingRelativePath(of: url, in: s)
            lines.append("- \(rel):")
            if let data = try? Data(contentsOf: url),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
                for (key, value) in plist.sorted(by: { $0.key < $1.key }) {
                    lines.append("    \(key) = \(String(describing: value).prefix(120))")
                }
            } else {
                lines.append("    (unreadable plist)")
            }
        }
        return .structured(["count": .int(settingsFiles.count)], summary: lines.joined(separator: "\n"))
    }

    func projectModelXcodeBuildSettingsInspector(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let target = call.string("target")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let specificKey = call.string("settingKey")?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let pbxproj = Self.projectModelFindPbxproj(in: root),
              let (proj, _) = try? Self.projectModelLoadPBXProj(at: pbxproj) else {
            return .text("No Xcode build settings returned. Ensure an .xcodeproj exists in the workspace.")
        }
        if let target, !target.isEmpty, proj.targets.first(where: { $0.string("name") == target }) == nil {
            throw MCPToolError("Target '\(target)' not found in project.pbxproj.")
        }
        let configuration = Self.projectModelDefaultConfiguration(proj)
        let (settings, _, _) = Self.projectModelMergedSettings(proj, targetName: target, configuration: configuration)
        if let key = specificKey, !key.isEmpty {
            if let val = settings[key] {
                return .text("\(key) = \(val)")
            }
            throw MCPToolError("Build setting '\(key)' was not found in xcodebuild output.")
        }
        if settings.isEmpty {
            return .text("No Xcode build settings returned. Ensure an .xcodeproj exists in the workspace.")
        }
        let keySettings = [
            "TARGET_NAME", "PRODUCT_NAME", "PRODUCT_BUNDLE_IDENTIFIER", "SWIFT_VERSION",
            "IPHONEOS_DEPLOYMENT_TARGET", "MACOSX_DEPLOYMENT_TARGET", "SDK_NAME", "ARCHS",
            "CONFIGURATION", "INFOPLIST_FILE", "ENABLE_PREVIEWS",
        ]
        var summary = "### Active Xcode Build Settings:\n\n"
        for k in keySettings {
            if let v = settings[k] {
                summary += "- **\(k)**: `\(v)`\n"
            }
        }
        return .text(summary)
    }

    func projectModelXcodeSchemeManager(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        guard let actionRaw = call.arguments["action"]?.string else {
            throw MCPToolError("Missing required parameter: action")
        }
        switch actionRaw.lowercased() {
        case "list_schemes", "list":
            guard s.model.kind != .package else {
                throw MCPToolError("No .xcodeproj or .xcworkspace found at the top level of the workspace.")
            }
            let schemes = s.model.schemeNames
            return .text("Xcode Schemes & Targets:\n\(schemes.joined(separator: "\n"))")
        case "inspect_scheme":
            guard let schemeName = call.string("schemeName"), !schemeName.isEmpty else {
                throw MCPToolError("schemeName parameter is required for inspect_scheme")
            }
            guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
                throw MCPToolError("Scheme file '\(schemeName).xcscheme' not found in workspace.")
            }
            var found: [URL] = []
            for case let url as URL in enumerator where url.lastPathComponent == "\(schemeName).xcscheme" {
                found.append(url)
            }
            guard let fileURL = found.sorted(by: { $0.path < $1.path }).first,
                  let xmlContent = try? String(contentsOf: fileURL, encoding: .utf8) else {
                throw MCPToolError("Scheme file '\(schemeName).xcscheme' not found in workspace.")
            }
            return .text("Scheme '\(schemeName)' found at \(fileURL.lastPathComponent):\n\n\(xmlContent.prefix(2000))")
        default:
            throw MCPToolError("Unsupported action '\(actionRaw)'. Valid: list_schemes, inspect_scheme")
        }
    }
}

extension YcodeMCPHost {
    // MARK: - Writing tools

    func projectModelCreateNewApp(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        guard let appName = call.arguments["appName"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !appName.isEmpty else {
            throw MCPToolError("Missing required parameter: appName")
        }
        guard let applicationDescription = call.arguments["applicationDescription"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !applicationDescription.isEmpty else {
            throw MCPToolError("Missing required parameter: applicationDescription")
        }
        _ = applicationDescription // Required by Legacy's schema; the
        // description is not stored anywhere in Ycode's project model.
        let platform = call.string("platform") ?? "macOS"
        let version = call.string("version") ?? "1.0"
        let build = call.string("build") ?? "1"
        let rawBundle = call.string("bundleIdentifier") ?? ""
        let safeName = appName.replacingOccurrences(of: " ", with: "")
        let bundleIdentifier = rawBundle.isEmpty ? "com.swiftcode.\(safeName.lowercased())" : rawBundle
        let targetDir: URL
        if let location = call.string("projectLocation"), !location.isEmpty {
            targetDir = try resolve(location, in: s)
        } else {
            targetDir = root.appendingPathComponent(appName)
        }
        if FileManager.default.fileExists(atPath: targetDir.path),
           !((try? FileManager.default.contentsOfDirectory(atPath: targetDir.path))?.isEmpty ?? true) {
            throw MCPToolError("Project directory '\(targetDir.path)' already exists.")
        }
        let tab: String
        switch platform.lowercased() {
        case "ios", "ipados": tab = "iOS"
        case "watchos": tab = "watchOS"
        case "visionos": tab = "visionOS"
        default: tab = "macOS"
        }
        guard let descriptor = ProjectTemplates.all.first(where: { $0.platform == tab && $0.title == "App" }) else {
            throw MCPToolError("No app template for platform '\(platform)'.")
        }
        let orgPrefix: String
        let bundleParts = bundleIdentifier.split(separator: ".").map(String.init)
        if bundleParts.count >= 2 {
            orgPrefix = bundleParts.dropLast().joined(separator: ".")
        } else {
            orgPrefix = "com.swiftcode"
        }
        let form = descriptor.makeForm(values: [
            TemplateOptionID.productName: appName,
            TemplateOptionID.organizationIdentifier: orgPrefix,
            TemplateOptionID.interface: "SwiftUI",
            TemplateOptionID.lifecycle: "SwiftUI",
            TemplateOptionID.language: "Swift",
            TemplateOptionID.testingSystem: "None",
            TemplateOptionID.storage: "None",
            TemplateOptionID.hostInCloudKit: "false",
        ])
        let generated: GeneratedProject
        do {
            generated = try ProjectGenerator.generate(descriptor, form)
        } catch {
            throw MCPToolError(error.localizedDescription)
        }
        for (rel, text) in generated.files.sorted(by: { $0.0 < $1.0 }) {
            guard !rel.hasSuffix("/") else { continue }
            let url = targetDir.appendingPathComponent(rel)
            let relPath = relative(url.path, in: s)
            try await commit(MCPChange(tool: call.name, path: url.path, relativePath: relPath, original: nil, proposed: text,
                                       summary: "Create \(relPath)"), call: call, session: s)
        }
        if let project = generated.project {
            let pbxURL = targetDir.appendingPathComponent("\(generated.projectName).xcodeproj/project.pbxproj")
            let pbxRel = relative(pbxURL.path, in: s)
            try await commit(MCPChange(tool: call.name, path: pbxURL.path, relativePath: pbxRel, original: nil,
                                       proposed: project.serialized(projectName: generated.projectName),
                                       summary: "Create \(pbxRel)"), call: call, session: s)
            let wsURL = targetDir.appendingPathComponent("\(generated.projectName).xcodeproj/project.xcworkspace/contents.xcworkspacedata")
            let wsRel = relative(wsURL.path, in: s)
            try await commit(MCPChange(tool: call.name, path: wsURL.path, relativePath: wsRel, original: nil,
                                       proposed: Self.projectModelSelfWorkspace, summary: "Create \(wsRel)"),
                             call: call, session: s)
        }
        return .text("""
        Successfully initialized Create New App workflow for '\(appName)'.
        Target Directory: \(targetDir.path)
        Bundle Identifier: \(bundleIdentifier)
        Platform: \(platform)
        Version: \(version) (\(build))
        Scaffolded with Ycode's '\(tab) App' template.
        Ready for autonomous implementation and iteration.
        """)
    }

    /// The embedded workspace every Ycode project carries (one
    /// `self:` FileRef), as `GeneratedProject.write` writes it.
    nonisolated static let projectModelSelfWorkspace = """
    <?xml version="1.0" encoding="UTF-8"?>
    <Workspace
       version = "1.0">
       <FileRef
          location = "self:">
       </FileRef>
    </Workspace>

    """

    func projectModelGenerateXcodeproj(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let spec = call.string("spec") ?? "project.yml"
        let useCache = (call.string("useCache") ?? "false").lowercased() == "true"
        let specURL = try resolveFileReadingPath(spec, in: s)
        guard FileManager.default.fileExists(atPath: specURL.path) else {
            throw MCPToolError("XcodeGen spec not found at '\(spec)' (resolved to \(specURL.path)). Create a project.yml first or pass the spec parameter.")
        }
        guard let specText = try? String(contentsOf: specURL, encoding: .utf8) else {
            throw MCPToolError("XcodeGen spec not found at '\(spec)' (resolved to \(specURL.path)). Create a project.yml first or pass the spec parameter.")
        }
        var projectName: String?
        for line in specText.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("name:") else { continue }
            var value = trimmed.dropFirst("name:".count).trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            if !value.isEmpty { projectName = String(value) }
            break
        }
        guard let projectName else {
            throw MCPToolError("Could not determine the project name from '\(spec)'; xcodegen output cannot be approved as a change.")
        }
        let bundleURL = root.appendingPathComponent("\(projectName).xcodeproj")
        let change = MCPChange(tool: call.name, path: bundleURL.path, relativePath: "\(projectName).xcodeproj", original: nil, proposed: "",
                               summary: "Generate \(projectName).xcodeproj from \(spec) with xcodegen")
        guard await call.approve(change) else {
            throw MCPToolError(MCPServer.rejectedMessage)
        }
        guard let xcodegen = await Self.projectModelFindXcodegen() else {
            throw MCPToolError("xcodegen is not installed and Homebrew was not found. Install Homebrew (https://brew.sh), then run this tool again — it will install xcodegen automatically.")
        }
        let startTime = Date()
        var arguments = ["generate", "--spec", specURL.path]
        if useCache { arguments.append("--use-cache") }
        let run = await Task.detached {
            Self.terminalRunFixed(xcodegen, arguments, workingDirectory: root, timeout: 300)
        }.value
        guard let run else {
            throw MCPToolError("xcodegen execution failed: could not start xcodegen.")
        }
        if run.timedOut {
            throw MCPToolError("xcodegen timed out after 300s.")
        }
        let duration = Date().timeIntervalSince(startTime)
        let durationText = String(format: "%.2fs", duration)
        let produced = ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? [])
            .filter { $0.pathExtension == "xcodeproj" }.map { $0.lastPathComponent }.sorted()
        if run.exitCode == 0, !produced.isEmpty {
            return .structured(["spec": .string(spec), "projects": .string(produced.joined(separator: ",")),
                                "duration": .string(durationText)],
                               summary: "XcodeGen succeeded (\(durationText)). Generated: \(produced.joined(separator: ", "))\n\(run.stdout.suffix(1200))")
        }
        let combined = run.stdout + "\n" + run.stderr
        throw MCPToolError("XcodeGen failed (exit \(run.exitCode), \(durationText)):\n\(combined.suffix(1500))")
    }

    /// Locates `xcodegen` at the known Homebrew paths or on `PATH`.
    /// Never installs anything.
    nonisolated static func projectModelFindXcodegen() async -> String? {
        let candidates = [
            "/opt/homebrew/bin/xcodegen",
            "/usr/local/bin/xcodegen",
            "/opt/homebrew/opt/xcodegen/bin/xcodegen",
        ]
        for path in candidates where FileManager.default.fileExists(atPath: path) {
            return path
        }
        let which = await Task.detached {
            Self.terminalRunFixed("/usr/bin/which", ["xcodegen"], timeout: 30)
        }.value
        if let which, which.exitCode == 0 {
            let found = which.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !found.isEmpty, FileManager.default.fileExists(atPath: found) { return found }
        }
        return nil
    }

    func projectModelProjectBuildSettings(_ call: MCPToolCall) async throws -> MCPToolResult {
        let action = (call.string("action") ?? "read").lowercased()
        let configuration = (call.string("configuration") ?? "Debug").trimmingCharacters(in: .whitespacesAndNewlines)
        let target = call.string("target")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = call.string("key")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = call.string("value")?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard action == "read" || action == "set" else {
            throw MCPToolError("Invalid action '\(action)'. Expected read or set.")
        }
        guard !configuration.isEmpty else {
            throw MCPToolError("Missing required parameter: configuration")
        }
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        guard let pbxURL = Self.projectModelFindPbxproj(in: root) else {
            throw MCPToolError("No project.pbxproj found in the workspace.")
        }
        if action == "set" {
            guard let key, !key.isEmpty else { throw MCPToolError("Missing required parameter: key for action=set") }
            guard let value, !value.isEmpty else { throw MCPToolError("Missing required parameter: value for action=set") }
            guard Self.projectModelIsValidSettingKey(key) else { throw MCPToolError("Invalid build setting key '\(key)'.") }
            var (proj, text) = try Self.projectModelLoadPBXProj(at: pbxURL)
            let listID: String?
            if let target, !target.isEmpty {
                guard let targetObj = proj.targets.first(where: { $0.string("name") == target }) else {
                    throw MCPToolError("Target '\(target)' not found in project.pbxproj.")
                }
                listID = targetObj.string("buildConfigurationList")
            } else {
                listID = proj.project?.string("buildConfigurationList")
            }
            guard let config = proj.buildConfigurations(listID: listID).first(where: { $0.string("name") == configuration }) else {
                throw MCPToolError("No XCBuildConfiguration block for configuration '\(configuration)' found in project.pbxproj.")
            }
            proj.setBuildSetting(key, .string(value), configuration: config.id)
            let updated = proj.serialized(projectName: Self.projectModelProjectName(for: pbxURL))
            let rel = fileReadingRelativePath(of: pbxURL, in: s)
            do {
                try await commit(MCPChange(tool: call.name, path: pbxURL.path, relativePath: rel, original: text, proposed: updated,
                                           summary: "Set build setting \(key) = \(value) in project.pbxproj"), call: call, session: s)
            } catch let error as MCPToolError where error.message == MCPServer.rejectedMessage {
                throw error
            } catch {
                throw MCPToolError("Failed to write project.pbxproj: \(error.localizedDescription)")
            }
            guard let (verifyProj, _) = try? Self.projectModelLoadPBXProj(at: pbxURL),
                  let verifyConfig = verifyProj.buildConfigurations(listID: listID).first(where: { $0.string("name") == configuration }),
                  verifyConfig["buildSettings"]?.dictionary?[key]?.string == value else {
                throw MCPToolError("Verification failed: '\(key) = \(value);' not found after writing project.pbxproj.")
            }
            return .structured(["key": .string(key), "value": .string(value), "configuration": .string(configuration),
                                "file": .string("project.pbxproj")],
                               summary: "Set build setting \(key) = \(value) for configuration '\(configuration)'.")
        }
        let (proj, _) = try Self.projectModelLoadPBXProj(at: pbxURL)
        if let target, !target.isEmpty, proj.targets.first(where: { $0.string("name") == target }) == nil {
            throw MCPToolError("Target '\(target)' not found in project.pbxproj.")
        }
        let (settings, _, configFound) = Self.projectModelMergedSettings(proj, targetName: target, configuration: configuration)
        guard configFound else {
            throw MCPToolError("No XCBuildConfiguration block for configuration '\(configuration)' found in project.pbxproj.")
        }
        if let key, !key.isEmpty {
            guard let found = settings[key] else {
                throw MCPToolError("Build setting '\(key)' not found for configuration '\(configuration)'.")
            }
            return .structured(["key": .string(key), "value": .string(found), "configuration": .string(configuration)],
                               summary: "Build setting \(key) = \(found)")
        }
        let preview = settings.sorted { $0.key < $1.key }.prefix(50).map { "\($0.key) = \($0.value)" }.joined(separator: "\n")
        return .structured(["count": .string("\(settings.count)"), "configuration": .string(configuration),
                            "settings": .string(preview)],
                           summary: "Found \(settings.count) build setting(s) for configuration '\(configuration)'.")
    }

    func projectModelProjectCapabilities(_ call: MCPToolCall) async throws -> MCPToolResult {
        let action = (call.string("action") ?? "list").lowercased()
        guard action == "list" || action == "enable" || action == "disable" else {
            throw MCPToolError("Invalid action '\(action)'. Expected list, enable, or disable.")
        }
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        if action == "list" {
            let entitlementsCaps = Self.projectModelEntitlementCapabilities(in: root)
            let pbxCaps = Self.projectModelPbxprojCapabilities(in: root)
            let all = Array(Set(entitlementsCaps + pbxCaps)).sorted()
            let summary = all.isEmpty ? "No capabilities found." : "Capabilities: \(all.joined(separator: ", "))"
            return .structured(["capabilities": .string(all.joined(separator: ",")), "count": .int(all.count),
                                "entitlements": .string(entitlementsCaps.joined(separator: ",")),
                                "pbxproj": .string(pbxCaps.joined(separator: ","))],
                               summary: summary)
        }
        guard let rawCapability = call.string("capability")?.trimmingCharacters(in: .whitespacesAndNewlines), !rawCapability.isEmpty else {
            throw MCPToolError("Missing required parameter: capability for action=\(action)")
        }
        guard let mapping = Self.projectModelCapabilityMapping(for: rawCapability) else {
            throw MCPToolError("Unknown capability '\(rawCapability)'. Supported: push, icloud, appGroups, appSandbox, keychain, network.")
        }
        guard let entitlementsURL = Self.projectModelFindEntitlementsFile(in: root) else {
            throw MCPToolError("No .entitlements file found in the workspace. Cannot \(action) capability '\(rawCapability)'.")
        }
        guard var dict = Self.projectModelReadPlist(at: entitlementsURL) else {
            throw MCPToolError("Entitlements file '\(entitlementsURL.lastPathComponent)' is not a valid property list dictionary.")
        }
        // The proposal's `original` is the file's text when it is
        // XML; a binary plist has no text form, so its XML
        // re-serialisation stands in (commit only writes `proposed`).
        let original = text(of: entitlementsURL) ?? Self.projectModelPlistXML(dict)
        if action == "enable" {
            dict[mapping.key] = mapping.defaultValue
        } else {
            guard dict[mapping.key] != nil else {
                throw MCPToolError("Capability '\(rawCapability)' (\(mapping.key)) is not enabled in entitlements.")
            }
            dict.removeValue(forKey: mapping.key)
        }
        guard let proposed = Self.projectModelPlistXML(dict) else {
            throw MCPToolError("Failed to write entitlements file.")
        }
        let rel = fileReadingRelativePath(of: entitlementsURL, in: s)
        do {
            try await commit(MCPChange(tool: call.name, path: entitlementsURL.path, relativePath: rel, original: original, proposed: proposed,
                                       summary: "\(action == "enable" ? "Enable" : "Disable") capability '\(rawCapability)' in \(rel)"),
                             call: call, session: s)
        } catch let error as MCPToolError where error.message == MCPServer.rejectedMessage {
            throw error
        } catch {
            throw MCPToolError("Failed to write entitlements file.")
        }
        guard let verify = Self.projectModelReadPlist(at: entitlementsURL) else {
            throw MCPToolError("Verification failed: could not re-read entitlements file.")
        }
        if action == "enable" {
            guard verify[mapping.key] != nil else {
                throw MCPToolError("Verification failed: '\(mapping.key)' not present after enabling '\(rawCapability)'.")
            }
            return .structured(["capability": .string(rawCapability), "entitlementsKey": .string(mapping.key), "action": .string("enable")],
                               summary: "Enabled capability '\(rawCapability)' (\(mapping.key)) in \(entitlementsURL.lastPathComponent).")
        }
        guard verify[mapping.key] == nil else {
            throw MCPToolError("Verification failed: '\(mapping.key)' still present after disabling '\(rawCapability)'.")
        }
        return .structured(["capability": .string(rawCapability), "entitlementsKey": .string(mapping.key), "action": .string("disable")],
                           summary: "Disabled capability '\(rawCapability)' (\(mapping.key)) in \(entitlementsURL.lastPathComponent).")
    }

    nonisolated static func projectModelCapabilityMapping(for name: String) -> (key: String, defaultValue: Any)? {
        switch name.lowercased() {
        case "push", "aps", "aps-environment":
            return ("aps-environment", "development")
        case "icloud", "cloudkit":
            return ("com.apple.developer.icloud-container-identifiers", [] as [String])
        case "appgroups", "app-groups", "app_groups":
            return ("com.apple.security.application-groups", [] as [String])
        case "appsandbox", "app-sandbox", "app_sandbox":
            return ("com.apple.security.app-sandbox", true)
        case "keychain", "keychain-access-groups":
            return ("keychain-access-groups", [] as [String])
        case "network", "network-client":
            return ("com.apple.security.network.client", true)
        default:
            return nil
        }
    }

    nonisolated static func projectModelEntitlementCapabilities(in root: URL) -> [String] {
        guard let url = projectModelFindEntitlementsFile(in: root),
              let dict = projectModelReadPlist(at: url) else { return [] }
        var caps: [String] = []
        for key in dict.keys {
            if key == "aps-environment" { caps.append("push") }
            else if key.contains("icloud") { caps.append("icloud") }
            else if key.contains("application-groups") { caps.append("appGroups") }
            else if key.contains("app-sandbox") { caps.append("appSandbox") }
            else if key.contains("keychain") { caps.append("keychain") }
            else if key.contains("network.client") { caps.append("network") }
            else { caps.append(key) }
        }
        return caps
    }

    nonisolated static func projectModelPbxprojCapabilities(in root: URL) -> [String] {
        guard let pbxURL = projectModelFindPbxproj(in: root),
              let content = try? String(contentsOf: pbxURL, encoding: .utf8) else { return [] }
        var caps: [String] = []
        for line in content.components(separatedBy: "\n") where line.contains("SystemCapabilities") {
            caps.append(line.trimmingCharacters(in: .whitespaces))
        }
        return caps
    }

    nonisolated static func projectModelFindEntitlementsFile(in root: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return nil
        }
        var found: [URL] = []
        for case let url as URL in enumerator where url.pathExtension == "entitlements" {
            found.append(url)
        }
        return found.sorted { $0.path < $1.path }.first
    }

    func projectModelProjectMutationController(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let actionRaw = call.arguments["action"]?.string else {
            throw MCPToolError("Missing action: add/remove/repair")
        }
        let action = actionRaw.lowercased()
        guard !action.isEmpty else {
            throw MCPToolError("Missing action: add/remove/repair")
        }
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let pbxURL: URL
        let pbxRel: String
        if let explicit = call.string("projectFile"), !explicit.isEmpty {
            pbxURL = try resolveFileReadingPath(explicit, in: s)
            pbxRel = fileReadingRelativePath(of: pbxURL, in: s)
        } else if let located = Self.projectModelTopLevelProject(in: root) {
            pbxURL = located.appendingPathComponent("project.pbxproj")
            pbxRel = fileReadingRelativePath(of: pbxURL, in: s)
        } else {
            throw MCPToolError("No Xcode project (.xcodeproj) found in the workspace root. Pass projectFile explicitly.")
        }
        guard let pbxText = text(of: pbxURL) else {
            throw MCPToolError("Could not read \(pbxRel): project.pbxproj does not exist or cannot be read.")
        }
        var proj: PBXProj
        do {
            proj = try PBXProj(parsing: pbxText)
        } catch {
            throw MCPToolError("Could not read \(pbxRel): \(error.localizedDescription)")
        }
        switch action {
        case "repair":
            let updated = pbxText.replacingOccurrences(of: "\n\n\n", with: "\n\n")
            try await commit(MCPChange(tool: call.name, path: pbxURL.path, relativePath: pbxRel, original: pbxText, proposed: updated,
                                       summary: "Repair formatting in \(pbxRel)"), call: call, session: s)
            return .structured(["project": .string(pbxRel)], summary: "Project mutation complete: \(action)")
        case "add":
            guard let filePath = call.arguments["filePath"]?.string else {
                throw MCPToolError("Missing filePath")
            }
            let fileName = (filePath as NSString).lastPathComponent
            let fileDir = (filePath as NSString).deletingLastPathComponent
            if pbxText.contains(filePath) || pbxText.contains(fileName) {
                return .text("File already referenced in project.pbxproj: \(filePath)")
            }
            guard let groupID = Self.projectModelGroupID(forFileDirectory: fileDir, in: proj) else {
                throw MCPToolError("No matching group found in \(pbxRel) for directory '\(fileDir)'. Create the group in Xcode first or pass a filePath inside an existing group.")
            }
            guard let sourcesPhaseID = Self.projectModelSourcesPhaseID(in: proj) else {
                throw MCPToolError("No PBXSourcesBuildPhase ('Sources') found in \(pbxRel).")
            }
            let fileRefID = proj.addFileReference(path: fileName, to: groupID)
            proj.addBuildFile(fileReference: fileRefID, to: sourcesPhaseID)
            let updated = proj.serialized(projectName: Self.projectModelProjectName(for: pbxURL))
            try await commit(MCPChange(tool: call.name, path: pbxURL.path, relativePath: pbxRel, original: pbxText, proposed: updated,
                                       summary: "Add \(fileName) to \(pbxRel)"), call: call, session: s)
            return .structured(["project": .string(pbxRel)],
                               summary: "Project mutation complete: added \(fileName) via 4-step registration protocol")
        case "remove":
            guard let filePath = call.arguments["filePath"]?.string else {
                throw MCPToolError("Missing filePath")
            }
            let fileName = (filePath as NSString).lastPathComponent
            // Collect first, then mutate: removing while iterating the
            // object graph would mutate during enumeration.
            let matches = proj.objects.values.filter { $0.isa == "PBXFileReference" }.filter {
                $0.string("path") == filePath || $0.string("path") == fileName || $0.string("name") == fileName
            }.map(\.id)
            var removed = false
            for id in matches {
                proj.removeFileReference(id)
                removed = true
            }
            if removed {
                let updated = proj.serialized(projectName: Self.projectModelProjectName(for: pbxURL))
                try await commit(MCPChange(tool: call.name, path: pbxURL.path, relativePath: pbxRel, original: pbxText, proposed: updated,
                                           summary: "Remove \(fileName) from \(pbxRel)"), call: call, session: s)
            }
            return .structured(["project": .string(pbxRel)], summary: "Project mutation complete: \(action)")
        default:
            throw MCPToolError("Unsupported action: \(action)")
        }
    }

    func projectModelProjectTargetAdd(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let rawName = call.arguments["targetName"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !rawName.isEmpty else {
            throw MCPToolError("Missing required parameter: targetName")
        }
        let type = (call.string("type") ?? "app").lowercased()
        guard type == "app" || type == "framework" || type == "test" else {
            throw MCPToolError("Invalid type '\(type)'. Expected app, framework, or test.")
        }
        let bundleId = call.string("bundleId")?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.projectModelIsValidTargetName(rawName) else {
            throw MCPToolError("Invalid target name '\(rawName)'. Use letters, digits, underscore, or hyphen only.")
        }
        if let bundleId, !bundleId.isEmpty, !Self.projectModelIsValidBundleId(bundleId) {
            throw MCPToolError("Invalid bundleId '\(bundleId)'.")
        }
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        guard let pbxURL = Self.projectModelFindPbxproj(in: root) else {
            throw MCPToolError("No project.pbxproj found in the workspace.")
        }
        var (proj, text) = try Self.projectModelLoadPBXProj(at: pbxURL)
        if proj.targets.contains(where: { $0.string("name") == rawName }) {
            throw MCPToolError("Target '\(rawName)' already exists in project.pbxproj.")
        }
        let targetDir = root.appendingPathComponent(rawName)
        if FileManager.default.fileExists(atPath: targetDir.path) {
            throw MCPToolError("Directory '\(rawName)' already exists in the workspace. No changes were made.")
        }
        let typeName = Self.projectModelSwiftTypeName(for: rawName)
        let swiftFile = "\(typeName).swift"
        let swiftContent = Self.projectModelSwiftSource(for: rawName, type: type)
        let productType: String
        let productPath: String
        let productFileType: String
        switch type {
        case "framework":
            productType = "com.apple.product-type.framework"
            productPath = "\(rawName).framework"
            productFileType = "wrapper.framework"
        case "test":
            productType = "com.apple.product-type.bundle.unit-test"
            productPath = "\(rawName).xctest"
            productFileType = "wrapper.cfbundle"
        default:
            productType = "com.apple.product-type.application"
            productPath = "\(rawName).app"
            productFileType = "wrapper.application"
        }
        var settings: [(String, PlistValue)] = [("PRODUCT_NAME", .string("$(TARGET_NAME)"))]
        if let bundleId, !bundleId.isEmpty {
            settings.append(("PRODUCT_BUNDLE_IDENTIFIER", .string(bundleId)))
        }
        let objectVersion = Int(proj.objectVersion) ?? 0
        let targetID = proj.addTarget(PBXProj.NewTarget(name: rawName, productType: productType, productPath: productPath,
                                                        productFileType: productFileType, settings: settings, phases: [],
                                                        sourceFolder: objectVersion >= 77 ? rawName : nil))
        if objectVersion < 77 {
            proj.addSourceGroup(path: rawName)
        }
        let updated = proj.serialized(projectName: Self.projectModelProjectName(for: pbxURL))
        let fileURL = targetDir.appendingPathComponent(swiftFile)
        let fileRel = relative(fileURL.path, in: s)
        do {
            try await commit(MCPChange(tool: call.name, path: fileURL.path, relativePath: fileRel, original: nil, proposed: swiftContent,
                                       summary: "Create \(fileRel)"), call: call, session: s)
        } catch let error as MCPToolError where error.message == MCPServer.rejectedMessage {
            throw error
        } catch {
            throw MCPToolError("Failed to create target source files: \(error.localizedDescription)")
        }
        let pbxRel = fileReadingRelativePath(of: pbxURL, in: s)
        do {
            try await commit(MCPChange(tool: call.name, path: pbxURL.path, relativePath: pbxRel, original: text, proposed: updated,
                                       summary: "Add target \(rawName) to \(pbxRel)"), call: call, session: s)
        } catch let error as MCPToolError where error.message == MCPServer.rejectedMessage {
            throw error
        } catch {
            throw MCPToolError("Failed to write project.pbxproj: \(error.localizedDescription)")
        }
        guard let (verifyProj, _) = try? Self.projectModelLoadPBXProj(at: pbxURL),
              verifyProj.targets.contains(where: { $0.string("name") == rawName }) else {
            throw MCPToolError("Verification failed: target '\(rawName)' not found after writing project.pbxproj.")
        }
        return .structured(["targetName": .string(rawName), "type": .string(type), "targetId": .string(targetID),
                            "sourceDirectory": .string(rawName)],
                           summary: "Added target '\(rawName)' (\(type)) with source directory '\(rawName)/'.")
    }

    nonisolated static func projectModelSwiftTypeName(for targetName: String) -> String {
        let cleaned = targetName.replacingOccurrences(of: "-", with: "_")
        guard let first = cleaned.first else { return "Main" }
        return String(first).uppercased() + String(cleaned.dropFirst())
    }

    nonisolated static func projectModelSwiftSource(for targetName: String, type: String) -> String {
        let typeName = projectModelSwiftTypeName(for: targetName)
        switch type {
        case "framework":
            return "import Foundation\n\n/// \(targetName) framework entry point.\npublic struct \(typeName) {\n    public init() {}\n}\n"
        case "test":
            return "import XCTest\n\nfinal class \(typeName)Tests: XCTestCase {\n    func testExample() {\n        XCTAssertTrue(true)\n    }\n}\n"
        default:
            return "import Foundation\n\n/// \(targetName) app entry point.\npublic struct \(typeName)App {\n    public init() {}\n}\n"
        }
    }
}

extension YcodeMCPHost {
    // MARK: - Snapshots

    func projectModelProjectSnapshot(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let message = call.string("message") ?? "Manual Snapshot"
        let snapshotId = UUID().uuidString
        do {
            let snapshotsDir = try Self.projectModelSnapshotsDirectory()
            let snapshotURL = snapshotsDir.appendingPathComponent(snapshotId, isDirectory: true)
            try FileManager.default.createDirectory(at: snapshotURL, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: root, to: snapshotURL.appendingPathComponent("files", isDirectory: true))
            let metadata: [String: Any] = [
                "id": snapshotId,
                "timestamp": ISO8601DateFormatter().string(from: Date()),
                "message": message,
                "rootPath": root.path,
            ]
            let metadataData = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            try metadataData.write(to: snapshotURL.appendingPathComponent("metadata.json"))
        } catch {
            throw MCPToolError("Failed to create snapshot: \(error.localizedDescription)")
        }
        return .structured(["snapshot_id": .string(snapshotId)],
                           summary: "Successfully created project snapshot: \(message)")
    }

    func projectModelProjectRestore(_ call: MCPToolCall) async throws -> MCPToolResult {
        guard let snapshotId = call.arguments["snapshot_id"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !snapshotId.isEmpty else {
            throw MCPToolError("Missing required parameter: snapshot_id")
        }
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let filesURL: URL
        do {
            let snapshotsDir = try Self.projectModelSnapshotsDirectory()
            filesURL = snapshotsDir.appendingPathComponent(snapshotId, isDirectory: true).appendingPathComponent("files", isDirectory: true)
        } catch {
            throw MCPToolError("Failed to restore snapshot: \(error.localizedDescription)")
        }
        guard FileManager.default.fileExists(atPath: filesURL.path) else {
            throw MCPToolError("Failed to restore snapshot: Snapshot '\(snapshotId)' not found.")
        }
        let change = MCPChange(tool: call.name, path: root.path, relativePath: ".", original: nil, proposed: "",
                               summary: "Restore project to snapshot \(snapshotId) — replaces all files in the workspace")
        guard await call.approve(change) else {
            throw MCPToolError(MCPServer.rejectedMessage)
        }
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            for url in contents {
                try FileManager.default.removeItem(at: url)
            }
            let restoredContents = try FileManager.default.contentsOfDirectory(at: filesURL, includingPropertiesForKeys: nil)
            for url in restoredContents {
                try FileManager.default.copyItem(at: url, to: root.appendingPathComponent(url.lastPathComponent))
            }
        } catch {
            throw MCPToolError("Failed to restore snapshot: \(error.localizedDescription)")
        }
        return .text("Successfully restored project to snapshot: \(snapshotId)")
    }
}
