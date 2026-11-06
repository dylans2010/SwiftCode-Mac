import Foundation
import SwiftCodeAssistant
import SwiftCodeBuild
import SwiftCodeIDECore

/// The ported Legacy project / Xcode / build tool family (Wave 7,
/// slice A).
///
/// Behaviour source: Legacy's `AssistBuildProjectTool`,
/// `AssistTestRunnerTool`, `AssistProjectCleanTool`,
/// `AssistProjectArchiveTool`, `AssistBuildLogAnalyzeTool`,
/// `AssistBuildSystemDetectTool`, `AssistBuildConfigurationListTool`,
/// `AssistBuildSettingsDiffTool`, `AssistBuildPhaseScriptsListTool`,
/// `AssistXCResultParserTool`, `AssistDerivedDataLocateTool`,
/// `AssistXcodeToolchainInfoTool` and
/// `AssistXcodeDeviceDestinationTool` (Dylan's own code, ported under
/// MIT). Full per-tool behaviour, including the deliberate deviations,
/// is in `~/SwiftCode-Migration-Workspace/scratch/wave7-slice-a-spec.md`.
///
/// Conventions, following Waves 1–6:
///
/// * Schemas are Legacy's `parametersSchema` verbatim, plus the
///   `workspace` parameter every SwiftCode tool carries. Legacy's
///   parameter-name aliases are NOT supported: SwiftCode's argument
///   validation rejects unknown arguments before the handler runs.
///   The Legacy aliases for this slice (`build` / `build_project` /
///   `run_build` / `xcodebuild` → `project_build`, `test` /
///   `run_tests` → `project_test`, `xcresult` → `xcresult_parser`,
///   `device_destinations` →
///   `xcode_device_destination_finder`) live in
///   `MCPServer.toolAliases`, which the coordinator owns — they are
///   not added here. (`build` and `test` must NOT be added there:
///   they would collide with SwiftCode's native `build` / `test`.)
/// * Structured data keeps Legacy's keys, with typed JSON values
///   (integers) the way SwiftCode's other tools do — Legacy's
///   string-only map is not reproduced. Tools whose Legacy result
///   carries no data (`xcresult_parser`,
///   `xcode_device_destination_finder`) return a plain text result.
/// * Paths resolve through the session resolvers
///   (`resolveFileReadingPath`, `resolve`) and never escape the
///   workspace, with two deliberate, read-only exceptions:
///   `xcresult_parser` searches the user's own DerivedData for
///   `.xcresult` bundles (its Legacy default) and accepts an
///   explicit bundle path as-is; `derived_data_locate` lists the
///   user's own DerivedData directory.
/// * Approval gating: the one writing tool (`project_clean`) is
///   `writes: true` with `destructive` annotations; its `build/`
///   removal goes through an explicit `MCPChange` + `approve()`.
///   `project_archive` is an execution tool (`writes: false`): it
///   creates the `.xcarchive` as its build product, the way the
///   `build` tool creates build products. There is no Autopilot
///   bypass.
/// * Build/test execution reuses SwiftCode's own build seam — the
///   session's `build(.build)` / `runTests()` / `build(.clean)`,
///   the same path the `build` / `test` / `clean` tools use — never
///   a second runner and never a shell. `project_archive` is the
///   one exception: SwiftCode's build seam has no archive action, so it
///   runs the real `xcodebuild archive` with the fixed-argv runner
///   (`terminalRunFixed`, off the main actor), as do
///   `xcode_toolchain_info` (`xcodebuild -version` / `-showsdks`)
///   and, via `runXcrun`, `xcresult_parser` (`xcrun xcresulttool`)
///   and `xcode_device_destination_finder` (`xcrun simctl`).
///   Execution always runs the real command and reports its actual
///   output — no result is ever invented.
///
/// Deliberate deviations from Legacy, recorded here:
///
/// * `project_build`: no `/usr/bin/xcodebuild` is spawned and no
///   `-scheme` / `-configuration` / `-destination` argv is built.
///   The session build is used, so the scheme's own build
///   configuration is honoured and the `configuration` argument is
///   accepted but does not override it. `projectPath` must name
///   the already-open workspace (the `compiler_diagnostics_engine`
///   rule) instead of being located by scanning the workspace
///   root. The `marker` data key is derived from the build status
///   (the session build has no xcodebuild stdout marker), and
///   there is no `BuildOutputAccumulator` line parser — the
///   session reports issues directly.
/// * `project_test`: Legacy's `AssistVerificationPipeline`
///   (`xcodebuild test`) is replaced by the session test runner,
///   the same path the `test` tool and `test_run_single` use.
/// * `project_clean`: the `derivedData` scope runs the session
///   clean (`s.build(.clean)`) instead of `xcodebuild clean`
///   against a located project; the `removed` value still says
///   `"xcodebuild clean"`, as in Legacy. The `build/` removal is
///   additionally gated by the write policy (both `confirm="true"`
///   AND `approve()` are required).
/// * `project_archive`: the project comes from the open
///   workspace's model instead of a top-level scan, and the run is
///   bounded at 900 s (Legacy waited unboundedly).
/// * `build_system_detect`: Legacy's Xcode-project check looked
///   for entries literally named `xcworkspace` / `xcodeproj`,
///   which a real `Foo.xcworkspace` / `Foo.xcodeproj` bundle never
///   is — a verbatim port would report "no build system" for
///   every real Xcode project. The port counts any root entry with
///   those extensions instead.
/// * `xcresult_parser`: stdout only is parsed (Legacy merged
///   stdout+stderr into one pipe); the run is bounded at 120 s.
/// * `xcode_device_destination_finder`: runtime sections are
///   sorted (Legacy iterated the JSON dictionary, whose order is
///   unspecified). Despite the description mentioning physical
///   devices, Legacy only ever ran `simctl list devices` — the
///   port keeps that (simulators only).
/// * `build_configuration_list` / `build_phase_scripts_list`:
///   Legacy's pbxproj regexes are reproduced verbatim (they are
///   file-format patterns, not Apple code).
/// * `generate_xcodeproj` (`AssistGenerateXcodeprojTool`, in the
///   same Legacy file as `project_build`) is NOT in this slice and
///   is not ported here.
extension SwiftCodeMCPHost {
    var projectBuildTools: [MCPTool] {
        let execution = MCPToolAnnotations(readOnly: false, idempotent: false)
        let build = MCPToolAnnotations(readOnly: false, idempotent: true)
        let destructive = MCPToolAnnotations(readOnly: false, destructive: true, idempotent: true)
        return [
            tool("project_build", "Build Project",
                 "Builds the user's Xcode project with xcodebuild, executed directly in the background without requiring terminal approval.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "projectPath": Schema.string("Workspace-relative path to the .xcodeproj or .xcworkspace to build. Defaults to the project found in the workspace root."),
                                       "scheme": Schema.string("The scheme to build. Defaults to the project's first listed scheme."),
                                       "configuration": Schema.string("Build configuration (Debug or Release). Default is Debug."),
                                       "destination": Schema.string("xcodebuild destination specifier. Default is 'platform=macOS'.")]),
                 output: Schema.output(["project": Schema.str, "scheme": Schema.str, "configuration": Schema.str, "status": Schema.str,
                                        "duration": Schema.str, "error_count": Schema.int, "warning_count": Schema.int, "marker": Schema.str]),
                 annotations: build) { h, call in
                try await h.projectBuildBuild(call)
            },
            tool("project_test", "Run Tests",
                 "Executes test suites and test plans using xcodebuild test with proper platform targeting.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "scheme": Schema.string("The scheme to test. Defaults to the project's first listed scheme."),
                                       "testPlan": Schema.string("Optional name of the test plan to execute.")]),
                 output: Schema.output(["status": Schema.str, "duration": Schema.str, "diagnostics_count": Schema.int]),
                 annotations: execution) { h, call in
                try await h.projectBuildTest(call)
            },
            tool("project_clean", "Clean Project",
                 "Cleans the project: removes the workspace build directory and/or runs xcodebuild clean. Requires explicit confirmation.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "scope": Schema.string("build, derivedData, or both. Default: build. build removes workspaceRoot/build only; derivedData runs xcodebuild clean."),
                                       "confirm": Schema.string("Must be \"true\" to proceed. Any other value fails without doing anything.")],
                                      required: ["confirm"]),
                 output: Schema.output(["removed": Schema.str, "scope": Schema.str]),
                 annotations: destructive, writes: true) { h, call in
                try await h.projectBuildClean(call)
            },
            tool("project_archive", "Archive Project",
                 "Archives the user's Xcode project with xcodebuild archive and verifies the .xcarchive exists.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "scheme": Schema.string("Scheme to archive. Required."),
                                       "configuration": Schema.string("Build configuration, e.g. Release or Debug. Default: Release."),
                                       "archivePath": Schema.string("Workspace-relative destination path for the .xcarchive. Required, must stay inside the workspace."),
                                       "exportOptionsPlist": Schema.string("Optional workspace-relative path to an ExportOptions.plist (not used by archive; reserved for export steps).")],
                                      required: ["scheme", "archivePath"]),
                 output: Schema.output(["archivePath": Schema.str, "scheme": Schema.str, "configuration": Schema.str, "exitCode": Schema.int]),
                 annotations: execution) { h, call in
                try await h.projectBuildArchive(call)
            },
            tool("build_log_analyze", "Build Log Analyze",
                 "Parses an xcodebuild/swift-build log file: extracts errors, warnings, build result, and timing summary.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "path": Schema.string("Workspace-relative path to the build log file.")],
                                      required: ["path"]),
                 output: Schema.output(["result": Schema.str, "errorCount": Schema.int, "warningCount": Schema.int])) { h, call in
                try h.projectBuildAnalyzeLog(call)
            },
            tool("build_system_detect", "Build System Detect",
                 "Detects the build systems in use: .xcworkspace/.xcodeproj, SwiftPM, CocoaPods, Carthage, Tuist, xcodegen, Bazel, CMake.",
                 input: Schema.object(["workspace": Schema.workspace]),
                 output: Schema.output(["count": Schema.int])) { h, call in
                try h.projectBuildDetectSystems(call)
            },
            tool("build_configuration_list", "Build Configuration List",
                 "Lists build configurations (Debug/Release/custom) for the project and each target from the .pbxproj.",
                 input: Schema.object(["workspace": Schema.workspace]),
                 output: Schema.output(["ownerCount": Schema.int, "configurations": Schema.str])) { h, call in
                try h.projectBuildListConfigurations(call)
            },
            tool("build_settings_diff", "Build Settings Diff",
                 "Diffs two .xcconfig files key-by-key, reporting added, removed, and changed build settings.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "oldPath": Schema.string("Workspace-relative path to the baseline .xcconfig."),
                                       "newPath": Schema.string("Workspace-relative path to the new .xcconfig.")],
                                      required: ["oldPath", "newPath"]),
                 output: Schema.output(["added": Schema.int, "removed": Schema.int, "changed": Schema.int])) { h, call in
                try h.projectBuildDiffSettings(call)
            },
            tool("build_phase_scripts_list", "Build Phase Scripts List",
                 "Lists Run Script build phases from the .pbxproj with their names and script bodies (truncated).",
                 input: Schema.object(["workspace": Schema.workspace]),
                 output: Schema.output(["count": Schema.int])) { h, call in
                try h.projectBuildListPhaseScripts(call)
            },
            tool("xcresult_parser", "XCResult Bundle Parser",
                 "Locates and parses .xcresult bundles to extract test failures, warnings, and compilation diagnostics.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "bundlePath": Schema.string("Optional specific path to an .xcresult bundle. If omitted, the latest result bundle in DerivedData is used.")])) { h, call in
                try await h.projectBuildParseXCResult(call)
            },
            tool("derived_data_locate", "DerivedData Locate",
                 "Locates the project's DerivedData directories under ~/Library/Developer/Xcode/DerivedData with sizes.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "nameFilter": Schema.string("Optional substring filter on the DerivedData folder name.")]),
                 output: Schema.output(["count": Schema.int])) { h, call in
                try h.projectBuildLocateDerivedData(call)
            },
            tool("xcode_toolchain_info", "Xcode Toolchain Info",
                 "Reports the active Xcode version, build number, and installed SDKs via xcodebuild.",
                 input: Schema.object(["workspace": Schema.workspace]),
                 output: Schema.output(["sdkCount": Schema.int])) { h, call in
                try await h.projectBuildToolchainInfo(call)
            },
            tool("xcode_device_destination_finder", "Xcode Device Destination Finder",
                 "Lists connected physical Apple devices and available simulator runtimes for building and testing.",
                 input: Schema.object(["workspace": Schema.workspace,
                                       "platform": Schema.string("Optional platform filter (e.g. 'iOS', 'watchOS', 'macOS').")])) { h, call in
                try await h.projectBuildFindDestinations(call)
            },
        ]
    }
}

