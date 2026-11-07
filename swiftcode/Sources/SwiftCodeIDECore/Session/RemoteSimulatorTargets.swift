import Foundation
import SwiftCodeBuild

public struct SwiftCodeSimulatorDeviceType: Equatable, Sendable {
    public let id: String
    public let name: String
    public let minRuntimeVersion: String
    public var platform = "iOS"
    public var newestDefaultRuntimeVersion: String?

    public init(id: String, name: String, minRuntimeVersion: String) {
        self.id = id
        self.name = name
        self.minRuntimeVersion = minRuntimeVersion
    }

    static func watch(_ id: String, _ name: String, _ min: String, through newest: String? = nil) -> SwiftCodeSimulatorDeviceType {
        var t = SwiftCodeSimulatorDeviceType(id: id, name: name, minRuntimeVersion: min)
        t.platform = "watchOS"
        t.newestDefaultRuntimeVersion = newest
        return t
    }

    public static let watches: [SwiftCodeSimulatorDeviceType] = [
        watch("apple-watch-series-12-46mm", "Apple Watch Series 12 (46mm)", "27.0"),
        watch("apple-watch-series-12-42mm", "Apple Watch Series 12 (42mm)", "27.0"),
        watch("apple-watch-ultra-4-49mm", "Apple Watch Ultra 4 (49mm)", "27.0"),
        watch("apple-watch-series-11-46mm", "Apple Watch Series 11 (46mm)", "26.0", through: "26.99"),
        watch("apple-watch-series-11-42mm", "Apple Watch Series 11 (42mm)", "26.0", through: "26.99"),
        watch("apple-watch-series-10-46mm", "Apple Watch Series 10 (46mm)", "11.0", through: "11.99"),
        watch("apple-watch-series-10-42mm", "Apple Watch Series 10 (42mm)", "11.0", through: "11.99"),
        watch("apple-watch-series-9-45mm", "Apple Watch Series 9 (45mm)", "10.0", through: "10.99"),
        watch("apple-watch-series-9-41mm", "Apple Watch Series 9 (41mm)", "10.0", through: "10.99"),
        watch("apple-watch-ultra-3-49mm", "Apple Watch Ultra 3 (49mm)", "26.0", through: "26.99"),
        watch("apple-watch-ultra-2-49mm", "Apple Watch Ultra 2 (49mm)", "10.0", through: "11.99"),
        watch("apple-watch-se-3-44mm", "Apple Watch SE 3 (44mm)", "26.0"),
        watch("apple-watch-se-3-40mm", "Apple Watch SE 3 (40mm)", "26.0"),
    ]

    public static func watches(onRuntimeVersion version: String?) -> [SwiftCodeSimulatorDeviceType] {
        let v = (version?.isEmpty ?? true) ? watches[0].minRuntimeVersion : version!
        return watches.filter { t in
            t.runs(onRuntimeVersion: v)
                && t.newestDefaultRuntimeVersion.map { DestinationCatalog.compareVersions(v, $0) != .orderedDescending } ?? true
        }
    }

    public static let iPhoneDuo = SwiftCodeSimulatorDeviceType(id: "iphone-duo", name: "iPhone Duo", minRuntimeVersion: "27.1")
    public static let iPhone18Pro = SwiftCodeSimulatorDeviceType(id: "iphone-18-pro", name: "iPhone 18 Pro", minRuntimeVersion: "27.0")
    public static let iPadA16 = SwiftCodeSimulatorDeviceType(id: "ipad-a16", name: "iPad (A16)", minRuntimeVersion: "18.3")
    public static let iPadPro13M5 = SwiftCodeSimulatorDeviceType(id: "ipad-pro-13-m5", name: "iPad Pro 13-inch (M5)", minRuntimeVersion: "26.0")

    public static let all: [SwiftCodeSimulatorDeviceType] = [iPhoneDuo, iPhone18Pro, iPadA16, iPadPro13M5]
    static let phones: [SwiftCodeSimulatorDeviceType] = [iPhoneDuo, iPhone18Pro]

    public static let simdDefault = iPhoneDuo

    public static let visionPro: SwiftCodeSimulatorDeviceType = {
        var t = SwiftCodeSimulatorDeviceType(id: "vision-pro", name: "Apple Vision Pro", minRuntimeVersion: "1.0")
        t.platform = "visionOS"
        return t
    }()

