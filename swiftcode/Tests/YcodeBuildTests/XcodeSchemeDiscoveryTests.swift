import Foundation
import Testing
@testable import YcodeBuild

@Suite struct XcodeSchemeDiscoveryTests {
    struct StubRunner: XcodebuildListRunner {
        var json: Data?
        func listJSON(containerArgs: [String], workingDirectory: URL) async -> Data? { json }
    }

    static let minimalScheme = """
    <?xml version="1.0" encoding="UTF-8"?>
    <Scheme version="1.7"></Scheme>
    """

    static func makeProject(at root: URL, name: String, schemes: [String]) throws -> URL {
        let proj = root.appendingPathComponent("\(name).xcodeproj", isDirectory: true)
        let dir = proj.appendingPathComponent("xcshareddata/xcschemes", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for scheme in schemes {
            try minimalScheme.write(to: dir.appendingPathComponent("\(scheme).xcscheme"), atomically: true, encoding: .utf8)
        }
        return proj
    }

    static func makeWorkspace(at root: URL, name: String, schemes: [String]) throws -> URL {
        let ws = root.appendingPathComponent("\(name).xcworkspace", isDirectory: true)
        let dir = ws.appendingPathComponent("xcshareddata/xcschemes", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for scheme in schemes {
            try minimalScheme.write(to: dir.appendingPathComponent("\(scheme).xcscheme"), atomically: true, encoding: .utf8)
        }
        return ws
    }

    static func tmpRoot() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("XcodeSchemeDiscoveryTests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func parseListJSONProjectShape() {
        let data = """
        {"project": {"name": "App", "targets": ["App"], "configurations": ["Debug"], "schemes": ["App", "AppTests"]}}
        """.data(using: .utf8)!
        #expect(XcodeSchemeDiscovery.parseListJSON(data) == ["App", "AppTests"])
    }

    @Test func parseListJSONWorkspaceShape() {
        let data = """
        {"workspace": {"name": "App", "schemes": ["Shared"]}}
        """.data(using: .utf8)!
        #expect(XcodeSchemeDiscovery.parseListJSON(data) == ["Shared"])
    }

    @Test func parseListJSONMalformedYieldsNothing() {
        #expect(XcodeSchemeDiscovery.parseListJSON("not json".data(using: .utf8)!) == [])
        #expect(XcodeSchemeDiscovery.parseListJSON("{}".data(using: .utf8)!) == [])
        #expect(XcodeSchemeDiscovery.parseListJSON("{\"project\": {}}".data(using: .utf8)!) == [])
    }

    @Test func listSchemesFromProjectFiles() throws {
        let root = Self.tmpRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let proj = try Self.makeProject(at: root, name: "App", schemes: ["App", "AppTests"])
        let discovery = XcodeSchemeDiscovery()
        #expect(discovery.listSchemes(container: .project(proj.path)) == ["App", "AppTests"])
    }

    @Test func listSchemesFromWorkspaceAndSiblings() throws {
        let root = Self.tmpRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let ws = try Self.makeWorkspace(at: root, name: "App", schemes: ["Shared"])
        _ = try Self.makeProject(at: root, name: "App", schemes: ["App"])
        _ = try Self.makeProject(at: root, name: "Kit", schemes: ["Kit", "App"])
        let discovery = XcodeSchemeDiscovery()
        #expect(discovery.listSchemes(container: .workspace(ws.path)) == ["App", "Kit", "Shared"])
    }

    @Test func listSchemesForPackageIsEmpty() {
        let discovery = XcodeSchemeDiscovery()
        #expect(discovery.listSchemes(container: .package("/tmp/SomePackage")) == [])
    }

    @Test func explicitSchemeWinsWhenKnown() async throws {
        let root = Self.tmpRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let proj = try Self.makeProject(at: root, name: "App", schemes: ["App", "AppTests"])
        let listed = """
        {"project": {"schemes": ["App", "AppTests"]}}
        """.data(using: .utf8)!
        let discovery = XcodeSchemeDiscovery(listRunner: StubRunner(json: listed))
        let resolved = await discovery.resolveScheme(explicit: "AppTests", container: .project(proj.path))
        #expect(resolved.scheme == "AppTests")
        #expect(resolved.source == .explicit)
        #expect(resolved.reason == nil)
    }

    @Test func firstListedSchemeWinsOverFiles() async throws {
        let root = Self.tmpRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let proj = try Self.makeProject(at: root, name: "App", schemes: ["Zebra"])
        let listed = """
        {"project": {"schemes": ["App", "AppTests"]}}
        """.data(using: .utf8)!
        let discovery = XcodeSchemeDiscovery(listRunner: StubRunner(json: listed))
        let resolved = await discovery.resolveScheme(explicit: nil, container: .project(proj.path))
        #expect(resolved.scheme == "App")
        #expect(resolved.source == .listed)
    }

    @Test func unknownExplicitFallsThroughToListed() async throws {
        let root = Self.tmpRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let proj = try Self.makeProject(at: root, name: "App", schemes: ["App"])
        let listed = """
        {"project": {"schemes": ["App", "AppTests"]}}
        """.data(using: .utf8)!
        let discovery = XcodeSchemeDiscovery(listRunner: StubRunner(json: listed))
        let resolved = await discovery.resolveScheme(explicit: "AppTarget", container: .project(proj.path))
        #expect(resolved.scheme == "App")
        #expect(resolved.source == .listed)
        #expect(resolved.reason?.contains("AppTarget") == true)
    }

    @Test func fileDiscoveryRunsWhenListIsUnavailable() async throws {
        let root = Self.tmpRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let proj = try Self.makeProject(at: root, name: "App", schemes: ["App"])
        let discovery = XcodeSchemeDiscovery(listRunner: StubRunner(json: nil))
        let resolved = await discovery.resolveScheme(explicit: nil, container: .project(proj.path))
        #expect(resolved.scheme == "App")
        #expect(resolved.source == .fileDiscovered)
        #expect(resolved.reason != nil)
    }

    @Test func containerNameFallbackRecordsItsReason() async throws {
        let root = Self.tmpRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let proj = root.appendingPathComponent("Empty.xcodeproj", isDirectory: true)
        try FileManager.default.createDirectory(at: proj, withIntermediateDirectories: true)
        let discovery = XcodeSchemeDiscovery(listRunner: StubRunner(json: nil))
        let resolved = await discovery.resolveScheme(explicit: nil, container: .project(proj.path))
        #expect(resolved.scheme == "Empty")
        #expect(resolved.source == .containerName)
        #expect(resolved.reason?.contains("No schemes could be discovered") == true)
        let targeted = await discovery.resolveScheme(explicit: "MyTarget", container: .project(proj.path))
        #expect(targeted.scheme == "MyTarget")
        #expect(targeted.source == .containerName)
        #expect(targeted.reason?.contains("requested target") == true)
    }

    @Test func packageUsesTargetNameAsScheme() async {
        let discovery = XcodeSchemeDiscovery(listRunner: StubRunner(json: nil))
        let resolved = await discovery.resolveScheme(explicit: "MyTarget", container: .package("/tmp/SomePackage"))
        #expect(resolved.scheme == "MyTarget")
        #expect(resolved.source == .explicit)
        #expect(resolved.reason?.contains("SwiftPM package") == true)
    }

    @Test func containerArgsMatchLegacyResolver() {
        let discovery = XcodeSchemeDiscovery()
        #expect(discovery.containerArgs(for: .project("/tmp/App.xcodeproj")) == ["-project", "/tmp/App.xcodeproj"])
        #expect(discovery.containerArgs(for: .workspace("/tmp/App.xcworkspace")) == ["-workspace", "/tmp/App.xcworkspace"])
        #expect(discovery.containerArgs(for: .package("/tmp/Pkg")) == nil)
        #expect(discovery.containerName(for: .project("/tmp/App.xcodeproj")) == "App")
    }
}
