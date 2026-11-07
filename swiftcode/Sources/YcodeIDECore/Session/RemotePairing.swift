import Foundation
import YcodeBuild

public struct RemoteDevicePair: Equatable, Sendable, Codable {
    public var id: String
    public var watchDirectory: String
    public var phoneDirectory: String
    public var watchUDID: String
    public var phoneUDID: String
    public var watchTypeName: String
    public var phoneTypeName: String
    public var active: Bool
    public var connected: Bool
    public var watchBooted: Bool
    public var phoneBooted: Bool

    public init(id: String, watchDirectory: String, phoneDirectory: String, watchUDID: String = "", phoneUDID: String = "",
                watchTypeName: String = "", phoneTypeName: String = "", active: Bool, connected: Bool = false,
                watchBooted: Bool = false, phoneBooted: Bool = false) {
        self.id = id
        self.watchDirectory = watchDirectory
        self.phoneDirectory = phoneDirectory
        self.watchUDID = watchUDID
        self.phoneUDID = phoneUDID
        self.watchTypeName = watchTypeName
        self.phoneTypeName = phoneTypeName
        self.active = active
        self.connected = connected
        self.watchBooted = watchBooted
        self.phoneBooted = phoneBooted
    }

    public var stateText: String { "(\(active ? "active" : "inactive"), \(connected ? "connected" : "disconnected"))" }
}

public enum RemotePairListing {
    public static func parse(_ data: Data) -> [RemoteDevicePair]? {
        let text = String(decoding: data, as: UTF8.self)
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end,
              let root = try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8)) as? [String: Any],
              let pairs = root["pairs"] as? [String: Any] else { return nil }
        var out: [RemoteDevicePair] = []
        for (id, value) in pairs {
            guard let p = value as? [String: Any], let w = p["watch"] as? [String: Any], let ph = p["phone"] as? [String: Any] else { continue }
            let (wType, wDir) = split(name: w["name"] as? String ?? "")
            let (pType, pDir) = split(name: ph["name"] as? String ?? "")
            guard let wDir, let pDir else { continue }
            let state = p["state"] as? String ?? ""
            out.append(RemoteDevicePair(id: id.uppercased(), watchDirectory: wDir, phoneDirectory: pDir,
                                        watchUDID: (w["udid"] as? String ?? "").uppercased(), phoneUDID: (ph["udid"] as? String ?? "").uppercased(),
                                        watchTypeName: wType, phoneTypeName: pType,
                                        active: state.hasPrefix("(active"), connected: state.contains(" connected"),
                                        watchBooted: w["state"] as? String == "Booted", phoneBooted: ph["state"] as? String == "Booted"))
        }
        return out.sorted { ($0.phoneDirectory, $0.watchDirectory) < ($1.phoneDirectory, $1.watchDirectory) }
    }

    public static func split(name: String) -> (type: String, directory: String?) {
        guard name.hasSuffix("]"), let open = name.range(of: " [", options: .backwards) else { return (name, nil) }
        let dir = String(name[open.upperBound..<name.index(before: name.endIndex)])
        return (String(name[..<open.lowerBound]), dir.isEmpty || dir == "missing" ? nil : dir)
    }
}

public struct RemoteCreatedDevice: Equatable, Sendable, Codable {
    public var name: String
    public var typeID: String
    public var runtimeRoot: String
    public var directoryName: String

    public init(name: String, typeID: String, runtimeRoot: String, directoryName: String) {
        self.name = name
        self.typeID = typeID
        self.runtimeRoot = runtimeRoot
        self.directoryName = directoryName
    }

    public static func directoryName(deviceName: String, typeID: String, runtimeTag: String, unique: String = UUID().uuidString) -> String {
        let hex = unique.replacingOccurrences(of: "-", with: "").lowercased().prefix(8)
        return "\(deviceName)-\(typeID)-\(runtimeTag)-\(hex)"
    }
}

extension RemoteSimulatorSettings {
    public static let createdDevicesKey = "SwiftCode.remote.createdDevices"

    public static func createdDevices(_ d: UserDefaults) -> [RemoteCreatedDevice] {
        guard let data = d.data(forKey: createdDevicesKey) else { return [] }
        return (try? JSONDecoder().decode([RemoteCreatedDevice].self, from: data)) ?? []
    }

