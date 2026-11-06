import Foundation
import Testing
@testable import SwiftCodeIDECore

/// Project Inspector scanner: file metrics, framework-usage counts, the
/// health rules and the pbxproj parse, all against throwaway fixtures.
@MainActor
struct ProjectInspectorTests {
    private func makeFixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-inspector-\(UUID().uuidString)")
        let sources = root.appendingPathComponent("Sources/App")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try """
        import SwiftUI
        import Observation

        @Observable
        final class Model {
            var count = 0
            func tick() async { count += 1 }
        }
        """.write(to: sources.appendingPathComponent("Model.swift"), atomically: true, encoding: .utf8)
        try """
        import AppKit

        actor Worker {
            func run() async {}
        }
        """.write(to: sources.appendingPathComponent("Worker.swift"), atomically: true, encoding: .utf8)
        try "# Fixture\n".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "{}".write(to: root.appendingPathComponent("data.json"), atomically: true, encoding: .utf8)
        return root
    }

    @Test func scanCountsFilesAndUsage() async throws {
        let root = try makeFixture()
        let scanner = InspectorProjectScanner()
        await scanner.scan(rootURL: root)
        #expect(scanner.totalSwiftFiles == 2)
        #expect(scanner.totalFiles == 4)
        #expect(scanner.swiftUIUsageCount == 1)
        #expect(scanner.appkitUsageCount == 1)
        #expect(scanner.observationUsageCount == 1)
        #expect(scanner.asyncUsageCount == 2)
        #expect(scanner.actorUsageCount == 1)
        #expect(scanner.markdownCount == 1)
        #expect(scanner.jsonCount == 1)
        #expect(scanner.largestFiles.count == 2)
        #expect(scanner.longestSwiftFiles.first?.name == "Model.swift")
    }

    @Test func healthPenalizesMissingLocalization() async throws {
        let root = try makeFixture()
        let scanner = InspectorProjectScanner()
        await scanner.scan(rootURL: root)
        #expect(scanner.projectHealthScore < 100)
        #expect(scanner.aiRecommendations.contains { $0.contains("localization") })
    }

    @Test func fileMetadataReadsImportsAndGit() throws {
        let root = try makeFixture()
        let file = root.appendingPathComponent("Sources/App/Model.swift")
        let meta = InspectorFileMetadata.load(from: file, root: root)
        #expect(meta?.imports.contains("SwiftUI") == true)
        #expect(meta?.imports.contains("Observation") == true)
        #expect(meta?.lineCount == 9)
        #expect(meta?.gitStatus == "Unknown")
    }

    @Test func pbxprojParseFindsTargetAndPackage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-inspector-pbx-\(UUID().uuidString)")
        let xcodeproj = root.appendingPathComponent("Demo.xcodeproj")
        try FileManager.default.createDirectory(at: xcodeproj, withIntermediateDirectories: true)
        let pbxproj = """
        // !$*UTF8*$!
        {
            archiveVersion = 1;
            classes = {};
            objectVersion = 56;
            objects = {
                AA0000000000000000000001 = { isa = PBXProject; buildConfigurationList = AA0000000000000000000005; mainGroup = AA0000000000000000000002; targets = (AA0000000000000000000003); };
                AA0000000000000000000002 = { isa = PBXGroup; children = (); sourceTree = "<group>"; };
                AA0000000000000000000003 = { isa = PBXNativeTarget; buildConfigurationList = AA0000000000000000000005; buildPhases = (); buildRules = (); dependencies = (); name = Demo; productName = Demo; productType = "com.apple.product-type.application"; };
                AA0000000000000000000005 = { isa = XCConfigurationList; buildConfigurations = (AA0000000000000000000006, AA0000000000000000000007); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };
                AA0000000000000000000006 = { isa = XCBuildConfiguration; buildSettings = { PRODUCT_BUNDLE_IDENTIFIER = "com.example.demo"; MARKETING_VERSION = "1.2.3"; CURRENT_PROJECT_VERSION = 9; MACOSX_DEPLOYMENT_TARGET = 15.0; }; name = Debug; };
                AA0000000000000000000007 = { isa = XCBuildConfiguration; buildSettings = { PRODUCT_BUNDLE_IDENTIFIER = "com.example.demo"; MARKETING_VERSION = "1.2.3"; CURRENT_PROJECT_VERSION = 9; }; name = Release; };
                AA0000000000000000000008 = { isa = XCRemoteSwiftPackageReference; repositoryURL = "https://github.com/apple/swift-collections.git"; requirement = { kind = upToNextMajorVersion; minimumVersion = 1.0.0; }; };
            };
            rootObject = AA0000000000000000000001;
        }
        """
        try pbxproj.write(to: xcodeproj.appendingPathComponent("project.pbxproj"), atomically: true, encoding: .utf8)
        let schemes = xcodeproj.appendingPathComponent("xcshareddata/xcschemes")
        try FileManager.default.createDirectory(at: schemes, withIntermediateDirectories: true)
        try "<Scheme></Scheme>".write(to: schemes.appendingPathComponent("Demo.xcscheme"), atomically: true, encoding: .utf8)
        let parsed = InspectorProjectScanner.parseXcodeProject(at: root)
        #expect(parsed.found)
        #expect(parsed.targets.count == 1)
        #expect(parsed.targets.first?.name == "Demo")
        #expect(parsed.targets.first?.configurationNames.sorted() == ["Debug", "Release"])
        #expect(parsed.configurations == ["Debug", "Release"])
        #expect(parsed.bundleIdentifier == "com.example.demo")
        #expect(parsed.version == "1.2.3")
        #expect(parsed.buildNumber == "9")
        #expect(parsed.deploymentTargets["macOS (Debug)"] == "15.0")
        #expect(parsed.packages.count == 1)
        #expect(parsed.packages.first?.name == "swift-collections")
        #expect(parsed.schemes.map { $0.name } == ["Demo"])
    }

    @Test func markdownReportMentionsHealth() async throws {
        let root = try makeFixture()
        let scanner = InspectorProjectScanner()
        await scanner.scan(rootURL: root)
        let report = scanner.markdownReport()
        #expect(report.contains("Health score:"))
        #expect(report.contains("Recommendations"))
    }
}
