import Foundation
import SwiftCodeBuild
import SwiftCodeProject

public struct DestinationMenuModel: Equatable, Sendable {
    public struct Section: Equatable, Sendable {
        public var title: String
        public var destinations: [Destination]
    }
    public var sections: [Section]
    public var incompatible: [Destination]

    public static let manageDevicesTitle = "Manage Devices…"
    public static let incompatibleTitle = "Incompatible"
    public static let showAllTitle = "Show All Run Destinations"
    public static let mismatchedPlatform = "mismatched platform"
    public static let osTooOld = "OS version lower than deployment target"

    public init(current: Destination?, devices: [Destination], simulators: [Destination],
                platforms: Set<String>, designedForIPad: Bool = false, deploymentTargets: [String: String] = [:], filter: String = "") {
        let ipadOnVision = designedForIPad && !platforms.contains("visionOS")
        func platformOK(_ d: Destination) -> Bool {
            platforms.isEmpty || platforms.contains(d.platform) || (ipadOnVision && d.platform == "visionOS")
        }
        func tooOld(_ d: Destination) -> Bool {
            guard let target = deploymentTargets[d.platform], !target.isEmpty, let v = d.osVersion else { return false }
            return DestinationCatalog.compareVersions(v, target) == .orderedAscending
        }
        func ok(_ d: Destination) -> Bool { platformOK(d) && !tooOld(d) }
        let f = filter.trimmingCharacters(in: .whitespaces)
        func match(_ d: Destination) -> Bool { f.isEmpty || d.name.localizedCaseInsensitiveContains(f) }
        var mac = Destination.myMac
        if designedForIPad && !platforms.contains("macOS") {
            mac.name = "My Mac (Designed for iPad)"
        }
        let macOK = platforms.isEmpty || platforms.contains("macOS") || designedForIPad
        let devs = devices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let sims = Self.orderedSimulators(simulators)
        var build: [Destination] = []
        for p in ["macOS", "iOS", "watchOS", "tvOS", "visionOS"] where !platforms.isEmpty && platforms.contains(p) {
            if p == "macOS" { build.append(.anyMac); continue }
            build.append(Destination(name: "Any \(p) Device (arm64)", specifier: "generic/platform=\(p)", platform: p, kind: .generic))
            build.append(Destination(name: "Any \(p) Simulator Device (arm64, x86_64)",
                                     specifier: "generic/platform=\(p) Simulator", platform: p, kind: .generic))
        }
        func titled(_ d: Destination) -> Destination {
            guard ipadOnVision, d.platform == "visionOS", d.kind == .simulator, let v = d.osVersion else { return d }
            var d = d
            d.name = "\(d.name) (Designed for iPad, \(v))"
            return d
        }
        var s: [Section] = []
        if let current, match(current) { s.append(Section(title: "Recent", destinations: [current])) }
        let devRows = ((macOK ? [mac] : []) + devs.filter(ok)).filter(match)
        if !devRows.isEmpty { s.append(Section(title: "Devices", destinations: devRows)) }
        let simRows = sims.filter(ok).map(titled).filter(match)
        if !simRows.isEmpty { s.append(Section(title: "Simulators", destinations: simRows)) }
        let buildRows = build.filter(match)
        if !buildRows.isEmpty { s.append(Section(title: "Build", destinations: buildRows)) }
        sections = s
        let runtimes = Dictionary(grouping: simulators, by: \.name).mapValues { Set($0.compactMap(\.osVersion)).count }
        func incompatibleRow(_ d: Destination) -> Destination {
            var d = d
            let reason = platformOK(d) ? Self.osTooOld : Self.mismatchedPlatform
            let runtime = d.kind == .simulator && runtimes[d.name, default: 0] > 1 ? d.osVersion.map { " (\($0))" } ?? "" : ""
            d.name = "\(d.name)\(runtime) (\(reason))"
            return d
        }
        incompatible = ((macOK ? [] : [mac]) + devs.filter { !ok($0) } + sims.filter { !ok($0) }).filter(match).map(incompatibleRow)
    }

    public func rows(_ label: String) -> [Destination] {
        sections.first { $0.title == label }?.destinations ?? []
    }

    public var selectable: [Destination] {
        sections.filter { $0.title != "Recent" }.flatMap(\.destinations)
    }

