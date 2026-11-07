import Foundation
import SwiftCodeDarwinKernel

public protocol PairingRelayLink: AnyObject, Sendable {
    var udid: String { get }
    var host: MachHostTask { get }
    @discardableResult func sendToPeer(_ peer: String, frame: [String: Any]) -> Bool
    func findInGuest(_ name: String) throws -> UInt32
}

public final class PairingTransportRelay: @unchecked Sendable {
    public struct Options: Sendable {
        public var requestTimeout: TimeInterval
        public var lookupWait: TimeInterval
        public var maximumPayload: Int
        public var chunkSize: Int
        public var queuedLimit: Int
        public var localName: String
        public init(requestTimeout: TimeInterval = 60, lookupWait: TimeInterval = 20, maximumPayload: Int = 1 << 30,
                    chunkSize: Int = 4 << 20, queuedLimit: Int = 64 << 20,
                    localName: String = "com.apple.IDSSimRPC.local") {
            self.requestTimeout = requestTimeout
            self.lookupWait = lookupWait
            self.maximumPayload = maximumPayload
            self.chunkSize = max(1, chunkSize)
            self.queuedLimit = max(1, queuedLimit)
            self.localName = localName
        }

        public static func fromEnvironment(_ env: [String: String] = ProcessInfo.processInfo.environment) -> Options {
            var o = Options()
            if let s = env["SWIFTCODE_PAIRING_RELAY_TIMEOUT_S"], let v = Double(s), v > 0 { o.requestTimeout = v }
            if let s = env["SWIFTCODE_PAIRING_RELAY_LOOKUP_S"], let v = Double(s), v >= 0 { o.lookupWait = v }
            if let s = env["SWIFTCODE_PAIRING_RELAY_MAX_MB"], let v = Int(s), v > 0 { o.maximumPayload = v << 20 }
            if let s = env["SWIFTCODE_PAIRING_RELAY_CHUNK_KB"], let v = Int(s), v > 0 { o.chunkSize = v << 10 }
            return o
        }
    }

    public enum Frame {
        public static let request = "relay-request"
        public static let reply = "relay-reply"
        public static let chunk = "relay-chunk"
    }

    public struct Statistics: Sendable, Equatable {
        public var requestsOut = 0, bytesOut = 0, repliesOut = 0, failedOut = 0, timedOutOut = 0
        public var requestsIn = 0, bytesIn = 0, failedIn = 0
        public var largestOut = 0, largestIn = 0
        public var chunkedOut = 0, chunksOut = 0
        public var roundTripsMs: [Double] = []
        public var oneWayMs: [Double] = []

        public func summary() -> String {
            func stats(_ v: [Double]) -> String {
                guard !v.isEmpty else { return "-" }
                let s = v.sorted()
                return String(format: "min %.2f, median %.2f, max %.2f ms", s.first!, s[s.count / 2], s.last!)
            }
            return "out \(requestsOut) requests (\(bytesOut) bytes, largest \(largestOut)), \(repliesOut) replies, "
                + "\(failedOut) failed, \(timedOutOut) timed out; round trip \(stats(roundTripsMs)); "
                + (chunkedOut > 0 ? "\(chunkedOut) sent in \(chunksOut) pieces; " : "")
                + "in \(requestsIn) requests (\(bytesIn) bytes, largest \(largestIn)), \(failedIn) failed; "
                + "relay one-way \(stats(oneWayMs))"
        }
    }

    public let options: Options
    public let log: (String) -> Void
    private let lock = NSLock()
    private var stats = Statistics()
    private static let keptSamples = 4096

    private struct Outgoing {
        var replyPort: UInt32
        var replyType: UInt32
        var id: Int32
        var deadline: UInt64
        var started: UInt64
    }
    private var outgoing: [String: [Int: Outgoing]] = [:]
    private var nextSeq: [String: Int] = [:]
    private var linkGeneration: [String: Int] = [:]

    private struct Incoming {
        var peer: String
        var seq: Int
        var generation: Int
        var deadline: UInt64
    }
    private var deliverQueues: [String: DispatchQueue] = [:]
    private var assembling: [String: Data] = [:]
    private var queuedBytes = 0
    private let queuedChanged = NSCondition()
    private var localPort: UInt32?
    private var incoming: [UInt32: Incoming] = [:]
    private var replySet: UInt32?
    private weak var farLink: PairingRelayLink?
    private var running = true
    private var threadsStarted = false

