import Foundation
import SwiftCodeDarwinKernel
import SwiftCodeXPC

public final class MetalHostService: @unchecked Sendable {
    public static let serviceNames = [
        "com.apple.metal.simulator",
        "com.apple.metal.simulator.SpringBoard",
        "com.apple.metal.simulator.SBRendererService",
        "com.apple.metal.simulator.backboardd",
        "com.apple.metal.simulator.PineBoard",
        "com.apple.metal.simulator.HeadBoard",
        "com.apple.metal.simulator.Carousel",
    ]
    static let handshakeID: Int32 = 0x7730_3074
    static let requestID: Int32 = 0x1000_0000
    static let replyID: Int32 = 0x2000_0000
    static let eventID: Int32 = 0x1000_0000

    public let host: MachHostTask
    public let servicePort: UInt32
    public let backend: MetalBackend
    let core: MetalHostCore
    private let portSet: UInt32
    private let log: (String) -> Void
    private let lock = NSLock()
    private var queues: [UInt32: DispatchQueue] = [:]
    private var stopping = false
    private var thread: Thread?
    private let finished = DispatchSemaphore(value: 0)
    private var shutDown = false

    public init(host: MachHostTask, backend: MetalBackend, memory: MetalGuestMemoryResolver?, surfaces: IOSurfaceResolver?,
                registryID: UInt64 = 0x1_0000_0059, log: @escaping (String) -> Void) throws {
        self.host = host
        self.backend = backend
        self.log = log
        core = MetalHostCore(backend: backend, memory: memory, surfaces: surfaces, registryID: registryID, log: log)
        servicePort = try host.makePort(sendRight: true, qlimit: 1024)
        portSet = try host.makePortSet()
        try host.addMember(servicePort, to: portSet)
        core.transport = self
    }

    public var statistics: MetalHostStatistics { core.statistics }

    public func setEventClock(_ clock: @escaping () -> Double) { core.eventClock = clock }

    public func clientPIDs() -> [Int32] { core.clientPIDs() }

    public func guestPID(of process: MetalProcessID) -> Int32? { core.guestPID(of: process) }

    public var snapshotBusyReason: String? { core.snapshotBusyReason }

    public func trySnapshotState() -> SnapshotFields? { core.trySnapshotState(log: log) }

    public func restoreState(_ r: SnapshotFieldReader) -> MetalReplayReport {
        let report = core.restoreState(r)
        let ports = core.connectionPorts
        lock.withLock {
            for port in ports where queues[port] == nil {
                queues[port] = DispatchQueue(label: "swiftcode.metal.connection.\(port)")
            }
        }
        return report
    }

    public func start() {
        let t = Thread { [self] in run() }
        t.name = "swiftcode-metal"
        thread = t
        t.start()
    }

    public func stop() { lock.withLock { stopping = true } }

    @discardableResult
    public func shutdown(drainTimeout: Double = 10) -> Bool {
        let (first, started) = lock.withLock { () -> (Bool, Bool) in
            defer { shutDown = true; stopping = true }
            return (!shutDown, thread != nil)
        }
        guard first else { return true }
        let deadline = DispatchTime.now() + drainTimeout
        if started, finished.wait(timeout: deadline) == .timedOut {
            log("metal: shutdown: the receive thread did not stop in \(drainTimeout) s")
        }
        let group = DispatchGroup()
        for q in lock.withLock({ Array(queues.values) }) { q.async(group: group) {} }
        let drained = group.wait(timeout: deadline) == .success
        if !drained { log("metal: shutdown: a connection was still busy after \(drainTimeout) s") }
        backend.shutdown()
        return drained
    }

    static let statsInterval: Double = ProcessInfo.processInfo.environment["SWIFTCODE_METAL_STATS"].flatMap(Double.init) ?? 0

    public func summaryLines() -> [String] {
        let s = core.statistics
        var lines = ["metal: summary: \(s.processes) processes, \(s.liveObjects) objects, \(s.submissions) submissions, "
            + "\(s.scheduledEvents) scheduled, \(s.completedEvents) completed, \(s.backendErrors) backend errors"
            + (s.unknownRecords.isEmpty ? "" : ", unknown records \(s.unknownRecords.sorted { $0.key < $1.key })")
            + (s.refused.isEmpty ? "" : ", refused \(s.refused.sorted { $0.key < $1.key })")]
        lines += core.processSummary().map { "metal:   " + $0 }
        if let b = backend.diagnosticSummary() { lines.append("metal:   backend: " + b) }
        lines += core.sharedTextureContent()
        return lines
    }