    public static func visions(onRuntimeVersion version: String?) -> [SwiftCodeSimulatorDeviceType] {
        [visionPro].filter { $0.runs(onRuntimeVersion: version) }
    }

    public static func named(_ id: String) -> SwiftCodeSimulatorDeviceType? { (all + watches + [visionPro]).first { $0.id == id } }

    public var isFoldable: Bool { id == Self.iPhoneDuo.id }

    public func runs(onRuntimeVersion version: String?) -> Bool {
        guard let version, !version.isEmpty else { return true }
        return DestinationCatalog.compareVersions(version, minRuntimeVersion) != .orderedAscending
    }

    public static func supported(onRuntimeVersion version: String?) -> [SwiftCodeSimulatorDeviceType] {
        guard let version, !version.isEmpty else { return all }
        let phone = phones.first { $0.runs(onRuntimeVersion: version) }
        return all.filter { $0.runs(onRuntimeVersion: version) && (!phones.contains($0) || $0 == phone) }
    }
}

public struct RemoteSimulatorTarget: Equatable, Sendable {
    public var runtimeRoot: String
    public var runtimeVersion: String?
    public var deviceType: SwiftCodeSimulatorDeviceType
    public var deviceDirectoryName: String
    public var isPrimary: Bool
    public var customName: String?

    package init(runtimeRoot: String, runtimeVersion: String? = nil, deviceType: SwiftCodeSimulatorDeviceType, deviceDirectoryName: String, isPrimary: Bool,
                 customName: String? = nil) {
        self.runtimeRoot = runtimeRoot
        self.runtimeVersion = runtimeVersion
        self.deviceType = deviceType
        self.deviceDirectoryName = deviceDirectoryName
        self.isPrimary = isPrimary
        self.customName = customName
    }

    public var isWatch: Bool { deviceType.platform == "watchOS" }

    public var isVision: Bool { deviceType.platform == "visionOS" }

    public var isCreated: Bool { customName != nil }

    public var identifier: String {
        if isPrimary { return RemoteSimulator.identifier }
        if isCreated { return "\(RemoteSimulator.identifier):device:\(deviceDirectoryName)" }
        return "\(RemoteSimulator.identifier):\(deviceType.id)@\(runtimeRoot)"
    }

    public var name: String { customName ?? "\(deviceType.name) (SwiftCode)" }

    public var destination: Destination {
        var d = RemoteSimulator.destination
        d.name = name
        d.identifier = identifier
        d.osVersion = runtimeVersion
        if isWatch {
            d.platform = "watchOS"
            d.specifier = "generic/platform=watchOS Simulator"
        } else if isVision {
            d.platform = "visionOS"
            d.specifier = "generic/platform=visionOS Simulator"
        }
        return d
    }

    public var deviceTypeArguments: [String] {
        deviceType == SwiftCodeSimulatorDeviceType.simdDefault ? [] : ["--device-type", deviceType.id]
    }

    package static func runtimeTag(root: String, version: String?) -> String {
        if let version, !version.isEmpty { return version }
        let comps = root.split(separator: "/").map(String.init).filter { $0 != "RuntimeRoot" && !$0.isEmpty }
        let base = comps.last ?? "runtime"
        return String(base.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? $0 : "-" })
    }
}

extension RemoteSimulatorSettings {
    public static let runtimesHelp = "More simulator runtimes on the host, separated by commas. Each runtime adds a run destination for every device type it supports (for example iOS 27.0 with iPads and its full app set). Every runtime and device type has its own device, so data and saved state are kept apart."

    public var allRuntimeRoots: [String] {
        var seen = Set<String>(), out: [String] = []
        for r in [runtimeRoot] + otherRuntimeRoots {
            let t = r.trimmingCharacters(in: .whitespaces)
            if !t.isEmpty, seen.insert(t).inserted { out.append(t) }
        }
        return out
    }