    public static func saveCreatedDevices(_ devices: [RemoteCreatedDevice], _ d: UserDefaults) {
        d.set(try? JSONEncoder().encode(devices), forKey: createdDevicesKey)
    }
}

public enum RemotePairedDestination {
    public static let prefix = RemoteSimulator.identifier + ":paired:"
    public static func identifier(phoneDirectory: String) -> String { prefix + phoneDirectory }
    public static func phoneDirectory(identifier: String) -> String? {
        identifier.hasPrefix(prefix) ? String(identifier.dropFirst(prefix.count)) : nil
    }
    public static func title(phone: String, watch: String) -> String { "\(phone) with \(watch)" }
}

extension Destination {
    public var isSwiftCodePairedDestination: Bool { identifier.map { $0.hasPrefix(RemotePairedDestination.prefix) } ?? false }
}

extension RemoteSimulatorSettings {
    public func pairedDestinations(_ pairs: [RemoteDevicePair]) -> [Destination] {
        let watches = watchTargets
        return targets.compactMap { phone in
            guard let pair = pairs.first(where: { $0.phoneDirectory == phone.deviceDirectoryName && $0.active }),
                  let watch = watches.first(where: { $0.deviceDirectoryName == pair.watchDirectory }) else { return nil }
            var d = watch.destination
            d.name = RemotePairedDestination.title(phone: phone.name, watch: watch.name)
            d.identifier = RemotePairedDestination.identifier(phoneDirectory: phone.deviceDirectoryName)
            return d
        }
    }

    public func pairedTargets(for destination: Destination?, pairs: [RemoteDevicePair]) -> (phone: RemoteSimulatorTarget, watch: RemoteSimulatorTarget)? {
        guard let id = destination?.identifier, let dir = RemotePairedDestination.phoneDirectory(identifier: id),
              let phone = targets.first(where: { $0.deviceDirectoryName == dir }) else { return nil }
        return pairedWatch(of: phone, pairs: pairs).map { (phone, $0) }
    }

    public func pairedWatch(of phone: RemoteSimulatorTarget, pairs: [RemoteDevicePair]) -> RemoteSimulatorTarget? {
        guard let pair = pairs.first(where: { $0.phoneDirectory == phone.deviceDirectoryName && $0.active }) else { return nil }
        return watchTargets.first { $0.deviceDirectoryName == pair.watchDirectory }
    }
}

extension RemoteSimulatorSettings {
    public func runtimeRoots(platform: String) -> [(root: String, version: String?)] {
        allRuntimeRoots.filter { runtimePlatform(forRoot: $0) == platform }.map { ($0, runtimeVersion(forRoot: $0)) }
    }

    public func newDeviceTypes(platform: String, root: String) -> [SwiftCodeSimulatorDeviceType] {
        let version = runtimeVersion(forRoot: root)
        if platform == "watchOS" { return SwiftCodeSimulatorDeviceType.watches(onRuntimeVersion: version) }
        if platform == "visionOS" { return SwiftCodeSimulatorDeviceType.visions(onRuntimeVersion: version) }
        return SwiftCodeSimulatorDeviceType.supported(onRuntimeVersion: version).filter { SwiftCodeSimulatorDeviceType.phones.contains($0) }
    }

    @discardableResult
    public static func createDevice(name: String, type: SwiftCodeSimulatorDeviceType, runtimeRoot: String, _ d: UserDefaults) -> RemoteCreatedDevice {
        let settings = load(d)
        let tag = RemoteSimulatorTarget.runtimeTag(root: runtimeRoot, version: settings.runtimeVersion(forRoot: runtimeRoot))
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let device = RemoteCreatedDevice(name: trimmed.isEmpty ? type.name : trimmed, typeID: type.id, runtimeRoot: runtimeRoot,
                                         directoryName: RemoteCreatedDevice.directoryName(deviceName: settings.deviceName, typeID: type.id, runtimeTag: tag))
        saveCreatedDevices(createdDevices(d) + [device], d)
        return device
    }

