import Foundation

extension DestinationCatalog {
    public static func simulatorsInMenuOrder(_ sims: [Destination]) -> [Destination] {
        func family(_ d: Destination) -> Int {
            if d.name.hasPrefix("iPhone") { return 0 }
            if d.name.hasPrefix("iPad") { return 1 }
            if d.name.hasPrefix("Apple Vision") { return 2 }
            return 3
        }
        return sims.sorted { a, b in
            let v = compareVersions(a.osVersion ?? "", b.osVersion ?? "")
            if v != .orderedSame { return v == .orderedDescending }
            let (fa, fb) = (family(a), family(b))
            if fa != fb { return fa < fb }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    public static func compareVersions(_ a: String, _ b: String) -> ComparisonResult {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }, pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    public static func defaultDestination(platform: String?, deploymentTarget: String?, simulators: [Destination],
                                          supportsMacOS: Bool = false, deviceFamilies: Set<String>? = nil,
                                          order: ([Destination]) -> [Destination] = simulatorsInMenuOrder) -> Destination {
        guard let platform, platform != "macOS", !supportsMacOS else { return .myMac }
        let candidates = order(simulators.filter { $0.platform == platform && $0.kind != .device && $0.kind != .mac }).filter { sim in
            if let families = deviceFamilies, let family = deviceFamily(of: sim), !families.contains(family) { return false }
            guard let target = deploymentTarget, !target.isEmpty, let v = sim.osVersion else { return true }
            return compareVersions(v, target) != .orderedAscending
        }
        let generations = candidates.map(proIPhoneGeneration(of:))
        if let newest = generations.compactMap({ $0 }).max(), let i = generations.firstIndex(of: newest) {
            return candidates[i]
        }
        return candidates.first ?? anySimulator(platform)
    }

    public static func deviceFamily(of d: Destination) -> String? {
        let words = [deviceTypeName(d.deviceType), d.deviceType == nil ? d.name : nil].compactMap { $0 }
        for w in words {
            for family in ["iPhone", "iPad", "Apple Vision"] where w.hasPrefix(family) { return family }
        }
        return nil
    }

    public static func proIPhoneGeneration(of d: Destination) -> Int? {
        var name = deviceTypeName(d.deviceType) ?? d.name
        if d.deviceType == nil, name.hasSuffix(")"), let open = name.range(of: " (", options: .backwards) {
            name = String(name[..<open.lowerBound])
        }
        let words = name.split(separator: " ")
        guard words.count == 3, words[0] == "iPhone", words[2] == "Pro", let n = Int(words[1]) else { return nil }
        return n
    }

    static func deviceTypeName(_ identifier: String?) -> String? {
        guard let identifier, let last = identifier.split(separator: ".").last else { return nil }
        return last.replacingOccurrences(of: "-", with: " ")
    }

    public static func deviceFamilies(targetedDeviceFamily value: String?) -> Set<String>? {
        let codes = (value ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        let names = Set(codes.compactMap { ["1": "iPhone", "2": "iPad"][$0] })
        return names.isEmpty ? nil : names
    }

    public static func anySimulator(_ platform: String) -> Destination {
        Destination(name: "Any \(platform) Simulator Device", specifier: "generic/platform=\(Destination.simulatorPlatform(platform))",
                    platform: platform, kind: .generic)
    }

    public static func deploymentTargetSetting(_ platform: String) -> String? {
        ["macOS": "MACOSX_DEPLOYMENT_TARGET", "iOS": "IPHONEOS_DEPLOYMENT_TARGET", "watchOS": "WATCHOS_DEPLOYMENT_TARGET",
         "tvOS": "TVOS_DEPLOYMENT_TARGET", "visionOS": "XROS_DEPLOYMENT_TARGET"][platform]
    }
}
