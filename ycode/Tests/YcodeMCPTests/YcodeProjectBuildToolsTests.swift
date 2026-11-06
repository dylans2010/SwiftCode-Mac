import Foundation
import Testing
import YcodeAssistant
@testable import YcodeMCP

/// The ported Legacy project / Xcode / build tools (Wave 7, slice A),
/// each driven black-box through the server's real write-policy path
/// against a copy of `Samples/AgentSamples/Greeter`.
///
/// Behaviour source: Legacy `AssistBuildProjectTool`,
/// `AssistTestRunnerTool`, `AssistProjectCleanTool`,
/// `AssistProjectArchiveTool`, `AssistBuildLogAnalyzeTool`,
/// `AssistBuildSystemDetectTool`, `AssistBuildConfigurationListTool`,
/// `AssistBuildSettingsDiffTool`, `AssistBuildPhaseScriptsListTool`,
/// `AssistXCResultParserTool`, `AssistDerivedDataLocateTool`,
/// `AssistXcodeToolchainInfoTool` and
/// `AssistXcodeDeviceDestinationTool` (Dylan's own code, ported under
/// MIT).
///
/// Assertions are on the tool RESULT (message + on-disk state), never
/// on internals. Messages quoted verbatim are Legacy's. Message
/// assertions use `firstText`, never an exact `resultText ==`
/// (structured results emit two text blocks). Tests that run the
/// real build/test seam are gated on `canBuildPackages`, like the
/// `test` tool's own tests; nothing here claims a build passed
/// without running one. Tests that need Xcode command line tools
/// adapt to the environment: where `xcodebuild` / `xcrun` / a
/// DerivedData directory is absent they assert the honest failure,
/// where it is present they assert the real result.
@MainActor
@Suite(.serialized) struct YcodeProjectBuildToolsTests {
    /// The 13 Wave 7 slice A tool IDs, verified live from each
    /// Legacy tool file's `id`.
    static let sliceAIDs = ["project_build", "project_test", "project_clean", "project_archive", "build_log_analyze",
                            "build_system_detect", "build_configuration_list", "build_settings_diff", "build_phase_scripts_list",
                            "xcresult_parser", "derived_data_locate", "xcode_toolchain_info", "xcode_device_destination_finder"]

