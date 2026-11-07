import Foundation
import Testing
import YcodeAssistant
@testable import YcodeMCP

@MainActor
@Suite(.serialized) struct SwiftCodeSigningToolsTests {
    static let sliceDIDs = ["code_signing_diagnose", "entitlements_diff", "entitlements_manager", "info_plist_audit",
                            "plist_editor", "project_entitlements", "project_info_plist", "project_signing",
                            "provisioning_check", "provisioning_profile_reader", "signing_certificate_inspector"]

    func opened(_ sample: TempSample, policy: MCPWritePolicy = .readOnly) async throws -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        host.server.writePolicy = policy
        let ported = Set(host.signingTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.signingTools
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.url.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    func writeFixture(_ sample: TempSample, _ rel: String, _ content: String) throws {
        let url = URL(fileURLWithPath: sample.path(rel))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
    }

    func writeFixtureData(_ sample: TempSample, _ rel: String, _ data: Data) throws {
        let url = URL(fileURLWithPath: sample.path(rel))
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    func exists(_ sample: TempSample, _ rel: String) -> Bool {
        FileManager.default.fileExists(atPath: sample.path(rel))
    }

    static let signingProjectText = """
    // !$*UTF8*$!
    {
    \tarchiveVersion = 1;
    \tclasses = {
    \t};
    \tobjectVersion = 77;
    \tobjects = {
    \t\tB10000000000000000000002 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = main.swift; sourceTree = "<group>"; };
    \t\tB10000000000000000000003 = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = SigningApp.app; sourceTree = BUILT_PRODUCTS_DIR; };
    \t\tB10000000000000000000004 = {isa = PBXGroup; children = (B10000000000000000000005, B10000000000000000000006); sourceTree = "<group>"; };
    \t\tB10000000000000000000005 = {isa = PBXGroup; children = (B10000000000000000000002); path = SigningApp; sourceTree = "<group>"; };
    \t\tB10000000000000000000006 = {isa = PBXGroup; children = (B10000000000000000000003); name = Products; sourceTree = "<group>"; };
    \t\tB10000000000000000000007 = {isa = PBXNativeTarget; buildConfigurationList = B10000000000000000000008; buildPhases = (); buildRules = (); dependencies = (); name = SigningApp; productName = SigningApp; productReference = B10000000000000000000003; productType = "com.apple.product-type.application"; };
    \t\tB10000000000000000000008 = {isa = XCConfigurationList; buildConfigurations = (B1000000000000000000000A, B1000000000000000000000B); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };
    \t\tB1000000000000000000000A = {isa = XCBuildConfiguration; buildSettings = {PRODUCT_NAME = "$(TARGET_NAME)"; PRODUCT_BUNDLE_IDENTIFIER = org.swiftcode.SigningApp; CODE_SIGN_STYLE = Automatic; DEVELOPMENT_TEAM = ABCDE12345; CODE_SIGN_IDENTITY = "Apple Development"; PROVISIONING_PROFILE_SPECIFIER = "SigningApp Dev"; }; name = Debug; };
    \t\tB1000000000000000000000B = {isa = XCBuildConfiguration; buildSettings = {PRODUCT_NAME = "$(TARGET_NAME)"; PRODUCT_BUNDLE_IDENTIFIER = org.swiftcode.SigningApp; CODE_SIGN_STYLE = Manual; DEVELOPMENT_TEAM = ABCDE12345; CODE_SIGN_IDENTITY = "Apple Distribution"; PROVISIONING_PROFILE_SPECIFIER = "SigningApp Dist"; }; name = Release; };
    \t\tB1000000000000000000000C = {isa = PBXProject; buildConfigurationList = B1000000000000000000000D; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = B10000000000000000000004; productRefGroup = B10000000000000000000006; preferredProjectObjectVersion = 77; projectDirPath = ""; projectRoot = ""; targets = (B10000000000000000000007); };
    \t\tB1000000000000000000000D = {isa = XCConfigurationList; buildConfigurations = (B1000000000000000000000E, B1000000000000000000000F); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };
    \t\tB1000000000000000000000E = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = macosx; }; name = Debug; };
    \t\tB1000000000000000000000F = {isa = XCBuildConfiguration; buildSettings = {SDKROOT = macosx; }; name = Release; };
    \t};
    \trootObject = B1000000000000000000000C;
    }
    """

    static let goodInfoPlist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
    \t<key>CFBundleIdentifier</key>
    \t<string>com.example.Greeter</string>
    \t<key>CFBundleName</key>
    \t<string>Greeter</string>
    \t<key>CFBundleShortVersionString</key>
    \t<string>1.0</string>
    \t<key>CFBundleVersion</key>
    \t<string>1</string>
    </dict>
    </plist>
    """

    static let badInfoPlist = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
    \t<key>CFBundleIdentifier</key>
    \t<string>com.example.Greeter</string>
    \t<key>CFBundleShortVersionString</key>
    \t<string>1.0-beta</string>
    \t<key>CFBundleVersion</key>
    \t<string>1</string>
    </dict>
    </plist>
    """

    static let oldEntitlements = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
    \t<key>com.apple.security.app-sandbox</key>
    \t<true/>
    \t<key>com.apple.security.network.client</key>
    \t<true/>
    \t<key>com.example.removed</key>
    \t<string>old</string>
    \t<key>com.example.changed</key>
    \t<string>before</string>
    </dict>
    </plist>
    """

    static let newEntitlements = """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
    \t<key>com.apple.security.app-sandbox</key>
    \t<true/>
    \t<key>com.apple.security.network.client</key>
    \t<true/>
    \t<key>com.example.added</key>
    \t<string>new</string>
    \t<key>com.example.changed</key>
    \t<string>after</string>
    </dict>
    </plist>
    """

    @Test func toolIDsAreRegisteredOnce() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        #expect(host.signingTools.map(\.name) == Self.sliceDIDs)
        for id in Self.sliceDIDs {
            #expect(host.server.tools.filter { $0.name == id }.count == 1, "\(id) must be registered exactly once")
        }
    }

    @Test func codeSigningDiagnoseRejectsMissingArgAndFile() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let noParam = try await host.server.callTool("code_signing_diagnose")
        #expect(noParam.isToolError)
        let missing = try await host.server.callTool("code_signing_diagnose", ["path": .string("Nope.app")])
        #expect(missing.isToolError && missing.firstText.contains("No file at path: Nope.app"))
        let outside = try await host.server.callTool("code_signing_diagnose", ["path": .string("../outside.app")])
        #expect(outside.isToolError && outside.firstText.contains("No file at path: ../outside.app"))
    }

    @Test func codeSigningDiagnoseFailsCleanlyWithoutCodesign() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        #if os(Linux)
        let r = try await host.server.callTool("code_signing_diagnose", ["path": .string("Sources/Greeter/Greeter.swift")])
        #expect(r.isToolError && r.firstText.contains("not available on this platform"))
        #else
        let r = try await host.server.callTool("code_signing_diagnose", ["path": .string("Sources/Greeter/Greeter.swift")])
        #expect(r.isToolError && r.firstText.contains("NOT SIGNED"))
        #expect(r.structured?["signed"]?.bool == false)
        #endif
    }

    @Test func entitlementsDiffReportsAddedRemovedChanged() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Old.entitlements", Self.oldEntitlements)
        try writeFixture(sample, "New.entitlements", Self.newEntitlements)
        let r = try await host.server.callTool("entitlements_diff",
                                               ["oldPath": .string("Old.entitlements"), "newPath": .string("New.entitlements")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["added"]?.int == 1 && r.structured?["removed"]?.int == 1 && r.structured?["changed"]?.int == 1)
        #expect(r.firstText.contains("- ADDED: com.example.added"))
        #expect(r.firstText.contains("- REMOVED: com.example.removed"))
        #expect(r.firstText.contains("- CHANGED: com.example.changed: 'before' -> 'after'"))
        let same = try await host.server.callTool("entitlements_diff",
                                                  ["oldPath": .string("Old.entitlements"), "newPath": .string("Old.entitlements")])
        #expect(!same.isToolError && same.firstText.contains("Entitlements are identical."))
        #expect(same.structured?["added"]?.int == 0 && same.structured?["removed"]?.int == 0 && same.structured?["changed"]?.int == 0)
        let missing = try await host.server.callTool("entitlements_diff",
                                                     ["oldPath": .string("Old.entitlements"), "newPath": .string("Nope.entitlements")])
        #expect(missing.isToolError && missing.firstText.contains("Cannot parse entitlements plist at: Nope.entitlements"))
        let noParam = try await host.server.callTool("entitlements_diff", ["oldPath": .string("Old.entitlements")])
        #expect(noParam.isToolError)
    }

    @Test func entitlementsManagerInspectAddRemove() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        try writeFixture(sample, "App.entitlements", Self.oldEntitlements)
        let inspect = try await host.server.callTool("entitlements_manager",
                                                     ["action": .string("inspect"), "filePath": .string("App.entitlements")])
        #expect(!inspect.isToolError, "\(inspect.resultText)")
        #expect(inspect.firstText.contains("Entitlements in 'App.entitlements' (4 configured):"))
        #expect(inspect.firstText.contains("- com.apple.security.app-sandbox: true"))
        let add = try await host.server.callTool("entitlements_manager",
                                                 ["action": .string("add_entitlement"), "filePath": .string("App.entitlements"),
                                                  "entitlementKey": .string("com.apple.security.network.server"), "value": .string("true")])
        #expect(!add.isToolError, "\(add.resultText)")
        #expect(add.firstText.contains("Successfully added entitlement 'com.apple.security.network.server' = true in App.entitlements"))
        #expect(sample.read("App.entitlements").contains("com.apple.security.network.server"))
        let remove = try await host.server.callTool("entitlements_manager",
                                                    ["action": .string("remove_entitlement"), "filePath": .string("App.entitlements"),
                                                     "entitlementKey": .string("com.example.removed")])
        #expect(!remove.isToolError, "\(remove.resultText)")
        #expect(remove.firstText.contains("Successfully removed entitlement 'com.example.removed' from App.entitlements"))
        #expect(!sample.read("App.entitlements").contains("com.example.removed"))
        let fresh = try await host.server.callTool("entitlements_manager",
                                                   ["action": .string("add_entitlement"), "filePath": .string("Fresh.entitlements"),
                                                    "entitlementKey": .string("com.apple.security.app-sandbox")])
        #expect(!fresh.isToolError, "\(fresh.resultText)")
        #expect(exists(sample, "Fresh.entitlements"))
        let noKey = try await host.server.callTool("entitlements_manager",
                                                   ["action": .string("add_entitlement"), "filePath": .string("App.entitlements")])
        #expect(noKey.isToolError && noKey.firstText.contains("entitlementKey is required for add_entitlement"))
        let missingKey = try await host.server.callTool("entitlements_manager",
                                                        ["action": .string("remove_entitlement"), "filePath": .string("App.entitlements"),
                                                         "entitlementKey": .string("com.example.absent")])
        #expect(missingKey.isToolError && missingKey.firstText.contains("Entitlement 'com.example.absent' not found in App.entitlements"))
        let badAction = try await host.server.callTool("entitlements_manager",
                                                       ["action": .string("prune"), "filePath": .string("App.entitlements")])
        #expect(badAction.isToolError && badAction.firstText.contains("Unsupported action 'prune'"))
        let missingFile = try await host.server.callTool("entitlements_manager",
                                                         ["action": .string("inspect"), "filePath": .string("Nope.entitlements")])
        #expect(missingFile.isToolError && missingFile.firstText.contains("Entitlements file not found at: Nope.entitlements"))
    }

    @Test func entitlementsManagerRefusedWhenReadOnlyAndRejected() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "App.entitlements", Self.oldEntitlements)
        let refused = try await host.server.callTool("entitlements_manager",
                                                     ["action": .string("add_entitlement"), "filePath": .string("App.entitlements"),
                                                      "entitlementKey": .string("com.apple.security.network.server")])
        #expect(refused.isToolError && refused.firstText == MCPServer.readOnlyMessage("entitlements_manager"))
        #expect(!sample.read("App.entitlements").contains("com.apple.security.network.server"))
        let reviewing = try await opened(sample, policy: .review { _ in false })
        let rejected = try await reviewing.server.callTool("entitlements_manager",
                                                          ["action": .string("add_entitlement"), "filePath": .string("App.entitlements"),
                                                           "entitlementKey": .string("com.apple.security.network.server")])
        #expect(rejected.isToolError && rejected.firstText == MCPServer.rejectedMessage)
        #expect(!sample.read("App.entitlements").contains("com.apple.security.network.server"),
                "a rejected change must write nothing")
    }

    @Test func infoPlistAuditFindsIssuesAndDuplicates() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let empty = try await host.server.callTool("info_plist_audit")
        #expect(!empty.isToolError, "\(empty.resultText)")
        #expect(empty.structured?["fileCount"]?.int == 0 && empty.structured?["issueCount"]?.int == 0)
        #expect(empty.firstText.contains("No Info.plist files found in the workspace."))
        try writeFixture(sample, "App/Info.plist", Self.goodInfoPlist)
        try writeFixture(sample, "Other/Info.plist", Self.badInfoPlist)
        let r = try await host.server.callTool("info_plist_audit")
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["fileCount"]?.int == 2)
        #expect(r.structured?["issueCount"]?.int == 3)
        #expect(r.firstText.contains("- App/Info.plist: OK"))
        #expect(r.firstText.contains("- Other/Info.plist: missing CFBundleName; CFBundleShortVersionString '1.0-beta' is not x.y[.z]"))
        #expect(r.firstText.contains("DUPLICATE bundle id 'com.example.Greeter' in: App/Info.plist, Other/Info.plist"))
    }

    @Test func plistEditorReadSetDeleteTyped() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        try writeFixture(sample, "Config.plist", Self.goodInfoPlist)
        let list = try await host.server.callTool("plist_editor",
                                                  ["action": .string("list_keys"), "filePath": .string("Config.plist")])
        #expect(!list.isToolError, "\(list.resultText)")
        #expect(list.firstText.contains("Plist contains 4 keys:"))
        #expect(list.firstText.contains("CFBundleIdentifier"))
        let read = try await host.server.callTool("plist_editor",
                                                  ["action": .string("read"), "filePath": .string("Config.plist"),
                                                   "key": .string("CFBundleName")])
        #expect(!read.isToolError && read.firstText.contains("CFBundleName = Greeter"))
        let setString = try await host.server.callTool("plist_editor",
                                                       ["action": .string("set"), "filePath": .string("Config.plist"),
                                                        "key": .string("CFBundleName"), "value": .string("Greeter2")])
        #expect(!setString.isToolError, "\(setString.resultText)")
        #expect(setString.firstText.contains("Successfully set 'CFBundleName' = Greeter2 in Config.plist"))
        let setBool = try await host.server.callTool("plist_editor",
                                                     ["action": .string("set"), "filePath": .string("Config.plist"),
                                                      "key": .string("CFBundleAllowMixedLocalizations"), "value": .string("true"),
                                                      "valueType": .string("boolean")])
        #expect(!setBool.isToolError, "\(setBool.resultText)")
        let setInt = try await host.server.callTool("plist_editor",
                                                    ["action": .string("set"), "filePath": .string("Config.plist"),
                                                     "key": .string("CFBundleVersion"), "value": .string("7"),
                                                     "valueType": .string("integer")])
        #expect(!setInt.isToolError, "\(setInt.resultText)")
        let after = try await host.server.callTool("plist_editor",
                                                   ["action": .string("read"), "filePath": .string("Config.plist"),
                                                    "key": .string("CFBundleVersion")])
        #expect(!after.isToolError && after.firstText.contains("CFBundleVersion = 7"))
        let delete = try await host.server.callTool("plist_editor",
                                                    ["action": .string("delete"), "filePath": .string("Config.plist"),
                                                     "key": .string("CFBundleName")])
        #expect(!delete.isToolError, "\(delete.resultText)")
        #expect(delete.firstText.contains("Successfully removed key 'CFBundleName' from Config.plist"))
        let gone = try await host.server.callTool("plist_editor",
                                                  ["action": .string("read"), "filePath": .string("Config.plist"),
                                                   "key": .string("CFBundleName")])
        #expect(gone.isToolError && gone.firstText.contains("Key 'CFBundleName' not found in Config.plist"))
        let noKey = try await host.server.callTool("plist_editor",
                                                   ["action": .string("read"), "filePath": .string("Config.plist")])
        #expect(noKey.isToolError && noKey.firstText.contains("key parameter is required for read"))
        let badAction = try await host.server.callTool("plist_editor",
                                                       ["action": .string("get"), "filePath": .string("Config.plist"),
                                                        "key": .string("CFBundleName")])
        #expect(badAction.isToolError && badAction.firstText.contains("Unsupported action 'get'"))
        let missing = try await host.server.callTool("plist_editor",
                                                     ["action": .string("read"), "filePath": .string("Nope.plist"),
                                                      "key": .string("CFBundleName")])
        #expect(missing.isToolError && missing.firstText.contains("Plist file does not exist at path: Nope.plist"))
    }

    @Test func plistEditorPreservesBinaryFormat() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let binary = try PropertyListSerialization.data(fromPropertyList: ["CFBundleName": "Greeter", "Answer": 42],
                                                        format: .binary, options: 0)
        try writeFixtureData(sample, "Binary.plist", binary)
        let set = try await host.server.callTool("plist_editor",
                                                 ["action": .string("set"), "filePath": .string("Binary.plist"),
                                                  "key": .string("Answer"), "value": .string("43"),
                                                  "valueType": .string("integer")])
        #expect(!set.isToolError, "\(set.resultText)")
        let data = try Data(contentsOf: URL(fileURLWithPath: sample.path("Binary.plist")))
        var format = PropertyListSerialization.PropertyListFormat.xml
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: &format) as? [String: Any]
        #expect(format == .binary, "a binary source stays binary after set")
        #expect(plist?["Answer"] as? Int == 43)
        #expect(plist?["CFBundleName"] as? String == "Greeter")
    }

    @Test func plistEditorRefusedWhenReadOnlyAndRejected() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Config.plist", Self.goodInfoPlist)
        let refused = try await host.server.callTool("plist_editor",
                                                     ["action": .string("set"), "filePath": .string("Config.plist"),
                                                      "key": .string("CFBundleName"), "value": .string("Changed")])
        #expect(refused.isToolError && refused.firstText == MCPServer.readOnlyMessage("plist_editor"))
        #expect(sample.read("Config.plist").contains("Greeter"))
        let reviewing = try await opened(sample, policy: .review { _ in false })
        let rejected = try await reviewing.server.callTool("plist_editor",
                                                          ["action": .string("set"), "filePath": .string("Config.plist"),
                                                           "key": .string("CFBundleName"), "value": .string("Changed")])
        #expect(rejected.isToolError && rejected.firstText == MCPServer.rejectedMessage)
        #expect(!sample.read("Config.plist").contains("Changed"), "a rejected change must write nothing")
    }

    @Test func plistEditorIsDistinctFromPlistEdit() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        #expect(host.server.tools.filter { $0.name == "plist_edit" }.count == 1, "plist_edit stays registered exactly once")
        #expect(host.server.tools.filter { $0.name == "plist_editor" }.count == 1, "plist_editor is a separate registration")
        try writeFixture(sample, "Config.plist", Self.goodInfoPlist)
        let wrongParams = try await host.server.callTool("plist_editor",
                                                         ["path": .string("Config.plist"), "action": .string("get"),
                                                          "key": .string("CFBundleName")])
        #expect(wrongParams.isToolError)
        let listKeys = try await host.server.callTool("plist_editor",
                                                      ["action": .string("list_keys"), "filePath": .string("Config.plist")])
        #expect(!listKeys.isToolError && listKeys.firstText.contains("Plist contains 4 keys:"))
        let editListKeys = try await host.server.callTool("plist_edit",
                                                          ["path": .string("Config.plist"), "action": .string("list_keys"),
                                                           "key": .string("CFBundleName")])
        #expect(editListKeys.isToolError && editListKeys.firstText.contains("Invalid action 'list_keys'"))
    }

    @Test func projectEntitlementsScansAndExplicitPath() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let none = try await host.server.callTool("project_entitlements")
        #expect(none.isToolError && none.firstText.contains("No .entitlements files found in the workspace."))
        try writeFixture(sample, "App.entitlements", Self.oldEntitlements)
        let r = try await host.server.callTool("project_entitlements")
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["files"]?.string == "App.entitlements" && r.structured?["count"]?.int == 4)
        #expect(r.structured?["keys"]?.string == "com.apple.security.app-sandbox,com.apple.security.network.client,com.example.changed,com.example.removed")
        #expect(r.firstText.contains("App.entitlements: com.apple.security.app-sandbox = true; com.apple.security.network.client = true;"))
        let explicit = try await host.server.callTool("project_entitlements", ["path": .string("App.entitlements")])
        #expect(!explicit.isToolError && explicit.structured?["count"]?.int == 4)
        let missing = try await host.server.callTool("project_entitlements", ["path": .string("Nope.entitlements")])
        #expect(missing.isToolError && missing.firstText.contains("Entitlements file not found at 'Nope.entitlements'."))
        let outside = try await host.server.callTool("project_entitlements", ["path": .string("../App.entitlements")])
        #expect(outside.isToolError && outside.firstText.contains("is outside the workspace or contains '..'"))
    }

    @Test func projectInfoPlistGetSetDelete() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let none = try await host.server.callTool("project_info_plist", ["action": .string("get")])
        #expect(none.isToolError && none.firstText.contains("No Info.plist found in the workspace."))
        try writeFixture(sample, "App/Info.plist", Self.goodInfoPlist)
        let get = try await host.server.callTool("project_info_plist", ["action": .string("get"), "key": .string("CFBundleName")])
        #expect(!get.isToolError, "\(get.resultText)")
        #expect(get.structured?["key"]?.string == "CFBundleName" && get.structured?["value"]?.string == "Greeter")
        #expect(get.structured?["file"]?.string == "Info.plist")
        #expect(get.firstText.contains("Info.plist CFBundleName = Greeter"))
        let all = try await host.server.callTool("project_info_plist", ["action": .string("get")])
        #expect(!all.isToolError && all.structured?["count"]?.int == 4)
        #expect(all.firstText.contains("Info.plist has 4 key(s):"))
        let set = try await host.server.callTool("project_info_plist",
                                                 ["action": .string("set"), "key": .string("CFBundleVersion"), "value": .string("2")])
        #expect(!set.isToolError, "\(set.resultText)")
        #expect(set.firstText.contains("Set Info.plist CFBundleVersion = 2 (was: 1)."))
        #expect(sample.read("App/Info.plist").contains("<integer>2</integer>"))
        let setBool = try await host.server.callTool("project_info_plist",
                                                     ["action": .string("set"), "key": .string("CFBundleAllowMixedLocalizations"),
                                                      "value": .string("true")])
        #expect(!setBool.isToolError, "\(setBool.resultText)")
        #expect(sample.read("App/Info.plist").contains("<true/>"))
        let delete = try await host.server.callTool("project_info_plist",
                                                    ["action": .string("delete"), "key": .string("CFBundleName")])
        #expect(!delete.isToolError, "\(delete.resultText)")
        #expect(delete.firstText.contains("Deleted Info.plist key 'CFBundleName'."))
        #expect(!sample.read("App/Info.plist").contains("CFBundleName"))
        let noValue = try await host.server.callTool("project_info_plist",
                                                     ["action": .string("set"), "key": .string("CFBundleVersion")])
        #expect(noValue.isToolError && noValue.firstText.contains("Missing required parameter: value for action=set"))
        let badAction = try await host.server.callTool("project_info_plist", ["action": .string("read")])
        #expect(badAction.isToolError && badAction.firstText.contains("Invalid action 'read'"))
        let absent = try await host.server.callTool("project_info_plist",
                                                    ["action": .string("get"), "key": .string("CFBundleAbsent")])
        #expect(absent.isToolError && absent.firstText.contains("Key 'CFBundleAbsent' not found in Info.plist."))
    }

    @Test func projectInfoPlistGetRefusedWhenReadOnlyAndRejected() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "App/Info.plist", Self.goodInfoPlist)
        let refused = try await host.server.callTool("project_info_plist", ["action": .string("get"), "key": .string("CFBundleName")])
        #expect(refused.isToolError && refused.firstText == MCPServer.readOnlyMessage("project_info_plist"))
        let reviewing = try await opened(sample, policy: .review { _ in false })
        let rejected = try await reviewing.server.callTool("project_info_plist",
                                                          ["action": .string("set"), "key": .string("CFBundleVersion"),
                                                           "value": .string("9")])
        #expect(rejected.isToolError && rejected.firstText == MCPServer.rejectedMessage)
        #expect(sample.read("App/Info.plist").contains("<string>1</string>"),
                "a rejected change must write nothing")
    }

    @Test func projectSigningFromPbxproj() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let noProject = try await host.server.callTool("project_signing")
        #expect(noProject.isToolError && noProject.firstText.contains("No .xcodeproj or .xcworkspace found at the top level of the workspace."))
        try writeFixture(sample, "Fake.xcodeproj/project.pbxproj", Self.signingProjectText)
        let open = try await host.server.callTool("workspace_open", ["path": .string(sample.path("Fake.xcodeproj"))])
        #expect(!open.isToolError, "\(open.resultText)")
        let debug = try await host.server.callTool("project_signing")
        #expect(!debug.isToolError, "\(debug.resultText)")
        #expect(debug.structured?["configuration"]?.string == "Debug")
        #expect(debug.structured?["codeSignStyle"]?.string == "Automatic")
        #expect(debug.structured?["developmentTeam"]?.string == "ABCDE12345")
        #expect(debug.structured?["bundleId"]?.string == "org.swiftcode.SigningApp")
        #expect(debug.structured?["codeSignIdentity"]?.string == "Apple Development")
        #expect(debug.structured?["provisioningProfileSpecifier"]?.string == "SigningApp Dev")
        #expect(debug.structured?["provisioningProfileCount"]?.int == 0)
        #expect(debug.firstText.contains("CODE_SIGN_STYLE = Automatic"))
        #expect(debug.firstText.contains("Provisioning profiles installed: 0"))
        let release = try await host.server.callTool("project_signing", ["configuration": .string("Release")])
        #expect(!release.isToolError, "\(release.resultText)")
        #expect(release.structured?["codeSignStyle"]?.string == "Manual")
        #expect(release.structured?["codeSignIdentity"]?.string == "Apple Distribution")
        let bogus = try await host.server.callTool("project_signing", ["configuration": .string("Bogus")])
        #expect(!bogus.isToolError, "\(bogus.resultText)")
        #expect(bogus.structured?["codeSignStyle"]?.string == "Manual")
        let byScheme = try await host.server.callTool("project_signing", ["scheme": .string("SigningApp")])
        #expect(!byScheme.isToolError && byScheme.structured?["scheme"]?.string == "SigningApp")
        #expect(byScheme.structured?["codeSignStyle"]?.string == "Automatic")
    }

    @Test func provisioningCheckFailsCleanlyWithoutSecurity() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("provisioning_check")
        #if os(Linux)
        #expect(r.isToolError && r.firstText.contains("security tool not found at /usr/bin/security."))
        #else
        if r.isToolError {
            #expect(r.firstText.contains("Provisioning Profiles") || r.firstText.contains("security tool not found"))
        } else {
            #expect(r.firstText.contains("Provisioning profiles:"))
        }
        #endif
    }

    @Test func provisioningProfileReaderRejectsMissingAndUndecodable() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let noParam = try await host.server.callTool("provisioning_profile_reader")
        #expect(noParam.isToolError)
        let missing = try await host.server.callTool("provisioning_profile_reader", ["path": .string("Nope.mobileprovision")])
        #expect(missing.isToolError && missing.firstText.contains("Provisioning profile not found at: Nope.mobileprovision"))
        try writeFixture(sample, "Fake.mobileprovision", "this is not a provisioning profile\n")
        let fake = try await host.server.callTool("provisioning_profile_reader", ["path": .string("Fake.mobileprovision")])
        #expect(fake.isToolError)
        #if os(Linux)
        #expect(fake.firstText.contains("Failed to execute security cms -D"))
        #else
        #expect(fake.firstText.contains("Failed to decode XML property list from provisioning profile."))
        #endif
    }

    @Test func signingCertificateInspectorReportsRealKeychainState() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("signing_certificate_inspector")
        #if os(Linux)
        #expect(r.isToolError && r.firstText.contains("Failed to execute security find-identity"))
        #else
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Available Code Signing Certificates:") || r.firstText.contains("No valid code-signing identities found"))
        #endif
    }

    @Test func outOfScopePathsAreRefused() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let diff = try await host.server.callTool("entitlements_diff",
                                                  ["oldPath": .string("../Old.entitlements"), "newPath": .string("../New.entitlements")])
        #expect(diff.isToolError && diff.firstText.contains("Cannot parse entitlements plist at: ../Old.entitlements"))
        let editor = try await host.server.callTool("plist_editor",
                                                    ["action": .string("list_keys"), "filePath": .string("../Config.plist")])
        #expect(editor.isToolError && editor.firstText.contains("Plist file does not exist at path: ../Config.plist"))
        let info = try await host.server.callTool("project_info_plist",
                                                  ["action": .string("get"), "path": .string("../Info.plist")])
        #expect(info.isToolError && info.firstText.contains("is outside the workspace or contains '..'"))
    }
}
