import Foundation
import Testing
import YcodeAssistant
@testable import YcodeMCP

@MainActor
@Suite(.serialized) struct SwiftCodeSPMDocsTests {
    static let sliceCIDs = ["swift_package_manager", "package_manifest_read", "package_manifest_validate",
                            "package_dependency_add", "package_dependency_audit", "package_dependency_update",
                            "spm_dependency_tree", "carthage_cartfile_inspector", "podfile_inspector",
                            "docc_build", "docs_generate", "docs_index_build", "project_changelog"]

    static let fixtureManifest = """
    // swift-tools-version: 5.9
    // Fixture manifest for the SPM/docs tools.
    import PackageDescription

    let package = Package(
        name: "Greeter",
        platforms: [.macOS(.v14)],
        products: [.executable(name: "greet", targets: ["greet"])],
        dependencies: [
            .package(url: "https://github.com/apple/swift-argument-parser", from: "1.0.0"),
        ],
        targets: [
            .target(name: "Greeter"),
            .executableTarget(name: "greet", dependencies: ["Greeter"]),
            .testTarget(name: "GreeterTests", dependencies: ["Greeter"]),
        ]
    )
    """

    static let fixtureResolved = """
    {
      "pins": [
        {
          "identity": "swift-argument-parser",
          "kind": "remoteSourceControl",
          "location": "https://github.com/apple/swift-argument-parser",
          "state": { "branch": null, "revision": "abcdef0123456789abcdef0123456789abcdef01", "version": "1.0.0" }
        }
      ],
      "version": 2
    }
    """

    func opened(_ sample: TempSample, policy: MCPWritePolicy = .readOnly) async throws -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        host.server.writePolicy = policy
        let ported = Set(host.spmDocsTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.spmDocsTools
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

    func read(_ sample: TempSample, _ rel: String) -> String {
        (try? String(contentsOfFile: sample.path(rel), encoding: .utf8)) ?? ""
    }

    @Test func toolIDsAreRegisteredOnce() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        #expect(host.spmDocsTools.map(\.name) == Self.sliceCIDs)
        for id in Self.sliceCIDs {
            #expect(host.server.tools.filter { $0.name == id }.count == 1, "\(id) must be registered exactly once")
        }
    }

