import Foundation

public enum PairingFamily: String, Sendable, Equatable {
    case phone
    case watch
    case other
}

public struct PairingDevice: Sendable, Equatable {
    public var udid: String
    public var directory: String
    public var family: PairingFamily
    public var typeName: String
    public var osVersion: String?

    public init(udid: String, directory: String, family: PairingFamily, typeName: String, osVersion: String? = nil) {
        self.udid = udid.uppercased()
        self.directory = directory
        self.family = family
        self.typeName = typeName
        self.osVersion = osVersion
    }
}

public enum PairingRules {
    public static func maxPairs(_ family: PairingFamily) -> Int {
        switch family {
        case .watch: 1
        case .phone: 100
        case .other: 0
        }
    }

    public static func minimumPartnerOS(_ family: PairingFamily) -> String? {
        switch family {
        case .watch: "12.0"
        case .phone: "3.2"
        case .other: nil
        }
    }

    public static func version(_ a: String, isAtLeast b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return true
    }
}

public enum PairingError: Error, Equatable, CustomStringConvertible {
    case doesNotPair(String)
    case tooManyPairs(String)
    case partnerTooOld(device: String, partnerVersion: String, minimum: String)
    case sameDevice
    case noSuchPair(String)
    case alreadyActive(String)
    case alreadyPaired(String)

    public var description: String {
        switch self {
        case .doesNotPair(let what): "Unable to pair devices: \(what) does not support pairing"
        case .tooManyPairs(let what): "Unable to pair devices: \(what) is already paired with the maximum number of devices"
        case let .partnerTooOld(device, partner, minimum):
            "Unable to pair devices: \(device) needs a partner on OS \(minimum) or later (it has \(partner))"
        case .sameDevice: "Unable to pair devices: a device cannot pair with itself"
        case .noSuchPair(let id): "Invalid device pair: \(id)"
        case .alreadyActive(let id): "The pair \(id) is already active"
        case .alreadyPaired(let id): "Unable to pair devices: they are already paired (pair \(id))"
        }
    }

    public var exitStatus: Int32 {
        switch self {
        case .noSuchPair: 148
        case .alreadyActive: 37
        default: 1
        }
    }
}

public struct DevicePair: Sendable, Equatable {
    public var id: String
    public var companion: String
    public var gizmo: String
    public var active: Bool
    public var companionDirectory: String?
    public var gizmoDirectory: String?

    public init(id: String, companion: String, gizmo: String, active: Bool,
                companionDirectory: String? = nil, gizmoDirectory: String? = nil) {
        self.id = id.uppercased()
        self.companion = companion.uppercased()
        self.gizmo = gizmo.uppercased()
        self.active = active
        self.companionDirectory = companionDirectory
        self.gizmoDirectory = gizmoDirectory
    }

    public func peer(of udid: String) -> String? {
        let u = udid.uppercased()
        if u == companion { return gizmo }
        if u == gizmo { return companion }
        return nil
    }

    public func contains(_ udid: String) -> Bool { peer(of: udid) != nil }

    var plist: [String: Any] {
        var d: [String: Any] = ["active": active, "companion": companion, "gizmo": gizmo]
        if let companionDirectory { d["companionDirectory"] = companionDirectory }
        if let gizmoDirectory { d["gizmoDirectory"] = gizmoDirectory }
        return d
    }

    init?(id: String, plist: [String: Any]) {
        guard let c = plist["companion"] as? String, let g = plist["gizmo"] as? String else { return nil }
        self.init(id: id, companion: c, gizmo: g, active: (plist["active"] as? Bool) ?? false,
                  companionDirectory: plist["companionDirectory"] as? String, gizmoDirectory: plist["gizmoDirectory"] as? String)
    }
}

public struct DevicePairStore: Sendable, Equatable {
    public static let fileName = "swiftcode-device-pairs.plist"
    public static let lockFileName = ".swiftcode-device-pairs.lock"
    public static let formatVersion = 1

    public private(set) var pairs: [DevicePair]

    public init(pairs: [DevicePair] = []) { self.pairs = pairs.sorted { $0.id < $1.id } }

    public static func path(inSet set: String) -> String { (set as NSString).appendingPathComponent(fileName) }

    public static func load(set: String) throws -> DevicePairStore {
        guard let data = FileManager.default.contents(atPath: path(inSet: set)) else { return DevicePairStore() }
        return try DevicePairStore(data: data)
    }

    public init(data: Data) throws {
        guard let root = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        let dict = root["DevicePairs"] as? [String: Any] ?? [:]
        self.init(pairs: dict.compactMap { id, value in (value as? [String: Any]).flatMap { DevicePair(id: id, plist: $0) } })
    }

