import Foundation
import SwiftCodeBuild
import SwiftCodeProject
import SwiftCodeWorkspace

public enum WatchCompanion {
    public static func targetName(scheme: String, schemes: [Scheme]) -> String {
        guard let s = schemes.first(where: { $0.name == scheme }) else { return scheme }
        return s.launchTarget?.blueprintName ?? s.buildEntries.first?.reference.blueprintName ?? scheme
    }

    static func target(named name: String, in proj: PBXProj) -> PBXObject? { proj.targets.first { $0.string("name") == name } }

    public static func platforms(ofTarget name: String, in proj: PBXProj) -> Set<String> {
        guard let t = target(named: name, in: proj) else { return [] }
        func value(_ listID: String?, _ key: String) -> String? {
            proj.buildConfigurations(listID: listID).lazy.compactMap { $0.attributes["buildSettings"]?.dictionary?[key]?.string }.first
        }
        let tl = t.string("buildConfigurationList"), pl = proj.project?.string("buildConfigurationList")
        return DestinationMenuModel.platforms(supportedPlatforms: value(tl, "SUPPORTED_PLATFORMS") ?? value(pl, "SUPPORTED_PLATFORMS"),
                                              sdkroot: value(tl, "SDKROOT") ?? value(pl, "SDKROOT"))
    }

    public static func deploymentTarget(ofTarget name: String, platform: String, in proj: PBXProj) -> String? {
        guard let t = target(named: name, in: proj), let key = DestinationCatalog.deploymentTargetSetting(platform) else { return nil }
        func value(_ listID: String?) -> String? {
            proj.buildConfigurations(listID: listID).lazy.compactMap { $0.attributes["buildSettings"]?.dictionary?[key]?.string }.first
        }
        return value(t.string("buildConfigurationList")) ?? value(proj.project?.string("buildConfigurationList"))
    }

    public static func companionTargets(of watchTarget: String, in proj: PBXProj) -> [String] {
        guard let watch = target(named: watchTarget, in: proj) else { return [] }
        let product = watch.string("productReference")
        return proj.targets.compactMap { t -> String? in
            guard t.id != watch.id, t.string("productType") == "com.apple.product-type.application" else { return nil }
            let depends = t.references("dependencies").contains { proj[$0]?.string("target") == watch.id }
            let copies = t.references("buildPhases").contains { id in
                guard let phase = proj[id], phase.isa == "PBXCopyFilesBuildPhase",
                      (phase.string("dstPath") ?? "").hasSuffix("/Watch") else { return false }
                return phase.references("files").contains { proj[$0]?.string("fileRef") == product }
            }
            return depends && copies ? t.string("name") : nil
        }
    }

    public static func scheme(forTarget name: String, schemes: [Scheme]) -> String {
        schemes.first { $0.launchTarget?.blueprintName == name }?.name
            ?? schemes.first { $0.buildEntries.contains { $0.reference.blueprintName == name } && $0.buildEntries.count == 1 }?.name
            ?? name
    }

    public static func companionScheme(watchScheme: String, projects: [PBXProj], schemes: [Scheme]) -> String? {
        let name = targetName(scheme: watchScheme, schemes: schemes)
        for proj in projects {
            if let c = companionTargets(of: name, in: proj).first { return scheme(forTarget: c, schemes: schemes) }
        }
        return nil
    }
}

extension WorkspaceModel {
    public func companionScheme(watchScheme: String) -> String? {
        WatchCompanion.companionScheme(watchScheme: watchScheme, projects: projects.keys.sorted().compactMap { projects[$0] }, schemes: loadSchemes())
    }

    public func platforms(scheme: String) -> Set<String> {
        let name = WatchCompanion.targetName(scheme: scheme, schemes: loadSchemes())
        for key in projects.keys.sorted() {
            let p = WatchCompanion.platforms(ofTarget: name, in: projects[key]!)
            if !p.isEmpty { return p }
        }
        return []
    }
}
