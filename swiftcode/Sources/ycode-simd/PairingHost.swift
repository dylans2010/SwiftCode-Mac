#if os(Linux) && arch(arm64)
import Foundation
import Glibc
import YcodeDarwinKernel
import YcodeHostServices
import YcodeSimFeatures

protocol PairingRelayContext: PairingRelayLink {}

protocol PairingRelay: AnyObject, Sendable {
    func endpoint(peer: String, received message: MachHostReceivedMessage, context: PairingRelayContext)
    func link(peer: String, received frame: [String: Any], context: PairingRelayContext)
    func linkChanged(peer: String, up: Bool, context: PairingRelayContext)
    func stop(context: PairingRelayContext)
    var summary: String { get }
}

final class TransportPairingRelay: PairingRelay, @unchecked Sendable {
    let core: PairingTransportRelay

    init(options: PairingTransportRelay.Options = .fromEnvironment(), log: @escaping (String) -> Void) {
        core = PairingTransportRelay(options: options, log: log)
    }

    func endpoint(peer: String, received message: MachHostReceivedMessage, context: PairingRelayContext) {
        core.endpoint(peer: peer, received: message, link: context)
    }

    func link(peer: String, received frame: [String: Any], context: PairingRelayContext) {
        if !core.link(peer: peer, received: frame, link: context) {
            core.log("pairing: link frame '\(frame["type"] as? String ?? "?")' from \(peer) ignored")
        }
    }

    func linkChanged(peer: String, up: Bool, context: PairingRelayContext) {
        core.linkChanged(peer: peer, up: up, link: context)
    }

    func stop(context: PairingRelayContext) { core.stop(link: context) }

    var summary: String { core.statistics.summary() }
}

final class AcknowledgingPairingRelay: PairingRelay, @unchecked Sendable {
    let log: (String) -> Void
    let answer: Bool
    private let lock = NSLock()
    private var counts: [String: (requests: Int, bytes: Int)] = [:]

    init(answer: Bool, log: @escaping (String) -> Void) {
        self.answer = answer
        self.log = log
    }

    static let ndr: [UInt8] = [0, 0, 0, 0, 1, 0, 0, 0]

    func endpoint(peer: String, received m: MachHostReceivedMessage, context: PairingRelayContext) {
        let bytes = m.descriptors.reduce(0) { n, d in
            if case let .ool(data, _, _) = d { return n + data.count }
            return n
        }
        let (n, total) = lock.withLock { () -> (Int, Int) in
            var c = counts[peer] ?? (0, 0)
            c.requests += 1
            c.bytes += bytes
            counts[peer] = c
            return (c.requests, c.bytes)
        }
        if n <= 3 || n.isMultiple(of: 100) {
            log("pairing: relay stub: request \(n) for \(peer): id \(m.id), \(bytes) out-of-line bytes (\(total) in all); "
                + (answer && m.id == PairingEndpoint.requestID ? "acknowledged, not delivered (W5)" : "dropped"))
        }
        guard answer, m.id == PairingEndpoint.requestID, MachPortName.isValid(m.replyPort) else {
            context.host.discard(m)
            return
        }
        for d in m.descriptors {
            switch d {
            case let .port(name, _), let .guardedPort(name, _, _): try? context.host.deallocate(name)
            case let .oolPorts(names, _): for x in names { try? context.host.deallocate(x) }
            case .ool: break
            }
        }
        do {
            try context.host.reply(to: m, id: PairingEndpoint.replyID, body: Self.ndr + [0, 0, 0, 0])
        } catch {
            log("pairing: relay stub: reply to \(peer) failed: \(error)")
        }
    }

    func link(peer: String, received frame: [String: Any], context: PairingRelayContext) {
        log("pairing: relay stub: link frame '\(frame["type"] as? String ?? "?")' from \(peer) ignored")
    }

    func linkChanged(peer: String, up: Bool, context: PairingRelayContext) {}

    func stop(context: PairingRelayContext) {}

