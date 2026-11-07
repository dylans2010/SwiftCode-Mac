import Foundation
import SwiftCodeBuild
import SwiftCodePlist
import SwiftCodeProject
import SwiftCodeXcodebuild

public enum DefaultsLevel {
    static let kept: Set<String> = ["SDKROOT", "SUPPORTED_PLATFORMS"]

    public static func stripped(_ proj: PBXProj) -> PBXProj {
        var p = proj
        for (id, var obj) in p.objects where obj.isa == "XCBuildConfiguration" {
            var keep = PlistDictionary()
            for (k, v) in obj["buildSettings"]?.dictionary ?? PlistDictionary() where kept.contains(k) { keep[k] = v }
            obj["buildSettings"] = .dictionary(keep)
            for k in ["baseConfigurationReference", "baseConfigurationReferenceAnchor", "baseConfigurationReferenceRelativePath"] { obj[k] = nil }
            p[id] = obj
        }
        return p
    }

    public static func swiftBuildDefaults(proj: PBXProj, xcodeprojURL: URL, target: String?, configuration: String,
                                          helper: String) throws -> [String: String] {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-defaults-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }
        let copy = work.appendingPathComponent(xcodeprojURL.lastPathComponent)
        try FileManager.default.createDirectory(at: copy, withIntermediateDirectories: true)
        let name = xcodeprojURL.deletingPathExtension().lastPathComponent
        try stripped(proj).serialized(projectName: name).write(to: copy.appendingPathComponent("project.pbxproj"), atomically: true, encoding: .utf8)
        let targetName = target ?? proj.targets.first?.string("name")
        let all = try SwiftBuildSettingsSource(helper: helper).buildSettings(
            for: BuildRequest(container: .project(copy.path), scheme: targetName, configuration: configuration))
        guard let s = all.first(where: { $0.target == targetName })?.settings ?? all.first?.settings else { return [:] }
        let fake = work.standardizedFileURL.path, real = xcodeprojURL.deletingLastPathComponent().standardizedFileURL.path
        let resolvedFake = work.resolvingSymlinksInPath().path
        return s.mapValues { $0.replacingOccurrences(of: resolvedFake, with: real).replacingOccurrences(of: fake, with: real) }
    }
}