    public init(options: Options = Options(), log: @escaping (String) -> Void) {
        self.options = options
        self.log = log
    }

    public var statistics: Statistics { lock.withLock { stats } }

    public func stop(link: PairingRelayLink) {
        let peers = lock.withLock { () -> [String] in
            running = false
            return Array(Set(outgoing.keys).union(deliverQueues.keys))
        }
        for p in peers { linkChanged(peer: p, up: false, link: link) }
        queuedChanged.lock()
        queuedChanged.broadcast()
        queuedChanged.unlock()
        if let set = lock.withLock({ () -> UInt32? in defer { replySet = nil }; return replySet }) {
            try? link.host.destroyPort(set)
        }
    }

    private static func now() -> UInt64 { DispatchTime.now().uptimeNanoseconds }
    private func deadline() -> UInt64 { Self.now() &+ UInt64(options.requestTimeout * 1e9) }

    public func endpoint(peer rawPeer: String, received m: MachHostReceivedMessage, link: PairingRelayLink) {
        let peer = rawPeer.uppercased()
        let host = link.host
        startThreads(link)
        var regions: [Data] = []
        var carriesRights = false
        for d in m.descriptors {
            switch d {
            case let .ool(data, _, _): regions.append(Data(data))
            default: carriesRights = true
            }
        }
        let size = regions.reduce(m.body.count) { $0 + $1.count }
        let wantsReply = MachPortName.isValid(m.replyPort)
        if carriesRights {
            log("pairing relay: request id \(m.id) for \(peer) carries port rights; not relayed")
            fail(m, code: MachMsgReturn.sendInvalidRight, host: host)
            return
        }
        if size > options.maximumPayload {
            log("pairing relay: request id \(m.id) for \(peer) is \(size) bytes (at most \(options.maximumPayload)); not relayed")
            fail(m, code: MachMsgReturn.sendTooLarge, host: host)
            return
        }
        let started = Self.now()
        let (seq, generation, n) = lock.withLock { () -> (Int, Int, Int) in
            let s = (nextSeq[peer] ?? 0) + 1
            nextSeq[peer] = s
            if wantsReply {
                outgoing[peer, default: [:]][s] = Outgoing(replyPort: m.replyPort, replyType: m.replyType, id: m.id,
                                                           deadline: deadline(), started: started)
            }
            stats.requestsOut += 1
            stats.bytesOut += size
            stats.largestOut = max(stats.largestOut, size)
            return (s, linkGeneration[peer] ?? 0, stats.requestsOut)
        }
        let frame: [String: Any] = ["type": Frame.request, "seq": seq, "generation": generation, "id": Int(m.id),
                                    "body": Data(m.body), "reply": wantsReply]
        if n <= 3 || n.isMultiple(of: 100) || size > options.chunkSize {
            log("pairing relay: request \(n) to \(peer): id \(m.id), \(size) bytes"
                + (regions.reduce(0) { $0 + $1.count } > options.chunkSize ? " (in pieces)" : ""))
        }
        guard sendMessage(to: peer, frame: frame, regions: regions, part: "request", seq: seq, generation: generation,
                          stamp: true, link: link) else {
            answerOutgoing(peer: peer, seq: seq, code: MachMsgReturn.sendInvalidDest, link: link)
            if !wantsReply { lock.withLock { stats.failedOut += 1 } }
            return
        }
    }

    private func sendMessage(to peer: String, frame base: [String: Any], regions: [Data], part: String, seq: Int,
                             generation: Int, stamp: Bool, link: PairingRelayLink) -> Bool {
        var frame = base
        let total = regions.reduce(0) { $0 + $1.count }
        if total <= options.chunkSize {
            frame["ool"] = regions
        } else {
            var pieces = 0
            for r in regions {
                var off = r.startIndex
                while off < r.endIndex {
                    let end = min(off + options.chunkSize, r.endIndex)
                    let piece = r.subdata(in: off..<end)
                    guard link.sendToPeer(peer, frame: ["type": Frame.chunk, "seq": seq, "generation": generation, "part": part,
                                                        "data": piece]) else { return false }
                    pieces += 1
                    off = end
                }
            }
            frame["oolSizes"] = regions.map { $0.count }
            lock.withLock {
                stats.chunkedOut += 1
                stats.chunksOut += pieces
            }
        }
        if stamp { frame["sent"] = NSNumber(value: Self.now()) }
        return link.sendToPeer(peer, frame: frame)
    }

