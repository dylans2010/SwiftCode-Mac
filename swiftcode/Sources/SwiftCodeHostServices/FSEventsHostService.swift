import Dispatch
import Foundation
import SwiftCodeDarwinABI
import SwiftCodeDarwinKernel

public final class FSEventsHostService: @unchecked Sendable {
    public static let serviceName = "com.apple.FSEvents"
    public static let disabled = getenv("SWIFTCODE_DEBUG_NO_FSEVENTS").map { String(cString: $0) == "1" } ?? false
    public static let changesDisabled = getenv("SWIFTCODE_FSEVENTS_NO_CHANGES").map { String(cString: $0) == "1" } ?? false

    enum ID {
        static let register: Int32 = 66000, flush: Int32 = 66001, deviceUUID: Int32 = 66002, currentID: Int32 = 66003
        static let lastIDBeforeTime: Int32 = 66004, stop: Int32 = 66006, events: Int32 = 67000
    }

    public enum Wire {
        public static let created: UInt32 = 0x1, removed: UInt32 = 0x2, inodeMetadata: UInt32 = 0x4, renamed: UInt32 = 0x8
        public static let modified: UInt32 = 0x10, createdDirectory: UInt32 = 0x80, changeOwner: UInt32 = 0x100
        public static let extendedAttribute: UInt32 = 0x200, cloned: UInt32 = 0x4000, hardLink: UInt32 = 0x0010_0000
        public static let ownEvent: UInt32 = 0x0020_0000, symbolicLink: UInt32 = 0x0040_0000, file: UInt32 = 0x0080_0000
        public static let directory: UInt32 = 0x0100_0000, historyDone: UInt32 = 0x0800_0000, dropped: UInt32 = 0x4000_0000
    }

    enum CreateFlag {
        static let noDefer: UInt32 = 0x2, ignoreSelf: UInt32 = 0x8, fileEvents: UInt32 = 0x10, markSelf: UInt32 = 0x20
        static let extendedData: UInt32 = 0x40
    }

    static let sinceNow = UInt64.max
    static let migBadID: Int32 = -303, migBadArguments: Int32 = -304
    static let ndr: [UInt8] = [0, 0, 0, 0, 1, 0, 0, 0]
    static let unknownDevice = "NO-UUID-UNKNOWN-DEVICE"
    static let idReservation: UInt64 = 10_000
    static let firstEventID: UInt64 = 1000
    static let batchLimit = 1024

    public struct Configuration {
        public var statePath: String?
        public var volumes: [UInt32: String]
        public var canonicalPath: ((String) -> String)?
        public var identity: ((String) -> (inode: UInt64, documentID: UInt32)?)?

        public init(statePath: String? = nil, volumes: [UInt32: String] = [:], canonicalPath: ((String) -> String)? = nil,
                    identity: ((String) -> (inode: UInt64, documentID: UInt32)?)? = nil) {
            self.statePath = statePath
            self.volumes = volumes
            self.canonicalPath = canonicalPath
            self.identity = identity
        }
    }

    final class Stream {
        let port: UInt32
        let client: UInt32
        let pid: Int32
        let dev: UInt32
        let paths: [(registered: String, canonical: String)]
        let exclusions: [String]
        let flags: UInt32
        let latencyMicroseconds: UInt64
        var stopped = false
        var lastID: UInt64 = 0
        var pending: [String: UInt32] = [:]
        var order: [String] = []
        var due: UInt64?
        var lastDelivery: UInt64 = 0
        var dropped = false

        init(port: UInt32, client: UInt32, pid: Int32, dev: UInt32, paths: [(registered: String, canonical: String)],
             exclusions: [String], flags: UInt32, latencyMicroseconds: UInt64) {
            self.port = port
            self.client = client
            self.pid = pid
            self.dev = dev
            self.paths = paths
            self.exclusions = exclusions
            self.flags = flags
            self.latencyMicroseconds = latencyMicroseconds
        }

        var fileEvents: Bool { flags & CreateFlag.fileEvents != 0 }
    }

