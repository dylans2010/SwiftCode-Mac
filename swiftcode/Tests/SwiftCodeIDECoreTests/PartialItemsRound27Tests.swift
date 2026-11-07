import Foundation
import Testing
import SwiftCodeBuild
import SwiftCodePlist
import SwiftCodeProject
@testable import SwiftCodeIDECore

@MainActor
@Suite struct PartialItemsRound27Tests {
    func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-r27-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    func generatedProject() throws -> (ProjectEditorModel, URL) {
        let base = try ProjectEditorReferenceTests().model()
        let text = ProjectEditorReferenceTests.pbxproj.replacingOccurrences(
            of: "PRODUCT_NAME = App;", with: "PRODUCT_NAME = App; GENERATE_INFOPLIST_FILE = YES; INFOPLIST_KEY_CFBundleDisplayName = Hi;")
        try text.write(to: base.xcodeprojURL.appendingPathComponent("project.pbxproj"), atomically: true, encoding: .utf8)
        return (ProjectEditorModel(proj: try PBXProj(parsing: text), xcodeprojURL: base.xcodeprojURL), base.xcodeprojURL.deletingLastPathComponent())
    }

    @Test func generatedInfoPlistTypeSectionsCreateTheFile() throws {
        let (m0, dir) = try generatedProject()
        var m = m0
        #expect(m.generatesInfoPlist(target: "App", configuration: "Debug"))
        #expect(m.infoTypeSections(target: "App", configuration: "Debug").allSatisfy { $0.hasSuffix("(0)") })
        try m.setInfoTypeEntries("CFBundleURLTypes", [], target: "App", configuration: "Debug")
        #expect(!FileManager.default.fileExists(atPath: dir.appendingPathComponent("App/Info.plist").path))

        try m.addInfoTypeEntry("CFBundleURLTypes", target: "App", configuration: "Debug")
        let file = dir.appendingPathComponent("App/Info.plist")
        let doc = try PropertyListDocument(data: Data(contentsOf: file))
        guard case .dictionary(let d) = doc.root else { Issue.record("not a dictionary"); return }
        #expect(d.map(\.key) == ["CFBundleURLTypes"])
        for c in ["Debug", "Release"] {
            #expect(m.resolve(target: "App", configuration: c)?.settings["INFOPLIST_FILE"] == "App/Info.plist")
        }
        #expect(m.generatesInfoPlist(target: "App", configuration: "Debug"))
        #expect(m.infoTypeEntries("CFBundleURLTypes", target: "App", configuration: "Debug").count == 1)
        #expect(m.infoRows(target: "App", configuration: "Debug").map(\.key).contains("CFBundleDisplayName"))
    }

    @Test func otherSetTypesCreateReadAndList() throws {
        let dir = try tempDir().appendingPathComponent("A.xcassets")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let c = AssetCatalog(url: dir)
        let data = try c.addSet(.dataSet, named: "Blob")
        let sym = try c.addSet(.symbolSet, named: "Star")
        let atlas = try c.addSet(.spriteAtlas, named: "Sprites")
        _ = try c.addSet(.imageSet, named: "Frame", in: "Sprites.spriteatlas")
        let ns = try c.addFolder(named: "Icons", namespace: true)
        #expect((AssetCatalog.readContents(ns)["properties"] as? [String: Bool])?["provides-namespace"] == true)
        #expect(AssetCatalog.readContents(data.url)["data"] as? [[String: String]] == [["idiom": "universal"]])
        #expect(AssetCatalog.readContents(sym.url)["symbols"] as? [[String: String]] == [["idiom": "universal"]])
        #expect(AssetCatalog.readContents(atlas.url).keys.sorted() == ["info"])
        #expect(c.sets().map { "\($0.group)|\($0.name)|\($0.kind.rawValue)" } ==
                ["|Blob|dataset", "|Sprites|spriteatlas", "Sprites|Frame|imageset", "|Star|symbolset"])

        let src = dir.deletingLastPathComponent().appendingPathComponent("payload.json")
        try Data("{}".utf8).write(to: src)
        try AssetCatalog.setImage(src, slot: 0, in: data)
        #expect(AssetCatalog.slots(of: data).first?.filename == "payload.json")
        try AssetCatalog.clearImage(slot: 0, in: data)
        #expect(AssetCatalog.slots(of: data).first?.filename == nil)
        #expect(!FileManager.default.fileExists(atPath: data.url.appendingPathComponent("payload.json").path))
        #expect(AssetCatalog.Kind.dataSet.typeLabel == "Data Set" && AssetCatalog.inspector(for: data).rows.first?.value == "Blob")
        for k in AssetCatalog.Kind.allCases { #expect(!k.typeLabel.isEmpty) }
    }

    @Test func swiftBuildPreferenceRunsProjectTestsThroughSwiftCodebuild() throws {
        let dir = try tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let tool = dir.appendingPathComponent("swiftcodebuild")
        try Data("#!/bin/sh\n".utf8).write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        #expect(TestRunnerSelection.locateSwiftCodebuild(environment: ["PATH": dir.path], executableDirectory: nil) == tool.path)
        #expect(TestRunnerSelection.locateSwiftCodebuild(environment: [:], executableDirectory: dir.path) == tool.path)
        #expect(TestRunnerSelection.locateSwiftCodebuild(environment: ["SWIFTCODE_BUILD_TOOL": tool.path], executableDirectory: nil) == tool.path)
        #expect(TestRunnerSelection.locateSwiftCodebuild(environment: [:], executableDirectory: nil) == nil)

        var r = TestRunnerSelection.runner(TestRunner(), preference: .swiftBuild, locate: { tool.path })
        #expect(r.xcodebuild == [tool.path])
        r.coverage = true
        let req = BuildRequest(container: .project(dir.appendingPathComponent("P.xcodeproj").path), scheme: "P", action: .test)
        let cmd = r.command(for: req).args
        #expect(cmd.first == tool.path && cmd.contains("-enableCodeCoverage"))
        #expect(TestRunnerSelection.runner(TestRunner(), preference: .xcodebuild, locate: { tool.path }).xcodebuild == TestRunner().xcodebuild)
        #expect(TestRunnerSelection.runner(TestRunner(), preference: .swiftBuild, locate: { nil }).xcodebuild == TestRunner().xcodebuild)
        var stub = TestRunner()
        stub.xcodebuild = ["/bin/echo"]
        #expect(TestRunnerSelection.runner(stub, preference: .swiftBuild, locate: { tool.path }).xcodebuild == ["/bin/echo"])
    }

    @Test func swiftcodebuildSummaryFeedsCoveragePage() {
        let json = #"{"targets":[{"name":"App","coveredLines":3,"executableLines":4,"files":[{"path":"/x/A.swift","coveredLines":3,"executableLines":4}]}]}"#
        let items = CoverageModel.parseSwiftCodebuildSummary(Data(json.utf8))
        #expect(items.map(\.name) == ["App"] && items.first?.files.map(\.name) == ["A.swift"])
        #expect(CoverageModel.total(items) == 0.75)
    }
}