    private static func assemblyKey(_ peer: String, _ part: String, _ seq: Int, _ generation: Int) -> String {
        "\(peer) \(part) \(seq) \(generation)"
    }

    private func receivedChunk(peer: String, frame f: [String: Any]) {
        guard let seq = (f["seq"] as? NSNumber)?.intValue, let part = f["part"] as? String, let data = f["data"] as? Data else { return }
        let generation = (f["generation"] as? NSNumber)?.intValue ?? 0
        let key = Self.assemblyKey(peer, part, seq, generation)
        lock.withLock {
            if assembling[key] == nil { assembling[key] = Data() }
            assembling[key]!.append(data)
        }
    }

    private func regions(of f: [String: Any], peer: String, part: String, seq: Int, generation: Int) -> [Data]? {
        guard let sizes = f["oolSizes"] as? [NSNumber] else { return (f["ool"] as? [Data]) ?? [] }
        let bytes = lock.withLock { assembling.removeValue(forKey: Self.assemblyKey(peer, part, seq, generation)) } ?? Data()
        let want = sizes.reduce(0) { $0 + $1.intValue }
        guard bytes.count == want else {
            log("pairing relay: \(part) \(seq) from \(peer): \(bytes.count) bytes in pieces, \(want) expected; dropped")
            return nil
        }
        var out: [Data] = []
        var off = bytes.startIndex
        for n in sizes.map(\.intValue) {
            out.append(bytes.subdata(in: off..<(off + n)))
            off += n
        }
        return out
    }

    private func fail(_ m: MachHostReceivedMessage, code: UInt32, host: MachHostTask) {
        lock.withLock { stats.failedOut += 1 }
        for d in m.descriptors {
            switch d {
            case let .port(name, _), let .guardedPort(name, _, _): try? host.deallocate(name)
            case let .oolPorts(names, _): for x in names { try? host.deallocate(x) }
            case .ool: break
            }
        }
        guard MachPortName.isValid(m.replyPort) else { return }
        sendErrorReply(port: m.replyPort, type: m.replyType, requestID: m.id, code: code, host: host)
    }

    private func sendErrorReply(port: UInt32, type: UInt32, requestID: Int32, code: UInt32, host: MachHostTask) {
        let body = Self.ndr + Self.le32(code)
        do {
            try host.send(MachHostOutgoingMessage(remotePort: port, remoteDisposition: type, id: requestID &+ 100, body: body),
                          timeout: 0)
        } catch {
            try? host.deallocate(port)
        }
    }

    private func answerOutgoing(peer: String, seq: Int, code: UInt32, link: PairingRelayLink) {
        guard let o = lock.withLock({ () -> Outgoing? in
            let o = outgoing[peer]?.removeValue(forKey: seq)
            if o != nil {
                stats.failedOut += 1
                if code == MachMsgReturn.sendTimedOut { stats.timedOutOut += 1 }
            }
            return o
        }) else { return }
        sendErrorReply(port: o.replyPort, type: o.replyType, requestID: o.id, code: code, host: link.host)
    }

    private func receivedReply(peer: String, frame f: [String: Any], link: PairingRelayLink) {
        guard let seq = (f["seq"] as? NSNumber)?.intValue else { return }
        let generation = (f["generation"] as? NSNumber)?.intValue ?? 0
        let code = UInt32(truncatingIfNeeded: (f["code"] as? NSNumber)?.int64Value ?? 0)
        guard let o = lock.withLock({ () -> Outgoing? in
            guard generation == (linkGeneration[peer] ?? 0) else { return nil }
            return outgoing[peer]?.removeValue(forKey: seq)
        }) else { return }
        let host = link.host
        if code != 0 {
            lock.withLock {
                _ = assembling.removeValue(forKey: Self.assemblyKey(peer, "reply", seq, generation))
                stats.failedOut += 1
                if code == MachMsgReturn.sendTimedOut { stats.timedOutOut += 1 }
            }
            sendErrorReply(port: o.replyPort, type: o.replyType, requestID: o.id, code: code, host: host)
            return
        }
        let id = Int32(truncatingIfNeeded: (f["id"] as? NSNumber)?.intValue ?? Int(o.id &+ 100))
        let body = [UInt8]((f["body"] as? Data) ?? Data())
        guard let regions = regions(of: f, peer: peer, part: "reply", seq: seq, generation: generation) else {
            lock.withLock { stats.failedOut += 1 }
            sendErrorReply(port: o.replyPort, type: o.replyType, requestID: o.id, code: MachMsgReturn.sendTooLarge, host: host)
            return
        }
        do {
            try host.send(MachHostOutgoingMessage(remotePort: o.replyPort, remoteDisposition: o.replyType, id: id,
                                                  descriptors: regions.map { .ool(data: [UInt8]($0), copy: 1) }, body: body),
                          timeout: 0)
        } catch {
            try? host.deallocate(o.replyPort)
        }
        let ms = Double(Self.now() &- o.started) / 1e6
        lock.withLock {
            stats.repliesOut += 1
            if stats.roundTripsMs.count < Self.keptSamples { stats.roundTripsMs.append(ms) }
        }
    }