    var summary: String {
        lock.withLock { counts.map { "\($0.key): \($0.value.requests) requests, \($0.value.bytes) bytes (stub)" }.sorted().joined(separator: "; ") }
    }

    var statistics: [String: (requests: Int, bytes: Int)] { lock.withLock { counts } }
}

final class PeerEndpoint: @unchecked Sendable {
    let peer: String
    let port: UInt32
    private let host: MachHostTask
    private let lock = NSLock()
    private var stopping = false

    init(peer: String, host: MachHostTask) throws {
        self.peer = peer
        self.host = host
        port = try host.makePort(sendRight: true, qlimit: 64)
    }

    var name: String { PairingEndpoint.remoteName(peer: peer) }

    func start(_ deliver: @escaping @Sendable (MachHostReceivedMessage) -> Void) {
        let t = Thread { [self] in
            while !lock.withLock({ stopping }) {
                let m: MachHostReceivedMessage
                do {
                    m = try host.receive(on: port, timeout: 250_000_000, tracked: true)
                } catch let e as MachHostError where e == .timedOut || e == .interrupted {
                    continue
                } catch {
                    return
                }
                deliver(m)
                host.finishedMessage()
            }
        }
        t.name = "swiftcode-pair-endpoint"
        t.start()
    }

    func stop() {
        lock.withLock { stopping = true }
        try? host.destroyPort(port)
    }
}

final class PeerLink: @unchecked Sendable {
    let fd: Int32
    private let writeLock = NSLock()
    private var buffer: [UInt8] = []
    private var closed = false
    var peer: String?

    init(fd: Int32) {
        self.fd = fd
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_KEEPALIVE, &on, socklen_t(MemoryLayout<Int32>.size))
    }

    @discardableResult
    func send(_ frame: [String: Any]) -> Bool {
        guard let bytes = PairLinkFrame.encode(frame) else { return false }
        return writeLock.withLock {
            guard !closed else { return false }
            var off = 0
            while off < bytes.count {
                let n = bytes[off...].withUnsafeBytes { Glibc.send(fd, $0.baseAddress, $0.count, Int32(MSG_NOSIGNAL)) }
                if n < 0 && errno == EINTR { continue }
                if n <= 0 { return false }
                off += n
            }
            return true
        }
    }

    func receive(timeout seconds: Int? = nil) -> [String: Any]? {
        if let seconds {
            var tv = timeval(tv_sec: seconds, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        }
        var chunk = [UInt8](repeating: 0, count: 65536)
        while true {
            do {
                if let frame = try PairLinkFrame.decodeFirst(&buffer) { return frame }
            } catch {
                return nil
            }
            let n = read(fd, &chunk, chunk.count)
            if n < 0 && errno == EINTR { continue }
            if n <= 0 { return nil }
            buffer += chunk[0..<n]
        }
    }

    func close() {
        writeLock.withLock {
            guard !closed else { return }
            closed = true
            shutdown(fd, Int32(SHUT_RDWR))
            Glibc.close(fd)
        }
    }
}

enum PairSockets {
    static func base() -> String { DeviceLayout.memoryBase ?? NSTemporaryDirectory() }

    static func path(udid: String) -> String { PairLinkFrame.socketPath(base: base(), uid: getuid(), udid: udid) }

    static func connect(udid: String) -> Int32? {
        let fd = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue) | Int32(SOCK_CLOEXEC.rawValue), 0)
        guard fd >= 0 else { return nil }
        if withUnixAddress(path(udid: udid), { Glibc.connect(fd, $0, $1) }) == 0 { return fd }
        Glibc.close(fd)
        return nil
    }

    static func command(udid: String, verb: String, args: [String] = [], timeout: Int = 30) -> [String: Any]? {
        guard let fd = connect(udid: udid) else { return nil }
        let link = PeerLink(fd: fd)
        defer { link.close() }
        guard link.send(["type": "command", "verb": verb, "args": args]) else { return nil }
        return link.receive(timeout: timeout)
    }
}