extension SwiftCodeMCPHost {
    // MARK: - Build / test / clean (session seam)

    func projectBuildBuild(_ call: MCPToolCall) async throws -> MCPToolResult {
        let configuration = call.string("configuration") ?? "Debug"
        let destination = call.string("destination") ?? "platform=macOS"
        let s = try session(for: call)
        if let projectPath = call.string("projectPath") {
            let url = try resolveFileReadingPath(projectPath, in: s)
            let modelURL = s.model.url.standardizedFileURL
            let folder = Self.folder(of: s.model)
            guard url.standardizedFileURL.path == modelURL.path || url.standardizedFileURL.path == folder.path else {
                throw MCPToolError("project \"\(projectPath)\" is not the open workspace; open it with workspace_open first.")
            }
        }
        try applyScheme(call.string("scheme"), destination: destination, to: s)
        delegate?.mcpHostSaveAll()
        let started = Date()
        let result = await reportingActivity(call.progress) { await s.build(.build) }
        let root = Self.folder(of: s.model).path
        let status = result.status == .succeeded ? "Passed" : "Failed"
        let duration = Date().timeIntervalSince(started)
        let issues = result.issues.filter { $0.severity != .note || $0.location != nil }
        let schemeName = s.scheme ?? s.model.displayName
        var summary = "Build \(status == "Passed" ? "Succeeded" : "Failed") (\(String(format: "%.2fs", duration))) — \(s.model.displayName) / \(schemeName) / \(configuration)."
        for d in issues.prefix(30) where d.severity == .error || d.severity == .warning {
            summary += "\n" + (Self.issueJSON(d, relativeTo: root)["path"]?.string.map { p in "\(p):\(d.location?.line ?? 0): " } ?? "") + "\(d.severity.rawValue): \(d.message)"
        }
        if result.status == .failed && result.errorCount == 0 { summary += "\nLast log lines:\n" + s.buildLog.suffix(15).joined(separator: "\n") }
        return .structured(["project": .string(s.model.displayName), "scheme": .string(schemeName),
                            "configuration": .string(configuration), "status": .string(status),
                            "duration": .string(String(format: "%.2fs", duration)),
                            "error_count": .int(result.errorCount), "warning_count": .int(result.warningCount),
                            "marker": .string(result.status == .succeeded ? "BUILD SUCCEEDED" : "BUILD FAILED")],
                           summary: summary)
    }