    public func data() throws -> Data {
        var dict: [String: Any] = [:]
        for p in pairs { dict[p.id] = p.plist }
        return try PropertyListSerialization.data(fromPropertyList: ["Version": Self.formatVersion, "DevicePairs": dict],
                                                  format: .xml, options: 0)
    }

    public func save(set: String) throws {
        try data().write(to: URL(fileURLWithPath: Self.path(inSet: set)), options: .atomic)
    }

    @discardableResult
    public static func update<R>(set: String, _ body: (inout DevicePairStore) throws -> R) throws -> R {
        let lockPath = (set as NSString).appendingPathComponent(lockFileName)
        let fd = open(lockPath, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
        guard fd >= 0 else { throw CocoaError(.fileWriteNoPermission) }
        defer { close(fd) }
        flock(fd, LOCK_EX)
        defer { flock(fd, LOCK_UN) }
        var store = try load(set: set)
        let result = try body(&store)
        try store.save(set: set)
        return result
    }

    public func pair(_ id: String) -> DevicePair? { pairs.first { $0.id == id.uppercased() } }

    public func pairs(of udid: String) -> [DevicePair] { pairs.filter { $0.contains(udid) } }

    public func activePair(ofPhone udid: String) -> DevicePair? {
        pairs.first { $0.companion == udid.uppercased() && $0.active }
    }

    public mutating func pair(_ a: PairingDevice, _ b: PairingDevice,
                              newID: () -> String = { UUID().uuidString }) throws -> DevicePair {
        guard a.udid != b.udid else { throw PairingError.sameDevice }
        for d in [a, b] where d.family == .other { throw PairingError.doesNotPair(d.typeName) }
        guard a.family != b.family else { throw PairingError.doesNotPair("\(a.typeName) with \(b.typeName)") }
        let phone = a.family == .phone ? a : b, watch = a.family == .watch ? a : b
        if let existing = pairs.first(where: { $0.companion == phone.udid && $0.gizmo == watch.udid }) {
            throw PairingError.alreadyPaired(existing.id)
        }
        for d in [phone, watch] where pairs(of: d.udid).count >= PairingRules.maxPairs(d.family) {
            throw PairingError.tooManyPairs("\(d.typeName) (\(d.udid))")
        }
        for (d, partner) in [(phone, watch), (watch, phone)] {
            if let minimum = PairingRules.minimumPartnerOS(d.family), let v = partner.osVersion,
               !PairingRules.version(v, isAtLeast: minimum) {
                throw PairingError.partnerTooOld(device: d.typeName, partnerVersion: v, minimum: minimum)
            }
        }
        let new = DevicePair(id: newID(), companion: phone.udid, gizmo: watch.udid, active: activePair(ofPhone: phone.udid) == nil,
                             companionDirectory: phone.directory, gizmoDirectory: watch.directory)
        pairs.append(new)
        pairs.sort { $0.id < $1.id }
        return new
    }

    public mutating func unpair(_ id: String) throws -> DevicePair {
        guard let i = pairs.firstIndex(where: { $0.id == id.uppercased() }) else { throw PairingError.noSuchPair(id) }
        return pairs.remove(at: i)
    }

    public mutating func activate(_ id: String) throws -> DevicePair {
        guard let i = pairs.firstIndex(where: { $0.id == id.uppercased() }) else { throw PairingError.noSuchPair(id) }
        guard !pairs[i].active else { throw PairingError.alreadyActive(pairs[i].id) }
        let phone = pairs[i].companion
        for j in pairs.indices where pairs[j].companion == phone { pairs[j].active = j == i }
        return pairs[i]
    }
}

public struct PairListingEntry: Sendable, Equatable {
    public struct Side: Sendable, Equatable {
        public var name: String
        public var udid: String
        public var state: String
        public init(name: String, udid: String, state: String) {
            self.name = name
            self.udid = udid
            self.state = state
        }
    }

    public var id: String
    public var watch: Side
    public var phone: Side
    public var active: Bool
    public var connected: Bool

    public init(id: String, watch: Side, phone: Side, active: Bool, connected: Bool) {
        self.id = id
        self.watch = watch
        self.phone = phone
        self.active = active
        self.connected = connected
    }

    public var stateText: String { "(\(active ? "active" : "inactive"), \(connected ? "connected" : "disconnected"))" }
}

public enum PairListing {
    public static func text(_ entries: [PairListingEntry]) -> String {
        var lines = ["== Device Pairs =="]
        for e in entries {
            lines.append("\(e.id) \(e.stateText)")
            lines.append("    Watch: \(e.watch.name) (\(e.watch.udid)) (\(e.watch.state))")
            lines.append("    Phone: \(e.phone.name) (\(e.phone.udid)) (\(e.phone.state))")
        }
        return lines.joined(separator: "\n")
    }

