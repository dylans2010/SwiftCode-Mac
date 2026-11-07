import Foundation
import Testing
import YcodeBuild
@testable import YcodeIDECore
import YcodeProject

private let swiftcodeDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

@Suite(.serialized, .heavyIntegration, .timeLimit(.minutes(5))) struct SigningBuildTests {
    @Test func ideBuildsSignTheirEntitlements() async throws {
        #if os(macOS)
        let probe = swiftcodeDir.appendingPathComponent("Tools/swiftcode-swb/.build/debug/swbuild").path
        guard let tool = SwiftBuildEngine.locate() ?? (FileManager.default.isExecutableFile(atPath: probe) ? probe : nil),
              SwiftBuildEngine.locateHelper(swbuild: tool) != nil else { return }
        let dir = swiftcodeDir.appendingPathComponent(".build-ide/signing-build")
        try? FileManager.default.removeItem(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = try ProjectTemplate.app.create(name: "Signed", organization: "org.swiftcode.tests", in: dir)
        var model = ProjectEditorModel(proj: try PBXProj(contentsOf: url), xcodeprojURL: url)
        try model.addCapability(.outgoingNetwork, target: "Signed", configuration: "Debug")
        try model.proj.serialized(projectName: "Signed").write(to: url.appendingPathComponent("project.pbxproj"), atomically: true, encoding: .utf8)
        let entitlementsFile = try #require(model.entitlementsURL(target: "Signed", configuration: "Debug"))
        var ents = try PropertyListSerialization.propertyList(from: Data(contentsOf: entitlementsFile), format: nil) as! [String: Any]
        ents["com.apple.security.application-groups"] = ["$(PRODUCT_BUNDLE_IDENTIFIER).shared"]
        try PropertyListSerialization.data(fromPropertyList: ents, format: .xml, options: 0).write(to: entitlementsFile)

        let engine = BuildSystemPreference.swiftBuild.makeEngine { tool }
        let req = BuildRequest(container: .project(url.path), scheme: "Signed", destination: "platform=macOS",
                               derivedDataPath: dir.appendingPathComponent("dd").path)
        let r = await engine.start(req).run()
        #expect(r.status == .succeeded, "\(r.issues)")
        let exe = try #require(engine.executablePath(for: req))
        let app = URL(fileURLWithPath: exe).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let signed = try signedEntitlements(app.path)
        #expect(signed["com.apple.security.app-sandbox"] as? Bool == true)
        #expect(signed["com.apple.security.network.client"] as? Bool == true)
        #expect(signed["com.apple.security.get-task-allow"] as? Bool == true)
        #expect(signed["com.apple.security.application-groups"] as? [String] == ["org.swiftcode.tests.Signed.shared"])
        #expect(signed["com.apple.application-identifier"] == nil)
        #endif
    }

    func signedEntitlements(_ path: String) throws -> [String: Any] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        p.arguments = ["-d", "--entitlements", ":-", path]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        try p.run()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]) ?? [:]
    }
}