    public static func removeCreatedDevice(directory: String, _ d: UserDefaults) {
        saveCreatedDevices(createdDevices(d).filter { $0.directoryName != directory }, d)
    }
}

extension RemoteSimulator {
    public var deviceSetPath: String { "\(settings.dataDirectory)/devices" }

    func pairingCommand(_ words: [String]) -> String {
        "exec env SWIFTCODE_SIM_DEVICE_SET=\(Self.quote(deviceSetPath)) \(Self.quote(settings.simdPath))" + words.map { " " + Self.quote($0) }.joined()
    }

    public var listPairsCommand: String { pairingCommand(["list-pairs", "--json"]) }

    public static func typeRecordCommand(devicePath: String, typeID: String) -> String {
        let d = quote(devicePath)
        return "{ [ -e \(d)/swiftcode-device-type ] || [ -e \(d)/data/var/run/launchd_bootstrap.plist ] || { mkdir -p \(d) && printf '%s\\n' \(quote(typeID)) > \(d)/swiftcode-device-type; }; }"
    }

    public func pairCommand(watch: RemoteSimulator) -> String {
        let records = [watch, self].compactMap { r in r.target.map { Self.typeRecordCommand(devicePath: r.remoteDevicePath, typeID: $0.deviceType.id) } }
        return (records + [pairingCommand(["pair", watch.remoteDevicePath, remoteDevicePath])]).joined(separator: " && ")
    }

    public func unpairCommand(_ pairID: String) -> String { pairingCommand(["unpair", pairID]) }

    public func activateCommand(_ pairID: String) -> String { pairingCommand(["pair-activate", pairID]) }

    public func runPairing(_ command: String) -> (Int32, String) {
        runLocal(settings.ssh, sshArguments(command))
    }

    public func readPairs() -> [RemoteDevicePair]? {
        let (status, data) = runLocalData(settings.ssh, sshArguments(listPairsCommand), errors: false)
        guard status == 0 else { return nil }
        return RemotePairListing.parse(data)
    }

    public static func pairID(fromPairOutput text: String) -> String? {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }
            .last { UUID(uuidString: $0) != nil }.map { $0.uppercased() }
    }

    public var deviceDirectoryName: String { target?.deviceDirectoryName ?? settings.deviceName }
}

@MainActor
public final class RemotePairsStore {
    public static let shared = RemotePairsStore()
    public static let didChange = Notification.Name("SwiftCodeRemotePairsDidChange")
    public static let defaultsKey = "SwiftCode.remote.pairs"

    public var defaults: UserDefaults = .standard {
        didSet { if defaults !== oldValue { loaded = false; pairs = [] } }
    }
    public private(set) var pairs: [RemoteDevicePair] = []
    private var loaded = false

    public init(defaults: UserDefaults? = nil) {
        if let defaults { self.defaults = defaults }
    }

    public func current() -> [RemoteDevicePair] {
        if !loaded {
            loaded = true
            if let data = defaults.data(forKey: Self.defaultsKey), let p = try? JSONDecoder().decode([RemoteDevicePair].self, from: data) { pairs = p }
        }
        return pairs
    }

    public func set(_ p: [RemoteDevicePair]) {
        loaded = true
        guard p != pairs else { return }
        pairs = p
        defaults.set(try? JSONEncoder().encode(p), forKey: Self.defaultsKey)
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    @discardableResult
    public func refresh(_ remote: RemoteSimulator) async -> Bool {
        guard remote.settings.isConfigured, let p = await Task.detached(operation: { remote.readPairs() }).value else { return false }
        set(p)
        return true
    }
}

public struct RemotePairing: Equatable, Sendable {
    public var pairs: [RemoteDevicePair]
    public init(_ pairs: [RemoteDevicePair]) { self.pairs = pairs }

    public func pairs(ofDirectory dir: String) -> [RemoteDevicePair] {
        pairs.filter { $0.phoneDirectory == dir || $0.watchDirectory == dir }.sorted { $0.active && !$1.active }
    }

    public func activePair(phone dir: String) -> RemoteDevicePair? { pairs.first { $0.phoneDirectory == dir && $0.active } }

    public func isPaired(watch dir: String) -> Bool { pairs.contains { $0.watchDirectory == dir } }
}