    public static func json(_ entries: [PairListingEntry]) -> String {
        func side(_ s: PairListingEntry.Side) -> [String: Any] { ["name": s.name, "udid": s.udid, "state": s.state] }
        var pairs: [String: Any] = [:]
        for e in entries { pairs[e.id] = ["watch": side(e.watch), "phone": side(e.phone), "state": e.stateText] }
        let data = (try? JSONSerialization.data(withJSONObject: ["pairs": pairs], options: [.prettyPrinted, .sortedKeys])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}

public enum PairingEndpoint {
    public static func remoteName(peer: String) -> String { "com.apple.IDSSimRPC.remote." + peer.uppercased() }
    public static let localName = "com.apple.IDSSimRPC.local"
    public static let requestID: Int32 = 1000
    public static let replyID: Int32 = 1100
}

public enum PairingAgentRequest: Sendable, Equatable {
    case connect(peer: String)
    case setActive(peer: String, previouslyPaired: Bool)
    case switchTo(peer: String)
    case removeUnpaired(hostPaired: [String])
    case unpair(peer: String)
    case disconnect(peer: String)

    public var op: String {
        switch self {
        case .connect: "connect"
        case .setActive, .switchTo: "setActive"
        case .removeUnpaired: "removeUnpaired"
        case .unpair: "unpair"
        case .disconnect: "disconnect"
        }
    }

    public var message: [String: Any] {
        switch self {
        case .connect(let p), .unpair(let p), .disconnect(let p): ["op": op, "peer": p]
        case let .setActive(p, before): ["op": op, "peer": p, "previouslyPaired": before, "peerRunning": true]
        case .switchTo(let p): ["op": op, "peer": p, "peerRunning": false]
        case .removeUnpaired(let list): ["op": op, "hostPaired": list]
        }
    }

    public var summary: String {
        switch self {
        case .connect(let p): "connect \(p)"
        case let .setActive(p, before): "set-active \(p)\(before ? " (paired before)" : "")"
        case .switchTo(let p): "set-active \(p) (not running: switch only)"
        case .removeUnpaired(let list): "remove-unpaired (host pairs: \(list.isEmpty ? "none" : list.joined(separator: ", ")))"
        case .unpair(let p): "unpair \(p)"
        case .disconnect(let p): "disconnect \(p)"
        }
    }
}

public enum PairingAgentChannel {
    public static let guestPaths = ["/private/var/run/dev.swiftcode.pairing", "/var/run/dev.swiftcode.pairing"]
    public static let protocolVersion = 1
}

public struct PairingSequencer: Sendable {
    public enum Action: Sendable, Equatable {
        case register(peer: String)
        case unregister(peer: String)
        case announceRegistered(peer: String)
        case agent(PairingAgentRequest)
    }

    public struct PeerState: Sendable, Equatable {
        public var linked = false
        public var registering = false
        public var localRegistered = false
        public var peerRegistered = false
        public var connectSent = false
        public var activeSent = false
        public var active = false
        public var previouslyPaired = false
        public var switchDue = false
        public var connected: Bool { linked && localRegistered && peerRegistered }
    }

    public private(set) var peers: [String: PeerState] = [:]
    public var switchAbsentPeers = true
    public private(set) var agentReady = false
    public private(set) var controlReady = false
    private var removeUnpairedSent = false
    public private(set) var hostPaired: [String] = []

    public init() {}

    public func state(of peer: String) -> PeerState { peers[peer.uppercased()] ?? PeerState() }

    public mutating func setPairs(_ list: [(peer: String, active: Bool, previouslyPaired: Bool)]) -> [Action] {
        hostPaired = list.map { $0.peer.uppercased() }.sorted()
        for (peer, active, before) in list {
            let p = peer.uppercased()
            var s = peers[p] ?? PeerState()
            if s.active != active {
                s.activeSent = false
                s.switchDue = active && peers[p] != nil && !s.connected
            }
            s.active = active
            s.previouslyPaired = s.previouslyPaired || before
            peers[p] = s
        }
        return advance()
    }

    public mutating func agentConnected() -> [Action] {
        agentReady = true
        removeUnpairedSent = false
        for k in peers.keys {
            peers[k]!.connectSent = false
            peers[k]!.activeSent = false
        }
        return advance()
    }

    public mutating func agentDisconnected() { agentReady = false }

    public mutating func controlBound() -> [Action] {
        controlReady = true
        return advance()
    }

    public mutating func linkUp(peer: String) -> [Action] {
        let p = peer.uppercased()
        var s = peers[p] ?? PeerState()
        s.linked = true
        s.peerRegistered = false
        peers[p] = s
        return advance()
    }

    public mutating func peerRegistered(peer: String) -> [Action] {
        let p = peer.uppercased()
        guard peers[p]?.linked == true else { return [] }
        peers[p]!.peerRegistered = true
        return advance()
    }

    public mutating func registered(peer: String, ok: Bool) -> [Action] {
        let p = peer.uppercased()
        guard var s = peers[p] else { return [] }
        s.registering = false
        s.localRegistered = ok && s.linked
        peers[p] = s
        if ok && !s.linked { return [.unregister(peer: p)] }
        return ok ? [.announceRegistered(peer: p)] + advance() : []
    }

    public mutating func activated(peer: String, ok: Bool) {
        let p = peer.uppercased()
        if ok { peers[p]?.previouslyPaired = true }
    }

    public mutating func linkDown(peer: String) -> [Action] {
        let p = peer.uppercased()
        guard var s = peers[p], s.linked else { return [] }
        let had = s.localRegistered || s.registering
        let disconnect = agentReady && s.connectSent
        s.linked = false
        s.localRegistered = false
        s.peerRegistered = false
        s.connectSent = false
        s.activeSent = false
        peers[p] = s
        return (had ? [.unregister(peer: p)] : []) + (disconnect ? [.agent(.disconnect(peer: p))] : [])
    }

    public mutating func unpaired(peer: String) -> [Action] {
        let p = peer.uppercased()
        let s = peers.removeValue(forKey: p) ?? PeerState()
        hostPaired.removeAll { $0 == p }
        var out: [Action] = []
        if agentReady && s.connectSent { out += [.agent(.unpair(peer: p)), .agent(.disconnect(peer: p))] }
        if s.localRegistered || s.registering { out.append(.unregister(peer: p)) }
        return out
    }

    private mutating func advance() -> [Action] {
        var out: [Action] = []
        if agentReady && !removeUnpairedSent {
            removeUnpairedSent = true
            out.append(.agent(.removeUnpaired(hostPaired: hostPaired)))
        }
        for p in peers.keys.sorted() {
            var s = peers[p]!
            if s.linked && controlReady && !s.localRegistered && !s.registering {
                s.registering = true
                out.append(.register(peer: p))
            }
            if s.connected { s.switchDue = false }
            if s.switchDue && s.active && agentReady && switchAbsentPeers {
                s.switchDue = false
                out.append(.agent(.switchTo(peer: p)))
            }
            if s.connected && agentReady {
                if !s.connectSent {
                    s.connectSent = true
                    out.append(.agent(.connect(peer: p)))
                }
                if s.active && !s.activeSent {
                    s.activeSent = true
                    out.append(.agent(.setActive(peer: p, previouslyPaired: s.previouslyPaired)))
                }
            }
            peers[p] = s
        }
        return out
    }
}

public enum PairLinkFrame {
    public static let protocolVersion = 1
    public static let maximumFrame = 17 << 20

    public static func encode(_ message: [String: Any]) -> [UInt8]? {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: message, format: .binary, options: 0),
              data.count <= maximumFrame else { return nil }
        let n = UInt32(data.count)
        return [UInt8(n >> 24), UInt8(n >> 16 & 0xFF), UInt8(n >> 8 & 0xFF), UInt8(n & 0xFF)] + [UInt8](data)
    }

    public static func decode(_ buffer: inout [UInt8]) throws -> [[String: Any]] {
        var out: [[String: Any]] = []
        while let o = try decodeFirst(&buffer) { out.append(o) }
        return out
    }

    public static func decodeFirst(_ buffer: inout [UInt8]) throws -> [String: Any]? {
        guard buffer.count >= 4 else { return nil }
        let n = Int(buffer[0]) << 24 | Int(buffer[1]) << 16 | Int(buffer[2]) << 8 | Int(buffer[3])
        guard n <= maximumFrame else { throw SettingsChannel.ChannelError.frameTooLarge(n) }
        guard buffer.count >= 4 + n else { return nil }
        let body = Data(buffer[4..<(4 + n)])
        buffer.removeFirst(4 + n)
        guard let o = try? PropertyListSerialization.propertyList(from: body, options: [], format: nil) as? [String: Any],
              o["type"] is String else {
            throw SettingsChannel.ChannelError.notADictionary
        }
        return o
    }

    public static func socketPath(base: String, uid: UInt32, udid: String) -> String {
        let id = udid.uppercased().replacingOccurrences(of: "-", with: "").prefix(16)
        return (base.hasSuffix("/") ? String(base.dropLast()) : base) + "/swiftcodepair-\(uid)-\(id).sock"
    }
}
