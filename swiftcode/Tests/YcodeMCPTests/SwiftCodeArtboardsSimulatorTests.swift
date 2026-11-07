import Foundation
import Testing
import YcodeAssistant
@testable import YcodeMCP

@MainActor
@Suite(.serialized) struct SwiftCodeArtboardsSimulatorTests {
    static let artboardIDs = ["artboard_compile", "artboard_create", "artboard_delete", "artboard_get",
                              "artboard_list", "artboard_run_app", "artboard_update", "fix_artboards"]
    static let simulatorIDs = ["device_list", "simulator_controller"]

    func opened(policy: MCPWritePolicy = .allow) async throws -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        host.server.writePolicy = policy
        let ported = Set(host.artboardTools.map(\.name) + host.simulatorTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.artboardTools + host.simulatorTools
        return host
    }

    @Test func toolsAreRegisteredWithLegacySchemas() async throws {
        let host = SwiftCodeMCPHost()
        let artboards = host.artboardTools
        #expect(artboards.map(\.name) == Self.artboardIDs)
        let sims = host.simulatorTools
        #expect(sims.map(\.name) == Self.simulatorIDs)
        #expect(host.server.tools.filter { $0.name == "simulator_boot" }.count == 1)
        #expect(host.server.tools.filter { $0.name == "simulator_list" }.count == 1)
        let expectedTitles: [String: String] = [
            "artboard_compile": "Compile Artboard Preview", "artboard_create": "Create Artboard",
            "artboard_delete": "Delete Artboard", "artboard_get": "Get Artboard Details",
            "artboard_list": "List Artboards", "artboard_run_app": "Run Full App",
            "artboard_update": "Update Artboard", "fix_artboards": "Fix Artboards and Visual UI Builder Errors",
            "device_list": "List Devices", "simulator_controller": "Simulator Controller",
        ]
        let expectedRequired: [String: [String]] = [
            "artboard_compile": [], "artboard_create": ["name"], "artboard_delete": ["identifier"],
            "artboard_get": [], "artboard_list": [], "artboard_run_app": [], "artboard_update": [],
            "fix_artboards": [], "device_list": [], "simulator_controller": ["action"],
        ]
        let expectedOutputs: [String: [String]] = [
            "artboard_compile": ["preview_target", "status"],
            "artboard_create": ["deviceFrame", "id", "name"],
            "artboard_delete": ["id", "name"],
            "artboard_get": ["deviceFrame", "hasCustomSource", "id", "name"],
            "artboard_list": ["active_artboard_id", "artboard_count", "artboards"],
            "artboard_run_app": ["output", "runId", "state"],
            "artboard_update": ["id", "name"],
            "fix_artboards": ["actions_count", "repaired"],
            "device_list": ["device_count", "devices", "source"],
            "simulator_controller": ["action", "device", "output"],
        ]
        let readOnlyIDs: Set<String> = ["artboard_get", "artboard_list", "device_list"]
        for tool in artboards + sims {
            #expect(tool.title == expectedTitles[tool.name])
            #expect(tool.inputSchema["properties"]?["workspace"] != nil, "\(tool.name) is missing the workspace parameter")
            let required = tool.inputSchema["required"]?.array?.compactMap(\.string) ?? []
            #expect(required == expectedRequired[tool.name], "\(tool.name) required: \(required)")
            let outputKeys = tool.outputSchema?["properties"]?.object?.keys.sorted() ?? []
            #expect(outputKeys == expectedOutputs[tool.name], "\(tool.name) output keys: \(outputKeys)")
            if readOnlyIDs.contains(tool.name) {
                #expect(tool.annotations.readOnly && tool.annotations.idempotent && !tool.writes,
                        "\(tool.name) must be a read-only tool")
            } else {
                #expect(!tool.annotations.readOnly && tool.annotations.idempotent && tool.writes,
                        "\(tool.name) must be a safeMutation write tool")
            }
        }
    }

    @Test func alignedSimulatorToolsKeepTheirSwiftCodeShape() async throws {
        let host = SwiftCodeMCPHost()
        let boot = try #require(host.server.tools.first { $0.name == "simulator_boot" })
        let list = try #require(host.server.tools.first { $0.name == "simulator_list" })
        let bootProps = boot.inputSchema["properties"]?.object?.keys.sorted() ?? []
        #expect(bootProps == ["action", "simulator", "udid"], "simulator_boot inputs: \(bootProps)")
        #expect(boot.inputSchema["required"]?.array?.compactMap(\.string) ?? [] == [])
        let listOutputs = list.outputSchema?["properties"]?.object?.keys.sorted() ?? []
        #expect(listOutputs == ["appleSimulators", "configured", "simulators"], "simulator_list outputs: \(listOutputs)")
        #expect(boot.writes && !boot.annotations.readOnly)
        #expect(!list.writes && list.annotations.readOnly)
    }

    @Test func artboardListStartsEmpty() async throws {
        let host = try await opened()
        let r = try await host.server.callTool("artboard_list")
        #expect(!r.isToolError)
        #expect(r.firstText == "No artboards currently configured in workspace.")
        #expect(r.structured?["artboard_count"]?.int == 0)
        #expect(r.structured?["artboards"]?.array == [])
    }

    @Test func artboardCreateRequiresAName() async throws {
        let host = try await opened()
        let missing = try await host.server.callTool("artboard_create")
        #expect(missing.isToolError)
        let blank = try await host.server.callTool("artboard_create", ["name": .string("   ")])
        #expect(blank.isToolError && blank.firstText.contains("Parameter 'name' is required."))
    }

    @Test func artboardCreateListGetRoundTrip() async throws {
        let host = try await opened()
        let created = try await host.server.callTool("artboard_create", ["name": .string("SettingsView")])
        #expect(!created.isToolError, "\(created.resultText)")
        #expect(created.firstText.contains("Successfully created artboard 'SettingsView'"))
        #expect(created.firstText.contains("with frame 'iPhone 16 Pro'"))
        #expect(created.structured?["name"]?.string == "SettingsView")
        #expect(created.structured?["deviceFrame"]?.string == "iPhone 16 Pro")
        let id = try #require(created.structured?["id"]?.string)
        #expect(UUID(uuidString: id) != nil)

        let list = try await host.server.callTool("artboard_list")
        #expect(list.firstText.contains("Found 1 artboard(s):"))
        #expect(list.firstText.contains("\"SettingsView\""))
        #expect(list.firstText.contains("[ACTIVE]"))
        #expect(list.firstText.contains("Device Frame: iPhone 16 Pro"))
        #expect(list.firstText.contains("Mode: component tree (Root: vStack, Children: 0)"))
        #expect(list.structured?["artboard_count"]?.int == 1)
        #expect(list.structured?["active_artboard_id"] == .string(id))

        let got = try await host.server.callTool("artboard_get", ["identifier": .string("SettingsView")])
        #expect(!got.isToolError, "\(got.resultText)")
        #expect(got.firstText.contains("Artboard: SettingsView"))
        #expect(got.firstText.contains("  ID: \(id)"))
        #expect(got.firstText.contains("  Appearance: System"))
        #expect(got.firstText.contains("  Orientation: Portrait"))
        #expect(got.firstText.contains("  Dynamic Type: Medium"))
        #expect(got.firstText.contains("  Scale: 1.0"))
        #expect(got.firstText.contains("  Safe Areas: Visible"))
        #expect(got.firstText.contains("Component Hierarchy:"))
        #expect(got.firstText.contains("- [vStack] SettingsView Root"))
        #expect(got.structured?["hasCustomSource"]?.bool == false)
    }

    @Test func artboardCreateWithSourceAndOptions() async throws {
        let host = try await opened()
        let source = "import SwiftUI\n\nstruct ProfileCanvas: View {\n    var body: some View { Text(\"Hi\") }\n}\n\n#Preview { ProfileCanvas() }\n"
        let created = try await host.server.callTool("artboard_create", [
            "name": .string("ProfileCanvas"), "deviceFrame": .string("iPad Pro"),
            "sourceCode": .string(source), "appearance": .string("Dark"), "isPortrait": .bool(false),
        ])
        #expect(!created.isToolError, "\(created.resultText)")
        let got = try await host.server.callTool("artboard_get")
        #expect(got.firstText.contains("  Device Frame: iPad Pro"))
        #expect(got.firstText.contains("  Appearance: Dark"))
        #expect(got.firstText.contains("  Orientation: Landscape"))
        #expect(got.firstText.contains("Custom SwiftUI Source Code:"))
        #expect(got.firstText.contains("struct ProfileCanvas: View"))
        #expect(got.structured?["hasCustomSource"]?.bool == true)
    }

    @Test func artboardGetAndDeleteUnknown() async throws {
        let host = try await opened()
        let get = try await host.server.callTool("artboard_get", ["identifier": .string("Nope")])
        #expect(get.isToolError && get.firstText.contains("Artboard matching 'Nope' not found."))
        let del = try await host.server.callTool("artboard_delete", ["identifier": .string("Nope")])
        #expect(del.isToolError && del.firstText.contains("No artboards currently configured in workspace."))
        _ = try await host.server.callTool("artboard_create", ["name": .string("One")])
        let del2 = try await host.server.callTool("artboard_delete", ["identifier": .string("Nope")])
        #expect(del2.isToolError && del2.firstText.contains("No artboard found matching 'Nope'."))
    }

    @Test func artboardUpdateRoundTrip() async throws {
        let host = try await opened()
        _ = try await host.server.callTool("artboard_create", ["name": .string("Old")])
        let updated = try await host.server.callTool("artboard_update", [
            "name": .string("New"), "deviceFrame": .string("iPhone 16 Pro Max"),
            "appearance": .string("Light"), "isPortrait": .bool(false),
        ])
        #expect(!updated.isToolError, "\(updated.resultText)")
        #expect(updated.firstText.contains("Updated artboard 'New':"))
        #expect(updated.firstText.contains("name: 'New'"))
        #expect(updated.firstText.contains("deviceFrame: 'iPhone 16 Pro Max'"))
        #expect(updated.firstText.contains("appearance: 'Light'"))
        #expect(updated.firstText.contains("isPortrait: false"))
        #expect(updated.structured?["name"]?.string == "New")
        let got = try await host.server.callTool("artboard_get", ["identifier": .string("New")])
        #expect(got.firstText.contains("  Device Frame: iPhone 16 Pro Max"))
        #expect(got.firstText.contains("  Appearance: Light"))
        #expect(got.firstText.contains("  Orientation: Landscape"))
        let missing = try await host.server.callTool("artboard_update", ["identifier": .string("Ghost")])
        #expect(missing.isToolError && missing.firstText.contains("Artboard not found matching 'Ghost'."))
    }

    @Test func artboardDeleteMovesTheActivePointer() async throws {
        let host = try await opened()
        _ = try await host.server.callTool("artboard_create", ["name": .string("First")])
        let second = try await host.server.callTool("artboard_create", ["name": .string("Second")])
        let secondID = try #require(second.structured?["id"]?.string)
        let deleted = try await host.server.callTool("artboard_delete", ["identifier": .string(secondID)])
        #expect(!deleted.isToolError, "\(deleted.resultText)")
        #expect(deleted.firstText.contains("Artboard 'Second' (ID: \(secondID)) deleted successfully."))
        let list = try await host.server.callTool("artboard_list")
        #expect(list.structured?["artboard_count"]?.int == 1)
        #expect(list.firstText.contains("\"First\""))
        #expect(list.firstText.contains("[ACTIVE]"))
    }

    @Test func defaultArtboardCannotBeDeleted() async throws {
        let host = try await opened()
        _ = try await host.server.callTool("artboard_create", ["name": .string("Default")])
        let deleted = try await host.server.callTool("artboard_delete", ["identifier": .string("Default")])
        #expect(deleted.isToolError && deleted.firstText.contains("The 'Default' artboard cannot be deleted as it is the workspace canvas root."))
    }

    @Test func artboardCompileNeedsCustomSource() async throws {
        let host = try await opened()
        let none = try await host.server.callTool("artboard_compile")
        #expect(none.isToolError && none.firstText.contains("No artboards currently configured in workspace."))
        _ = try await host.server.callTool("artboard_create", ["name": .string("Plain")])
        let noSource = try await host.server.callTool("artboard_compile")
        #expect(noSource.isToolError)
        #expect(noSource.firstText.contains("has no custom SwiftUI source to compile"))
        #expect(noSource.firstText.contains("preview_render"))
    }

    @Test func artboardCompileFailsWithoutAPreview() async throws {
        let host = try await opened()
        let source = "import SwiftUI\n\nstruct NoPreview: View {\n    var body: some View { Text(\"Hi\") }\n}\n"
        _ = try await host.server.callTool("artboard_create", ["name": .string("NoPreview"), "sourceCode": .string(source)])
        let r = try await host.server.callTool("artboard_compile")
        #expect(r.isToolError)
        #expect(r.firstText.contains("Artboard preview compilation failed."))
        #expect(r.firstText.contains("declares no preview"))
        #expect(r.structured?["status"]?.string == "failed")
        let got = try await host.server.callTool("artboard_get")
        #expect(got.firstText.contains("  Compile Error:"))
    }

    @Test func fixArtboardsRepairsSource() async throws {
        let host = try await opened()
        let source = "struct Bare: View {\n    var body: some View { Text(\"Hi\") }\n}\n"
        _ = try await host.server.callTool("artboard_create", ["name": .string("Bare"), "sourceCode": .string(source)])
        let r = try await host.server.callTool("fix_artboards")
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Fix with Assist completed audit and repairs:"))
        #expect(r.firstText.contains("Injected missing 'import SwiftUI' header into artboard 'Bare'"))
        #expect(r.firstText.contains("Appended missing #Preview macro for 'Bare'"))
        #expect(r.firstText.contains("Recompiled artboard 'Bare' live preview session"))
        #expect(r.structured?["repaired"]?.bool == true)
        let got = try await host.server.callTool("artboard_get")
        #expect(got.firstText.contains("import SwiftUI"))
        #expect(got.firstText.contains("#Preview {"))
        #expect(got.firstText.contains("Bare()"))
    }

    @Test func fixArtboardsValidatesScopeAndNotesStaleBuilds() async throws {
        let host = try await opened()
        let bad = try await host.server.callTool("fix_artboards", ["scope": .string("everything")])
        #expect(bad.isToolError && bad.firstText.contains("Invalid scope: 'everything'. Expected 'preview', 'full_app', or 'all'."))
        let r = try await host.server.callTool("fix_artboards", ["errorContext": .string("build failed with exit code 70")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Stale-build clean skipped: SwiftCode has no DerivedData cache to clean"))
        #expect(r.firstText.contains("Result Status: Healthy / Resolved"))
    }

    @Test func artboardRunAppNeedsAWorkspace() async throws {
        let host = try await opened()
        let r = try await host.server.callTool("artboard_run_app")
        #expect(r.isToolError && r.firstText.contains("no workspace is open"))
    }

    @Test func readOnlyPolicyRefusesArtboardWrites() async throws {
        let host = try await opened(policy: .readOnly)
        let created = try await host.server.callTool("artboard_create", ["name": .string("Nope")])
        #expect(created.isToolError && created.firstText.contains("read-only"))
        let controlled = try await host.server.callTool("simulator_controller", ["action": .string("boot")])
        #expect(controlled.isToolError && controlled.firstText.contains("read-only"))
        let list = try await host.server.callTool("artboard_list")
        #expect(!list.isToolError)
    }

    @Test func alignedSimulatorListKeepsSwiftCodeKeys() async throws {
        let host = SwiftCodeMCPHost()
        let r = try await host.server.callTool("simulator_list")
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["configured"]?.bool == false)
        #expect(r.structured?["simulators"]?.array == [])
        #expect(r.structured?["appleSimulators"] != nil)
        #expect(r.firstText.contains("No SwiftCode Simulator host is set up."))
#if os(macOS)
#else
        #expect(r.structured?["appleSimulators"]?.array == [])
        #expect(r.firstText.contains("Apple simulators: unavailable (xcrun not found"))
#endif
    }

    @Test func alignedSimulatorBootValidatesBeforeBooting() async throws {
        let host = SwiftCodeMCPHost()
        host.server.writePolicy = .allow
        let noArg = try await host.server.callTool("simulator_boot")
        #expect(noArg.isToolError && noArg.firstText.contains("no SwiftCode Simulator host"))
        let badUdid = try await host.server.callTool("simulator_boot", ["udid": .string("not-a-uuid")])
        #expect(badUdid.isToolError && badUdid.firstText.contains("Invalid udid: 'not-a-uuid' is not a valid UUID."))
        let badAction = try await host.server.callTool("simulator_boot", [
            "udid": .string("00000000-0000-0000-0000-000000000000"), "action": .string("explode"),
        ])
        #expect(badAction.isToolError && badAction.firstText.contains("Invalid action: 'explode'. Expected boot or shutdown."))
        let actionOnly = try await host.server.callTool("simulator_boot", ["action": .string("shutdown")])
        #expect(actionOnly.isToolError && actionOnly.firstText.contains("Pass a udid to boot or shut down an Apple simulator"))
        let udid = try await host.server.callTool("simulator_boot", [
            "udid": .string("00000000-0000-0000-0000-000000000000"),
        ])
        #expect(udid.isToolError)
#if os(macOS)
#else
        #expect(udid.firstText.contains("xcrun not found at /usr/bin/xcrun"))
#endif
    }

    @Test func deviceListFailsClearlyWithoutXcrun() async throws {
        let host = try await opened()
        let r = try await host.server.callTool("device_list")
#if os(macOS)
        _ = r
        #expect(r.structured?["device_count"] != nil || r.isToolError)
#else
        #expect(r.isToolError && r.firstText.contains("xcrun not found at /usr/bin/xcrun"))
#endif
    }

    @Test func simulatorControllerValidatesActions() async throws {
        let host = try await opened()
        let missing = try await host.server.callTool("simulator_controller")
        #expect(missing.isToolError)
        let unknown = try await host.server.callTool("simulator_controller", ["action": .string("explode")])
        #expect(unknown.isToolError && unknown.firstText.contains("Unsupported action 'explode'. Supported: boot, shutdown, install, launch, openurl."))
        let install = try await host.server.callTool("simulator_controller", ["action": .string("install")])
        #expect(install.isToolError && install.firstText.contains("Action 'install' requires 'appPath'."))
        let launch = try await host.server.callTool("simulator_controller", ["action": .string("launch")])
        #expect(launch.isToolError && launch.firstText.contains("Action 'launch' requires 'bundleId'."))
        let openurl = try await host.server.callTool("simulator_controller", ["action": .string("openurl")])
        #expect(openurl.isToolError && openurl.firstText.contains("Action 'openurl' requires 'url'."))
    }

    @Test func simulatorControllerNeedsXcrunOnLinux() async throws {
        let host = try await opened()
        let r = try await host.server.callTool("simulator_controller", ["action": .string("boot"), "device": .string("booted")])
        #expect(r.isToolError)
#if os(macOS)
#else
        #expect(r.firstText.contains("xcrun not found at /usr/bin/xcrun"))
#endif
    }
}