final class PairingHost: HostChannelServer, PairingRelayContext, @unchecked Sendable {
    let udid: String
    let dev: String
    let set: String
    let family: PairingFamily
    let host: MachHostTask
    private weak var session: DeviceSession?
    let log: (String) -> Void
    var relay: PairingRelay

    private let lock = NSLock()
    private var sequencer = PairingSequencer()
    private var links: [String: PeerLink] = [:]
    private var endpoints: [String: PeerEndpoint] = [:]
    private var listenFD: Int32 = -1
    private var running = true
    private let endpointQueue = DispatchQueue(label: "swiftcode.pairing.endpoints")
    private let agentQueue = DispatchQueue(label: "swiftcode.pairing.agent")
    private let started = Date()

    private var agentLink: SettingsAgentLink?
    private var agentBuffer: [UInt8] = []
    private var agentPID: Int?
    private var nextID = 1
    private var waiting: [Int: (semaphore: DispatchSemaphore, reply: [String: Any]?)] = [:]
    private var activation: [String: String] = [:]
    var agentReplyTimeout: TimeInterval = Double(ProcessInfo.processInfo.environment["SWIFTCODE_PAIRING_AGENT_WAIT_S"] ?? "") ?? 120

    init(udid: String, dev: String, set: String, family: PairingFamily, host: MachHostTask, session: DeviceSession?,
         log: @escaping (String) -> Void) {
        self.udid = udid.uppercased()
        self.dev = dev
        self.set = set
        self.family = family
        self.host = host
        self.session = session
        self.log = log
        sequencer.switchAbsentPeers = ProcessInfo.processInfo.environment["SWIFTCODE_PAIRING_SWITCH_ABSENT"] != "defer"
        switch ProcessInfo.processInfo.environment["SWIFTCODE_PAIRING_RELAY"] ?? "relay" {
        case "ack": relay = AcknowledgingPairingRelay(answer: true, log: log)
        case "none": relay = AcknowledgingPairingRelay(answer: false, log: log)
        default: relay = TransportPairingRelay(log: log)
        }
    }

    private func elapsed() -> String { String(format: "%.1f s", Date().timeIntervalSince(started)) }

    static func deviceSet(for dev: String) -> String {
        if let s = ProcessInfo.processInfo.environment["SWIFTCODE_DEVICE_SET"], !s.isEmpty { return absolutePath(s) }
        return (dev as NSString).deletingLastPathComponent
    }

    func start() {
        reloadRecords(reason: "boot")
        startListener()
        Thread.detachNewThread { [self] in
            while lock.withLock({ running }) {
                if session?.boundControl != nil {
                    let actions = lock.withLock { sequencer.controlBound() }
                    perform(actions)
                    return
                }
                Thread.sleep(forTimeInterval: 0.5)
            }
        }
        if family == .watch {
            let t = Thread { [self] in connectorLoop() }
            t.name = "swiftcode-pair-connector"
            t.start()
        }
    }

    func stop() {
        let (eps, ls, fd) = lock.withLock { () -> ([PeerEndpoint], [PeerLink], Int32) in
            running = false
            defer { endpoints = [:]; links = [:]; listenFD = -1 }
            return (Array(endpoints.values), Array(links.values), listenFD)
        }
        eps.forEach { $0.stop() }
        relay.stop(context: self)
        ls.forEach { $0.close() }
        if fd >= 0 { shutdown(fd, Int32(SHUT_RDWR)); close(fd) }
        unlink(PairSockets.path(udid: udid))
    }

    private func loadPairs() -> [DevicePair] {
        do {
            return try DevicePairStore.load(set: set).pairs(of: udid)
        } catch {
            log("pairing: cannot read the pair records in \(set): \(error)")
            return []
        }
    }

    var pairedBeforePath: String { dev + "/swiftcode-paired-peers" }

    private func pairedBefore() -> Set<String> {
        let text = (try? String(contentsOfFile: pairedBeforePath, encoding: .utf8)) ?? ""
        return Set(text.split(whereSeparator: \.isNewline).map { $0.uppercased() })
    }

