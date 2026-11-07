import Foundation
import Testing
import SwiftCodeAssistant
@testable import SwiftCodeMCP

@MainActor
@Suite(.serialized) struct SwiftCodeProjectBuildToolsTests {
    static let sliceAIDs = ["project_build", "project_test", "project_clean", "project_archive", "build_log_analyze",
                            "build_system_detect", "build_configuration_list", "build_settings_diff", "build_phase_scripts_list",
                            "xcresult_parser", "derived_data_locate", "xcode_toolchain_info", "xcode_device_destination_finder"]

    func opened(_ sample: TempSample, policy: MCPWritePolicy = .readOnly) async throws -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        host.server.writePolicy = policy
        let ported = Set(host.projectBuildTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.projectBuildTools
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.url.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

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
    }

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
        #expect(r.structured?["result"]?.string == "succeeded" && r.structured?["errorCount"]?.int == 2 && r.structured?["warningCount"]?.int == 1)
        #expect(r.firstText.contains("Build log analysis for Logs/build.log:"))
        #expect(r.firstText.contains("- Result: succeeded"))
        #expect(r.firstText.contains("- Errors: 2"))
        #expect(r.firstText.contains("- Warnings: 1"))
        #expect(r.firstText.contains("ERROR: /Sources/A.swift:10: error: cannot find 'foo' in scope"))
        #expect(r.firstText.contains("WARNING: /Sources/B.swift:20: warning: unused variable 'x'"))
        #expect(r.firstText.components(separatedBy: "cannot find 'foo'").count - 1 == 1)

        try writeFixture(sample, "Logs/failed.log", "** BUILD FAILED **\n")
        let failed = try await host.server.callTool("build_log_analyze", ["path": .string("Logs/failed.log")])
        #expect(!failed.isToolError, "\(failed.resultText)")
        #expect(failed.structured?["result"]?.string == "failed")

        try writeFixture(sample, "Logs/plain.log", "nothing to see here\n")
        let unknown = try await host.server.callTool("build_log_analyze", ["path": .string("Logs/plain.log")])
        #expect(unknown.structured?["result"]?.string == "unknown")