    public static func submenuTitle(_ d: Destination) -> String {
        d.osVersion.map { "\(d.name) \($0)" } ?? d.name
    }

    public static func orderedSimulators(_ sims: [Destination]) -> [Destination] {
        let newest = sims.compactMap(\.osVersion).max { DestinationCatalog.compareVersions($0, $1) == .orderedAscending }
        let unversioned = sims.indices.filter { sims[$0].isSwiftCodeRemoteSimulator && sims[$0].osVersion == nil }
        guard !unversioned.isEmpty, let newest else { return DestinationCatalog.simulatorsInMenuOrder(sims) }
        var keyed = sims
        for i in unversioned { keyed[i].osVersion = newest }
        let unknown = Set(unversioned.compactMap { sims[$0].identifier })
        return DestinationCatalog.simulatorsInMenuOrder(keyed).map { d in
            guard d.isSwiftCodeRemoteSimulator, let id = d.identifier, unknown.contains(id) else { return d }
            var o = d
            o.osVersion = nil
            return o
        }
    }

    public static func platforms(supportedPlatforms: String?, sdkroot: String?) -> Set<String> {
        let names = ["macosx": "macOS", "iphoneos": "iOS", "iphonesimulator": "iOS", "watchos": "watchOS",
                     "watchsimulator": "watchOS", "appletvos": "tvOS", "appletvsimulator": "tvOS",
                     "xros": "visionOS", "xrsimulator": "visionOS"]
        let words = (supportedPlatforms ?? sdkroot ?? "").split(separator: " ").map(String.init)
        return Set(words.compactMap { names[$0] })
    }

    public static func platforms(of proj: PBXProj) -> (platforms: Set<String>, designedForIPad: Bool) {
        func value(_ listID: String?, _ key: String) -> String? {
            proj.buildConfigurations(listID: listID).lazy.compactMap { $0.attributes["buildSettings"]?.dictionary?[key]?.string }.first
        }
        let target = proj.targets.first
        let tl = target?.string("buildConfigurationList"), pl = proj.project?.string("buildConfigurationList")
        let p = platforms(supportedPlatforms: value(tl, "SUPPORTED_PLATFORMS") ?? value(pl, "SUPPORTED_PLATFORMS"),
                          sdkroot: value(tl, "SDKROOT") ?? value(pl, "SDKROOT"))
        let isApp = target?.string("productType") == "com.apple.product-type.application"
        return (p, isApp && p.contains("iOS"))
    }

    public static func productPlatform(of proj: PBXProj) -> (platform: String?, deploymentTarget: String?) {
        func value(_ listID: String?, _ key: String) -> String? {
            proj.buildConfigurations(listID: listID).lazy.compactMap { $0.attributes["buildSettings"]?.dictionary?[key]?.string }.first
        }
        let tl = proj.targets.first?.string("buildConfigurationList"), pl = proj.project?.string("buildConfigurationList")
        func setting(_ key: String) -> String? { value(tl, key) ?? value(pl, key) }
        let fromSDK = platforms(supportedPlatforms: nil, sdkroot: setting("SDKROOT")).first
        let supported = platforms(supportedPlatforms: setting("SUPPORTED_PLATFORMS"), sdkroot: nil)
        let platform = fromSDK ?? (supported.contains("iOS") ? "iOS" : supported.contains("macOS") ? "macOS"
            : ["watchOS", "tvOS", "visionOS"].first(where: supported.contains))
        let target = platform.flatMap(DestinationCatalog.deploymentTargetSetting).flatMap(setting)
        return (platform, target)
    }

    public static func defaultDestinationTraits(of proj: PBXProj) -> (supportsMacOS: Bool, deviceFamilies: Set<String>?) {
        func value(_ listID: String?, _ key: String) -> String? {
            proj.buildConfigurations(listID: listID).lazy.compactMap { $0.attributes["buildSettings"]?.dictionary?[key]?.string }.first
        }
        let tl = proj.targets.first?.string("buildConfigurationList"), pl = proj.project?.string("buildConfigurationList")
        let families = DestinationCatalog.deviceFamilies(targetedDeviceFamily: value(tl, "TARGETED_DEVICE_FAMILY") ?? value(pl, "TARGETED_DEVICE_FAMILY"))
        return (platforms(of: proj).platforms.contains("macOS"), families)
    }
}
