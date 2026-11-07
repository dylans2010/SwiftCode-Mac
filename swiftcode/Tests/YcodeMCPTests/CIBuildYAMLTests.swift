import Foundation
import Testing
@testable import YcodeMCP

@Suite struct CIBuildYAMLTests {
    private func makeConfig(
        projectName: String = "DemoApp",
        timeoutMinutes: Int = 30,
        triggerMode: CIBuildYAML.CIBuildYAMLConfig.CITriggerMode = .pushAndManual,
        includeTests: Bool = false,
        includeLint: Bool = false,
        exportFormat: CIBuildYAML.CIBuildYAMLConfig.CIExportFormat = .ipa
    ) -> CIBuildYAML.CIBuildYAMLConfig {
        CIBuildYAML.CIBuildYAMLConfig(
            projectName: projectName,
            scheme: "DemoApp",
            xcodeVersion: "16.0",
            buildConfiguration: .release,
            destinationType: .simulator,
            outputName: "DemoApp",
            triggerBranch: "main",
            triggerMode: triggerMode,
            includeTests: includeTests,
            includeLint: includeLint,
            exportFormat: exportFormat,
            timeoutMinutes: timeoutMinutes)
    }

    private func tempWorkspace() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-ci-\(UUID().uuidString)")
    }

    @Test func generatedYAMLHasWorkflowNameRunnerAndBuild() {
        let yaml = CIBuildYAML.generateBuildYAML(config: makeConfig())
        #expect(yaml.contains("name: Build DemoApp"))
        #expect(yaml.contains("runs-on: macos-14"))
        #expect(yaml.contains("xcodebuild -project DemoApp.xcodeproj"))
        #expect(yaml.contains("-scheme DemoApp"))
        #expect(yaml.contains("-configuration Release"))
        #expect(yaml.contains("workflow_dispatch:"))
        #expect(yaml.contains("push:"))
        #expect(yaml.contains("- main"))
        #expect(yaml.contains("timeout-minutes: 30"))
    }

    @Test func manualOnlyTriggerHasNoPushOrPR() {
        let yaml = CIBuildYAML.generateBuildYAML(config: makeConfig(triggerMode: .manualOnly))
        #expect(yaml.contains("workflow_dispatch:"))
        #expect(!yaml.contains("push:"))
        #expect(!yaml.contains("pull_request:"))
    }

    @Test func timeoutIsClampedToFiveThroughOneEighty() {
        #expect(CIBuildYAML.generateBuildYAML(config: makeConfig(timeoutMinutes: 500)).contains("timeout-minutes: 180"))
        #expect(CIBuildYAML.generateBuildYAML(config: makeConfig(timeoutMinutes: 1)).contains("timeout-minutes: 5"))
        let clamped = CIBuildYAML.CIBuildYAMLConfig(
            projectName: "DemoApp", scheme: "DemoApp", xcodeVersion: "16.0",
            buildConfiguration: .debug, destinationType: .simulator,
            outputName: "DemoApp", triggerBranch: "main", timeoutMinutes: 999)
        #expect(clamped.timeoutMinutes == 180)
    }

    @Test func testAndLintSectionsAppearOnlyWhenRequested() {
        let plain = CIBuildYAML.generateBuildYAML(config: makeConfig())
        #expect(!plain.contains("Run Unit Tests"))
        #expect(!plain.contains("Swift Lint"))
        let full = CIBuildYAML.generateBuildYAML(config: makeConfig(includeTests: true, includeLint: true))
        #expect(full.contains("Run Unit Tests"))
        #expect(full.contains("Swift Lint (basic)"))
    }

    @Test func xcarchiveExportUploadsArchiveInsteadOfIPA() {
        let yaml = CIBuildYAML.generateBuildYAML(config: makeConfig(exportFormat: .xcarchive))
        #expect(yaml.contains("Upload XCArchive Artifact"))
        #expect(!yaml.contains("Create IPA"))
    }

    @Test func fileFormWritesBuildYMLUnderGitHubWorkflows() throws {
        let root = tempWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try CIBuildYAML.generateBuildYAML(config: makeConfig(), workspaceRoot: root)
        #expect(url == root.appendingPathComponent(".github/workflows/build.yml"))
        #expect(FileManager.default.fileExists(atPath: url.path))
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("name: Build DemoApp"))
    }

    @Test func outputNameIsSanitizedToAPathComponent() {
        let config = CIBuildYAML.CIBuildYAMLConfig(
            projectName: "DemoApp", scheme: "DemoApp", xcodeVersion: "16.0",
            buildConfiguration: .debug, destinationType: .device,
            outputName: "My App!", triggerBranch: "main")
        let yaml = CIBuildYAML.generateBuildYAML(config: config)
        #expect(yaml.contains("My-App-.xcarchive"))
        #expect(!yaml.contains("My App!"))
    }

    @Test func validateCountsValidAndInvalidPipelines() throws {
        let root = tempWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent(".github/workflows")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "name: Good\njobs:\n  build:\n    steps:\n      - name: Build\n        run: xcodebuild\n"
            .write(to: dir.appendingPathComponent("good.yml"), atomically: true, encoding: .utf8)
        try "jobs:\n  build:\n    steps: []\n"
            .write(to: dir.appendingPathComponent("bad.yml"), atomically: true, encoding: .utf8)
        try "not yaml at all"
            .write(to: dir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        let result = try CIBuildYAML.validateCIPipelines(workspaceRoot: root)
        #expect(result.pipelinesFound == 2)
        #expect(result.valid == 1)
        #expect(result.invalid == 1)
        #expect(result.validPipelines == ["good.yml"])
        #expect(result.errors.count == 1)
        #expect(result.errors[0].hasPrefix("bad.yml:"))
    }

    @Test func validateThrowsWhenWorkflowsDirectoryIsMissing() {
        let root = tempWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        var threw = false
        do {
            _ = try CIBuildYAML.validateCIPipelines(workspaceRoot: root)
        } catch {
            threw = true
        }
        #expect(threw)
    }
}
