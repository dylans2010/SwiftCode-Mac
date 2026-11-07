import Foundation
import Testing
@testable import YcodeBuild

struct AssetCompilerHookTests {
    func tool() throws -> (dir: URL, tool: String) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-hook-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let t = dir.appendingPathComponent("swiftcode")
        try Data("#!/bin/sh\n".utf8).write(to: t)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: t.path)
        return (dir, t.path)
    }

    @Test func defaultsPerPlatformAndSettingsWin() {
        #if os(macOS)
        #expect(AssetCompilerHook.choice(settings: [], environment: [:]) == .actool)
        #else
        #expect(AssetCompilerHook.choice(settings: [], environment: [:]) == .swiftcode)
        #endif
        #expect(AssetCompilerHook.choice(settings: [], environment: ["SWIFTCODE_ASSET_COMPILER": "swiftcode"]) == .swiftcode)
        #expect(AssetCompilerHook.choice(settings: [("SWIFTCODE_ASSET_COMPILER", "actool")], environment: ["SWIFTCODE_ASSET_COMPILER": "swiftcode"]) == .actool)
        #expect(AssetCompilerHook.choice(settings: [("SWIFTCODE_ASSET_COMPILER", "actool"), ("SWIFTCODE_ASSET_COMPILER", "swiftcode")], environment: [:]) == .swiftcode)
    }

    @Test func writesAWrapperAndTheOverride() throws {
        let (dir, swiftcode) = try tool()
        defer { try? FileManager.default.removeItem(at: dir) }
        let o = AssetCompilerHook.overrides(settings: [("SWIFTCODE_ASSET_COMPILER", "swiftcode"), ("SWIFTCODE_ASSETS_TOOL", swiftcode)],
                                            directory: dir.appendingPathComponent("w"), environment: [:])
        let wrapper = dir.appendingPathComponent("w/actool").path
        #expect(o.map(\.0) == ["ASSETCATALOG_EXEC"] && o.map(\.1) == [wrapper])
        #expect(FileManager.default.isExecutableFile(atPath: wrapper))
        let text = try String(contentsOfFile: wrapper, encoding: .utf8)
        #expect(text.hasPrefix("#!/bin/sh\n") && text.hasSuffix("exec '\(swiftcode)' assets compile \"$@\"\n"))
        #expect(AssetCompilerHook.wrapperScript(swiftcode: "/a/it's").contains("exec '/a/it'\\''s' assets compile"))
    }

    @Test func leavesActoolAndExplicitSettingsAlone() throws {
        let (dir, swiftcode) = try tool()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(AssetCompilerHook.overrides(settings: [("SWIFTCODE_ASSET_COMPILER", "actool"), ("SWIFTCODE_ASSETS_TOOL", swiftcode)], directory: dir, environment: [:]).isEmpty)
        #expect(AssetCompilerHook.overrides(settings: [("SWIFTCODE_ASSET_COMPILER", "swiftcode"), ("SWIFTCODE_ASSETS_TOOL", swiftcode), ("ASSETCATALOG_EXEC", "/x/actool")],
                                            directory: dir, environment: [:]).isEmpty)
        #expect(AssetCompilerHook.overrides(settings: [("SWIFTCODE_ASSET_COMPILER", "swiftcode"), ("SWIFTCODE_ASSETS_TOOL", "/no/such/swiftcode")], directory: dir, environment: [:]).isEmpty)
    }

    @Test func swiftBuildRequestsCarryTheOverride() throws {
        let (dir, swiftcode) = try tool()
        defer { try? FileManager.default.removeItem(at: dir) }
        let pkg = dir.appendingPathComponent("pkg")
        var request = BuildRequest(container: .project(pkg.appendingPathComponent("App.xcodeproj").path))
        request.settings = [("SWIFTCODE_ASSET_COMPILER", "swiftcode"), ("SWIFTCODE_ASSETS_TOOL", swiftcode)]
        request.derivedDataPath = dir.appendingPathComponent("dd").path
        let inv = try SwiftBuildEngine.invocation(for: request, pifPath: dir.appendingPathComponent("p.json"),
                                                  parametersPath: dir.appendingPathComponent("b.json"), source: StubPIF())
        let params = try JSONSerialization.jsonObject(with: inv.parameters) as? [String: Any]
        let table = ((params?["overrides"] as? [String: Any])?["commandLine"] as? [String: Any])?["table"] as? [String: String]
        #expect(table?["ASSETCATALOG_EXEC"] == dir.appendingPathComponent("dd/SwiftCodeAssetCompiler/actool").path)
    }

    struct StubPIF: PIFSource {
        func pif(for request: BuildRequest) throws -> (data: Data, targets: [String]) { (Data("[]".utf8), ["App"]) }
    }
}
