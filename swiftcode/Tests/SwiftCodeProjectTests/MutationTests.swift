import Foundation
import Testing
import SwiftCodePlist
@testable import SwiftCodeProject

@Suite struct MutationTests {
    func fixture() throws -> (text: String, proj: PBXProj) {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/Hello.xcodeproj/project", withExtension: "pbxproj"))
        let text = try String(contentsOf: url, encoding: .utf8)
        return (text, try PBXProj(parsing: text))
    }

    func addedLines(_ a: String, _ b: String) -> [String] {
        var pool = a.components(separatedBy: "\n")
        return b.components(separatedBy: "\n").filter { line in
            if let i = pool.firstIndex(of: line) { pool.remove(at: i); return false }
            return true
        }
    }

    @Test func buildSettingEditsAreLocal() throws {
        var (text, proj) = try fixture()
        let target = try #require(proj.targets.first)
        proj.setBuildSetting("MARKETING_VERSION", "2.0", inListOf: target.id)
        let edited = proj.serialized(projectName: "Hello")
        let added = addedLines(text, edited)
        #expect(added.count == 2 && added.allSatisfy { $0.contains("MARKETING_VERSION = 2.0;") })
        #expect(addedLines(edited, text).allSatisfy { $0.contains("MARKETING_VERSION") })
        let again = try PBXProj(parsing: edited)
        let configs = again.buildConfigurations(listID: again.targets[0].string("buildConfigurationList"))
        #expect(configs.allSatisfy { $0["buildSettings"]?.dictionary?["MARKETING_VERSION"]?.string == "2.0" })
        proj.setBuildSetting("SWIFTCODE_TEMP", "1", inListOf: target.id)
        proj.setBuildSetting("SWIFTCODE_TEMP", nil, inListOf: target.id)
        #expect(proj.serialized(projectName: "Hello") == edited)
    }

    @Test func addAndRemoveFiles() throws {
        var (text, proj) = try fixture()
        let main = try #require(proj.project?.string("mainGroup"))
        let target = try #require(proj.targets.first)
        let sources = try #require(proj.buildPhases(ofTarget: target.id).first { $0.isa == "PBXSourcesBuildPhase" })
        let ref = proj.addFileReference(path: "Extra.swift", to: main)
        let bf = proj.addBuildFile(fileReference: ref, to: sources.id)
        #expect(ref.count == 24 && ref.allSatisfy(\.isHexDigit) && ref != bf)
        let edited = proj.serialized(projectName: "Hello")
        #expect(edited.contains("/* Extra.swift in Sources */") && edited.contains("lastKnownFileType = sourcecode.swift; path = Extra.swift;"))
        let again = try PBXProj(parsing: edited)
        #expect(again.fileReference(ofBuildFile: bf)?.string("path") == "Extra.swift")
        proj.removeBuildFile(bf)
        #expect(!proj.serialized(projectName: "Hello").contains("Extra.swift in Sources"))
        proj.removeFileReference(ref)
        #expect(proj.serialized(projectName: "Hello") == text)
        let r2 = proj.addFileReference(path: "Two.swift", to: main)
        proj.addBuildFile(fileReference: r2, to: sources.id)
        proj.removeFileReference(r2)
        #expect(proj.serialized(projectName: "Hello") == text)
    }

    @Test func fileTypes() {
        #expect(PBXProj.fileType(forPath: "a.swift") == "sourcecode.swift")
        #expect(PBXProj.fileType(forPath: "Info.plist") == "text.plist.xml")
        #expect(PBXProj.fileType(forPath: "x.unknown") == "text")
    }
}