    var receiving: Bool { lock.withLock { _receiving } }
    private var _receiving = false
    private var summaryRunning = false

    private func run() {
        lock.withLock { _receiving = true }
        defer {
            lock.withLock { _receiving = false }
            finished.signal()
        }
        var nextSummary = Self.statsInterval > 0 ? ProcessInfo.processInfo.systemUptime + Self.statsInterval : .infinity
        while !lock.withLock({ stopping }) {
            if ProcessInfo.processInfo.systemUptime >= nextSummary {
                nextSummary += Self.statsInterval
                if lock.withLock({ () -> Bool in
                    if summaryRunning { return false }
                    summaryRunning = true
                    return true
                }) {
                    Thread.detachNewThread { [self] in
                        for line in summaryLines() { log(line) }
                        lock.withLock { summaryRunning = false }
                    }
                }
            }
            let m: MachHostReceivedMessage
            do {
                m = try host.receive(on: portSet, timeout: 200_000_000, tracked: true)
            } catch let e as MachHostError where e == .timedOut || e == .interrupted {
                continue
            } catch {
                if !lock.withLock({ stopping }) { log("metal: receive failed: \(error); stopping") }
                return
            }
            dispatch(m)
        }
    }

    func dispatch(_ m: MachHostReceivedMessage) {
        if m.localPort == servicePort {
            if m.id == Self.handshakeID { connect(m) } else { host.discard(m) }
            host.finishedMessage()
            return
        }
        guard let queue = lock.withLock({ queues[m.localPort] }) else {
            host.discard(m)
            host.finishedMessage()
            return
        }
        if m.id == MachNotify.noSenders {
            let port = m.localPort
            queue.async { [self] in close(port); host.finishedMessage() }
        } else if m.id == Self.requestID {
            let receivedAt = Self.opTrace == nil ? 0 : DispatchTime.now().uptimeNanoseconds
            queue.async { [self] in request(m, receivedAt: receivedAt); host.finishedMessage() }
        } else {
            host.discard(m)
            host.finishedMessage()
        }
    }

    private func connect(_ m: MachHostReceivedMessage) {
        guard m.descriptors.count >= 2, case let .port(connection, type) = m.descriptors[0], type == 16,
              case let .port(client, _) = m.descriptors[1] else {
            log("metal: malformed hand-shake")
            host.discard(m)
            return
        }
        do {
            try host.addMember(connection, to: portSet)
            _ = try host.requestNotification(connection, id: MachNotify.noSenders, sync: 0, notifyPort: connection)
        } catch {
            log("metal: cannot serve connection \(connection): \(error)")
            try? host.destroyPort(connection)
            try? host.deallocate(client)
            return
        }
        core.connectionOpened(connection, clientPort: client)
        lock.withLock { queues[connection] = DispatchQueue(label: "swiftcode.metal.connection.\(connection)") }
    }

    private func close(_ port: UInt32) {
        lock.withLock { queues[port] = nil }
        let client = core.connectionClosed(port)
        try? host.destroyPort(port)
        if let client, MachPortName.isValid(client) { try? host.deallocate(client) }
    }

    static let opTrace: OpTraceFile? = ProcessInfo.processInfo.environment["SWIFTCODE_METAL_TRACE"]
        .flatMap { $0.isEmpty ? nil : OpTraceFile(path: $0 + ".ops") }