    /// Opens a copy of Greeter and installs the ported project/build
    /// tools on the server (same shape as Wave 6's `opened`).
    func opened(_ sample: TempSample, policy: MCPWritePolicy = .readOnly) async throws -> YcodeMCPHost {
        let host = YcodeMCPHost()
        host.server.writePolicy = policy
        let ported = Set(host.projectBuildTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.projectBuildTools
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.url.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    /// Writes a fixture file directly (not through a tool under test).
    func writeFixture(_ sample: TempSample, _ rel: String, _ content: String) throws {
        let url = URL(fileURLWithPath: sample.path(rel))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func exists(_ sample: TempSample, _ rel: String) -> Bool {
        FileManager.default.fileExists(atPath: sample.path(rel))
    }

    final class Reviews: @unchecked Sendable {
        var changes: [MCPChange] = []
        var accept = false
    }

    @Test func toolIDsAreRegisteredOnce() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        #expect(host.projectBuildTools.map(\.name) == Self.sliceAIDs)
        for id in Self.sliceAIDs {
            #expect(host.server.tools.filter { $0.name == id }.count == 1, "\(id) must be registered exactly once")
        }
        // The slice's Legacy aliases (`build` / `build_project` /
        // `run_build` / `xcodebuild` → `project_build`, `test` /
        // `run_tests` → `project_test`, `xcresult` →
        // `xcresult_parser`, `device_destinations` →
        // `xcode_device_destination_finder`) live in
        // `MCPServer.toolAliases`, which the coordinator owns — they
        // are reported as a wiring fragment instead of asserted
        // here. `build` and `test` must NOT be added there: they
        // would collide with Ycode's native `build` / `test`.
    }

    // MARK: - Pure reads: build logs

    @Test func buildLogAnalyzeCountsDedupsAndTruncates() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Logs/build.log", """
        ** BUILD SUCCEEDED **
        /Sources/A.swift:10: error: cannot find 'foo' in scope
        /Sources/A.swift:10: error: cannot find 'foo' in scope
        /Sources/B.swift:20: warning: unused variable 'x'
        /Sources/C.swift:30: error: type mismatch
        """)
        let r = try await host.server.callTool("build_log_analyze", ["path": .string("Logs/build.log")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["result"] == "succeeded" && r.structured?["errorCount"] == 2 && r.structured?["warningCount"] == 1)
        #expect(r.firstText.contains("Build log analysis for Logs/build.log:"))
        #expect(r.firstText.contains("- Result: succeeded"))
        #expect(r.firstText.contains("- Errors: 2"))
        #expect(r.firstText.contains("- Warnings: 1"))
        #expect(r.firstText.contains("ERROR: /Sources/A.swift:10: error: cannot find 'foo' in scope"))
        #expect(r.firstText.contains("WARNING: /Sources/B.swift:20: warning: unused variable 'x'"))
        // A duplicated error line is counted once; the duplicate does
        // not appear twice.
        #expect(r.firstText.components(separatedBy: "cannot find 'foo'").count - 1 == 1)

        try writeFixture(sample, "Logs/failed.log", "** BUILD FAILED **\n")
        let failed = try await host.server.callTool("build_log_analyze", ["path": .string("Logs/failed.log")])
        #expect(!failed.isToolError, "\(failed.resultText)")
        #expect(failed.structured?["result"] == "failed")

        try writeFixture(sample, "Logs/plain.log", "nothing to see here\n")
        let unknown = try await host.server.callTool("build_log_analyze", ["path": .string("Logs/plain.log")])
        #expect(unknown.structured?["result"] == "unknown")

        let missing = try await host.server.callTool("build_log_analyze", ["path": .string("Logs/nope.log")])
        #expect(missing.isToolError && missing.firstText.contains("Cannot read build log at: Logs/nope.log"))
        let noParam = try await host.server.callTool("build_log_analyze")
        #expect(noParam.isToolError)
        let outside = try await host.server.callTool("build_log_analyze", ["path": .string("../outside.log")])
        #expect(outside.isToolError && outside.firstText.contains("Cannot read build log at: ../outside.log"))
    }

    // MARK: - Pure reads: build systems

    @Test func buildSystemDetectFindsSwiftPMAndXcodeBundles() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        // Greeter is a SwiftPM package.
        let r = try await host.server.callTool("build_system_detect")
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["count"] == 1)
        #expect(r.firstText.contains("- SwiftPM: Package.swift"))
        // A real .xcodeproj bundle and a Podfile are detected too —
        // Legacy's check looked for entries literally named
        // `xcworkspace` / `xcodeproj` and could never match these.
        try FileManager.default.createDirectory(atPath: sample.path("Foo.xcodeproj"), withIntermediateDirectories: true)
        try writeFixture(sample, "Podfile", "platform :ios\n")
        let again = try await host.server.callTool("build_system_detect")
        #expect(!again.isToolError, "\(again.resultText)")
        #expect(again.structured?["count"] == 3)
        #expect(again.firstText.contains("- .xcodeproj: Foo.xcodeproj"))
        #expect(again.firstText.contains("- CocoaPods: Podfile"))
    }

    // MARK: - Pure reads: pbxproj (configurations, scripts)

    /// A minimal pbxproj with two configuration lists (project +
    /// target, Debug/Release) and one Run Script phase.
    static let pbxprojFixture = """
    /* Begin XCConfigurationList section */
    \t\tAAAAAAAA0000000000000001 /* Build configuration list for PBXProject "Greeter" */ = {
    \t\t\tisa = XCConfigurationList;
    \t\t\tbuildConfigurations = (
    \t\t\t\tAAAAAAAA0000000000000010 /* Debug */,
    \t\t\t\tAAAAAAAA0000000000000011 /* Release */,
    \t\t\t);
    \t\t\tdefaultConfigurationIsVisible = 0;
    \t\t\tdefaultConfigurationName = Release;
    \t\t};
    \t\tAAAAAAAA0000000000000002 /* Build configuration list for PBXNativeTarget "Greeter" */ = {
    \t\t\tisa = XCConfigurationList;
    \t\t\tbuildConfigurations = (
    \t\t\t\tAAAAAAAA0000000000000010 /* Debug */,
    \t\t\t\tAAAAAAAA0000000000000011 /* Release */,
    \t\t\t);
    \t\t\tdefaultConfigurationIsVisible = 0;
    \t\t\tdefaultConfigurationName = Release;
    \t\t};
    /* End XCConfigurationList section */
    /* Begin XCBuildConfiguration section */
    \t\tAAAAAAAA0000000000000010 /* Debug */ = {
    \t\t\tisa = XCBuildConfiguration;
    \t\t\tbuildSettings = {
    \t\t\t};
    \t\t\tname = Debug;
    \t\t};
    \t\tAAAAAAAA0000000000000011 /* Release */ = {
    \t\t\tisa = XCBuildConfiguration;
    \t\t\tbuildSettings = {
    \t\t\t};
    \t\t\tname = Release;
    \t\t};
    /* End XCBuildConfiguration section */
    /* Begin PBXShellScriptBuildPhase section */
    \t\tBBBBBBBB0000000000000001 /* Run Script */ = {
    \t\t\tisa = PBXShellScriptBuildPhase;
    \t\t\tbuildActionMask = 2147483647;
    \t\t\tfiles = (
    \t\t\t);
    \t\t\tname = "Run Script";
    \t\t\trunOnlyForDeploymentPostprocessing = 0;
    \t\t\tshellPath = /bin/sh;
    \t\t\tshellScript = "echo hello\\n echo world";
    \t\t};
    /* End PBXShellScriptBuildPhase section */
    """

    @Test func buildConfigurationListParsesPbxproj() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        // Greeter has no pbxproj.
        let none = try await host.server.callTool("build_configuration_list")
        #expect(none.isToolError && none.firstText.contains("No .pbxproj found in the workspace."))
        try writeFixture(sample, "Greeter.xcodeproj/project.pbxproj", Self.pbxprojFixture)
        let r = try await host.server.callTool("build_configuration_list")
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["ownerCount"] == 2)
        #expect(r.structured?["configurations"] == "Debug,Release")
        #expect(r.firstText.contains("- Greeter: Debug, Release"))
    }

    @Test func buildPhaseScriptsListFindsRunScripts() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let none = try await host.server.callTool("build_phase_scripts_list")
        #expect(none.isToolError && none.firstText.contains("No .pbxproj found in the workspace."))
        try writeFixture(sample, "Greeter.xcodeproj/project.pbxproj", Self.pbxprojFixture)
        let r = try await host.server.callTool("build_phase_scripts_list")
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["count"] == 1)
        #expect(r.firstText.contains("Run Script build phases (1):"))
        #expect(r.firstText.contains("- Run Script (phase: Run Script):"))
        #expect(r.firstText.contains("echo hello"))
        #expect(r.firstText.contains("echo world"))
        // A script over 600 characters is truncated with Legacy's note.
        let longScript = String(repeating: "x ", count: 400)
        let longFixture = Self.pbxprojFixture.replacingOccurrences(of: "echo hello\\n echo world", with: longScript)
        try writeFixture(sample, "Greeter.xcodeproj/project.pbxproj", longFixture)
        let truncated = try await host.server.callTool("build_phase_scripts_list")
        #expect(!truncated.isToolError, "\(truncated.resultText)")
        #expect(truncated.firstText.contains(" [truncated]"))
        #expect(truncated.firstText.contains("script truncated: showing first 600 of 800 characters"))
    }

    // MARK: - Pure reads: xcconfig diff

    @Test func buildSettingsDiffReportsAddedRemovedChanged() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Configs/old.xcconfig", """
        // comment
        # another comment
        PRODUCT_NAME = Greeter
        SWIFT_VERSION = 5.0
        DEAD_KEY = gone

        """)
        try writeFixture(sample, "Configs/new.xcconfig", """
        PRODUCT_NAME = GreeterApp
        SWIFT_VERSION = 5.0
        NEW_KEY = added
        """)
        let r = try await host.server.callTool("build_settings_diff", ["oldPath": .string("Configs/old.xcconfig"),
                                                                       "newPath": .string("Configs/new.xcconfig")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["added"] == 1 && r.structured?["removed"] == 1 && r.structured?["changed"] == 1)
        #expect(r.firstText.contains("Build settings diff (Configs/old.xcconfig -> Configs/new.xcconfig):"))
        #expect(r.firstText.contains("- ADDED: NEW_KEY = added"))
        #expect(r.firstText.contains("- REMOVED: DEAD_KEY (was: gone)"))
        #expect(r.firstText.contains("- CHANGED: PRODUCT_NAME: 'Greeter' -> 'GreeterApp'"))
        let identical = try await host.server.callTool("build_settings_diff", ["oldPath": .string("Configs/old.xcconfig"),
                                                                               "newPath": .string("Configs/old.xcconfig")])
        #expect(!identical.isToolError, "\(identical.resultText)")
        #expect(identical.structured?["added"] == 0 && identical.structured?["removed"] == 0 && identical.structured?["changed"] == 0)
        #expect(identical.firstText.contains("Build settings are identical."))
        let noParam = try await host.server.callTool("build_settings_diff", ["oldPath": .string("Configs/old.xcconfig")])
        #expect(noParam.isToolError)
        let unreadable = try await host.server.callTool("build_settings_diff", ["oldPath": .string("Configs/nope.xcconfig"),
                                                                                "newPath": .string("Configs/new.xcconfig")])
        #expect(unreadable.isToolError && unreadable.firstText.contains("Cannot parse xcconfig at: Configs/nope.xcconfig"))
    }

    // MARK: - project_clean (the slice's only write tool)

    @Test func projectCleanRequiresConfirmAndRemovesBuildDir() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        try writeFixture(sample, "build/dummy.txt", "x\n")
        let noConfirm = try await host.server.callTool("project_clean", ["scope": .string("build")])
        #expect(noConfirm.isToolError)
        #expect(exists(sample, "build/dummy.txt"))
        let refused = try await host.server.callTool("project_clean", ["scope": .string("build"), "confirm": .string("false")])
        #expect(refused.isToolError && refused.firstText.contains("Clean requires confirm=\"true\". No changes were made."))
        #expect(exists(sample, "build/dummy.txt"))
        let badScope = try await host.server.callTool("project_clean", ["scope": .string("bogus"), "confirm": .string("true")])
        #expect(badScope.isToolError && badScope.firstText.contains("Invalid scope 'bogus'. Expected build, derivedData, or both."))
        #expect(exists(sample, "build/dummy.txt"))
        let cleaned = try await host.server.callTool("project_clean", ["scope": .string("build"), "confirm": .string("true")])
        #expect(!cleaned.isToolError, "\(cleaned.resultText)")
        #expect(cleaned.structured?["removed"] == "build/" && cleaned.structured?["scope"] == "build")
        #expect(cleaned.firstText.contains("Cleaned: build/."))
        #expect(!exists(sample, "build"))
        // A second clean reports that there was nothing to remove.
        let again = try await host.server.callTool("project_clean", ["scope": .string("build"), "confirm": .string("true")])
        #expect(!again.isToolError, "\(again.resultText)")
        #expect(again.structured?["removed"] == "")
        #expect(again.firstText.contains("Nothing to clean. build/ did not exist."))
        // A JSON boolean true counts as confirmation too.
        try writeFixture(sample, "build/dummy.txt", "x\n")
        let boolConfirmed = try await host.server.callTool("project_clean", ["scope": .string("build"), "confirm": .bool(true)])
        #expect(!boolConfirmed.isToolError, "\(boolConfirmed.resultText)")
        #expect(!exists(sample, "build"))
    }

    @Test func projectCleanRefusedInReadOnlyMode() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "build/dummy.txt", "x\n")
        let refused = try await host.server.callTool("project_clean", ["scope": .string("build"), "confirm": .string("true")])
        #expect(refused.isToolError && refused.firstText.contains("read-only"))
        #expect(exists(sample, "build/dummy.txt"))
    }

    @Test func projectCleanReviewRefusalWritesNothing() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let reviews = Reviews()
        let host = try await opened(sample, policy: .review { c in reviews.changes.append(c); return reviews.accept })
        try writeFixture(sample, "build/dummy.txt", "x\n")
        let rejected = try await host.server.callTool("project_clean", ["scope": .string("build"), "confirm": .string("true")])
        #expect(rejected.isToolError && rejected.firstText == MCPServer.rejectedMessage)
        #expect(exists(sample, "build/dummy.txt"))
        let change = try #require(reviews.changes.first)
        #expect(change.tool == "project_clean" && change.relativePath == "build")
        #expect(change.summary.contains("Delete build/ directory"))
        reviews.accept = true
        let cleaned = try await host.server.callTool("project_clean", ["scope": .string("build"), "confirm": .string("true")])
        #expect(!cleaned.isToolError, "\(cleaned.resultText)")
        #expect(!exists(sample, "build"))
    }

    @Test func projectCleanDerivedDataScopeRunsSessionClean() async throws {
        guard canBuildPackages else { return }
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let r = try await host.server.callTool("project_clean", ["scope": .string("derivedData"), "confirm": .string("true")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["removed"] == "xcodebuild clean" && r.structured?["scope"] == "derivedData")
    }

    // MARK: - project_archive (argument validation; no xcodebuild here)

    @Test func projectArchiveRejectsBadArguments() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let noScheme = try await host.server.callTool("project_archive", ["archivePath": .string("Archives/Greeter.xcarchive")])
        #expect(noScheme.isToolError)
        let blankScheme = try await host.server.callTool("project_archive", ["scheme": .string(""),
                                                                              "archivePath": .string("Archives/Greeter.xcarchive")])
        #expect(blankScheme.isToolError && blankScheme.firstText.contains("missing the required argument \"scheme\""))
        let noPath = try await host.server.callTool("project_archive", ["scheme": .string("Greeter")])
        #expect(noPath.isToolError)
        let badExtension = try await host.server.callTool("project_archive", ["scheme": .string("Greeter"),
                                                                               "archivePath": .string("Archives/Greeter.zip")])
        #expect(badExtension.isToolError && badExtension.firstText.contains("archivePath must end in .xcarchive."))
        let outside = try await host.server.callTool("project_archive", ["scheme": .string("Greeter"),
                                                                          "archivePath": .string("../evil.xcarchive")])
        #expect(outside.isToolError && outside.firstText.contains("archivePath '../evil.xcarchive' is outside the workspace or contains '..'."))
        let missingPlist = try await host.server.callTool("project_archive", ["scheme": .string("Greeter"),
                                                                               "archivePath": .string("Archives/Greeter.xcarchive"),
                                                                               "exportOptionsPlist": .string("Nope.plist")])
        #expect(missingPlist.isToolError && missingPlist.firstText.contains("exportOptionsPlist 'Nope.plist' not found inside the workspace."))
        // Greeter is a SwiftPM package, not an Xcode project — the
        // archive cannot proceed, and it fails before any xcodebuild
        // is attempted.
        let package = try await host.server.callTool("project_archive", ["scheme": .string("Greeter"),
                                                                          "archivePath": .string("Archives/Greeter.xcarchive")])
        #expect(package.isToolError && package.firstText.contains("No .xcodeproj or .xcworkspace found at the top level of the workspace."))
        #expect(!exists(sample, "Archives"))
    }

    // MARK: - project_build / project_test (validation; real runs gated)

    @Test func projectBuildRejectsUnknownSchemeAndForeignProject() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let badScheme = try await host.server.callTool("project_build", ["scheme": .string("NopeScheme")])
        #expect(badScheme.isToolError && badScheme.firstText.contains("no scheme \"NopeScheme\""))
        let badDestination = try await host.server.callTool("project_build", ["destination": .string("platform=bogus")])
        #expect(badDestination.isToolError && badDestination.firstText.contains("no destination \"platform=bogus\""))
        let foreign = try await host.server.callTool("project_build", ["projectPath": .string("Sources")])
        #expect(foreign.isToolError && foreign.firstText.contains("project \"Sources\" is not the open workspace; open it with workspace_open first."))
    }

    @Test func projectTestRejectsUnknownSchemeAndPlan() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let badScheme = try await host.server.callTool("project_test", ["scheme": .string("NopeScheme")])
        #expect(badScheme.isToolError && badScheme.firstText.contains("no scheme \"NopeScheme\""))
        let badPlan = try await host.server.callTool("project_test", ["testPlan": .string("NopePlan")])
        #expect(badPlan.isToolError && badPlan.firstText.contains("the scheme has no test plan \"NopePlan\""))
    }

    @Test func projectBuildAndTestRunRealBuildWhenPossible() async throws {
        guard canBuildPackages else { return }
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let built = try await host.server.callTool("project_build")
        #expect(!built.isToolError, "\(built.resultText)")
        #expect(built.structured?["status"] == "Passed" && built.structured?["error_count"] == 0)
        #expect(built.structured?["marker"] == "BUILD SUCCEEDED")
        #expect(built.firstText.contains("Build Succeeded"))
        let tested = try await host.server.callTool("project_test")
        #expect(!tested.isToolError, "\(tested.resultText)")
        #expect(tested.structured?["status"] == "Passed")
        #expect(tested.firstText.contains("Tests Passed"))
    }

    // MARK: - DerivedData / toolchain / destinations (environment-adaptive)

    @Test func derivedDataLocateAdaptsToEnvironment() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let dd = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        let r = try await host.server.callTool("derived_data_locate", ["nameFilter": .string("zzz-no-such-dd-zzz")])
        if FileManager.default.fileExists(atPath: dd.path) {
            #expect(!r.isToolError, "\(r.resultText)")
            #expect(r.structured?["count"] == 0)
            #expect(r.firstText.contains("No DerivedData directories matched."))
        } else {
            #expect(r.isToolError && r.firstText.contains("DerivedData directory not found at \(dd.path)."))
        }
    }

    @Test func xcresultParserReportsNoBundleWhenNoneExists() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let dd = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        var hasBundle = false
        if let enumerator = FileManager.default.enumerator(at: dd, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            while let item = enumerator.nextObject() as? URL {
                if item.pathExtension == "xcresult" { hasBundle = true; break }
            }
        }
        if !hasBundle {
            let r = try await host.server.callTool("xcresult_parser")
            #expect(!r.isToolError, "\(r.resultText)")
            #expect(r.firstText.contains("No .xcresult bundle found. Run a build or test suite first."))
            // A non-existent explicit bundle falls through to the
            // same search instead of failing.
            let explicit = try await host.server.callTool("xcresult_parser", ["bundlePath": .string("nope.xcresult")])
            #expect(!explicit.isToolError, "\(explicit.resultText)")
            #expect(explicit.firstText.contains("No .xcresult bundle found. Run a build or test suite first."))
        } else {
            // A bundle exists: parsing it through the real
            // xcresulttool must not error at the tool level.
            let r = try await host.server.callTool("xcresult_parser")
            #expect(!r.isToolError, "\(r.resultText)")
        }
    }

    @Test func xcodeToolchainInfoAdaptsToEnvironment() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("xcode_toolchain_info")
        if FileManager.default.fileExists(atPath: "/usr/bin/xcodebuild") {
            #expect(!r.isToolError, "\(r.resultText)")
            #expect(r.firstText.contains("Xcode toolchain:"))
            #expect(r.firstText.contains("Installed SDKs ("))
        } else {
            #expect(r.isToolError && r.firstText.contains("xcodebuild is not available (Xcode command-line tools missing?)."))
        }
    }

    @Test func xcodeDeviceDestinationFinderAdaptsToEnvironment() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("xcode_device_destination_finder")
        if FileManager.default.fileExists(atPath: "/usr/bin/xcrun") {
            #expect(!r.isToolError, "\(r.resultText)")
            #expect(r.firstText.contains("Available Simulator Destinations") || r.firstText.contains("No available simulators matching the requested filter."))
        } else {
            #expect(r.isToolError && r.firstText.contains("Failed to query simulator devices via simctl:"))
        }
    }
}