    private func setPairedBefore(_ peer: String, _ on: Bool) {
        var s = pairedBefore()
        if on { s.insert(peer) } else { s.remove(peer) }
        try? (s.sorted().joined(separator: "\n") + (s.isEmpty ? "" : "\n")).write(toFile: pairedBeforePath, atomically: true, encoding: .utf8)
    }

    @discardableResult
    func reloadRecords(reason: String) -> [DevicePair] {
        let pairs = loadPairs()
        let before = pairedBefore()
        let list = pairs.map { p -> (peer: String, active: Bool, previouslyPaired: Bool) in
            let peer = p.peer(of: udid)!
            return (peer, family == .watch || p.active, before.contains(peer))
        }
        var actions: [PairingSequencer.Action] = []
        var unpairActions: [PairingSequencer.Action] = []
        let gone: [String] = lock.withLock {
            let now = Set(list.map { $0.peer.uppercased() })
            let old = Set(sequencer.peers.keys)
            var out: [String] = []
            for p in old.subtracting(now).sorted() {
                unpairActions += sequencer.unpaired(peer: p)
                out.append(p)
            }
            actions += sequencer.setPairs(list)
            return out
        }
        log("pairing: \(reason): \(pairs.isEmpty ? "no pairs" : pairs.map { "pair \($0.id) with \($0.peer(of: udid)!)\($0.active ? " (active)" : "")" }.joined(separator: ", "))"
            + (gone.isEmpty ? "" : "; removed: \(gone.joined(separator: ", "))"))
        perform(actions)
        for a in unpairActions {
            if case .agent = a { perform([a]) }
        }
        if !gone.isEmpty {
            let afterAgent = unpairActions
            agentQueue.async { [self] in
                for a in afterAgent {
                    if case .unregister(let peer) = a { endpointQueue.async { [self] in unregister(peer) } }
                }
                for p in gone { dropLink(p) }
            }
        }
        return pairs
    }

    private func perform(_ actions: [PairingSequencer.Action]) {
        for a in actions {
            switch a {
            case .register(let peer):
                endpointQueue.async { [self] in register(peer) }
            case .unregister(let peer):
                endpointQueue.async { [self] in unregister(peer) }
            case .announceRegistered(let peer):
                endpointQueue.async { [self] in
                    let link = lock.withLock { links[peer] }
                    _ = link?.send(["type": "registered", "udid": udid])
                }
            case .agent(let request):
                agentQueue.async { [self] in runAgent(request) }
            }
        }
    }

    private func register(_ peer: String) {
        guard let c = session?.boundControl else {
            perform(lock.withLock { sequencer.registered(peer: peer, ok: false) })
            return
        }
        let name = PairingEndpoint.remoteName(peer: peer)
        do {
            let ep = try PeerEndpoint(peer: peer, host: host)
            ep.start { [weak self] m in
                guard let self else { return }
                relay.endpoint(peer: peer, received: m, context: self)
            }
            do {
                try c.registerEndpoint(name, port: ep.port)
            } catch let e as LaunchSimControlError where e.errno == 17 || e.code == 17 {
                try? c.unregisterEndpoint(name)
                try c.registerEndpoint(name, port: ep.port)
            }
            lock.withLock { endpoints[peer] = ep }
            log("pairing: 701 registered \(name) (\(elapsed()) after the start)")
            perform(lock.withLock { sequencer.registered(peer: peer, ok: true) })
        } catch {
            log("pairing: 701 register \(name) failed: \(error)")
            perform(lock.withLock { sequencer.registered(peer: peer, ok: false) })
        }
    }

    private func unregister(_ peer: String) {
        let name = PairingEndpoint.remoteName(peer: peer)
        let ep = lock.withLock { endpoints.removeValue(forKey: peer) }
        if let c = session?.boundControl {
            do {
                try c.unregisterEndpoint(name)
                log("pairing: 709 unregistered \(name)")
            } catch {
                log("pairing: 709 unregister \(name): \(error)")
            }
        }
        ep?.stop()
    }