    private func request(_ m: MachHostReceivedMessage, receivedAt: UInt64 = 0) {
        let startedAt = Self.opTrace == nil ? 0 : DispatchTime.now().uptimeNanoseconds
        var traceType = -1, traceOp = -1
        let wire: [XPCWireDescriptor] = m.descriptors.map {
            switch $0 {
            case let .port(name, type): return .port(name: name, disposition: type)
            case let .ool(data, _, _): return .ool(bytes: data)
            case let .oolPorts(names, type): return .oolPorts(names: names, disposition: type)
            case let .guardedPort(name, _, type): return .guardedPort(name: name, disposition: type)
            }
        }
        var outcome = MetalHostCore.Outcome(reply: [:])
        do {
            guard case let .dictionary(d) = try XPCWire.decode(body: m.body, descriptors: wire) else {
                throw XPCWireError.rootNotDictionary
            }
            if Self.opTrace != nil {
                traceType = d["messageType"]?.integerValue.map { Int($0) } ?? -1
                if traceType == 12, case let .data(bytes)? = d["command"], let rec = try? MetalRecord.parse(bytes) {
                    traceOp = Int(rec.op)
                }
            }
            outcome = core.handle(d, connection: m.localPort, senderPID: m.sender?.pid ?? 0)
        } catch {
            log("metal: undecodable request: \(error)")
        }
        var replied = false
        if let reply = outcome.reply, MachPortName.isValid(m.replyPort) {
            do {
                let encoded = try XPCWire.encode(.dictionary(reply), magic: XPCWire.sim2hostMagic)
                let descriptors: [MachHostDescriptor] = encoded.descriptors.compactMap {
                    if case let .port(name, disposition) = $0 { return .port(name: name, disposition: disposition) }
                    return nil
                }
                try host.reply(to: m, id: Self.replyID, descriptors: descriptors, body: encoded.body)
                replied = true
            } catch {
                log("metal: reply failed: \(error)")
            }
        }
        if let t = Self.opTrace {
            t.write("\(m.localPort) \(traceType) \(traceOp) \(replied ? 1 : 0) \(receivedAt) \(startedAt) \(DispatchTime.now().uptimeNanoseconds)\n")
        }
        var keep = outcome.retained
        var names: [UInt32] = []
        if !replied, MachPortName.isValid(m.replyPort) { names.append(m.replyPort) }
        for d in m.descriptors {
            switch d {
            case let .port(name, _), let .guardedPort(name, _, _): names.append(name)
            case let .oolPorts(list, _): names += list
            case .ool: break
            }
        }
        for name in names where MachPortName.isValid(name) {
            if let i = keep.firstIndex(of: name) {
                keep.remove(at: i)
                continue
            }
            dropRight(name)
        }
    }
}

extension MetalHostService: MetalHostTransport {
    func sendEvent(_ event: XPCDict, to port: UInt32) -> Bool {
        guard MachPortName.isValid(port), let encoded = try? XPCWire.encode(.dictionary(event), magic: XPCWire.sim2hostMagic) else {
            return false
        }
        let message = MachHostOutgoingMessage(remotePort: port, remoteDisposition: MachMsgType.copySend, id: Self.eventID,
                                              body: encoded.body)
        for _ in 0..<50 {
            do {
                try host.send(message, timeout: 100_000_000)
                return true
            } catch let e as MachHostError where e.code == MachMsgReturn.sendTimedOut {
                if lock.withLock({ stopping }) { return false }
                continue
            } catch {
                return false
            }
        }
        log("metal: event port \(port) stayed full; event dropped")
        return false
    }

    func makeEventPort() -> UInt32? { try? host.makePort(sendRight: false, qlimit: 1) }

    func destroyEventPort(_ name: UInt32) { try? host.destroyPort(name) }

    func dropRight(_ name: UInt32) {
        guard MachPortName.isValid(name), let (type, _) = host.rights(of: name) else { return }
        if type & MachPortType.receive != 0 {
            if type & MachPortType.send != 0 { try? host.modRefs(name, right: MachPortRight.send, delta: -1) }
        } else {
            try? host.deallocate(name)
        }
    }
}

final class OpTraceFile: @unchecked Sendable {
    private let file: FileHandle
    private let lock = NSLock()
    init?(path: String) {
        FileManager.default.createFile(atPath: path, contents: nil)
        guard let f = FileHandle(forWritingAtPath: path) else { return nil }
        file = f
        f.write(Data("# swiftcode Metal request trace v1: connection type deviceop replied received_ns started_ns done_ns\n".utf8))
    }
    func write(_ line: String) {
        lock.withLock { file.write(Data(line.utf8)) }
    }
}
