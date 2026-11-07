import Foundation
import Testing
@testable import SwiftCodeMCP

@Suite("Misc gap tests — native XcodeGen generator")
@MainActor
struct MiscGapTests {
    private static let appSpec = """
        name: DemoApp
        options:
          bundleIdPrefix: com.example
        targets:
          DemoApp:
            type: application
            platform: iOS
            sources: [DemoApp]
        """

    private func sampleWithSource() throws -> TempSample {
        let sample = try TempSample()
        let sourceURL = sample.url.appendingPathComponent("DemoApp/App.swift")
        try FileManager.default.createDirectory(at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "import Foundation\n\npublic struct App {\n    public init() {}\n}\n".write(to: sourceURL, atomically: true, encoding: .utf8)
        return sample
    }

    private func openedPackage(_ sample: TempSample, policy: MCPWritePolicy = .allow) async throws -> SwiftCodeMCPHost {
        let host = SwiftCodeMCPHost()
        host.server.writePolicy = policy
        let ported = Set(host.projectModelTools.map(\.name))
        host.server.tools = host.server.tools.filter { !ported.contains($0.name) } + host.projectModelTools
        let r = try await host.server.callTool("workspace_open", ["path": .string(sample.url.path)])
        #expect(!r.isToolError, "\(r.resultText)")
        return host
    }

    @Test("A minimal app spec generates a project, a scheme, and a pbxproj naming the app")
    func minimalAppSpecGenerates() throws {
        let sample = try sampleWithSource()
        defer { sample.remove() }
        let generated = try XcodeGenNativeGenerator.generate(specText: Self.appSpec, specDirectory: sample.url)
        #expect(generated.projectName == "DemoApp")
        #expect(generated.targetNames == ["DemoApp"])
        #expect(generated.schemeNames.contains("DemoApp"))
        let pbxproj = generated.files.first { $0.relativePath == "DemoApp.xcodeproj/project.pbxproj" }
        #expect(pbxproj != nil)
        #expect(pbxproj?.content.contains("DemoApp") == true)
        #expect(pbxproj?.content.contains("com.apple.product-type.application") == true)
        #expect(pbxproj?.content.contains("com.example.DemoApp") == true)
        let scheme = generated.files.first { $0.relativePath.hasSuffix(".xcscheme") }
        #expect(scheme != nil)
        #expect(scheme?.content.contains("DemoApp") == true)
    }

    @Test("A spec without a name fails honestly and names the missing key")
    func specWithoutNameFails() throws {
        let sample = try sampleWithSource()
        defer { sample.remove() }
        let spec = """
            options:
              bundleIdPrefix: com.example
            targets:
              DemoApp:
                type: application
                platform: iOS
            """
        do {
            _ = try XcodeGenNativeGenerator.generate(specText: spec, specDirectory: sample.url)
            Issue.record("Expected a missing-name error")
        } catch let error as XcodeGenSpecError {
            #expect(error.localizedDescription.contains("name"))
        }
    }

    @Test("An unknown target type fails honestly and names the type")
    func unknownTargetTypeFails() throws {
        let sample = try sampleWithSource()
        defer { sample.remove() }
        let spec = """
            name: DemoApp
            options:
              bundleIdPrefix: com.example
            targets:
              DemoApp:
                type: time-machine
                platform: iOS
            """
        do {
            _ = try XcodeGenNativeGenerator.generate(specText: spec, specDirectory: sample.url)
            Issue.record("Expected an unsupported-type error")
        } catch let error as XcodeGenSpecError {
            #expect(error.localizedDescription.contains("time-machine"))
        }
    }

    @Test("An app target without a bundleIdPrefix fails honestly")
    func appWithoutBundleIdPrefixFails() throws {
        let sample = try sampleWithSource()
        defer { sample.remove() }
        let spec = """
            name: DemoApp
            targets:
              DemoApp:
                type: application
                platform: iOS
            """
        do {
            _ = try XcodeGenNativeGenerator.generate(specText: spec, specDirectory: sample.url)
            Issue.record("Expected a missing-bundleIdPrefix error")
        } catch let error as XcodeGenSpecError {
            #expect(error.localizedDescription.contains("bundleIdPrefix"))
        }
    }

    @Test("generate_xcodeproj writes the .xcodeproj into the workspace")
    func toolWritesXcodeproj() async throws {
        let sample = try sampleWithSource()
        defer { sample.remove() }
        try Self.appSpec.write(
            to: sample.url.appendingPathComponent("project.yml"), atomically: true, encoding: .utf8)
        let host = try await openedPackage(sample)
        let r = try await host.server.callTool("generate_xcodeproj")
        #expect(!r.isToolError, "\(r.firstText)")
        #expect(r.structured?["projects"]?.string == "DemoApp.xcodeproj")
        let pbxprojURL = sample.url.appendingPathComponent("DemoApp.xcodeproj/project.pbxproj")
        #expect(FileManager.default.fileExists(atPath: pbxprojURL.path))
        let pbxproj = try String(contentsOf: pbxprojURL, encoding: .utf8)
        #expect(pbxproj.contains("DemoApp"))
        #expect(pbxproj.contains("com.apple.product-type.application"))
        let schemeURL = sample.url.appendingPathComponent("DemoApp.xcodeproj/xcshareddata/xcschemes/DemoApp.xcscheme")
        #expect(FileManager.default.fileExists(atPath: schemeURL.path))
    }

    @Test("generate_xcodeproj regenerates over its own output")
    func toolRegenerates() async throws {
        let sample = try sampleWithSource()
        defer { sample.remove() }
        try Self.appSpec.write(
            to: sample.url.appendingPathComponent("project.yml"), atomically: true, encoding: .utf8)
        let host = try await openedPackage(sample)
        let first = try await host.server.callTool("generate_xcodeproj")
        #expect(!first.isToolError, "\(first.firstText)")
        let second = try await host.server.callTool("generate_xcodeproj")
        #expect(!second.isToolError, "\(second.firstText)")
        #expect(second.structured?["projects"]?.string == "DemoApp.xcodeproj")
    }

    @Test("generate_xcodeproj fails honestly when the spec file is missing")
    func toolFailsWithoutSpecFile() async throws {
        let sample = try sampleWithSource()
        defer { sample.remove() }
        let host = try await openedPackage(sample)
        let r = try await host.server.callTool("generate_xcodeproj", ["spec": .string("missing.yml")])
        #expect(r.isToolError)
        #expect(r.firstText.contains("XcodeGen spec not found"))
    }

    @Test("generate_xcodeproj fails honestly on an unsupported spec, with an xcodegen hint")
    func toolFailsOnUnsupportedSpec() async throws {
        let sample = try sampleWithSource()
        defer { sample.remove() }
        let spec = """
            name: DemoApp
            options:
              bundleIdPrefix: com.example
            targets:
              DemoApp:
                type: time-machine
                platform: iOS
            """
        try spec.write(
            to: sample.url.appendingPathComponent("project.yml"), atomically: true, encoding: .utf8)
        let host = try await openedPackage(sample)
        let r = try await host.server.callTool("generate_xcodeproj")
        #expect(r.isToolError)
        #expect(r.firstText.contains("time-machine"))
        #expect(r.firstText.contains("xcodegen"))
    }
}