    private func runAgent(_ request: PairingAgentRequest) {
        log("pairing: agent: \(request.summary) (\(elapsed()) after the start)")
        let activePeer: String? = {
            switch request {
            case let .setActive(p, _), let .switchTo(p): p
            default: nil
            }
        }()
        if let activePeer { lock.withLock { activation[activePeer] = "sent at \(elapsed())" } }
        let reply = agentRequest(request.message)
        let ok = (reply?["ok"] as? Bool) ?? false
        let detail = [reply?["detail"] as? String, reply?["error"] as? String].compactMap { $0 }.joined(separator: "; ")
        let outcome = reply == nil ? "not answered" : ok ? "done" : "failed"
        log("pairing: agent: \(request.op) \(outcome)\(detail.isEmpty ? "" : ": \(detail)")")
        if let activePeer {
            lock.withLock { activation[activePeer] = "\(outcome) at \(elapsed())" + (detail.isEmpty ? "" : ": \(detail)") }
        }
        switch request {
        case let .setActive(peer, _):
            lock.withLock { sequencer.activated(peer: peer, ok: ok) }
            if ok { setPairedBefore(peer, true) }
        case let .switchTo(peer):
            if ok, reply?["switched"] as? Bool == true {
                lock.withLock { sequencer.activated(peer: peer, ok: true) }
                setPairedBefore(peer, true)
            }
        case let .unpair(peer):
            if ok { setPairedBefore(peer, false) }
        default:
            break
        }
    }

    private func linkUp(_ peer: String, _ link: PeerLink) {
        link.peer = peer
        let old = lock.withLock { () -> PeerLink? in
            let o = links[peer]
            links[peer] = link
            return o
        }
        old?.close()
        log("pairing: link with \(peer) up (both devices run; \(elapsed()) after the start)")
        relay.linkChanged(peer: peer, up: true, context: self)
        perform(lock.withLock { sequencer.linkUp(peer: peer) })
        while let frame = link.receive() {
            switch frame["type"] as? String {
            case "registered":
                log("pairing: \(peer)'s guest has its endpoint")
                perform(lock.withLock { sequencer.peerRegistered(peer: peer) })
            default:
                relay.link(peer: peer, received: frame, context: self)
            }
        }
        let current = lock.withLock { () -> Bool in
            guard links[peer] === link else { return false }
            links[peer] = nil
            return true
        }
        link.close()
        guard current else { return }
        log("pairing: link with \(peer) down (\(elapsed()) after the start)")
        relay.linkChanged(peer: peer, up: false, context: self)
        perform(lock.withLock { sequencer.linkDown(peer: peer) })
    }

    private func dropLink(_ peer: String) {
        lock.withLock { links[peer] }?.close()
    }

    private func connectorLoop() {
        var said = false
        while lock.withLock({ running }) {
            let phone = loadPairs().first?.companion
            if let phone, lock.withLock({ links[phone] == nil }), let fd = PairSockets.connect(udid: phone) {
                let link = PeerLink(fd: fd)
                if link.send(["type": "hello", "udid": udid, "role": "gizmo", "pid": Int(getpid()), "version": PairLinkFrame.protocolVersion]),
                   let answer = link.receive(timeout: 10), answer["type"] as? String == "welcome" {
                    var tv = timeval(tv_sec: 0, tv_usec: 0)
                    setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
                    said = false
                    linkUp(phone, link)
                } else {
                    link.close()
                    if !said { log("pairing: the phone \(phone) refused the link") }
                    said = true
                }
            }
            Thread.sleep(forTimeInterval: 2)
        }
    }

