import Foundation
import Testing
import YcodeBuild
@testable import YcodeIDECore

private let swiftcodeDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@MainActor
@Suite(.serialized) struct ToolbarIssuesR39R41Tests {
    func scratch(_ name: String) -> URL {
        swiftcodeDir.appendingPathComponent(".build-ide/r39/\(name)-\(UUID().uuidString)")
    }

    @Test func packageIssuesGroupByPackageTarget() throws {
        let dir = scratch("n1-pkg")
        defer { try? FileManager.default.removeItem(at: dir) }
        let fm = FileManager.default
        for t in ["Sources/Kit", "Sources/Tool", "Tests/KitTests"] {
            try fm.createDirectory(at: dir.appendingPathComponent(t), withIntermediateDirectories: true)
        }
        try "// swift-tools-version: 6.0\nimport PackageDescription\nlet package = Package(name: \"Kit\")\n"
            .write(to: dir.appendingPathComponent("Package.swift"), atomically: true, encoding: .utf8)
        let session = WorkspaceSession(model: try WorkspaceModel(url: dir))
        let g = session.issueGrouping
        #expect(g.projectName == dir.lastPathComponent && g.targetOrder == ["Kit", "Tool", "KitTests"])
        #expect(g.targetsOfFile(dir.appendingPathComponent("Tests/KitTests/KitTests.swift").path) == ["KitTests"])
        #expect(g.targetsOfFile(dir.appendingPathComponent("Package.swift").path).isEmpty)
    }

    @Test func toolbarFitSteps() {
        let steps = ToolbarFit.steps(activityNatural: 150)
        #expect(steps.first == ToolbarFit())
        #expect(steps[1] == ToolbarFit(schemeGlyphsOnly: true))
        #expect(steps[2] == ToolbarFit(editorModesInOverflow: true, schemeGlyphsOnly: true))
        let caps = steps.compactMap(\.activityWidth)
        #expect(!caps.isEmpty && caps.first! < 150 && caps == caps.sorted(by: >) && caps.last == ToolbarFit.activityMinimum)
        #expect(steps.dropFirst(2).allSatisfy { $0.schemeGlyphsOnly && $0.editorModesInOverflow })
        #expect(ToolbarFit.steps(activityNatural: 60).count == 3)
        #expect(!ToolbarFit().accepts(overflowed: ["editorModes"]) && ToolbarFit().accepts(overflowed: []))
        #expect(!steps[1].accepts(overflowed: ["editorModes"]))
        #expect(steps[2].accepts(overflowed: ["editorModes"]) && !steps[2].accepts(overflowed: ["editorModes", "history"]))
    }
}