        let missing = try await host.server.callTool("build_log_analyze", ["path": .string("Logs/nope.log")])
        #expect(missing.isToolError && missing.firstText.contains("Cannot read build log at: Logs/nope.log"))
        let noParam = try await host.server.callTool("build_log_analyze")
        #expect(noParam.isToolError)
        let outside = try await host.server.callTool("build_log_analyze", ["path": .string("../outside.log")])
        #expect(outside.isToolError && outside.firstText.contains("Cannot read build log at: ../outside.log"))
    }

    @Test func buildSystemDetectFindsSwiftPMAndXcodeBundles() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("build_system_detect")
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["count"]?.int == 1)
        #expect(r.firstText.contains("- SwiftPM: Package.swift"))
        try FileManager.default.createDirectory(atPath: sample.path("Foo.xcodeproj"), withIntermediateDirectories: true)
        try writeFixture(sample, "Podfile", "platform :ios\n")
        let again = try await host.server.callTool("build_system_detect")
        #expect(!again.isToolError, "\(again.resultText)")
        #expect(again.structured?["count"]?.int == 3)
        #expect(again.firstText.contains("- .xcodeproj: Foo.xcodeproj"))
        #expect(again.firstText.contains("- CocoaPods: Podfile"))
    }

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
        let none = try await host.server.callTool("build_configuration_list")
        #expect(none.isToolError && none.firstText.contains("No .pbxproj found in the workspace."))
        try writeFixture(sample, "Greeter.xcodeproj/project.pbxproj", Self.pbxprojFixture)
        let r = try await host.server.callTool("build_configuration_list")
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["ownerCount"]?.int == 2)
        #expect(r.structured?["configurations"]?.string == "Debug,Release")
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
        #expect(r.structured?["count"]?.int == 1)
        #expect(r.firstText.contains("Run Script build phases (1):"))
        #expect(r.firstText.contains("- Run Script (phase: Run Script):"))
        #expect(r.firstText.contains("echo hello"))
        #expect(r.firstText.contains("echo world"))
        let longScript = String(repeating: "x ", count: 400)
        let longFixture = Self.pbxprojFixture.replacingOccurrences(of: "echo hello\\n echo world", with: longScript)
        try writeFixture(sample, "Greeter.xcodeproj/project.pbxproj", longFixture)
        let truncated = try await host.server.callTool("build_phase_scripts_list")
        #expect(!truncated.isToolError, "\(truncated.resultText)")
        #expect(truncated.firstText.contains(" [truncated]"))
        #expect(truncated.firstText.contains("script truncated: showing first 600 of 800 characters"))
    }

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
        #expect(r.structured?["added"]?.int == 1 && r.structured?["removed"]?.int == 1 && r.structured?["changed"]?.int == 1)
        #expect(r.firstText.contains("Build settings diff (Configs/old.xcconfig -> Configs/new.xcconfig):"))
        #expect(r.firstText.contains("- ADDED: NEW_KEY = added"))
        #expect(r.firstText.contains("- REMOVED: DEAD_KEY (was: gone)"))
        #expect(r.firstText.contains("- CHANGED: PRODUCT_NAME: 'Greeter' -> 'GreeterApp'"))
        let identical = try await host.server.callTool("build_settings_diff", ["oldPath": .string("Configs/old.xcconfig"),
                                                                               "newPath": .string("Configs/old.xcconfig")])
        #expect(!identical.isToolError, "\(identical.resultText)")
        #expect(identical.structured?["added"]?.int == 0 && identical.structured?["removed"]?.int == 0 && identical.structured?["changed"]?.int == 0)
        #expect(identical.firstText.contains("Build settings are identical."))
        let noParam = try await host.server.callTool("build_settings_diff", ["oldPath": .string("Configs/old.xcconfig")])
        #expect(noParam.isToolError)
        let unreadable = try await host.server.callTool("build_settings_diff", ["oldPath": .string("Configs/nope.xcconfig"),
                                                                                "newPath": .string("Configs/new.xcconfig")])
        #expect(unreadable.isToolError && unreadable.firstText.contains("Cannot parse xcconfig at: Configs/nope.xcconfig"))
    }

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
        #expect(cleaned.structured?["removed"]?.string == "build/" && cleaned.structured?["scope"]?.string == "build")
        #expect(cleaned.firstText.contains("Cleaned: build/."))
        #expect(!exists(sample, "build"))
        let again = try await host.server.callTool("project_clean", ["scope": .string("build"), "confirm": .string("true")])
        #expect(!again.isToolError, "\(again.resultText)")
        #expect(again.structured?["removed"]?.string == "")
        #expect(again.firstText.contains("Nothing to clean. build/ did not exist."))
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
        #expect(r.structured?["removed"]?.string == "xcodebuild clean" && r.structured?["scope"]?.string == "derivedData")
    }

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
        let package = try await host.server.callTool("project_archive", ["scheme": .string("Greeter"),
                                                                          "archivePath": .string("Archives/Greeter.xcarchive")])
        #expect(package.isToolError && package.firstText.contains("No .xcodeproj or .xcworkspace found at the top level of the workspace."))
        #expect(!exists(sample, "Archives"))
    }

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
        #expect(built.structured?["status"]?.string == "Passed" && built.structured?["error_count"]?.int == 0)
        #expect(built.structured?["marker"]?.string == "BUILD SUCCEEDED")
        #expect(built.firstText.contains("Build Succeeded"))
        let tested = try await host.server.callTool("project_test")
        #expect(!tested.isToolError, "\(tested.resultText)")
        #expect(tested.structured?["status"]?.string == "Passed")
        #expect(tested.firstText.contains("Tests Passed"))
    }

    @Test func derivedDataLocateAdaptsToEnvironment() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let dd = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Developer/Xcode/DerivedData")
        let r = try await host.server.callTool("derived_data_locate", ["nameFilter": .string("zzz-no-such-dd-zzz")])
        if FileManager.default.fileExists(atPath: dd.path) {
            #expect(!r.isToolError, "\(r.resultText)")
            #expect(r.structured?["count"]?.int == 0)
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
            let explicit = try await host.server.callTool("xcresult_parser", ["bundlePath": .string("nope.xcresult")])
            #expect(!explicit.isToolError, "\(explicit.resultText)")
            #expect(explicit.firstText.contains("No .xcresult bundle found. Run a build or test suite first."))
        } else {
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
