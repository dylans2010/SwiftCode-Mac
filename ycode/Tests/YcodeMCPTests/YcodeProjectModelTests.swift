import Foundation
import Testing
import YcodeAssistant
@testable import YcodeMCP

/// The ported Legacy project-model / pbxproj tools (Wave 7, slice B),
/// each driven black-box through the server's real write-policy path
/// against a fixture `.xcodeproj` built inside a copy of
/// `Samples/AgentSamples/Greeter`.
///
/// Behaviour source: Legacy `AssistCreateNewAppTool`,
/// `AssistGenerateXcodeprojTool`, `AssistPbxprojLintTool`,
/// `AssistProjectBuildSettingsTool`, `AssistProjectCapabilitiesTool`,
/// `AssistDiffTool`, `AssistProjectMutationController`,
/// `AssistRestoreSnapshotTool`, `AssistProjectSchemeListTool`,
/// `AssistSnapshotProjectTool`, `AssistProjectStructureMapTool`,
/// `AssistProjectTargetAddTool`, `AssistProjectTargetListTool`,
/// `AssistSchemeTestPlanListTool`, `AssistTargetDependenciesListTool`,
/// `AssistTargetSourceListTool`, `AssistWorkspaceSettingsReadTool`,
/// `AssistXcodeBuildSettingsTool` and `AssistXcodeSchemeTool`
/// (Dylan's own code, ported under MIT).
///
/// Assertions are on the tool RESULT (message + on-disk state), never
/// on internals. Messages quoted verbatim are Legacy's. Message
/// assertions use `firstText`, never an exact `resultText ==`
/// (structured results emit two text blocks). Tests that run the
/// real build/test seam are gated on `canBuildPackages`, like the
/// `test` tool's own tests; nothing here claims a build passed
/// without running one.
@MainActor
@Suite(.serialized) struct YcodeProjectModelTests {
    /// The 19 Wave 7 slice B tool IDs, verified live from each
    /// Legacy tool file's `id`, in the slice's order.
    static let sliceBIDs = ["create_new_app", "generate_xcodeproj", "pbxproj_lint", "project_build_settings",
                            "project_capabilities", "project_diff", "project_mutation_controller", "project_restore",
                            "project_scheme_list", "project_snapshot", "project_structure_map", "project_target_add",
                            "project_target_list", "scheme_test_plan_list", "target_dependencies_list", "target_source_list",
                            "workspace_settings_read", "xcode_build_settings_inspector", "xcode_scheme_manager"]

