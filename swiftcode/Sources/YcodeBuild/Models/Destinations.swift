import Foundation
import YcodeSubprocess

public struct Destination: Equatable, Sendable, Hashable {
    public enum Kind: String, Sendable, Hashable {
        case mac, device, simulator
        case generic
    }

    public var name: String
    public var specifier: String
    public var platform: String
    public var kind: Kind
    public var osVersion: String?
    public var identifier: String?
    public var deviceType: String?

    public init(name: String, specifier: String, platform: String, kind: Kind, osVersion: String? = nil, identifier: String? = nil,
                deviceType: String? = nil) {
        self.name = name
        self.specifier = specifier
        self.platform = platform
        self.kind = kind
        self.osVersion = osVersion
        self.identifier = identifier
        self.deviceType = deviceType
    }

    public static let myMac = Destination(name: "My Mac", specifier: "platform=macOS", platform: "macOS", kind: .mac)
    public static let anyMac = Destination(name: "Any Mac", specifier: "generic/platform=macOS", platform: "macOS", kind: .generic)

    static func simulatorPlatform(_ p: String) -> String { "\(p) Simulator" }
}

public struct DestinationGroup: Equatable, Sendable {
    public var title: String
    public var destinations: [Destination]
    public init(title: String, destinations: [Destination]) {
        self.title = title
        self.destinations = destinations
    }
}

public enum DestinationCatalog {
    static let platformOrder = ["macOS", "iOS", "watchOS", "tvOS", "visionOS"]
    static let runtimePlatforms = ["iOS": "iOS", "watchOS": "watchOS", "tvOS": "tvOS", "xrOS": "visionOS", "visionOS": "visionOS"]

    public static func simulators(fromSimctlJSON data: Data) -> [Destination] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let byRuntime = root["devices"] as? [String: [[String: Any]]] else { return [] }
        var out: [Destination] = []
        for (runtime, devices) in byRuntime {
            let tail = runtime.split(separator: ".").last.map(String.init) ?? runtime
            let parts = tail.split(separator: "-").map(String.init)
            guard let first = parts.first, let platform = runtimePlatforms[first] else { continue }
            let version = parts.dropFirst().joined(separator: ".")
            for d in devices where (d["isAvailable"] as? Bool) ?? true {
                guard let name = d["name"] as? String, let udid = d["udid"] as? String else { continue }
                out.append(Destination(name: name, specifier: "platform=\(Destination.simulatorPlatform(platform)),id=\(udid)",
                                       platform: platform, kind: .simulator, osVersion: version.isEmpty ? nil : version, identifier: udid,
                                       deviceType: d["deviceTypeIdentifier"] as? String))
            }
        }
        return out
    }

    public static func devices(fromDevicectlJSON data: Data) -> [Destination] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = (root["result"] as? [String: Any])?["devices"] as? [[String: Any]] else { return [] }
        return list.compactMap { d in
            let hw = d["hardwareProperties"] as? [String: Any] ?? [:]
            let props = d["deviceProperties"] as? [String: Any] ?? [:]
            guard (hw["reality"] as? String) == "physical",
                  let platform = hw["platform"] as? String, let udid = hw["udid"] as? String,
                  let name = props["name"] as? String else { return nil }
            return Destination(name: name, specifier: "platform=\(platform),id=\(udid)", platform: platform, kind: .device,
                               osVersion: props["osVersionNumber"] as? String, identifier: udid)
        }
    }

    public static func groups(devices: [Destination], simulators: [Destination]) -> [DestinationGroup] {
        var groups = [DestinationGroup(title: "My Mac", destinations: [.myMac]),
                      DestinationGroup(title: "Build", destinations: [.anyMac])]
        let platforms = Set(devices.map(\.platform) + simulators.map(\.platform))
            .sorted { (platformOrder.firstIndex(of: $0) ?? 99, $0) < (platformOrder.firstIndex(of: $1) ?? 99, $1) }
        for p in platforms where p != "macOS" {
            let generic = Destination(name: "Any \(p) Device (arm64)", specifier: "generic/platform=\(p)", platform: p, kind: .generic)
            let devs = devices.filter { $0.platform == p }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            groups.append(DestinationGroup(title: "\(p) Device", destinations: devs + [generic]))
            let sims = simulators.filter { $0.platform == p }.sorted {
                let n = $0.name.localizedStandardCompare($1.name)
                return n != .orderedSame ? n == .orderedAscending : compareVersions($0.osVersion ?? "", $1.osVersion ?? "") == .orderedDescending
            }
            if !sims.isEmpty {
                let anySim = Destination(name: "Any \(p) Simulator Device", specifier: "generic/platform=\(Destination.simulatorPlatform(p))",
                                         platform: p, kind: .generic)
                groups.append(DestinationGroup(title: "\(p) Simulators", destinations: [anySim] + sims))
            }
        }
        return groups
    }

    #if os(macOS)
    public static func load(scratchDirectory: URL = FileManager.default.temporaryDirectory) -> [DestinationGroup] {
        func run(_ args: [String]) -> Data? {
            MainThreadGuard.blockingCall("xcrun \(args.joined(separator: " "))")
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            p.arguments = args
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return nil }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            return p.terminationStatus == 0 ? data : nil
        }
        let sims = run(["simctl", "list", "-j", "devices"]).map(simulators(fromSimctlJSON:)) ?? []
        let file = scratchDirectory.appendingPathComponent("swiftcode-devicectl-\(ProcessInfo.processInfo.processIdentifier).json")
        defer { try? FileManager.default.removeItem(at: file) }
        _ = run(["devicectl", "list", "devices", "--json-output", file.path, "-q"])
        let devs = (try? Data(contentsOf: file)).map(devices(fromDevicectlJSON:)) ?? []
        return groups(devices: devs, simulators: sims)
    }
    #endif
}