    private func startListener() {
        let path = PairSockets.path(udid: udid)
        unlink(path)
        let fd = socket(AF_UNIX, Int32(SOCK_STREAM.rawValue) | Int32(SOCK_CLOEXEC.rawValue), 0)
        guard fd >= 0, withUnixAddress(path, { bind(fd, $0, $1) }) == 0, chmod(path, 0o600) == 0, listen(fd, 8) == 0 else {
            log("pairing: no rendezvous socket at \(path): \(String(cString: strerror(errno)))")
            if fd >= 0 { close(fd) }
            return
        }
        lock.withLock { listenFD = fd }
        log("pairing: rendezvous socket \(path)")
        let t = Thread { [self] in
            while true {
                let c = accept(fd, nil, nil)
                if c < 0 {
                    if errno == EINTR { continue }
                    return
                }
                let t = Thread { [self] in serveConnection(PeerLink(fd: c)) }
                t.name = "swiftcode-pair-connection"
                t.start()
            }
        }
        t.name = "swiftcode-pair-listener"
        t.start()
    }

    private func serveConnection(_ link: PeerLink) {
        guard let first = link.receive(timeout: 10) else {
            link.close()
            return
        }
        switch first["type"] as? String {
        case "hello":
            guard let peer = (first["udid"] as? String)?.uppercased() else { link.close(); return }
            let pairs = reloadRecords(reason: "hello from \(peer)")
            guard family == .phone, pairs.contains(where: { $0.gizmo == peer }) else {
                _ = link.send(["type": "refused", "reason": "no pair with \(peer)"])
                link.close()
                return
            }
            _ = link.send(["type": "welcome", "udid": udid, "pid": Int(getpid())])
            var tv = timeval(tv_sec: 0, tv_usec: 0)
            setsockopt(link.fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            linkUp(peer, link)
        case "command":
            let verb = first["verb"] as? String ?? ""
            let args = first["args"] as? [String] ?? []
            let (ok, text) = command(verb, args)
            var answer: [String: Any] = ["type": "answer", "ok": ok, "text": text]
            if verb == "state" { answer["state"] = stateDictionary() }
            _ = link.send(answer)
            link.close()
        default:
            link.close()
        }
    }

    func stateDictionary() -> [String: Any] {
        lock.withLock {
            var peers: [String: Any] = [:]
            for (p, s) in sequencer.peers {
                var d: [String: Any] = ["linked": s.linked, "localRegistered": s.localRegistered, "peerRegistered": s.peerRegistered,
                                        "connected": s.connected, "connectSent": s.connectSent, "active": s.active]
                if let a = activation[p] { d["activation"] = a }
                peers[p] = d
            }
            return ["udid": udid, "pid": Int(getpid()), "agent": agentPID != nil, "peers": peers]
        }
    }

    func command(_ verb: String, _ args: [String]) -> (Bool, String) {
        switch verb {
        case "state":
            let s = lock.withLock {
                sequencer.peers.map { p, v in
                    "\(p) \(v.connected ? "connected" : v.linked ? "linked" : "not linked")\(v.active ? " active" : "")"
                        + (activation[p].map { " (set-active \($0))" } ?? "")
                }
            }
            return (true, "\(udid): agent \(lock.withLock { agentPID != nil } ? "up" : "not up"); " + (s.isEmpty ? "no pairs" : s.sorted().joined(separator: ", ")))
        case "reload":
            let pairs = reloadRecords(reason: "the pair records changed")
            return (true, "\(pairs.count) pairs")
        case "unpair":
            guard let peer = args.first?.uppercased() else { return (false, "unpair <peer UDID>") }
            reloadRecords(reason: "unpair from \(peer)")
            agentQueue.sync {}
            endpointQueue.sync {}
            dropLink(peer)
            setPairedBefore(peer, false)
            return (true, "unpaired from \(peer)")
        case "agent":
            guard let op = args.first else { return (false, "agent <op> [key=value]…") }
            var body: [String: Any] = ["op": op]
            for kv in args.dropFirst() {
                let parts = kv.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 { body[parts[0]] = parts[1] == "true" ? true as Any : parts[1] == "false" ? false as Any : parts[1] as Any }
            }
            guard let r = agentRequest(body) else { return (false, "the agent did not answer") }
            let ok = r["ok"] as? Bool ?? false
            return (ok, [r["detail"] as? String, r["error"] as? String].compactMap { $0 }.joined(separator: "; "))
        case "relay":
            return (true, relay.summary)
        case "shutdown":
            log("pairing: shutting the device down (\(args.joined(separator: " ")))")
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) { [weak session] in session?.end() }
            return (true, "shutting down")
        default:
            return (false, "unknown pairing command '\(verb)'")
        }
    }