    private func receivedRequest(peer: String, frame f: [String: Any], link: PairingRelayLink) {
        guard let seq = (f["seq"] as? NSNumber)?.intValue else { return }
        let generation = (f["generation"] as? NSNumber)?.intValue ?? 0
        let id = Int32(truncatingIfNeeded: (f["id"] as? NSNumber)?.intValue ?? 0)
        let body = [UInt8]((f["body"] as? Data) ?? Data())
        let wantsReply = (f["reply"] as? Bool) ?? true
        let sent = (f["sent"] as? NSNumber)?.uint64Value
        startThreads(link)
        guard let regions = regions(of: f, peer: peer, part: "request", seq: seq, generation: generation) else {
            if wantsReply { answerPeer(peer, seq: seq, generation: generation, code: MachMsgReturn.sendTooLarge, link: link) }
            return
        }
        let size = regions.reduce(body.count) { $0 + $1.count }
        let waitUntil = Date().addingTimeInterval(options.requestTimeout)
        queuedChanged.lock()
        while queuedBytes > 0, queuedBytes + size > options.queuedLimit, lock.withLock({ running }), Date() < waitUntil {
            _ = queuedChanged.wait(until: min(waitUntil, Date().addingTimeInterval(0.25)))
        }
        queuedBytes += size
        queuedChanged.unlock()
        let (queue, own) = lock.withLock { () -> (DispatchQueue, Int) in
            let own = linkGeneration[peer] ?? 0
            if let q = deliverQueues[peer] { return (q, own) }
            let q = DispatchQueue(label: "swiftcode.pairing.relay.deliver.\(peer.prefix(8))")
            deliverQueues[peer] = q
            return (q, own)
        }
        let deadline = deadline()
        queue.async { [self] in
            defer {
                queuedChanged.lock()
                queuedBytes -= size
                queuedChanged.broadcast()
                queuedChanged.unlock()
            }
            deliver(peer: peer, seq: seq, generation: generation, ownGeneration: own, id: id, body: body, regions: regions,
                    wantsReply: wantsReply, sent: sent, deadline: deadline, link: link)
        }
    }

    private func answerPeer(_ peer: String, seq: Int, generation: Int, code: UInt32, link: PairingRelayLink) {
        lock.withLock { stats.failedIn += 1 }
        link.sendToPeer(peer, frame: ["type": Frame.reply, "seq": seq, "generation": generation, "code": NSNumber(value: code)])
    }

    private func guestPort(link: PairingRelayLink, until: UInt64, stillWanted: () -> Bool) -> UInt32? {
        if let p = lock.withLock({ localPort }) { return p }
        var said = false
        while true {
            do {
                let p = try link.findInGuest(options.localName)
                lock.withLock { localPort = p }
                if said { log("pairing relay: found \(options.localName) in this guest") }
                return p
            } catch {
                if !said { log("pairing relay: \(options.localName) not found in this guest (\(error)); retrying") }
                said = true
            }
            if Self.now() >= until || !stillWanted() { return nil }
            Thread.sleep(forTimeInterval: 0.25)
        }
    }

    private func forgetGuestPort(_ p: UInt32, host: MachHostTask) {
        let drop = lock.withLock { () -> Bool in
            guard localPort == p else { return false }
            localPort = nil
            return true
        }
        if drop { try? host.deallocate(p) }
    }