    /// Opens the fixture `.xcodeproj` and installs the ported project
    /// tools on the server (same shape as Wave 6's `opened`).
    func openedProject(_ sample: TempSample, policy: MCPWritePolicy = .readOnly) async throws -> YcodeMCPHost {
        let host = YcodeMCPHost()
        host.server.writePolicy = policy
        let ported = Set(host.projectModelTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.projectModelTools
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.path("FixtureApp.xcodeproj"))])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    /// Opens the Greeter package itself (no `.xcodeproj` inside).
    func openedPackage(_ sample: TempSample, policy: MCPWritePolicy = .readOnly) async throws -> YcodeMCPHost {
        let host = YcodeMCPHost()
        host.server.writePolicy = policy
        let ported = Set(host.projectModelTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.projectModelTools
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

    func read(_ sample: TempSample, _ rel: String) -> String {
        (try? String(contentsOfFile: sample.path(rel), encoding: .utf8)) ?? ""
    }

    /// The fixture `.xcodeproj`: two targets (`FixtureApp` app,
    /// `FixtureFramework` framework; the app depends on the
    /// framework), two source files, one missing file reference,
    /// one duplicate path, one dangling build file, one scheme, one
    /// test plan, one entitlements file, one `.xcsettings` file.
    /// Reference counts the lint test relies on: 6 file references
    /// (4 source + 2 products), 3 missing (Gone.swift,
    /// FixtureApp.app, FixtureFramework.framework), 1 duplicate
    /// (FixtureApp/App.swift twice), 1 dangling build file.
    func fixtureProject(_ sample: TempSample) throws {
        try writeFixture(sample, "FixtureApp/App.swift", "import Foundation\n\npublic struct App {\n    public init() {}\n}\n")
        try writeFixture(sample, "FixtureApp/Helper.swift", "import Foundation\n\npublic struct Helper {\n    public init() {}\n}\n")
        try writeFixture(sample, "FixtureApp/FixtureApp.entitlements", """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>aps-environment</key>
        \t<string>development</string>
        \t<key>com.apple.security.app-sandbox</key>
        \t<true/>
        </dict>
        </plist>
        """)
        try writeFixture(sample, "Plans/Smoke.xctestplan", """
        {
          "testTargets" : [
            {
              "target" : {
                "name" : "FixtureAppTests"
              }
            }
          ],
          "version" : 1
        }
        """)
        try writeFixture(sample, "FixtureApp.xcodeproj/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings", """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
        \t<key>BuildSystemType</key>
        \t<string>Latest</string>
        \t<key>DerivedDataLocationStyle</key>
        \t<string>Default</string>
        </dict>
        </plist>
        """)
        try writeFixture(sample, "FixtureApp.xcodeproj/xcshareddata/xcschemes/FixtureApp.xcscheme", """
        <?xml version="1.0" encoding="UTF-8"?>
        <Scheme LastUpgradeVersion="1500" version="1.3">
           <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
              <BuildActionEntries>
                 <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
                    <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="AAAA00000000000000000009" BuildableName="FixtureApp.app" BlueprintName="FixtureApp" ReferencedContainer="container:FixtureApp.xcodeproj"/>
                 </BuildActionEntry>
              </BuildActionEntries>
           </BuildAction>
           <TestAction buildConfiguration="Debug"/>
           <LaunchAction buildConfiguration="Debug"/>
           <ProfileAction buildConfiguration="Release"/>
           <AnalyzeAction buildConfiguration="Debug"/>
        </Scheme>
        """)
        try writeFixture(sample, "FixtureApp.xcodeproj/project.pbxproj", Self.fixturePbxproj)
    }

    /// Minimal but realistic pbxproj (object version 56) for the
    /// fixture. IDs are fixed 24-hex strings; comments follow
    /// Xcode's layout because `pbxproj_lint`'s regexes read them.
    static let fixturePbxproj = """
    // !$*UTF8*$!
    {
    \tarchiveVersion = 1;
    \tclasses = {
    \t};
    \tobjectVersion = 56;
    \tobjects = {

    /* Begin PBXBuildFile section */
    \t\tAAAA0000000000000000000D /* App.swift in Sources */ = {isa = PBXBuildFile; fileRef = AAAA00000000000000000005 /* App.swift */; };
    \t\tAAAA0000000000000000000E /* Helper.swift in Sources */ = {isa = PBXBuildFile; fileRef = AAAA00000000000000000006 /* Helper.swift */; };
    \t\tAAAA0000000000000000001D /* Gone.swift in Sources */ = {isa = PBXBuildFile; fileRef = AAAA0000000000000000001C /* Gone.swift */; };
    /* End PBXBuildFile section */

    /* Begin PBXContainerItemProxy section */
    \t\tAAAA00000000000000000010 /* PBXContainerItemProxy */ = {
    \t\t\tisa = PBXContainerItemProxy;
    \t\t\tcontainerPortal = AAAA00000000000000000001 /* FixtureApp */;
    \t\t\tproxyType = 1;
    \t\t\tremoteGlobalIDString = AAAA0000000000000000000A;
    \t\t\tremoteInfo = FixtureFramework;
    \t\t};
    /* End PBXContainerItemProxy section */

    /* Begin PBXFileReference section */
    \t\tAAAA00000000000000000005 /* App.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = FixtureApp/App.swift; sourceTree = "<group>"; };
    \t\tAAAA00000000000000000006 /* Helper.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = FixtureApp/Helper.swift; sourceTree = "<group>"; };
    \t\tAAAA00000000000000000007 /* FixtureApp.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = FixtureApp.app; sourceTree = BUILT_PRODUCTS_DIR; };
    \t\tAAAA00000000000000000008 /* FixtureFramework.framework */ = {isa = PBXFileReference; explicitFileType = wrapper.framework; includeInIndex = 0; path = FixtureFramework.framework; sourceTree = BUILT_PRODUCTS_DIR; };
    \t\tAAAA0000000000000000001A /* Gone.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = FixtureApp/Gone.swift; sourceTree = "<group>"; };
    \t\tAAAA0000000000000000001B /* App.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = FixtureApp/App.swift; sourceTree = "<group>"; };
    /* End PBXFileReference section */

    /* Begin PBXGroup section */
    \t\tAAAA00000000000000000002 /* FixtureApp */ = {
    \t\t\tisa = PBXGroup;
    \t\t\tchildren = (
    \t\t\t\tAAAA00000000000000000003 /* FixtureApp */,
    \t\t\t\tAAAA00000000000000000004 /* Products */,
    \t\t\t);
    \t\t\tsourceTree = "<group>";
    \t\t};
    \t\tAAAA00000000000000000003 /* FixtureApp */ = {
    \t\t\tisa = PBXGroup;
    \t\t\tchildren = (
    \t\t\t\tAAAA00000000000000000005 /* App.swift */,
    \t\t\t\tAAAA00000000000000000006 /* Helper.swift */,
    \t\t\t\tAAAA0000000000000000001A /* Gone.swift */,
    \t\t\t\tAAAA0000000000000000001B /* App.swift */,
    \t\t\t);
    \t\t\tpath = FixtureApp;
    \t\t\tsourceTree = "<group>";
    \t\t};
    \t\tAAAA00000000000000000004 /* Products */ = {
    \t\t\tisa = PBXGroup;
    \t\t\tchildren = (
    \t\t\t\tAAAA00000000000000000007 /* FixtureApp.app */,
    \t\t\t\tAAAA00000000000000000008 /* FixtureFramework.framework */,
    \t\t\t);
    \t\t\tname = Products;
    \t\t\tsourceTree = "<group>";
    \t\t};
    /* End PBXGroup section */

    /* Begin PBXNativeTarget section */
    \t\tAAAA00000000000000000009 /* FixtureApp */ = {
    \t\t\tisa = PBXNativeTarget;
    \t\t\tbuildConfigurationList = AAAA00000000000000000012 /* Build configuration list for PBXNativeTarget "FixtureApp" */;
    \t\t\tbuildPhases = (
    \t\t\t\tAAAA0000000000000000000B /* Sources */,
    \t\t\t);
    \t\t\tbuildRules = (
    \t\t\t);
    \t\t\tdependencies = (
    \t\t\t\tAAAA0000000000000000000F /* PBXTargetDependency */,
    \t\t\t);
    \t\t\tname = FixtureApp;
    \t\t\tproductName = FixtureApp;
    \t\t\tproductReference = AAAA00000000000000000007 /* FixtureApp.app */;
    \t\t\tproductType = "com.apple.product-type.application";
    \t\t};
    \t\tAAAA0000000000000000000A /* FixtureFramework */ = {
    \t\t\tisa = PBXNativeTarget;
    \t\t\tbuildConfigurationList = AAAA00000000000000000013 /* Build configuration list for PBXNativeTarget "FixtureFramework" */;
    \t\t\tbuildPhases = (
    \t\t\t\tAAAA0000000000000000000C /* Sources */,
    \t\t\t);
    \t\t\tbuildRules = (
    \t\t\t);
    \t\t\tdependencies = (
    \t\t\t);
    \t\t\tname = FixtureFramework;
    \t\t\tproductName = FixtureFramework;
    \t\t\tproductReference = AAAA00000000000000000008 /* FixtureFramework.framework */;
    \t\t\tproductType = "com.apple.product-type.framework";
    \t\t};
    /* End PBXNativeTarget section */

    /* Begin PBXProject section */
    \t\tAAAA00000000000000000001 /* FixtureApp */ = {
    \t\t\tisa = PBXProject;
    \t\t\tattributes = {
    \t\t\t\tLastUpgradeCheck = 1500;
    \t\t\t\tTargetAttributes = {
    \t\t\t\t\tAAAA00000000000000000009 = {
    \t\t\t\t\t\tSystemCapabilities = {
    \t\t\t\t\t\t\tcom.apple.Push = {
    \t\t\t\t\t\t\t\tenabled = 1;
    \t\t\t\t\t\t\t};
    \t\t\t\t\t\t};
    \t\t\t\t\t};
    \t\t\t\t};
    \t\t\t};
    \t\t\tbuildConfigurationList = AAAA00000000000000000011 /* Build configuration list for PBXProject "FixtureApp" */;
    \t\t\tcompatibilityVersion = "Xcode 14.0";
    \t\t\tdevelopmentRegion = en;
    \t\t\thasScannedForEncodings = 0;
    \t\t\tknownRegions = (
    \t\t\t\ten,
    \t\t\t\tBase,
    \t\t\t);
    \t\t\tmainGroup = AAAA00000000000000000002;
    \t\t\tproductRefGroup = AAAA00000000000000000004 /* Products */;
    \t\t\tprojectDirPath = "";
    \t\t\tprojectRoot = "";
    \t\t\ttargets = (
    \t\t\t\tAAAA00000000000000000009 /* FixtureApp */,
    \t\t\t\tAAAA0000000000000000000A /* FixtureFramework */,
    \t\t\t);
    \t\t};
    /* End PBXProject section */

    /* Begin PBXSourcesBuildPhase section */
    \t\tAAAA0000000000000000000B /* Sources */ = {
    \t\t\tisa = PBXSourcesBuildPhase;
    \t\t\tbuildActionMask = 2147483647;
    \t\t\tfiles = (
    \t\t\t\tAAAA0000000000000000000D /* App.swift in Sources */,
    \t\t\t\tAAAA0000000000000000000E /* Helper.swift in Sources */,
    \t\t\t\tAAAA0000000000000000001D /* Gone.swift in Sources */,
    \t\t\t);
    \t\t\trunOnlyForDeploymentPostprocessing = 0;
    \t\t};
    \t\tAAAA0000000000000000000C /* Sources */ = {
    \t\t\tisa = PBXSourcesBuildPhase;
    \t\t\tbuildActionMask = 2147483647;
    \t\t\tfiles = (
    \t\t\t);
    \t\t\trunOnlyForDeploymentPostprocessing = 0;
    \t\t};
    /* End PBXSourcesBuildPhase section */

    /* Begin PBXTargetDependency section */
    \t\tAAAA0000000000000000000F /* PBXTargetDependency */ = {
    \t\t\tisa = PBXTargetDependency;
    \t\t\ttarget = AAAA0000000000000000000A /* FixtureFramework */;
    \t\t\ttargetProxy = AAAA00000000000000000010 /* PBXContainerItemProxy */;
    \t\t};
    /* End PBXTargetDependency section */

    /* Begin XCBuildConfiguration section */
    \t\tAAAA00000000000000000014 /* Debug */ = {
    \t\t\tisa = XCBuildConfiguration;
    \t\t\tbuildSettings = {
    \t\t\t\tMACOSX_DEPLOYMENT_TARGET = 15.0;
    \t\t\t\tPRODUCT_NAME = FixtureApp;
    \t\t\t};
    \t\t\tname = Debug;
    \t\t};
    \t\tAAAA00000000000000000015 /* Release */ = {
    \t\t\tisa = XCBuildConfiguration;
    \t\t\tbuildSettings = {
    \t\t\t\tMACOSX_DEPLOYMENT_TARGET = 15.0;
    \t\t\t\tPRODUCT_NAME = FixtureApp;
    \t\t\t};
    \t\t\tname = Release;
    \t\t};
    \t\tAAAA00000000000000000016 /* Debug */ = {
    \t\t\tisa = XCBuildConfiguration;
    \t\t\tbuildSettings = {
    \t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.example.fixtureapp;
    \t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
    \t\t\t\tSWIFT_VERSION = 5.0;
    \t\t\t};
    \t\t\tname = Debug;
    \t\t};
    \t\tAAAA00000000000000000017 /* Release */ = {
    \t\t\tisa = XCBuildConfiguration;
    \t\t\tbuildSettings = {
    \t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.example.fixtureapp;
    \t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
    \t\t\t\tSWIFT_VERSION = 5.0;
    \t\t\t};
    \t\t\tname = Release;
    \t\t};
    \t\tAAAA00000000000000000018 /* Debug */ = {
    \t\t\tisa = XCBuildConfiguration;
    \t\t\tbuildSettings = {
    \t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
    \t\t\t\tSWIFT_VERSION = 5.0;
    \t\t\t};
    \t\t\tname = Debug;
    \t\t};
    \t\tAAAA00000000000000000019 /* Release */ = {
    \t\t\tisa = XCBuildConfiguration;
    \t\t\tbuildSettings = {
    \t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
    \t\t\t\tSWIFT_VERSION = 5.0;
    \t\t\t};
    \t\t\tname = Release;
    \t\t};
    /* End XCBuildConfiguration section */

    /* Begin XCConfigurationList section */
    \t\tAAAA00000000000000000011 /* Build configuration list for PBXProject "FixtureApp" */ = {
    \t\t\tisa = XCBuildConfigurationList;
    \t\t\tbuildConfigurations = (
    \t\t\t\tAAAA00000000000000000014 /* Debug */,
    \t\t\t\tAAAA00000000000000000015 /* Release */,
    \t\t\t);
    \t\t\tdefaultConfigurationIsVisible = 0;
    \t\t\tdefaultConfigurationName = Release;
    \t\t};
    \t\tAAAA00000000000000000012 /* Build configuration list for PBXNativeTarget "FixtureApp" */ = {
    \t\t\tisa = XCBuildConfigurationList;
    \t\t\tbuildConfigurations = (
    \t\t\t\tAAAA00000000000000000016 /* Debug */,
    \t\t\t\tAAAA00000000000000000017 /* Release */,
    \t\t\t);
    \t\t\tdefaultConfigurationIsVisible = 0;
    \t\t\tdefaultConfigurationName = Release;
    \t\t};
    \t\tAAAA00000000000000000013 /* Build configuration list for PBXNativeTarget "FixtureFramework" */ = {
    \t\t\tisa = XCBuildConfigurationList;
    \t\t\tbuildConfigurations = (
    \t\t\t\tAAAA00000000000000000018 /* Debug */,
    \t\t\t\tAAAA00000000000000000019 /* Release */,
    \t\t\t);
    \t\t\tdefaultConfigurationIsVisible = 0;
    \t\t\tdefaultConfigurationName = Release;
    \t\t};
    /* End XCConfigurationList section */

    \t};
    \trootObject = AAAA00000000000000000001 /* FixtureApp */;
    }
    """

    final class Reviews: @unchecked Sendable {
        var changes: [MCPChange] = []
        var accept = false
    }

    @Test func toolIDsAreRegisteredOnce() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await openedPackage(sample)
        #expect(host.projectModelTools.map(\.name) == Self.sliceBIDs)
        for id in Self.sliceBIDs {
            #expect(host.server.tools.filter { $0.name == id }.count == 1, "\(id) must be registered exactly once")
        }
        // The slice's Legacy aliases, `xcode_scheme` →
        // `xcode_scheme_manager` and `build_settings` →
        // `xcode_build_settings_inspector` (registry alias table),
        // live in `MCPServer.toolAliases`, which the coordinator
        // owns — they are reported as wiring fragments instead of
        // asserted here.
    }

    // MARK: - Pure reads: lint, schemes, targets, sources, plans, settings

    @Test func pbxprojLintCountsMissingDuplicatesAndDangling() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try fixtureProject(sample)
        let host = try await openedProject(sample)
        let r = try await host.server.callTool("pbxproj_lint")
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["fileRefCount"]?.int == 6)
        #expect(r.structured?["missingCount"]?.int == 3)
        #expect(r.structured?["duplicateCount"]?.int == 1)
        #expect(r.structured?["danglingCount"]?.int == 1)
        #expect(r.structured?["clean"]?.bool == false)
        #expect(r.firstText.contains("MISSING: FixtureApp/Gone.swift"))
        #expect(r.firstText.contains("DUPLICATE: FixtureApp/App.swift"))
        #expect(r.firstText.contains("DANGLING: Gone.swift"))
    }

    @Test func pbxprojLintFailsWithoutPbxproj() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await openedPackage(sample)
        let r = try await host.server.callTool("pbxproj_lint")
        #expect(r.isToolError)
        #expect(r.firstText == "No .pbxproj found in the workspace.")
    }

    @Test func projectSchemeListListsFixtureScheme() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try fixtureProject(sample)
        let host = try await openedProject(sample)
        let r = try await host.server.callTool("project_scheme_list")
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["project"]?.string == "FixtureApp.xcodeproj")
        let schemes = r.structured?["schemes"]?.string ?? ""
        #expect(schemes.contains("FixtureApp"))
        #expect((r.structured?["count"]?.int ?? 0) >= 1)
    }

    @Test func projectSchemeListFailsForPackage() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await openedPackage(sample)
        let r = try await host.server.callTool("project_scheme_list")
        #expect(r.isToolError)
        #expect(r.firstText == "No .xcodeproj or .xcworkspace found at the top level of the workspace.")
    }

    @Test func projectTargetListListsBothTargets() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try fixtureProject(sample)
        let host = try await openedProject(sample)
        let r = try await host.server.callTool("project_target_list")
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["targets"]?.string == "FixtureApp,FixtureFramework")
        #expect(r.structured?["count"]?.int == 2)
        #expect(r.structured?["sources"]?.string == "project.pbxproj")
    }

    @Test func projectTargetListFailsWithoutPbxproj() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await openedPackage(sample)
        let r = try await host.server.callTool("project_target_list")
        #expect(r.isToolError)
        #expect(r.firstText == "No Xcode targets found. No .xcodeproj with a project.pbxproj was located in the workspace.")
    }

    @Test func targetSourceListListsCompiledSources() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try fixtureProject(sample)
        let host = try await openedProject(sample)
        let one = try await host.server.callTool("target_source_list", ["target": .string("FixtureApp")])
        #expect(!one.isToolError, "\(one.resultText)")
        #expect(one.structured?["targetCount"]?.int == 1)
        #expect(one.firstText.contains("FixtureApp/App.swift"))
        #expect(one.firstText.contains("FixtureApp/Helper.swift"))
        #expect(!one.firstText.contains("Gone.swift"))
        let all = try await host.server.callTool("target_source_list")
        #expect(!all.isToolError, "\(all.resultText)")
        #expect(all.structured?["targetCount"]?.int == 2)
        #expect(all.firstText.contains("FixtureFramework (0 files)"))
        let missing = try await host.server.callTool("target_source_list", ["target": .string("Nope")])
        #expect(missing.isToolError)
        #expect(missing.firstText == "Target 'Nope' not found in the pbxproj.")
    }

    @Test func targetDependenciesListShowsAppDependsOnFramework() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try fixtureProject(sample)
        let host = try await openedProject(sample)
        let r = try await host.server.callTool("target_dependencies_list")
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["targetCount"]?.int == 2)
        #expect(r.structured?["edgeCount"]?.int == 1)
        #expect(r.firstText.contains("- FixtureApp: FixtureFramework"))
        #expect(r.firstText.contains("- FixtureFramework: (no target dependencies)"))
    }

    @Test func projectStructureMapCountsDirsAndTargets() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try fixtureProject(sample)
        let host = try await openedProject(sample)
        let r = try await host.server.callTool("project_structure_map", ["maxDepth": .int(1)])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["targets"]?.string == "FixtureApp,FixtureFramework")
        #expect((r.structured?["directoryCount"]?.int ?? 0) >= 1)
        #expect(r.firstText.contains("- FixtureApp/ — 3 files"))
        #expect(r.firstText.contains("Xcode targets: FixtureApp, FixtureFramework"))
    }

    @Test func schemeTestPlanListListsPlanTargets() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try fixtureProject(sample)
        let host = try await openedProject(sample)
        let r = try await host.server.callTool("scheme_test_plan_list")
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["count"]?.int == 1)
        #expect(r.firstText.contains("Plans/Smoke.xctestplan — targets: FixtureAppTests"))
        let bare = try TempSample()
        defer { bare.remove() }
        let empty = try await openedPackage(bare)
        let none = try await empty.server.callTool("scheme_test_plan_list")
        #expect(!none.isToolError, "\(none.resultText)")
        #expect(none.firstText == "No .xctestplan files found in the workspace.")
    }

    @Test func workspaceSettingsReadListsXcsettings() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try fixtureProject(sample)
        let host = try await openedProject(sample)
        let r = try await host.server.callTool("workspace_settings_read")
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["count"]?.int == 1)
        #expect(r.firstText.contains("BuildSystemType = Latest"))
        #expect(r.firstText.contains("DerivedDataLocationStyle = Default"))
        let bare = try TempSample()
        defer { bare.remove() }
        let empty = try await openedPackage(bare)
        let none = try await empty.server.callTool("workspace_settings_read")
        #expect(!none.isToolError, "\(none.resultText)")
        #expect(none.firstText == "No .xcsettings files found (default Xcode workspace settings apply).")
    }

    @Test func xcodeBuildSettingsInspectorReadsFromPbxproj() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try fixtureProject(sample)
        let host = try await openedProject(sample)
        let one = try await host.server.callTool("xcode_build_settings_inspector",
                                                 ["target": .string("FixtureApp"), "settingKey": .string("PRODUCT_BUNDLE_IDENTIFIER")])
        #expect(!one.isToolError, "\(one.resultText)")
        #expect(one.firstText == "PRODUCT_BUNDLE_IDENTIFIER = com.example.fixtureapp")
        let all = try await host.server.callTool("xcode_build_settings_inspector", ["target": .string("FixtureApp")])
        #expect(!all.isToolError, "\(all.resultText)")
        #expect(all.firstText.contains("### Active Xcode Build Settings:"))
        #expect(all.firstText.contains("- **SWIFT_VERSION**: `5.0`"))
        let missing = try await host.server.callTool("xcode_build_settings_inspector", ["settingKey": .string("NOPE")])
        #expect(missing.isToolError)
        #expect(missing.firstText == "Build setting 'NOPE' was not found in xcodebuild output.")
        let badTarget = try await host.server.callTool("xcode_build_settings_inspector", ["target": .string("Nope")])
        #expect(badTarget.isToolError)
        #expect(badTarget.firstText == "Target 'Nope' not found in project.pbxproj.")
    }

    @Test func xcodeSchemeManagerListsAndInspects() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try fixtureProject(sample)
        let host = try await openedProject(sample)
        let list = try await host.server.callTool("xcode_scheme_manager", ["action": .string("list_schemes")])
        #expect(!list.isToolError, "\(list.resultText)")
        #expect(list.firstText.contains("Xcode Schemes & Targets:"))
        #expect(list.firstText.contains("FixtureApp"))
        let inspect = try await host.server.callTool("xcode_scheme_manager",
                                                     ["action": .string("inspect_scheme"), "schemeName": .string("FixtureApp")])
        #expect(!inspect.isToolError, "\(inspect.resultText)")
        #expect(inspect.firstText.contains("Scheme 'FixtureApp' found at FixtureApp.xcscheme:"))
        #expect(inspect.firstText.contains("BuildAction"))
        let missing = try await host.server.callTool("xcode_scheme_manager",
                                                     ["action": .string("inspect_scheme"), "schemeName": .string("Nope")])
        #expect(missing.isToolError)
        #expect(missing.firstText == "Scheme file 'Nope.xcscheme' not found in workspace.")
        let noName = try await host.server.callTool("xcode_scheme_manager", ["action": .string("inspect_scheme")])
        #expect(noName.isToolError)
        #expect(noName.firstText == "schemeName parameter is required for inspect_scheme")
        let bad = try await host.server.callTool("xcode_scheme_manager", ["action": .string("bogus")])
        #expect(bad.isToolError)
        #expect(bad.firstText == "Unsupported action 'bogus'. Valid: list_schemes, inspect_scheme")
    }

    @Test func projectDiffFailsOutsideGitRepo() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try fixtureProject(sample)
        let host = try await openedProject(sample)
        let r = try await host.server.callTool("project_diff")
        #expect(r.isToolError)
        #expect(r.firstText.contains("Diff inspection failed:"))
    }

    @Test func projectDiffReportsRealWorkingTreeDiff() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try fixtureProject(sample)
        guard gitAvailable() else {
            // Without git the tool fails honestly; that path is
            // covered by projectDiffFailsOutsideGitRepo's sibling
            // assertion here.
            let host = try await openedProject(sample)
            let r = try await host.server.callTool("project_diff")
            #expect(r.isToolError && r.firstText.contains("Diff inspection failed:"))
            return
        }
        let dir = sample.url
        #expect(runGit(["init", "-q"], in: dir) == 0)
        #expect(runGit(["add", "-A"], in: dir) == 0)
        #expect(runGit(["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "init"], in: dir) == 0)
        try writeFixture(sample, "FixtureApp/App.swift", "import Foundation\n\n// changed\npublic struct App {\n    public init() {}\n}\n")
        let host = try await openedProject(sample)
        let r = try await host.server.callTool("project_diff")
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["staged_count"]?.int == 0)
        #expect(r.structured?["unstaged_count"]?.int == 1)
        #expect(r.firstText.contains("App.swift"))
        #expect(r.firstText.contains("diff hunks"))
        #expect((r.structured?["diff"]?.string ?? "").contains("changed"))
        // A clean tree reports clean.
        #expect(runGit(["add", "-A"], in: dir) == 0)
        #expect(runGit(["-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "change"], in: dir) == 0)
        let clean = try await host.server.callTool("project_diff")
        #expect(!clean.isToolError, "\(clean.resultText)")
        #expect(clean.firstText == "No changes detected. Working tree is clean.")
        #expect(clean.structured?["diff"]?.string == "")
    }

    func gitAvailable() -> Bool {
        FileManager.default.isExecutableFile(atPath: "/usr/bin/git")
    }

    func runGit(_ args: [String], in dir: URL) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = args
        p.currentDirectoryURL = dir
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    // MARK: - Writes: build settings, capabilities, mutation, targets

    @Test func projectBuildSettingsReadsMergedSettings() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try fixtureProject(sample)
        let host = try await openedProject(sample)
        let all = try await host.server.callTool("project_build_settings",
                                                 ["action": .string("read"), "target": .string("FixtureApp"), "configuration": .string("Debug")])
        #expect(!all.isToolError, "\(all.resultText)")
        #expect(all.firstText == "Found 4 build setting(s) for configuration 'Debug'.")
        #expect((all.structured?["settings"]?.string ?? "").contains("PRODUCT_BUNDLE_IDENTIFIER = com.example.fixtureapp"))
        #expect((all.structured?["settings"]?.string ?? "").contains("PRODUCT_NAME = $(TARGET_NAME)"))
        let one = try await host.server.callTool("project_build_settings",
                                                 ["action": .string("read"), "target": .string("FixtureApp"),
                                                  "configuration": .string("Debug"), "key": .string("SWIFT_VERSION")])
        #expect(!one.isToolError, "\(one.resultText)")
        #expect(one.firstText == "Build setting SWIFT_VERSION = 5.0")
        let missing = try await host.server.callTool("project_build_settings",
                                                     ["action": .string("read"), "key": .string("NOPE")])
        #expect(missing.isToolError)
        #expect(missing.firstText == "Build setting 'NOPE' not found for configuration 'Debug'.")
        let badAction = try await host.server.callTool("project_build_settings", ["action": .string("explode")])
        #expect(badAction.isToolError)
        #expect(badAction.firstText == "Invalid action 'explode'. Expected read or set.")
    }

    @Test func projectBuildSettingsSetWritesThroughApproval() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try fixtureProject(sample)
        let host = try await openedProject(sample, policy: .allow)
        let set = try await host.server.callTool("project_build_settings",
                                                 ["action": .string("set"), "target": .string("FixtureApp"),
                                                  "configuration": .string("Debug"), "key": .string("SWIFT_VERSION"),
                                                  "value": .string("6.0")])
        #expect(!set.isToolError, "\(set.resultText)")
        #expect(set.firstText == "Set build setting SWIFT_VERSION = 6.0 for configuration 'Debug'.")
        let read = try await host.server.callTool("project_build_settings",
                                                  ["action": .string("read"), "target": .string("FixtureApp"),
                                                   "configuration": .string("Debug"), "key": .string("SWIFT_VERSION")])
        #expect(!read.isToolError, "\(read.resultText)")
        #expect(read.firstText == "Build setting SWIFT_VERSION = 6.0")
        let badKey = try await host.server.callTool("project_build_settings",
                                                    ["action": .string("set"), "key": .string("BAD KEY!"), "value": .string("1")])
        #expect(badKey.isToolError)
        #expect(badKey.firstText == "Invalid build setting key 'BAD KEY!'.")
        let noValue = try await host.server.callTool("project_build_settings",
                                                     ["action": .string("set"), "key": .string("SWIFT_VERSION")])
        #expect(noValue.isToolError)
        #expect(noValue.firstText == "Missing required parameter: value for action=set")
        let badTarget = try await host.server.callTool("project_build_settings",
                                                       ["action": .string("set"), "target": .string("Nope"),
                                                        "key": .string("SWIFT_VERSION"), "value": .string("6.0")])
        #expect(badTarget.isToolError)
        #expect(badTarget.firstText == "Target 'Nope' not found in project.pbxproj.")
    }

    @Test func projectBuildSettingsSetRefusedInReadOnlyMode() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try fixtureProject(sample)
        let host = try await openedProject(sample)
        let r = try await host.server.callTool("project_build_settings",
                                               ["action": .string("set"), "key": .string("SWIFT_VERSION"), "value": .string("6.0")])
        #expect(r.isToolError && r.firstText.contains("read-only"))
        #expect(read(sample, "FixtureApp.xcodeproj/project.pbxproj").contains("SWIFT_VERSION = 5.0"))
    }

    @Test func projectCapabilitiesListEnableDisable() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try fixtureProject(sample)
        let host = try await openedProject(sample, policy: .allow)
        let list = try await host.server.callTool("project_capabilities")
        #expect(!list.isToolError, "\(list.resultText)")
        let caps = list.structured?["capabilities"]?.string ?? ""
        #expect(caps.contains("push"))
        #expect(caps.contains("appSandbox"))
        let enable = try await host.server.callTool("project_capabilities",
                                                    ["action": .string("enable"), "capability": .string("network")])
        #expect(!enable.isToolError, "\(enable.resultText)")
        #expect(enable.firstText == "Enabled capability 'network' (com.apple.security.network.client) in FixtureApp.entitlements.")
        let list2 = try await host.server.callTool("project_capabilities")
        #expect((list2.structured?["capabilities"]?.string ?? "").contains("network"))
        let disable = try await host.server.callTool("project_capabilities",
                                                     ["action": .string("disable"), "capability": .string("push")])
        #expect(!disable.isToolError, "\(disable.resultText)")
        #expect(disable.firstText == "Disabled capability 'push' (aps-environment) in FixtureApp.entitlements.")
        let list3 = try await host.server.callTool("project_capabilities")
        #expect(!(list3.structured?["capabilities"]?.string ?? "").contains("push"))
        let unknown = try await host.server.callTool("project_capabilities",
                                                     ["action": .string("enable"), "capability": .string("teleport")])
        #expect(unknown.isToolError)
        #expect(unknown.firstText == "Unknown capability 'teleport'. Supported: push, icloud, appGroups, appSandbox, keychain, network.")
        let disableAbsent = try await host.server.callTool("project_capabilities",
                                                           ["action": .string("disable"), "capability": .string("push")])
        #expect(disableAbsent.isToolError)
        #expect(disableAbsent.firstText == "Capability 'push' (aps-environment) is not enabled in entitlements.")
    }

    @Test func projectMutationControllerAddRemoveRepair() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try fixtureProject(sample)
        let host = try await openedProject(sample, policy: .allow)
        let add = try await host.server.callTool("project_mutation_controller",
                                                 ["action": .string("add"), "filePath": .string("FixtureApp/NewFile.swift")])
        #expect(!add.isToolError, "\(add.resultText)")
        #expect(add.firstText == "Project mutation complete: added NewFile.swift via 4-step registration protocol")
        #expect(add.structured?["project"]?.string == "FixtureApp.xcodeproj/project.pbxproj")
        let sources = try await host.server.callTool("target_source_list", ["target": .string("FixtureApp")])
        #expect(sources.firstText.contains("NewFile.swift"))
        let again = try await host.server.callTool("project_mutation_controller",
                                                   ["action": .string("add"), "filePath": .string("FixtureApp/NewFile.swift")])
        #expect(!again.isToolError, "\(again.resultText)")
        #expect(again.firstText == "File already referenced in project.pbxproj: FixtureApp/NewFile.swift")
        let remove = try await host.server.callTool("project_mutation_controller",
                                                    ["action": .string("remove"), "filePath": .string("FixtureApp/NewFile.swift")])
        #expect(!remove.isToolError, "\(remove.resultText)")
        #expect(remove.firstText == "Project mutation complete: remove")
        let sources2 = try await host.server.callTool("target_source_list", ["target": .string("FixtureApp")])
        #expect(!sources2.firstText.contains("NewFile.swift"))
        let repair = try await host.server.callTool("project_mutation_controller", ["action": .string("repair")])
        #expect(!repair.isToolError, "\(repair.resultText)")
        #expect(repair.firstText == "Project mutation complete: repair")
        let noGroup = try await host.server.callTool("project_mutation_controller",
                                                     ["action": .string("add"), "filePath": .string("NopeDir/File.swift")])
        #expect(noGroup.isToolError)
        #expect(noGroup.firstText.contains("No matching group found in FixtureApp.xcodeproj/project.pbxproj for directory 'NopeDir'."))
        let badAction = try await host.server.callTool("project_mutation_controller", ["action": .string("explode")])
        #expect(badAction.isToolError)
        #expect(badAction.firstText == "Unsupported action: explode")
        let noFile = try await host.server.callTool("project_mutation_controller", ["action": .string("add")])
        #expect(noFile.isToolError)
        #expect(noFile.firstText == "Missing filePath")
    }

    @Test func projectMutationControllerRefusedInReview() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try fixtureProject(sample)
        let reviews = Reviews()
        let host = try await openedProject(sample, policy: .review { c in reviews.changes.append(c); return reviews.accept })
        let rejected = try await host.server.callTool("project_mutation_controller",
                                                      ["action": .string("add"), "filePath": .string("FixtureApp/NewFile.swift")])
        #expect(rejected.isToolError && rejected.firstText == MCPServer.rejectedMessage)
        #expect(!read(sample, "FixtureApp.xcodeproj/project.pbxproj").contains("NewFile.swift"))
        #expect(reviews.changes.first?.tool == "project_mutation_controller")
    }

    @Test func projectTargetAddCreatesTargetAndSourceFile() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try fixtureProject(sample)
        let host = try await openedProject(sample, policy: .allow)
        let add = try await host.server.callTool("project_target_add",
                                                 ["targetName": .string("Widget"), "type": .string("app")])
        #expect(!add.isToolError, "\(add.resultText)")
        #expect(add.structured?["targetName"]?.string == "Widget")
        #expect(add.structured?["type"]?.string == "app")
        #expect(add.structured?["sourceDirectory"]?.string == "Widget")
        #expect(!(add.structured?["targetId"]?.string ?? "").isEmpty)
        #expect(add.firstText == "Added target 'Widget' (app) with source directory 'Widget/'.")
        #expect(exists(sample, "Widget/Widget.swift"))
        #expect(read(sample, "Widget/Widget.swift").contains("public struct WidgetApp"))
        let list = try await host.server.callTool("project_target_list")
        #expect((list.structured?["targets"]?.string ?? "").contains("Widget"))
        #expect(list.structured?["count"]?.int == 3)
        let dup = try await host.server.callTool("project_target_add", ["targetName": .string("Widget")])
        #expect(dup.isToolError)
        #expect(dup.firstText == "Target 'Widget' already exists in project.pbxproj.")
        let badType = try await host.server.callTool("project_target_add",
                                                     ["targetName": .string("Other"), "type": .string("daemon")])
        #expect(badType.isToolError)
        #expect(badType.firstText == "Invalid type 'daemon'. Expected app, framework, or test.")
        let badName = try await host.server.callTool("project_target_add", ["targetName": .string("Bad Name!")])
        #expect(badName.isToolError)
        #expect(badName.firstText == "Invalid target name 'Bad Name!'. Use letters, digits, underscore, or hyphen only.")
        let framework = try await host.server.callTool("project_target_add",
                                                       ["targetName": .string("Kit"), "type": .string("framework")])
        #expect(!framework.isToolError, "\(framework.resultText)")
        #expect(read(sample, "Kit/Kit.swift").contains("public struct Kit"))
    }

    @Test func createNewAppScaffoldsInsideWorkspace() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try fixtureProject(sample)
        let host = try await openedProject(sample, policy: .allow)
        let r = try await host.server.callTool("create_new_app",
                                               ["appName": .string("DemoNotes"),
                                                "applicationDescription": .string("A notes app."),
                                                "platform": .string("macOS")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Successfully initialized Create New App workflow for 'DemoNotes'."))
        #expect(r.firstText.contains("Bundle Identifier: com.swiftcode.demonotes"))
        #expect(exists(sample, "DemoNotes/DemoNotes.xcodeproj/project.pbxproj"))
        #expect(exists(sample, "DemoNotes/DemoNotes.xcodeproj/project.xcworkspace/contents.xcworkspacedata"))
        let outside = try await host.server.callTool("create_new_app",
                                                     ["appName": .string("Elsewhere"),
                                                      "applicationDescription": .string("A notes app."),
                                                      "projectLocation": .string("/tmp/elsewhere")])
        #expect(outside.isToolError)
        #expect(outside.firstText.contains("outside the workspace"))
        let missing = try await host.server.callTool("create_new_app",
                                                     ["applicationDescription": .string("A notes app.")])
        #expect(missing.isToolError)
    }

    @Test func generateXcodeprojFailsHonestlyWithoutSpecOrName() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try fixtureProject(sample)
        let host = try await openedProject(sample, policy: .allow)
        let missing = try await host.server.callTool("generate_xcodeproj")
        #expect(missing.isToolError)
        #expect(missing.firstText.contains("XcodeGen spec not found at 'project.yml'"))
        try writeFixture(sample, "project.yml", "targets:\n  Foo:\n    type: application\n")
        let noName = try await host.server.callTool("generate_xcodeproj")
        #expect(noName.isToolError)
        #expect(noName.firstText == "Could not determine the project name from 'project.yml'; xcodegen output cannot be approved as a change.")
    }

    // MARK: - Snapshots

    func snapshotStoreURL(_ id: String) throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("YcodeSnapshots", isDirectory: true)
            .appendingPathComponent(id, isDirectory: true)
    }

    @Test func projectSnapshotAndRestoreRoundTrip() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try fixtureProject(sample)
        let host = try await openedProject(sample, policy: .allow)
        let snap = try await host.server.callTool("project_snapshot", ["message": .string("Before edit")])
        #expect(!snap.isToolError, "\(snap.resultText)")
        let id = try #require(snap.structured?["snapshot_id"]?.string)
        #expect(!id.isEmpty)
        let storeURL = try snapshotStoreURL(id)
        defer { try? FileManager.default.removeItem(at: storeURL) }
        #expect(FileManager.default.fileExists(atPath: storeURL.appendingPathComponent("metadata.json").path))
        #expect(snap.firstText == "Successfully created project snapshot: Before edit")
        let original = read(sample, "FixtureApp/App.swift")
        try writeFixture(sample, "FixtureApp/App.swift", "import Foundation\n\n// edited\n")
        #expect(read(sample, "FixtureApp/App.swift").contains("edited"))
        let restore = try await host.server.callTool("project_restore", ["snapshot_id": .string(id)])
        #expect(!restore.isToolError, "\(restore.resultText)")
        #expect(restore.firstText == "Successfully restored project to snapshot: \(id)")
        #expect(read(sample, "FixtureApp/App.swift") == original)
        let unknown = try await host.server.callTool("project_restore", ["snapshot_id": .string("no-such-snapshot")])
        #expect(unknown.isToolError)
        #expect(unknown.firstText == "Failed to restore snapshot: Snapshot 'no-such-snapshot' not found.")
        let empty = try await host.server.callTool("project_restore", ["snapshot_id": .string("")])
        #expect(empty.isToolError)
        #expect(empty.firstText == "Missing required parameter: snapshot_id")
    }

    @Test func projectSnapshotRefusedInReadOnlyMode() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try fixtureProject(sample)
        let host = try await openedProject(sample)
        let r = try await host.server.callTool("project_snapshot")
        #expect(r.isToolError && r.firstText.contains("read-only"))
    }

    @Test func projectRestoreRefusedInReviewLeavesWorkspaceAlone() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        try fixtureProject(sample)
        let allowed = try await openedProject(sample, policy: .allow)
        let snap = try await allowed.server.callTool("project_snapshot", ["message": .string("Before edit")])
        let id = try #require(snap.structured?["snapshot_id"]?.string)
        defer { try? FileManager.default.removeItem(at: snapshotStoreURL(id)) }
        let reviews = Reviews()
        let host = try await openedProject(sample, policy: .review { c in reviews.changes.append(c); return reviews.accept })
        try writeFixture(sample, "FixtureApp/App.swift", "import Foundation\n\n// edited\n")
        let rejected = try await host.server.callTool("project_restore", ["snapshot_id": .string(id)])
        #expect(rejected.isToolError && rejected.firstText == MCPServer.rejectedMessage)
        #expect(read(sample, "FixtureApp/App.swift").contains("edited"))
        #expect(reviews.changes.first?.tool == "project_restore")
    }
}