    struct Event: Equatable {
        var path: String
        var flags: UInt32
        var id: UInt64
        var inode: UInt64 = 0
        var documentID: UInt32 = 0
    }

    public let servicePort: UInt32
    private let host: MachHostTask
    private let portSet: UInt32
    private let log: (String) -> Void
    private let configuration: Configuration
    private let lock = NSLock()
    private let sendLock = NSLock()
    private let wake = NSCondition()
    private var woken = false
    private var stopping = false
    private var feeding = false
    private var streams: [UInt32: Stream] = [:]
    private var lastIssuedID: UInt64 = firstEventID
    private var reservedID: UInt64 = firstEventID
    public let storeUUID: String
    private var logged: [Int32: Int] = [:]
    public private(set) var requestCount = 0
    public private(set) var eventCount = 0

    public init(host: MachHostTask, configuration: Configuration, log: @escaping (String) -> Void) throws {
        self.host = host
        self.log = log
        self.configuration = configuration
        servicePort = try host.makePort(sendRight: true, qlimit: 64)
        portSet = try host.makePortSet()
        try host.addMember(servicePort, to: portSet)
        var uuid: String?
        var reserved = Self.firstEventID
        if let path = configuration.statePath, let data = FileManager.default.contents(atPath: path),
           let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] {
            uuid = (plist["UUID"] as? String).flatMap { UUID(uuidString: $0)?.uuidString }
            if let n = plist["ReservedEventID"] as? NSNumber { reserved = max(reserved, n.uint64Value) }
        }
        storeUUID = uuid ?? UUID().uuidString
        lastIssuedID = reserved
        reservedID = reserved + Self.idReservation
        saveState()
    }

    public func start() {
        let t = Thread { [self] in run() }
        t.name = "swiftcode-fsevents"
        t.start()
        let d = Thread { [self] in deliver() }
        d.name = "swiftcode-fsevents-delivery"
        d.start()
        if !Self.changesDisabled {
            FileChangeFeed.install({ [weak self] change in self?.changed(change) })
            lock.withLock { feeding = true }
            updateListening()
        }
    }

    public func stop() {
        let fed = lock.withLock { () -> Bool in
            stopping = true
            defer { feeding = false }
            return feeding
        }
        if fed { FileChangeFeed.install(nil) }
        wakeDelivery()
    }

    private func wakeDelivery() {
        wake.lock()
        woken = true
        wake.signal()
        wake.unlock()
    }

    private func saveState() {
        guard let path = configuration.statePath else { return }
        let plist: [String: Any] = ["UUID": storeUUID, "ReservedEventID": NSNumber(value: reservedID)]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) else { return }
        try? data.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    private func issueID() -> UInt64 {
        lastIssuedID += 1
        if lastIssuedID >= reservedID {
            reservedID = lastIssuedID + Self.idReservation
            saveState()
        }
        return lastIssuedID
    }

    public var currentEventID: UInt64 { lock.withLock { lastIssuedID } }

    private func run() {
        while !lock.withLock({ stopping }) {
            let m: MachHostReceivedMessage
            do {
                m = try host.receive(on: portSet, timeout: 200_000_000, tracked: true)
            } catch let e as MachHostError where e == .timedOut || e == .interrupted || e == .portChanged {
                continue
            } catch let e as MachHostError where e == MachHostError(MachMsgReturn.rcvInvalidName) {
                return
            } catch {
                if !lock.withLock({ stopping }) { log("fsevents: receive failed: \(error); stopping") }
                return
            }
            handle(m)
            host.finishedMessage()
        }
    }

    func handle(_ m: MachHostReceivedMessage) {
        let first: Bool = lock.withLock {
            requestCount += 1
            logged[m.id, default: 0] += 1
            return logged[m.id] == 1
        }
        if first {
            log("fsevents: first request id \(m.id)\(m.sender.map { " from pid \($0.pid)" } ?? ""), \(m.body.count) body bytes, "
                + "\(m.descriptors.count) descriptors")
        }
        if m.id == MachNotify.noSenders, m.isFromKernel {
            endStream(m.localPort)
            return
        }
        guard MachPortName.isValid(m.replyPort) else {
            host.discard(m)
            return
        }
        let onStream = m.localPort != servicePort
        switch (m.id, onStream) {
        case (ID.register, false):
            register(m)
        case (ID.deviceUUID, false):
            reply(m, body: Self.ndr + fseRet(0) + uuidField(device: fseU32(m.body, 8)))
        case (ID.currentID, false):
            reply(m, body: Self.ndr + fseRet(0) + fseLE64(currentEventID))
        case (ID.lastIDBeforeTime, false):
            reply(m, body: Self.ndr + fseRet(0) + fseLE64(0))
        case (ID.flush, true):
            let id = flush(m.localPort)
            reply(m, body: Self.ndr + fseRet(0) + fseLE64(id))
        case (ID.stop, true):
            lock.withLock {
                if let s = streams[m.localPort] {
                    s.stopped = true
                    s.pending.removeAll()
                    s.order.removeAll()
                    s.due = nil
                }
            }
            updateListening()
            reply(m, body: Self.ndr + fseRet(0))
        default:
            dropRights(m)
            reply(m, body: Self.ndr + fseRet(Self.migBadID))
        }
    }

    func uuidField(device: UInt32) -> [UInt8] {
        let text = configuration.volumes[device] != nil && device != 0 ? storeUUID : Self.unknownDevice
        var bytes = Array(text.utf8.prefix(36))
        bytes += [UInt8](repeating: 0, count: 36 - bytes.count)
        return bytes
    }

    struct Registration: Equatable {
        var client: UInt32
        var dev: UInt32
        var paths: [String]
        var exclusions: [String]
        var latencyMicroseconds: UInt64
        var flags: UInt32
        var sinceWhen: UInt64
    }

    static func parseRegistration(_ m: MachHostReceivedMessage) -> Registration? {
        guard m.descriptors.count == 5, case let .port(client, _) = m.descriptors[0], m.body.count >= 56 else { return nil }
        var ool: [[UInt8]] = []
        for d in m.descriptors.dropFirst() {
            guard case let .ool(data, _, _) = d else { return nil }
            ool.append(data)
        }
        let b = m.body
        let dev = fseU32(b, 8), pathCount = Int(fseU32(b, 16)), exclusionCount = Int(fseU32(b, 28))
        func strings(offsets: [UInt8], bytes: [UInt8], count: Int) -> [String]? {
            guard count >= 0, offsets.count >= 4 * count else { return nil }
            var out: [String] = []
            for i in 0..<count {
                let at = Int(fseU32(offsets, 4 * i))
                guard at >= 0, at <= bytes.count else { return nil }
                out.append(String(decoding: bytes[at...].prefix { $0 != 0 }, as: UTF8.self))
            }
            return out
        }
        guard let paths = strings(offsets: ool[0], bytes: ool[1], count: pathCount), !paths.isEmpty,
              let exclusions = strings(offsets: ool[2], bytes: ool[3], count: exclusionCount) else { return nil }
        return Registration(client: client, dev: dev, paths: paths, exclusions: exclusions,
                            latencyMicroseconds: fseU64(b, 36), flags: fseU32(b, 44), sinceWhen: fseU64(b, 48))
    }

    private func register(_ m: MachHostReceivedMessage) {
        guard let r = Self.parseRegistration(m) else {
            dropRights(m)
            reply(m, body: Self.ndr + fseRet(Self.migBadArguments))
            return
        }
        let mount = r.dev == 0 ? nil : configuration.volumes[r.dev]
        func absolute(_ p: String) -> String? {
            if r.dev == 0 { return p.hasPrefix("/") ? p : nil }
            guard let mount else { return nil }
            let rel = p.hasPrefix("/") ? String(p.dropFirst()) : p
            return rel.isEmpty ? mount : (mount == "/" ? "/" + rel : mount + "/" + rel)
        }
        func canonical(_ p: String) -> String {
            var c = configuration.canonicalPath?(p) ?? p
            while c.count > 1 && c.hasSuffix("/") { c.removeLast() }
            return c
        }
        let paths = r.paths.compactMap { p in absolute(p).map { (registered: p, canonical: canonical($0)) } }
        let exclusions = r.exclusions.compactMap { absolute($0).map(canonical) }
        let port: UInt32
        do {
            port = try host.makePort()
            try host.addMember(port, to: portSet)
        } catch {
            log("fsevents: register: no stream port: \(error)")
            dropRights(m)
            reply(m, body: Self.ndr + fseRet(Self.migBadArguments))
            return
        }
        let stream = Stream(port: port, client: r.client, pid: m.sender?.pid ?? 0, dev: r.dev, paths: paths,
                            exclusions: exclusions, flags: r.flags, latencyMicroseconds: r.latencyMicroseconds)
        let count = lock.withLock { () -> Int in
            streams[port] = stream
            return streams.count
        }
        updateListening()
        lock.withLock {
            if logged[-1, default: 0] < 64 {
                logged[-1, default: 0] += 1
                let shown = r.paths.first.map { $0.count > 120 ? "…" + $0.suffix(119) : $0 } ?? ""
                log("fsevents: stream \(count) of pid \(stream.pid): \(shown)"
                    + (r.paths.count > 1 ? " and \(r.paths.count - 1) more paths" : "")
                    + (r.dev != 0 ? " (relative to device 0x\(String(r.dev, radix: 16)))" : "")
                    + ", flags 0x\(String(r.flags, radix: 16)), latency \(r.latencyMicroseconds) us"
                    + (r.sinceWhen == Self.sinceNow ? "" : ", since \(r.sinceWhen)"))
            }
        }
        do {
            try host.reply(to: m, descriptors: [.port(name: port, disposition: MachMsgType.makeSend)], body: [])
            _ = try host.requestNotification(port, id: MachNotify.noSenders, sync: 1, notifyPort: port)
        } catch {
            log("fsevents: register reply failed: \(error)")
        }
        if r.sinceWhen != Self.sinceNow, let first = r.paths.first {
            sendLock.withLock {
                _ = send(stream, [Event(path: first, flags: Wire.historyDone, id: r.sinceWhen)])
            }
        }
    }

    private func endStream(_ port: UInt32) {
        let s = lock.withLock { streams.removeValue(forKey: port) }
        updateListening()
        guard let s else { return }
        try? host.deallocate(s.client)
        try? host.removeMember(port, from: portSet)
        try? host.modRefs(port, right: MachPortRight.receive, delta: -1)
    }

    private func updateListening() {
        let (any, fed) = lock.withLock { (streams.values.contains { !$0.stopped && !$0.paths.isEmpty }, feeding) }
        if fed { FileChangeFeed.setListening(any) }
    }

    static func wireFlags(_ c: FileChange) -> UInt32 {
        var f: UInt32
        switch c.kind {
        case .created: f = c.item == .directory ? Wire.createdDirectory : Wire.created
        case .removed: f = Wire.removed
        case .renamed: f = Wire.renamed
        case .modified: f = Wire.modified
        case .inodeMetadata: f = Wire.inodeMetadata
        case .owner: f = Wire.changeOwner
        case .extendedAttribute: f = Wire.extendedAttribute
        case .cloned: f = Wire.cloned
        }
        switch c.item {
        case .file: f |= Wire.file
        case .directory: f |= Wire.directory
        case .symbolicLink: f |= Wire.symbolicLink
        case .other: break
        }
        return f
    }

    static func isBelow(_ path: String, _ root: String) -> Bool {
        path == root || path.hasPrefix(root == "/" ? "/" : root + "/")
    }

    func changed(_ c: FileChange) {
        let now = DispatchTime.now().uptimeNanoseconds
        var signal = false
        lock.withLock {
            for s in streams.values where !s.stopped {
                guard let match = s.paths.first(where: { Self.isBelow(c.path, $0.canonical) }) else { continue }
                if s.exclusions.contains(where: { Self.isBelow(c.path, $0) }) { continue }
                let own = c.pid != 0 && c.pid == s.pid
                if own && s.flags & CreateFlag.ignoreSelf != 0 { continue }
                var flags = Self.wireFlags(c)
                if own && s.flags & CreateFlag.markSelf != 0 { flags |= Wire.ownEvent }
                let base = match.registered.count > 1 && match.registered.hasSuffix("/")
                    ? String(match.registered.dropLast()) : match.registered
                var path = base + String(c.path.dropFirst(match.canonical.count))
                if !s.fileEvents {
                    if let slash = path.lastIndex(of: "/"), slash != path.startIndex {
                        path = String(path[...slash])
                    } else {
                        path = match.registered.hasSuffix("/") ? match.registered : match.registered + "/"
                    }
                    flags &= Wire.cloned | Wire.dropped
                }
                if s.pending[path] == nil { s.order.append(path) }
                s.pending[path, default: 0] |= flags
                if s.due == nil {
                    let latency = s.latencyMicroseconds * 1000
                    let idle = now &- s.lastDelivery >= latency
                    s.due = s.flags & CreateFlag.noDefer != 0 && idle ? now : now + latency
                    signal = true
                }
            }
        }
        if signal { wakeDelivery() }
    }

    private func deliver() {
        while !lock.withLock({ stopping }) {
            let now = DispatchTime.now().uptimeNanoseconds
            let next: UInt64? = lock.withLock { streams.values.compactMap(\.due).min() }
            if let next, next <= now {
                let due = lock.withLock { streams.values.filter { ($0.due ?? .max) <= now }.map(\.port) }
                for port in due { _ = flush(port) }
                continue
            }
            wake.lock()
            if !woken {
                let wait = next.map { Double($0 - now) / 1e9 } ?? 1.0
                _ = wake.wait(until: Date().addingTimeInterval(min(1.0, max(0.001, wait))))
            }
            woken = false
            wake.unlock()
        }
    }

    @discardableResult
    func flush(_ port: UInt32) -> UInt64 {
        sendLock.withLock {
            let taken: (Stream, [Event])? = lock.withLock {
                guard let s = streams[port] else { return nil }
                var events: [Event] = []
                for path in s.order {
                    var flags = s.pending[path] ?? 0
                    if s.dropped {
                        flags |= Wire.dropped
                        s.dropped = false
                    }
                    events.append(Event(path: path, flags: flags, id: issueID()))
                }
                s.pending.removeAll()
                s.order.removeAll()
                s.due = nil
                if !events.isEmpty { s.lastDelivery = DispatchTime.now().uptimeNanoseconds }
                return (s, events)
            }
            guard let (s, events) = taken else { return 0 }
            if !events.isEmpty { _ = send(s, events) }
            return lock.withLock { s.lastID }
        }
    }

    private func send(_ s: Stream, _ events: [Event]) -> Bool {
        var events = events
        if s.flags & CreateFlag.extendedData != 0, let identity = configuration.identity {
            for i in events.indices where events[i].flags & Wire.historyDone == 0 {
                let p = s.paths.first { $0.registered == events[i].path || events[i].path.hasPrefix($0.registered) }
                let canonical = p.map { $0.canonical + String(events[i].path.dropFirst($0.registered.count)) } ?? events[i].path
                if let id = identity(canonical) {
                    events[i].inode = id.inode
                    events[i].documentID = id.documentID
                }
            }
        }
        var start = 0
        var ok = true
        while start < events.count {
            let chunk = Array(events[start..<min(events.count, start + Self.batchLimit)])
            start += chunk.count
            let (descriptors, body) = Self.eventMessage(chunk, extended: s.flags & CreateFlag.extendedData != 0)
            do {
                try host.send(MachHostOutgoingMessage(remotePort: s.client, remoteDisposition: MachMsgType.copySend,
                                                      id: ID.events, descriptors: descriptors, body: body), timeout: 0)
                lock.withLock {
                    s.lastID = chunk.last!.id
                    eventCount += chunk.count
                }
            } catch {
                lock.withLock { s.dropped = true }
                ok = false
            }
        }
        return ok
    }

    static func eventMessage(_ events: [Event], extended: Bool) -> (descriptors: [MachHostDescriptor], body: [UInt8]) {
        var offsets: [UInt8] = [], flags: [UInt8] = [], ids: [UInt8] = [], records: [UInt8] = []
        for e in events {
            offsets += fseLE32(UInt32(records.count))
            flags += fseLE32(e.flags)
            ids += fseLE64(e.id)
            records += Array(e.path.utf8) + [0]
            if extended && e.flags & Wire.historyDone == 0 { records += fseLE64(e.inode) + fseLE32(e.documentID) }
        }
        let n = UInt32(events.count)
        let body = ndr + fseLE32(n) + fseLE32(n) + fseLE32(n) + fseLE32(n) + fseLE32(UInt32(records.count))
        return ([.ool(data: offsets), .ool(data: flags), .ool(data: ids), .ool(data: records)], body)
    }

    public struct StreamRecord: Equatable, Sendable {
        public var port: UInt32, client: UInt32, pid: Int32, dev: UInt32
        public var registered: [String], canonical: [String], exclusions: [String]
        public var flags: UInt32, latencyMicroseconds: UInt64, lastID: UInt64, stopped: Bool
        public init(port: UInt32, client: UInt32, pid: Int32, dev: UInt32, registered: [String], canonical: [String],
                    exclusions: [String], flags: UInt32, latencyMicroseconds: UInt64, lastID: UInt64, stopped: Bool) {
            self.port = port; self.client = client; self.pid = pid; self.dev = dev
            self.registered = registered; self.canonical = canonical; self.exclusions = exclusions
            self.flags = flags; self.latencyMicroseconds = latencyMicroseconds; self.lastID = lastID; self.stopped = stopped
        }
    }

    public var snapshotStreams: [StreamRecord] {
        lock.withLock {
            streams.values.sorted { $0.port < $1.port }.map { s in
                StreamRecord(port: s.port, client: s.client, pid: s.pid, dev: s.dev, registered: s.paths.map(\.registered),
                             canonical: s.paths.map(\.canonical), exclusions: s.exclusions, flags: s.flags,
                             latencyMicroseconds: s.latencyMicroseconds, lastID: s.lastID, stopped: s.stopped)
            }
        }
    }

    public func restoreStreams(_ list: [StreamRecord]) {
        lock.withLock {
            for r in list {
                let s = Stream(port: r.port, client: r.client, pid: r.pid, dev: r.dev,
                               paths: zip(r.registered, r.canonical).map { (registered: $0, canonical: $1) },
                               exclusions: r.exclusions, flags: r.flags, latencyMicroseconds: r.latencyMicroseconds)
                s.lastID = r.lastID
                s.stopped = r.stopped
                streams[r.port] = s
            }
        }
        for r in list { try? host.addMember(r.port, to: portSet) }
        updateListening()
    }

    private func reply(_ m: MachHostReceivedMessage, body: [UInt8]) {
        do {
            try host.reply(to: m, body: body)
        } catch {
            log("fsevents: reply to id \(m.id) failed: \(error)")
        }
    }

    private func dropRights(_ m: MachHostReceivedMessage) {
        for d in m.descriptors {
            switch d {
            case let .port(name, _), let .guardedPort(name, _, _): try? host.deallocate(name)
            case let .oolPorts(names, _): for n in names { try? host.deallocate(n) }
            case .ool: break
            }
        }
    }
}

private func fseLE32(_ v: UInt32) -> [UInt8] { (0..<4).map { UInt8(truncatingIfNeeded: v >> (8 * UInt32($0))) } }
private func fseRet(_ v: Int32) -> [UInt8] { fseLE32(UInt32(bitPattern: v)) }
private func fseLE64(_ v: UInt64) -> [UInt8] { (0..<8).map { UInt8(truncatingIfNeeded: v >> (8 * UInt64($0))) } }
func fseU32(_ b: [UInt8], _ at: Int) -> UInt32 {
    guard b.count >= at + 4 else { return 0 }
    return (0..<4).reduce(0) { $0 | UInt32(b[at + $1]) << (8 * UInt32($1)) }
}
func fseU64(_ b: [UInt8], _ at: Int) -> UInt64 {
    guard b.count >= at + 8 else { return 0 }
    return (0..<8).reduce(0) { $0 | UInt64(b[at + $1]) << (8 * UInt64($1)) }
}