    private func deliver(peer: String, seq: Int, generation: Int, ownGeneration: Int, id: Int32, body: [UInt8], regions: [Data],
                         wantsReply: Bool, sent: UInt64?, deadline: UInt64, link: PairingRelayLink) {
        let host = link.host
        let current = { [self] in lock.withLock { running && (linkGeneration[peer] ?? 0) == ownGeneration } }
        guard current() else { return }
        let size = regions.reduce(body.count) { $0 + $1.count }
        let lookupUntil = min(deadline, Self.now() &+ UInt64(options.lookupWait * 1e9))
        var attempts = 0
        while true {
            attempts += 1
            guard let target = guestPort(link: link, until: lookupUntil, stillWanted: current) else {
                if wantsReply { answerPeer(peer, seq: seq, generation: generation, code: MachMsgReturn.sendInvalidDest, link: link) }
                return
            }
            var reply: UInt32 = 0
            if wantsReply {
                do {
                    reply = try host.makePort()
                    guard let set = lock.withLock({ replySet }) else { throw MachHostError(MachKern.failure) }
                    try host.addMember(reply, to: set)
                } catch {
                    if MachPortName.isValid(reply) { try? host.destroyPort(reply) }
                    answerPeer(peer, seq: seq, generation: generation, code: MachMsgReturn.sendNoBuffer, link: link)
                    return
                }
                lock.withLock { incoming[reply] = Incoming(peer: peer, seq: seq, generation: generation, deadline: deadline) }
            }
            let left = deadline > Self.now() ? deadline - Self.now() : 0
            do {
                try host.send(MachHostOutgoingMessage(
                    remotePort: target, remoteDisposition: MachMsgType.copySend,
                    localPort: reply, localDisposition: wantsReply ? MachMsgType.makeSendOnce : 0, id: id,
                    descriptors: regions.map { .ool(data: [UInt8]($0), copy: 1) }, body: body), timeout: left)
            } catch let e as MachHostError {
                if wantsReply {
                    lock.withLock { _ = incoming.removeValue(forKey: reply) }
                    try? host.destroyPort(reply)
                }
                if e.code == MachMsgReturn.sendInvalidDest && attempts == 1 {
                    forgetGuestPort(target, host: host)
                    continue
                }
                if e.code == MachMsgReturn.sendInvalidDest { forgetGuestPort(target, host: host) }
                log("pairing relay: delivery of \(peer)'s request id \(id) failed: \(e)")
                if wantsReply { answerPeer(peer, seq: seq, generation: generation, code: e.code, link: link) }
                return
            } catch {
                if wantsReply {
                    lock.withLock { _ = incoming.removeValue(forKey: reply) }
                    try? host.destroyPort(reply)
                    answerPeer(peer, seq: seq, generation: generation, code: MachKern.failure, link: link)
                }
                return
            }
            let n = lock.withLock { () -> Int in
                stats.requestsIn += 1
                stats.bytesIn += size
                stats.largestIn = max(stats.largestIn, size)
                if let sent, stats.oneWayMs.count < Self.keptSamples {
                    stats.oneWayMs.append(Double(Self.now() &- sent) / 1e6)
                }
                return stats.requestsIn
            }
            if n <= 3 || n.isMultiple(of: 100) {
                log("pairing relay: request \(n) from \(peer) delivered: id \(id), \(size) bytes")
            }
            return
        }
    }

    private func startThreads(_ link: PairingRelayLink) {
        let start = lock.withLock { () -> Bool in
            guard !threadsStarted, running else { return false }
            threadsStarted = true
            farLink = link
            return true
        }
        guard start else { return }
        let host = link.host
        do {
            let set = try host.makePortSet()
            lock.withLock { replySet = set }
        } catch {
            log("pairing relay: no port set for replies: \(error)")
        }
        let receiver = Thread { [weak self] in self?.receiveReplies(host: host) }
        receiver.name = "swiftcode-pair-relay-replies"
        receiver.start()
        let sweeper = Thread { [weak self] in
            while let self, lock.withLock({ running }) {
                sweep()
                Thread.sleep(forTimeInterval: 0.25)
            }
        }
        sweeper.name = "swiftcode-pair-relay-timeouts"
        sweeper.start()
    }