    func projectBuildTest(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        try applyScheme(call.string("scheme"), destination: nil, to: s)
        if let plan = call.string("testPlan") {
            guard s.testPlanNames.contains(plan) else {
                throw MCPToolError("the scheme has no test plan \"\(plan)\"\(s.testPlanNames.isEmpty ? "" : "; its plans: " + s.testPlanNames.joined(separator: ", "))")
            }
            s.activeTestPlan = plan
        }
        delegate?.mcpHostSaveAll()
        let started = Date()
        let outcomes = await reportingActivity(call.progress) { await s.runTests() }
        let duration = Date().timeIntervalSince(started)
        let passed = outcomes.filter { $0.status == .passed }.count
        let failed = outcomes.filter { $0.status == .failed }.count
        let skipped = outcomes.filter { $0.status == .skipped }.count
        let lastReportOK = s.reports.first?.succeeded ?? (failed == 0)
        let status = failed > 0 || !lastReportOK ? "Failed" : "Passed"
        var summary = "Tests \(status) (\(String(format: "%.2fs", duration))):"
        for o in outcomes {
            summary += "\n\(o.status == .passed ? "✓" : o.status == .failed ? "✗" : "–") \(o.suite.map { "\($0)/" } ?? "")\(o.name)"
            for f in o.failures.prefix(3) { summary += "\n    " + f.description }
        }
        if outcomes.isEmpty && status == "Failed" {
            let issues = s.displayedIssues.prefix(20).map(\.description)
            summary += "\nNo test ran." + (issues.isEmpty ? "\nLast log lines:\n" + s.buildLog.suffix(20).joined(separator: "\n") : "\n" + issues.joined(separator: "\n"))
        }
        return .structured(["status": .string(status), "duration": .string(String(format: "%.2fs", duration)),
                            "diagnostics_count": .int(s.displayedIssues.count)],
                           summary: summary)
    }