    @Test func manifestReadSummarizesFixture() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Package.swift", Self.fixtureManifest)
        let r = try await host.server.callTool("package_manifest_read")
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["packageName"]?.string == "Greeter")
        #expect(r.structured?["platforms"]?.string == "macOS")
        #expect(r.structured?["products"]?.string == "greet")
        #expect(r.structured?["targets"]?.string == "Greeter,greet,GreeterTests")
        #expect(r.structured?["dependencies"]?.string == "https://github.com/apple/swift-argument-parser")
        #expect(r.structured?["productCount"]?.int == 1 && r.structured?["targetCount"]?.int == 3 && r.structured?["dependencyCount"]?.int == 1)
        #expect(r.firstText.contains("Package: Greeter"))
        #expect(r.firstText.contains("Targets (3): Greeter, greet, GreeterTests"))
        let missing = try await host.server.callTool("package_manifest_read", ["path": .string("Nope.swift")])
        #expect(missing.isToolError && missing.firstText.contains("Package manifest not found at 'Nope.swift'."))
        let outside = try await host.server.callTool("package_manifest_read", ["path": .string("../outside.swift")])
        #expect(outside.isToolError && outside.firstText.contains("must be inside the workspace"))
    }

    @Test func manifestValidateRunsOrFailsHonestly() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Package.swift", Self.fixtureManifest)
        let r = try await host.server.callTool("package_manifest_validate")
        if canBuildPackages {
            #expect(!r.isToolError, "\(r.resultText)")
            #expect(r.structured?["packageName"]?.string == "Greeter")
            #expect(r.structured?["targetCount"]?.int == 3)
            #expect(r.structured?["exitCode"]?.int == 0)
            #expect(r.firstText.contains("Package manifest is valid: Greeter with 3 target(s)."))
        } else {
            #expect(r.isToolError && r.firstText.contains("Swift not found at /usr/bin/swift."))
        }
        let missing = try await host.server.callTool("package_manifest_validate", ["path": .string("Nope.swift")])
        if canBuildPackages {
            #expect(missing.isToolError && missing.firstText.contains("Package manifest not found at 'Nope.swift'."))
        } else {
            #expect(missing.isToolError && missing.firstText.contains("Swift not found at /usr/bin/swift."))
        }
    }

    @Test func swiftPackageManagerRejectsBadActionAndMissingManifest() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let noParam = try await host.server.callTool("swift_package_manager")
        #expect(noParam.isToolError)
        let bad = try await host.server.callTool("swift_package_manager", ["action": .string("explode")])
        #expect(bad.isToolError && bad.firstText.contains("Unsupported action 'explode'. Valid: resolve, update, status, dump_manifest, describe"))
        let outside = try await host.server.callTool("swift_package_manager", ["action": .string("status"), "packageDir": .string("../outside")])
        #expect(outside.isToolError && outside.firstText.contains("must be inside the workspace"))
    }

    @Test func swiftPackageManagerStatusRunsWhenSwiftExists() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        guard canBuildPackages else {
            let r = try await host.server.callTool("swift_package_manager", ["action": .string("status")])
            #expect(r.isToolError && r.firstText.contains("Swift not found at /usr/bin/swift."))
            return
        }
        let r = try await host.server.callTool("swift_package_manager", ["action": .string("status")])
        #expect(!r.isToolError, "\(r.resultText)")
    }

    @Test func dependencyAddInsertsAndReportsAlreadyPresent() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        try writeFixture(sample, "Package.swift", Self.fixtureManifest)
        let r = try await host.server.callTool("package_dependency_add",
                                               ["url": .string("https://github.com/apple/swift-log"),
                                                "requirement": .string("1.5.0")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["url"]?.string == "https://github.com/apple/swift-log")
        #expect(r.structured?["requirement"]?.string == "from: \"1.5.0\"")
        #expect(r.structured?["alreadyPresent"]?.bool == false)
        #expect(read(sample, "Package.swift").contains("https://github.com/apple/swift-log"))
        let again = try await host.server.callTool("package_dependency_add",
                                                   ["url": .string("https://github.com/apple/swift-log")])
        #expect(!again.isToolError, "\(again.resultText)")
        #expect(again.structured?["alreadyPresent"]?.bool == true)
        #expect(again.firstText.contains("Dependency already present in Package.swift: https://github.com/apple/swift-log"))
        let badURL = try await host.server.callTool("package_dependency_add",
                                                    ["url": .string("https://example.com/a b")])
        #expect(badURL.isToolError && badURL.firstText.contains("Invalid url: must not contain spaces, newlines, or quotes."))
        let noURL = try await host.server.callTool("package_dependency_add")
        #expect(noURL.isToolError)
    }

    @Test func dependencyAddWiresProductIntoTarget() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        try writeFixture(sample, "Package.swift", Self.fixtureManifest)
        let r = try await host.server.callTool("package_dependency_add",
                                               ["url": .string("https://github.com/apple/swift-argument-parser"),
                                                "product": .string("ArgumentParser"),
                                                "target": .string("greet")])
        #expect(!r.isToolError, "\(r.resultText)")
        let fresh = try await host.server.callTool("package_dependency_add",
                                                   ["url": .string("https://github.com/apple/swift-log"),
                                                    "product": .string("Logging"),
                                                    "target": .string("greet")])
        #expect(!fresh.isToolError, "\(fresh.resultText)")
        #expect(fresh.structured?["targetWiring"]?.string == "wired product 'Logging' into target 'greet'")
        #expect(read(sample, "Package.swift").contains("\"Logging\""))
        let missingTarget = try await host.server.callTool("package_dependency_add",
                                                           ["url": .string("https://github.com/apple/swift-nio"),
                                                            "product": .string("NIO"),
                                                            "target": .string("NoSuchTarget")])
        #expect(!missingTarget.isToolError, "\(missingTarget.resultText)")
        #expect((missingTarget.structured?["targetWiring"]?.string ?? "").contains("not wired"))
    }

    @Test func dependencyAddRefusesInReadOnlyAndOnReviewRejection() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let readOnlyHost = try await opened(sample)
        try writeFixture(sample, "Package.swift", Self.fixtureManifest)
        let refused = try await readOnlyHost.server.callTool("package_dependency_add",
                                                             ["url": .string("https://github.com/apple/swift-log")])
        #expect(refused.isToolError && refused.firstText.contains("read-only"))
        #expect(!read(sample, "Package.swift").contains("swift-log"))
        let reviewHost = try await opened(sample, policy: .review { _ in false })
        let rejected = try await reviewHost.server.callTool("package_dependency_add",
                                                            ["url": .string("https://github.com/apple/swift-log")])
        #expect(rejected.isToolError && rejected.firstText.contains(MCPServer.rejectedMessage))
        #expect(!read(sample, "Package.swift").contains("swift-log"))
    }

    @Test func dependencyAddFailsWithoutDependenciesArray() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let r = try await host.server.callTool("package_dependency_add",
                                               ["url": .string("https://github.com/apple/swift-log")])
        #expect(r.isToolError && r.firstText.contains("Could not find a 'dependencies:' array in Package.swift. Add one manually first."))
    }

    @Test func dependencyAuditFlagsMissingResolved() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Package.swift", Self.fixtureManifest)
        let unpinned = try await host.server.callTool("package_dependency_audit")
        #expect(!unpinned.isToolError, "\(unpinned.resultText)")
        #expect(unpinned.structured?["declaredCount"]?.int == 1)
        #expect(unpinned.structured?["hasResolved"]?.bool == false)
        #expect(unpinned.structured?["unpinnedCount"]?.int == 1)
        #expect(unpinned.firstText.contains("Missing Package.resolved: dependencies are not pinned to exact revisions."))
        try writeFixture(sample, "Package.resolved", Self.fixtureResolved)
        let pinned = try await host.server.callTool("package_dependency_audit")
        #expect(!pinned.isToolError, "\(pinned.resultText)")
        #expect(pinned.structured?["declaredCount"]?.int == 1)
        #expect(pinned.structured?["pinnedCount"]?.int == 1)
        #expect(pinned.structured?["hasResolved"]?.bool == true)
        #expect(pinned.structured?["unpinnedCount"]?.int == 1)
        #expect(pinned.firstText.contains("swift-argument-parser (requirement: from, resolved: 1.0.0"))
    }

    @Test func dependencyUpdateValidatesNameAndSwift() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Package.swift", Self.fixtureManifest)
        if canBuildPackages {
            let bad = try await host.server.callTool("package_dependency_update",
                                                     ["package": .string("two words")])
            #expect(bad.isToolError && bad.firstText.contains("Invalid package name: must be a single dependency name without spaces, slashes, or '..'."))
            let traversal = try await host.server.callTool("package_dependency_update",
                                                           ["package": .string("../escape")])
            #expect(traversal.isToolError && traversal.firstText.contains("Invalid package name"))
        } else {
            let r = try await host.server.callTool("package_dependency_update")
            #expect(r.isToolError && r.firstText.contains("Swift not found at /usr/bin/swift."))
        }
    }

    @Test func dependencyTreeParsesResolvedAndReportsMissing() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let absent = try await host.server.callTool("spm_dependency_tree")
        #expect(!absent.isToolError, "\(absent.resultText)")
        #expect(absent.firstText.contains("No Package.resolved file found in workspace."))
        try writeFixture(sample, "Package.resolved", Self.fixtureResolved)
        let r = try await host.server.callTool("spm_dependency_tree")
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Total Resolved Packages**: 1"))
        #expect(r.firstText.contains("swift-argument-parser"))
        #expect(r.firstText.contains("1.0.0"))
        #expect(r.firstText.contains("abcdef01"))
        #expect(r.firstText.contains("https://github.com/apple/swift-argument-parser"))
        let explicit = try await host.server.callTool("spm_dependency_tree", ["path": .string("Package.resolved")])
        #expect(!explicit.isToolError && explicit.firstText.contains("swift-argument-parser"))
        let outside = try await host.server.callTool("spm_dependency_tree", ["path": .string("../outside.resolved")])
        #expect(outside.isToolError && outside.firstText.contains("must be inside the workspace"))
    }

    @Test func carthageInspectorReportsDeclaredAndResolved() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let absent = try await host.server.callTool("carthage_cartfile_inspector")
        #expect(!absent.isToolError, "\(absent.resultText)")
        #expect(absent.firstText.contains("No Carthage Cartfile or Cartfile.resolved found in workspace root."))
        try writeFixture(sample, "Cartfile", "# comment\ngithub \"Alamofire/Alamofire\" ~> 5.0\n")
        try writeFixture(sample, "Cartfile.resolved", "github \"Alamofire/Alamofire\" \"5.9.1\"\n")
        let r = try await host.server.callTool("carthage_cartfile_inspector")
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Declared in Cartfile:"))
        #expect(r.firstText.contains("Alamofire/Alamofire"))
        #expect(!r.firstText.contains("# comment"))
        #expect(r.firstText.contains("Resolved in Cartfile.resolved:"))
        #expect(r.firstText.contains("5.9.1"))
    }

    @Test func podfileInspectorReportsPodsAndLockedVersions() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let absent = try await host.server.callTool("podfile_inspector")
        #expect(!absent.isToolError, "\(absent.resultText)")
        #expect(absent.firstText.contains("No CocoaPods Podfile or Podfile.lock found in workspace root."))
        try writeFixture(sample, "Podfile", "platform :ios, '15.0'\ntarget 'App' do\n  pod 'Alamofire', '~> 5.0'\nend\n")
        try writeFixture(sample, "Podfile.lock", """
        PODS:
          - Alamofire (5.9.1)
          - SomeOther (1.0)

        DEPENDENCIES:
          - Alamofire (~> 5.0)
        """)
        let r = try await host.server.callTool("podfile_inspector")
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Declared Pods in Podfile (1):"))
        #expect(r.firstText.contains("pod 'Alamofire'"))
        #expect(r.firstText.contains("Locked Pod Versions (2):"))
        #expect(r.firstText.contains("Alamofire (5.9.1)"))
    }

    @Test func doccBuildRejectsMissingSchemeAndMissingXcodebuild() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let noParam = try await host.server.callTool("docc_build")
        #expect(noParam.isToolError)
        let badOutput = try await host.server.callTool("docc_build",
                                                       ["scheme": .string("Greeter"), "outputPath": .string("../outside")])
        #expect(badOutput.isToolError && badOutput.firstText.contains("Invalid outputPath:"))
        if !FileManager.default.fileExists(atPath: "/usr/bin/xcodebuild") {
            let r = try await host.server.callTool("docc_build", ["scheme": .string("Greeter")])
            #expect(r.isToolError && r.firstText.contains("xcodebuild not found at /usr/bin/xcodebuild. Install Xcode command line tools first."))
        }
    }

    @Test func docsGenerateWritesAndRefusesOverwrite() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample, policy: .allow)
        let r = try await host.server.callTool("docs_generate", ["title": .string("Greeter API")])
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["output_relative"]?.string == "DOCS_GENERATED.md")
        #expect((r.structured?["file_count"]?.int ?? 0) > 0)
        #expect((r.structured?["declaration_count"]?.int ?? 0) > 0)
        let generated = read(sample, "DOCS_GENERATED.md")
        #expect(generated.contains("# Greeter API"))
        #expect(generated.contains("public struct Greeter"))
        #expect(generated.contains("## Sources/Greeter/Greeter.swift"))
        let again = try await host.server.callTool("docs_generate")
        #expect(again.isToolError && again.firstText.contains("Refusing to overwrite existing file at 'DOCS_GENERATED.md'. Pass overwrite=true to replace it."))
        let overwrite = try await host.server.callTool("docs_generate", ["overwrite": .string("true")])
        #expect(!overwrite.isToolError, "\(overwrite.resultText)")
        let outside = try await host.server.callTool("docs_generate", ["outputPath": .string("../outside.md")])
        #expect(outside.isToolError && outside.firstText.contains("Invalid outputPath:"))
    }

    @Test func docsGenerateRefusesInReadOnly() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("docs_generate")
        #expect(r.isToolError && r.firstText.contains("read-only"))
        #expect(!exists(sample, "DOCS_GENERATED.md"))
    }

    @Test func docsIndexBuildsTableFromMarkdown() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        try writeFixture(sample, "Docs/Guide.md", "# User Guide\n\nSome text.\n")
        try writeFixture(sample, "README.md", "No heading here.\n")
        let r = try await host.server.callTool("docs_index_build")
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.structured?["count"]?.int == 2)
        #expect(r.firstText.contains("Markdown index (2 files):"))
        #expect(r.firstText.contains("| Docs/Guide.md | User Guide |"))
        #expect(r.firstText.contains("| README.md | (no title) |"))
    }

    @Test func changelogReturnsLogKeyWithoutInventingHistory() async throws {
        let sample = try TempSample()
        defer { sample.remove() }
        let host = try await opened(sample)
        let r = try await host.server.callTool("project_changelog")
        #expect(!r.isToolError, "\(r.resultText)")
        #expect(r.firstText.contains("Changelog retrieved successfully."))
        #expect(r.structured?["log"] != nil)
        if !FileManager.default.fileExists(atPath: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AssistSnapshots").path) {
            #expect(r.structured?["log"]?.string == "No snapshot history found.")
        }
    }
}