    private func receiveReplies(host: MachHostTask) {
        while true {
            guard let set = lock.withLock({ running ? replySet : nil }) else { return }
            let m: MachHostReceivedMessage
            do {
                m = try host.receive(on: set, timeout: 250_000_000, tracked: true)
            } catch let e as MachHostError where e == .timedOut || e == .interrupted {
                continue
            } catch {
                return
            }
            defer { host.finishedMessage() }
            let (entry, link) = lock.withLock { (incoming.removeValue(forKey: m.localPort), farLink) }
            try? host.destroyPort(m.localPort)
            guard let entry, let link else {
                host.discard(m)
                continue
            }
            var regions: [Data] = []
            for d in m.descriptors {
                switch d {
                case let .ool(data, _, _): regions.append(Data(data))
                case let .port(name, _), let .guardedPort(name, _, _): try? host.deallocate(name)
                case let .oolPorts(names, _): for x in names { try? host.deallocate(x) }
                }
            }
            if MachPortName.isValid(m.replyPort) { try? host.deallocate(m.replyPort) }
            if m.isFromKernel && m.id == MachNotify.sendOnce {
                answerPeer(entry.peer, seq: entry.seq, generation: entry.generation, code: MachKern.migServerDied, link: link)
                continue
            }
            _ = sendMessage(to: entry.peer, frame: ["type": Frame.reply, "seq": entry.seq, "generation": entry.generation,
                                                    "code": NSNumber(value: 0), "id": Int(m.id), "body": Data(m.body)],
                            regions: regions, part: "reply", seq: entry.seq, generation: entry.generation, stamp: false, link: link)
        }
    }

    private func sweep() {
        let now = Self.now()
        let (late, lateIn, link, host) = lock.withLock { () -> ([(String, Int)], [(UInt32, Incoming)], PairingRelayLink?, MachHostTask?) in
            var out: [(String, Int)] = []
            for (p, list) in outgoing {
                for (s, o) in list where o.deadline <= now { out.append((p, s)) }
            }
            let inc = incoming.filter { $0.value.deadline <= now }.map { ($0.key, $0.value) }
            for (k, _) in inc { incoming.removeValue(forKey: k) }
            return (out, inc, farLink, farLink?.host)
        }
        guard let link, let host else { return }
        for (p, s) in late {
            log("pairing relay: request \(s) to \(p) got no answer in \(Int(options.requestTimeout)) s")
            answerOutgoing(peer: p, seq: s, code: MachMsgReturn.sendTimedOut, link: link)
        }
        for (port, e) in lateIn {
            try? host.destroyPort(port)
            answerPeer(e.peer, seq: e.seq, generation: e.generation, code: MachMsgReturn.sendTimedOut, link: link)
        }
    }

    @discardableResult
    public func link(peer rawPeer: String, received frame: [String: Any], link: PairingRelayLink) -> Bool {
        let peer = rawPeer.uppercased()
        switch frame["type"] as? String {
        case Frame.request: receivedRequest(peer: peer, frame: frame, link: link)
        case Frame.reply: receivedReply(peer: peer, frame: frame, link: link)
        case Frame.chunk: receivedChunk(peer: peer, frame: frame)
        default: return false
        }
        return true
    }

    public func linkChanged(peer rawPeer: String, up: Bool, link: PairingRelayLink) {
        let peer = rawPeer.uppercased()
        let (waiting, abandoned) = lock.withLock { () -> ([Int], [UInt32]) in
            linkGeneration[peer] = (linkGeneration[peer] ?? 0) + 1
            let w = Array((outgoing[peer] ?? [:]).keys).sorted()
            let a = incoming.filter { $0.value.peer == peer }.map(\.key)
            for k in a { incoming.removeValue(forKey: k) }
            for k in assembling.keys where k.hasPrefix(peer + " ") { assembling.removeValue(forKey: k) }
            return (w, a)
        }
        for p in abandoned { try? link.host.destroyPort(p) }
        for s in waiting { answerOutgoing(peer: peer, seq: s, code: MachMsgReturn.sendInvalidDest, link: link) }
        let st = lock.withLock { stats }
        if !up || st.requestsOut + st.requestsIn > 0 {
            log("pairing relay: link with \(peer) \(up ? "up" : "down")"
                + (waiting.isEmpty ? "" : "; \(waiting.count) requests answered MACH_SEND_INVALID_DEST")
                + (abandoned.isEmpty ? "" : "; \(abandoned.count) deliveries abandoned") + "; " + st.summary())
        }
    }

    static let ndr: [UInt8] = [0, 0, 0, 0, 1, 0, 0, 0]
    static func le32(_ v: UInt32) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 24)] }
}