    func projectBuildClean(_ call: MCPToolCall) async throws -> MCPToolResult {
        let confirmed: Bool
        if let boolValue = call.bool("confirm") {
            confirmed = boolValue
        } else if let stringValue = call.arguments["confirm"]?.string {
            confirmed = stringValue.lowercased() == "true"
        } else {
            confirmed = false
        }
        guard confirmed else {
            throw MCPToolError("Clean requires confirm=\"true\". No changes were made.")
        }
        let scope = (call.arguments["scope"]?.string ?? "build").lowercased()
        guard scope == "build" || scope == "derivedData" || scope == "both" else {
            throw MCPToolError("Invalid scope '\(scope)'. Expected build, derivedData, or both.")
        }
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        var removed: [String] = []
        var notes: [String] = []

        if scope == "build" || scope == "both" {
            let buildDir = root.appendingPathComponent("build").standardizedFileURL
            guard buildDir.path == root.path + "/build" else {
                throw MCPToolError("Refusing to remove path outside the workspace.")
            }
            if FileManager.default.fileExists(atPath: buildDir.path) {
                try await approveFileWritingChange(tool: call.name, path: buildDir, relativePath: "build", original: nil,
                                                   summary: "Delete build/ directory and all its contents permanently", call: call)
                do {
                    try FileManager.default.removeItem(at: buildDir)
                    removed.append("build/")
                } catch {
                    throw MCPToolError("Failed to remove build directory: \(error.localizedDescription)")
                }
                noteFileWritingChanged(buildDir, in: s)
            } else {
                notes.append("build/ did not exist.")
            }
        }

        if scope == "derivedData" || scope == "both" {
            let result = await reportingActivity(call.progress) { await s.build(.clean) }
            guard result.status == .succeeded else {
                let detail = result.issues.filter { $0.severity == .error }.prefix(8).map(\.description).joined(separator: "\n")
                throw MCPToolError("xcodebuild clean failed: \(detail.isEmpty ? "clean failed" : detail)")
            }
            removed.append("xcodebuild clean")
        }

        let summary = removed.isEmpty
            ? "Nothing to clean. \(notes.joined(separator: " "))"
            : "Cleaned: \(removed.joined(separator: ", ")). \(notes.joined(separator: " "))"
        return .structured(["removed": .string(removed.joined(separator: ",")), "scope": .string(scope)],
                           summary: summary.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Archive (fixed-argv xcodebuild; the build seam has no archive action)

    func projectBuildArchive(_ call: MCPToolCall) async throws -> MCPToolResult {
        let scheme = try call.require("scheme").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !scheme.isEmpty else { throw MCPToolError("Missing required parameter: scheme") }
        let rawArchivePath = try call.require("archivePath").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawArchivePath.isEmpty else { throw MCPToolError("Missing required parameter: archivePath") }
        let configuration: String
        if let rawConfiguration = call.arguments["configuration"]?.string {
            configuration = rawConfiguration.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !configuration.isEmpty else { throw MCPToolError("Missing required parameter: configuration") }
        } else {
            configuration = "Release"
        }
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        if let exportPlist = call.string("exportOptionsPlist") {
            let resolved: URL
            do {
                resolved = try resolveFileReadingPath(exportPlist, in: s)
            } catch {
                throw MCPToolError("exportOptionsPlist '\(exportPlist)' not found inside the workspace.")
            }
            guard FileManager.default.fileExists(atPath: resolved.path) else {
                throw MCPToolError("exportOptionsPlist '\(exportPlist)' not found inside the workspace.")
            }
        }
        let archiveURL: URL
        do {
            archiveURL = try resolve(rawArchivePath, in: s)
        } catch {
            throw MCPToolError("archivePath '\(rawArchivePath)' is outside the workspace or contains '..'.")
        }
        guard archiveURL.pathExtension == "xcarchive" else {
            throw MCPToolError("archivePath must end in .xcarchive.")
        }
        guard s.model.kind != .package else {
            throw MCPToolError("No .xcodeproj or .xcworkspace found at the top level of the workspace.")
        }
        let projectURL = s.model.url
        let parentDir = archiveURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
        } catch {
            throw MCPToolError("Failed to create archive parent directory: \(error.localizedDescription)")
        }
        guard FileManager.default.fileExists(atPath: "/usr/bin/xcodebuild") else {
            throw MCPToolError("xcodebuild not found at /usr/bin/xcodebuild. Install Xcode command line tools first.")
        }
        var args: [String] = s.model.kind == .workspace ? ["-workspace", projectURL.path] : ["-project", projectURL.path]
        args += ["-scheme", scheme, "-configuration", configuration, "-archivePath", archiveURL.path, "archive"]
        let run = await Task.detached {
            Self.terminalRunFixed("/usr/bin/xcodebuild", args, workingDirectory: root, timeout: 900)
        }.value
        guard let run else {
            throw MCPToolError("Failed to run xcodebuild archive: could not start /usr/bin/xcodebuild.")
        }
        if run.timedOut {
            throw MCPToolError("xcodebuild archive timed out after 900s.")
        }
        guard run.exitCode == 0 else {
            let output = (run.stdout + "\n" + run.stderr).trimmingCharacters(in: .whitespacesAndNewlines)
            throw MCPToolError("xcodebuild archive failed (exit \(run.exitCode)): \(String(output.suffix(1500)))")
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: archiveURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw MCPToolError("Verification failed: .xcarchive not found at '\(rawArchivePath)' after a successful xcodebuild run.")
        }
        return .structured(["archivePath": .string(rawArchivePath), "scheme": .string(scheme),
                            "configuration": .string(configuration), "exitCode": .int(Int(run.exitCode))],
                           summary: "Archived scheme '\(scheme)' to '\(rawArchivePath)' (exit 0).")
    }

    // MARK: - Pure reads: logs, systems, configurations, settings, scripts

    func projectBuildAnalyzeLog(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        guard let raw = call.arguments["path"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            throw MCPToolError("Missing required parameter: path")
        }
        let text: String
        do {
            let url = try resolveFileReadingPath(raw, in: s)
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw MCPToolError("Cannot read build log at: \(raw)")
        }
        let lines = text.components(separatedBy: .newlines)
        var errors: [String] = []
        var warnings: [String] = []
        var result = "unknown"
        for line in lines {
            if line.contains("** BUILD FAILED **") { result = "failed" }
            if line.contains("** BUILD SUCCEEDED **") { result = "succeeded" }
            if line.contains(": error:") {
                errors.append(String(line.trimmingCharacters(in: .whitespaces).prefix(300)))
            } else if line.contains(": warning:") {
                warnings.append(String(line.trimmingCharacters(in: .whitespaces).prefix(300)))
            }
        }
        errors = Self.projectBuildDedup(errors)
        warnings = Self.projectBuildDedup(warnings)
        var out = ["Build log analysis for \(raw):", "- Result: \(result)", "- Errors: \(errors.count)", "- Warnings: \(warnings.count)"]
        for e in errors.prefix(20) { out.append("  ERROR: \(e)") }
        if errors.count > 20 { out.append("  … [truncated: showing 20 of \(errors.count)]") }
        for w in warnings.prefix(10) { out.append("  WARNING: \(w)") }
        if warnings.count > 10 { out.append("  … [truncated: showing 10 of \(warnings.count)]") }
        return .structured(["result": .string(result), "errorCount": .int(errors.count), "warningCount": .int(warnings.count)],
                           summary: out.joined(separator: "\n"))
    }

    /// De-duplication preserving first order (Legacy's `NSOrderedSet`).
    nonisolated static func projectBuildDedup(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }

    func projectBuildDetectSystems(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        var found: [(name: String, system: String)] = []
        // Project bundles (Legacy's order: workspace first, then
        // project). Legacy looked for entries literally named
        // `xcworkspace` / `xcodeproj`, which a real bundle never is;
        // the port counts any root entry with those extensions.
        for ext in ["xcworkspace", "xcodeproj"] {
            if let bundle = entries.filter({ $0.pathExtension == ext }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).first {
                found.append((name: bundle.lastPathComponent, system: "." + ext))
            }
        }
        let checks: [(String, String)] = [
            ("Package.swift", "SwiftPM"), ("Podfile", "CocoaPods"),
            ("Cartfile", "Carthage"), ("Project.swift", "Tuist"),
            ("project.yml", "xcodegen"), ("BUILD", "Bazel"),
            ("CMakeLists.txt", "CMake"), ("Makefile", "Make")
        ]
        for (name, system) in checks {
            let url = root.appendingPathComponent(name)
            var isDir: ObjCBool = false
            // Directories only count for bundle-style markers, and
            // none of these markers starts with ".", so effectively
            // files only — Legacy's rule, preserved.
            if fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue {
                found.append((name: name, system: system))
            }
        }
        if found.isEmpty {
            return .structured(["count": .int(0)], summary: "No recognized build system files found in the workspace root.")
        }
        var lines = ["Build systems detected:"]
        for (name, system) in found {
            lines.append("- \(system): \(name)")
        }
        return .structured(["count": .int(found.count)], summary: lines.joined(separator: "\n"))
    }

    func projectBuildListConfigurations(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        guard let pbxproj = Self.reviewDocsFindPbxproj(in: root),
              let text = try? String(contentsOf: pbxproj, encoding: .utf8) else {
            throw MCPToolError("No .pbxproj found in the workspace.")
        }
        guard let listPattern = try? NSRegularExpression(
            pattern: #"([0-9A-F]{24}) /\* Build configuration list for (PBXProject|PBXNativeTarget) "([^"]+)" \*/ = \{\s*isa = XCConfigurationList;.*?buildConfigurations = \((.*?)\);"#,
            options: [.dotMatchesLineSeparators]
        ) else {
            throw MCPToolError("Internal regex error.")
        }
        let lists = listPattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var configIdToName: [String: String] = [:]
        if let cp = try? NSRegularExpression(pattern: #"([0-9A-F]{24}) /\* ([^*]+?) \*/ = \{\s*isa = XCBuildConfiguration;"#) {
            for m in cp.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let r1 = Range(m.range(at: 1), in: text), let r2 = Range(m.range(at: 2), in: text) {
                    configIdToName[String(text[r1])] = String(text[r2]).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        let idPattern = try? NSRegularExpression(pattern: #"([0-9A-F]{24})"#)
        var lines = ["Build configurations:"]
        var configNames: Set<String> = []
        for m in lists {
            guard let ownerRange = Range(m.range(at: 3), in: text),
                  let configsRange = Range(m.range(at: 4), in: text) else { continue }
            let owner = String(text[ownerRange])
            let block = String(text[configsRange])
            let ids = idPattern?.matches(in: block, range: NSRange(block.startIndex..., in: block)).compactMap { dm -> String? in
                guard let r = Range(dm.range(at: 1), in: block) else { return nil }
                return String(block[r])
            } ?? []
            let names = ids.compactMap { configIdToName[$0] }.sorted()
            names.forEach { configNames.insert($0) }
            lines.append("- \(owner): \(names.isEmpty ? "(none parsed)" : names.joined(separator: ", "))")
        }
        if lists.isEmpty {
            throw MCPToolError("No configuration lists parsed from the pbxproj.")
        }
        return .structured(["ownerCount": .int(lists.count), "configurations": .string(configNames.sorted().joined(separator: ","))],
                           summary: lines.joined(separator: "\n"))
    }

    func projectBuildDiffSettings(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        guard let oldRaw = call.arguments["oldPath"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !oldRaw.isEmpty,
              let newRaw = call.arguments["newPath"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !newRaw.isEmpty else {
            throw MCPToolError("Missing required parameters: oldPath and newPath")
        }
        func parse(_ raw: String) -> [String: String]? {
            guard let url = try? resolveFileReadingPath(raw, in: s),
                  let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
            var dict: [String: String] = [:]
            for line in text.components(separatedBy: .newlines) {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.isEmpty || t.hasPrefix("//") || t.hasPrefix("#") { continue }
                let parts = t.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    dict[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
            return dict
        }
        guard let old = parse(oldRaw) else { throw MCPToolError("Cannot parse xcconfig at: \(oldRaw)") }
        guard let new = parse(newRaw) else { throw MCPToolError("Cannot parse xcconfig at: \(newRaw)") }
        let added = Set(new.keys).subtracting(old.keys).sorted()
        let removed = Set(old.keys).subtracting(new.keys).sorted()
        let changed = Set(old.keys).intersection(new.keys).filter { old[$0] != new[$0] }.sorted()
        if added.isEmpty && removed.isEmpty && changed.isEmpty {
            return .structured(["added": .int(0), "removed": .int(0), "changed": .int(0)],
                               summary: "Build settings are identical.")
        }
        var lines = ["Build settings diff (\(oldRaw) -> \(newRaw)):"]
        lines += added.map { "- ADDED: \($0) = \(new[$0] ?? "")" }
        lines += removed.map { "- REMOVED: \($0) (was: \(old[$0] ?? ""))" }
        lines += changed.map { "- CHANGED: \($0): '\(old[$0] ?? "")' -> '\(new[$0] ?? "")'" }
        return .structured(["added": .int(added.count), "removed": .int(removed.count), "changed": .int(changed.count)],
                           summary: lines.joined(separator: "\n"))
    }

    func projectBuildListPhaseScripts(_ call: MCPToolCall) throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        guard let pbxproj = Self.reviewDocsFindPbxproj(in: root),
              let text = try? String(contentsOf: pbxproj, encoding: .utf8) else {
            throw MCPToolError("No .pbxproj found in the workspace.")
        }
        guard let p = try? NSRegularExpression(
            pattern: #"/\* (.+?) \*/ = \{\s*isa = PBXShellScriptBuildPhase;.*?name = (.+?);.*?shellScript = "(.*?)";"#,
            options: [.dotMatchesLineSeparators]
        ) else {
            throw MCPToolError("Internal regex error.")
        }
        let matches = p.matches(in: text, range: NSRange(text.startIndex..., in: text))
        if matches.isEmpty {
            return .structured(["count": .int(0)], summary: "No Run Script build phases found.")
        }
        var lines = ["Run Script build phases (\(matches.count)):"]
        for m in matches {
            guard let cr = Range(m.range(at: 1), in: text),
                  let nr = Range(m.range(at: 2), in: text),
                  let sr = Range(m.range(at: 3), in: text) else { continue }
            let name = String(text[nr]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let script = String(text[sr]).replacingOccurrences(of: "\\n", with: "\n")
            let (preview, wasTruncated) = Self.projectBuildTruncated(script, limit: 600, label: "script truncated")
            lines.append("- \(String(text[cr])) (phase: \(name)):")
            lines.append("```sh\n\(preview)\n```" + (wasTruncated ? " [truncated]" : ""))
        }
        return .structured(["count": .int(matches.count)], summary: lines.joined(separator: "\n"))
    }

    /// Legacy's `AssistTextFormat.truncated`: the first `limit`
    /// characters plus a note when the text was longer.
    nonisolated static func projectBuildTruncated(_ text: String, limit: Int, label: String) -> (String, Bool) {
        guard text.count > limit else { return (text, false) }
        return (String(text.prefix(limit)) + "\n… [\(label): showing first \(limit) of \(text.count) characters]", true)
    }

    // MARK: - xcresult / DerivedData / toolchain / destinations

    func projectBuildParseXCResult(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let derivedData = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        var targetURL: URL?
        if let customPath = call.string("bundlePath"), !customPath.isEmpty {
            let u = customPath.hasPrefix("/") ? URL(fileURLWithPath: customPath) : Self.folder(of: s.model).appendingPathComponent(customPath)
            if FileManager.default.fileExists(atPath: u.path) {
                targetURL = u
            }
        }
        if targetURL == nil {
            if let enumerator = FileManager.default.enumerator(at: derivedData, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) {
                var candidates: [(url: URL, date: Date)] = []
                while let item = enumerator.nextObject() as? URL {
                    if item.pathExtension == "xcresult" {
                        let date = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                        candidates.append((url: item, date: date))
                    }
                }
                targetURL = candidates.sorted(by: { $0.date > $1.date }).first?.url
            }
        }
        guard let xcresultURL = targetURL else {
            return .text("No .xcresult bundle found. Run a build or test suite first.")
        }
        guard let run = await Self.runXcrun(["xcresulttool", "get", "--format", "json", "--path", xcresultURL.path], timeout: 120) else {
            throw MCPToolError("Failed to parse .xcresult via xcresulttool: could not start /usr/bin/xcrun.")
        }
        guard let data = run.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .text("Parsed .xcresult at \(xcresultURL.lastPathComponent), but output is non-JSON or bundle is empty.")
        }
        var report = "### XCResult Summary (\(xcresultURL.lastPathComponent)):\n\n"
        if let issues = json["issues"] as? [String: Any] {
            if let errors = issues["errorSummaries"] as? [String: Any], let val = errors["_values"] as? [[String: Any]] {
                report += "#### Errors (\(val.count)):\n"
                for err in val.prefix(10) {
                    if let msg = (err["message"] as? [String: Any])?["_value"] as? String {
                        report += "- ❌ \(msg)\n"
                    }
                }
            }
            if let warnings = issues["warningSummaries"] as? [String: Any], let val = warnings["_values"] as? [[String: Any]] {
                report += "#### Warnings (\(val.count)):\n"
                for warn in val.prefix(10) {
                    if let msg = (warn["message"] as? [String: Any])?["_value"] as? String {
                        report += "- ⚠️ \(msg)\n"
                    }
                }
            }
        } else {
            report += "No compile errors or test failure summaries recorded in bundle."
        }
        return .text(report)
    }

    func projectBuildLocateDerivedData(_ call: MCPToolCall) throws -> MCPToolResult {
        _ = try session(for: call)
        let filter = call.string("nameFilter")?.trimmingCharacters(in: .whitespacesAndNewlines)
        let dd = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
        guard let entries = try? FileManager.default.contentsOfDirectory(at: dd, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            throw MCPToolError("DerivedData directory not found at \(dd.path).")
        }
        var rows: [(String, Int64)] = []
        for entry in entries {
            if let filter, !filter.isEmpty, !entry.lastPathComponent.localizedCaseInsensitiveContains(filter) { continue }
            var size: Int64 = 0
            if let enumerator = FileManager.default.enumerator(at: entry, includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey]) {
                while let child = enumerator.nextObject() as? URL {
                    let isDir = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
                    if !isDir { size += Self.projectBuildFileSize(of: child) }
                    if size > 20_000_000_000 { break }
                }
            }
            rows.append((entry.lastPathComponent, size))
        }
        rows.sort { $0.1 > $1.1 }
        if rows.isEmpty {
            return .structured(["count": .int(0)], summary: "No DerivedData directories matched.")
        }
        var lines = ["DerivedData directories (\(rows.count)):"]
        for (name, size) in rows.prefix(30) {
            lines.append(String(format: "- %@ — %.2f GB", name, Double(size) / 1_073_741_824.0))
        }
        return .structured(["count": .int(rows.count)], summary: lines.joined(separator: "\n"))
    }

    /// Legacy's `AssistWorkspaceScan.fileSize`.
    nonisolated static func projectBuildFileSize(of url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }

    func projectBuildToolchainInfo(_ call: MCPToolCall) async throws -> MCPToolResult {
        let s = try session(for: call)
        let root = Self.folder(of: s.model)
        func run(_ args: [String]) async -> String {
            guard let run = await Task.detached {
                Self.terminalRunFixed("/usr/bin/xcodebuild", args, workingDirectory: root, timeout: 60)
            }.value else { return "" }
            return run.stdout
        }
        let version = (await run(["-version"])).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !version.isEmpty else {
            throw MCPToolError("xcodebuild is not available (Xcode command-line tools missing?).")
        }
        let sdksRaw = await run(["-showsdks"])
        var sdks: [String] = []
        for line in sdksRaw.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("-sdk ") { sdks.append(t) }
        }
        var lines = ["Xcode toolchain:", version]
        lines.append("Installed SDKs (\(sdks.count)):")
        lines += sdks.prefix(20).map { "  \($0)" }
        return .structured(["sdkCount": .int(sdks.count)], summary: lines.joined(separator: "\n"))
    }

    func projectBuildFindDestinations(_ call: MCPToolCall) async throws -> MCPToolResult {
        _ = try session(for: call)
        let platformFilter = call.string("platform")?.lowercased()
        guard let run = await Self.runXcrun(["simctl", "list", "devices", "available", "-j"], timeout: 60) else {
            throw MCPToolError("Failed to query simulator devices via simctl: could not start /usr/bin/xcrun.")
        }
        guard let data = run.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devicesDict = json["devices"] as? [String: [[String: Any]]] else {
            throw MCPToolError("Unable to parse simctl JSON response.")
        }
        var report = "### Available Simulator Destinations:\n\n"
        var count = 0
        for runtime in devicesDict.keys.sorted() {
            guard let devices = devicesDict[runtime] else { continue }
            if let filter = platformFilter, !runtime.lowercased().contains(filter) { continue }
            let cleanRuntime = runtime.replacingOccurrences(of: "com.apple.CoreSimulator.SimRuntime.", with: "")
            report += "#### \(cleanRuntime)\n"
            for dev in devices.prefix(6) {
                let name = dev["name"] as? String ?? "Device"
                let udid = dev["udid"] as? String ?? ""
                let state = dev["state"] as? String ?? "Shutdown"
                report += "- **\(name)** (`\(state)`) — UDID: `\(udid)`\n"
                count += 1
            }
            report += "\n"
        }
        if count == 0 {
            return .text("No available simulators matching the requested filter.")
        }
        return .text(report)
    }
}