    func controlCommand(_ words: [String]) -> String? {
        guard words.first == "pairing" else { return nil }
        let (ok, text) = command(words.count > 1 ? words[1] : "state", Array(words.dropFirst(2)))
        return (ok ? "ok " : "error: ") + text
    }

    @discardableResult
    func sendToPeer(_ peer: String, frame: [String: Any]) -> Bool {
        lock.withLock { links[peer.uppercased()] }?.send(frame) ?? false
    }

    func findInGuest(_ name: String) throws -> UInt32 {
        guard let c = session?.boundControl else { throw LaunchSimControlError(operation: "find \(name): no session", code: 3) }
        return try c.findEndpoint(name)
    }

    func channelOpened(_ connection: HostChannelConnection) {
        let old = lock.withLock { () -> SettingsAgentLink? in
            let o = agentLink
            agentLink = connection
            agentBuffer = []
            return o
        }
        if let old, old !== connection { old.close() }
        log("pairing: the agent connected (pid \(connection.pid))")
    }

    func channel(_ connection: HostChannelConnection, received bytes: [UInt8]) {
        var messages: [[String: Any]] = []
        let bad: Bool = lock.withLock {
            guard agentLink === connection else { return false }
            agentBuffer += bytes
            do { messages = try SettingsChannel.takeFrames(&agentBuffer) } catch { return true }
            return false
        }
        if bad {
            log("pairing: a malformed frame from the agent; closing")
            connection.close()
            channelClosed(connection)
            return
        }
        for m in messages { agentMessage(m) }
    }

    func channelClosed(_ connection: HostChannelConnection) {
        let pending = lock.withLock { () -> [DispatchSemaphore] in
            guard agentLink === connection else { return [] }
            agentLink = nil
            agentPID = nil
            sequencer.agentDisconnected()
            return waiting.values.map(\.semaphore)
        }
        for s in pending { s.signal() }
        log("pairing: the agent's connection closed" + (pending.isEmpty ? "" : " (\(pending.count) requests unanswered)"))
    }

    private func agentMessage(_ m: [String: Any]) {
        if let event = m["event"] as? String {
            if event == "hello" {
                let pid = (m["pid"] as? NSNumber)?.intValue
                let actions = lock.withLock { () -> [PairingSequencer.Action] in
                    agentPID = pid
                    return sequencer.agentConnected()
                }
                log("pairing: agent pid \(pid ?? -1), protocol \((m["version"] as? NSNumber)?.intValue ?? 0) (\(elapsed()) after the start)")
                perform(actions)
            } else if event == "log" {
                log("pairing: agent says: \(m["text"] as? String ?? "")")
            }
            return
        }
        guard let id = (m["id"] as? NSNumber)?.intValue else { return }
        let s: DispatchSemaphore? = lock.withLock {
            guard waiting[id] != nil else { return nil }
            waiting[id]!.reply = m
            return waiting[id]!.semaphore
        }
        s?.signal()
    }

    func agentRequest(_ body: [String: Any]) -> [String: Any]? {
        let s = DispatchSemaphore(value: 0)
        let (link, id) = lock.withLock { () -> (SettingsAgentLink?, Int) in
            let id = nextID
            nextID += 1
            waiting[id] = (s, nil)
            return (agentPID != nil ? agentLink : nil, id)
        }
        defer { _ = lock.withLock { waiting.removeValue(forKey: id) } }
        var message = body
        message["id"] = id
        guard let link, let frame = SettingsChannel.frame(message), link.send(frame) else { return nil }
        _ = s.wait(timeout: .now() + agentReplyTimeout)
        return lock.withLock { waiting[id]?.reply }
    }
}
#endif