    public static func runtimeRoots(fromText text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0.isNewline }).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    public func runtimeVersion(forRoot root: String) -> String? {
        if root == runtimeRoot, let runtimeVersion { return runtimeVersion }
        return runtimeVersions[root] ?? Self.version(inPath: root)
    }

    public func runtimePlatform(forRoot root: String) -> String {
        if let p = runtimePlatforms[root] { return p }
        let name = Self.runtimeName(inPath: root)
        if name.range(of: "watchOS", options: .caseInsensitive) != nil { return "watchOS" }
        if name.range(of: "xrOS", options: .caseInsensitive) != nil || name.range(of: "visionOS", options: .caseInsensitive) != nil { return "visionOS" }
        return "iOS"
    }

    static func runtimeName(inPath root: String) -> String {
        var comps = root.split(separator: "/").map(String.init)
        while let last = comps.last, ["RuntimeRoot", "Resources", "Contents"].contains(last) { comps.removeLast() }
        return comps.last ?? ""
    }

    public var targets: [RemoteSimulatorTarget] { iOSTargets + createdTargets.filter { !$0.isWatch && !$0.isVision } }

    public var createdTargets: [RemoteSimulatorTarget] {
        let roots = Set(allRuntimeRoots)
        return createdDevices.compactMap { c in
            guard roots.contains(c.runtimeRoot), let type = SwiftCodeSimulatorDeviceType.named(c.typeID) else { return nil }
            let version = runtimeVersion(forRoot: c.runtimeRoot)
            guard runtimePlatform(forRoot: c.runtimeRoot) == type.platform, type.runs(onRuntimeVersion: version) else { return nil }
            return RemoteSimulatorTarget(runtimeRoot: c.runtimeRoot, runtimeVersion: version, deviceType: type,
                                         deviceDirectoryName: c.directoryName, isPrimary: false, customName: c.name)
        }
    }

    private var iOSTargets: [RemoteSimulatorTarget] {
        var out: [RemoteSimulatorTarget] = []
        for (i, root) in allRuntimeRoots.enumerated() where runtimePlatform(forRoot: root) == "iOS" {
            let version = runtimeVersion(forRoot: root)
            for (j, type) in SwiftCodeSimulatorDeviceType.supported(onRuntimeVersion: version).enumerated() {
                let primary = i == 0 && j == 0 && type == .simdDefault
                let dir = primary ? deviceName : "\(deviceName)-\(type.id)-\(RemoteSimulatorTarget.runtimeTag(root: root, version: version))"
                out.append(RemoteSimulatorTarget(runtimeRoot: root, runtimeVersion: version, deviceType: type,
                                                 deviceDirectoryName: dir, isPrimary: primary))
            }
        }
        return out
    }

    public var hubTargets: [RemoteSimulatorTarget] { targets + watchTargets + visionTargets }

    public var visionTargets: [RemoteSimulatorTarget] {
        var out: [RemoteSimulatorTarget] = []
        for root in allRuntimeRoots where runtimePlatform(forRoot: root) == "visionOS" {
            let version = runtimeVersion(forRoot: root)
            for type in SwiftCodeSimulatorDeviceType.visions(onRuntimeVersion: version) {
                let dir = "\(deviceName)-\(type.id)-\(RemoteSimulatorTarget.runtimeTag(root: root, version: version))"
                out.append(RemoteSimulatorTarget(runtimeRoot: root, runtimeVersion: version, deviceType: type,
                                                 deviceDirectoryName: dir, isPrimary: false))
            }
        }
        return out + createdTargets.filter(\.isVision)
    }

    public var watchTargets: [RemoteSimulatorTarget] {
        var out: [RemoteSimulatorTarget] = []
        for root in allRuntimeRoots where runtimePlatform(forRoot: root) == "watchOS" {
            let version = runtimeVersion(forRoot: root)
            for type in SwiftCodeSimulatorDeviceType.watches(onRuntimeVersion: version) {
                let dir = "\(deviceName)-\(type.id)-\(RemoteSimulatorTarget.runtimeTag(root: root, version: version))"
                out.append(RemoteSimulatorTarget(runtimeRoot: root, runtimeVersion: version, deviceType: type,
                                                 deviceDirectoryName: dir, isPrimary: false))
            }
        }
        return out + createdTargets.filter(\.isWatch)
    }

    public func target(for destination: Destination?) -> RemoteSimulatorTarget? {
        let all = hubTargets
        if let id = destination?.identifier {
            if let t = all.first(where: { $0.identifier == id }) { return t }
            if let dir = RemotePairedDestination.phoneDirectory(identifier: id), let t = all.first(where: { $0.deviceDirectoryName == dir }) { return t }
        }
        return targets.first
    }

    public func target(directory: String) -> RemoteSimulatorTarget? { hubTargets.first { $0.deviceDirectoryName == directory } }
}
