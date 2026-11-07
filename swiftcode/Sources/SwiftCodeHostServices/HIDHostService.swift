import Foundation
import SwiftCodeDarwinKernel
import SwiftCodeDisplayStream

public final class HIDHostService: @unchecked Sendable {
    public static let serviceName = "dev.swiftcode.simulator.hid"
    static let registerID: Int32 = 0x5948_0001
    static let eventID: Int32 = 0x5948_0002

    public enum Kind: UInt32, Sendable {
        case touch = 1, key = 2, button = 3, keyboardAttach = 4, orientation = 5
        case hingeAngle = 6
        case deviceOrientation = 7
        case crownRotation = 8
        case watchGesture = 9
        case visionPose = 10
        case visionSelection = 11
    }

    public enum Phase: UInt32, Sendable {
        case began = 1, moved = 2, unchanged = 3, ended = 4, cancelled = 5
    }

    public enum Edge: UInt32, Sendable {
        case none = 0, top = 1, left = 2, bottom = 3, right = 4
    }

    public struct Contact: Equatable, Sendable {
        public var index: UInt32
        public var phase: Phase
        public var edge: Edge
        public var x: Double, y: Double

        public init(index: UInt32, phase: Phase, edge: Edge, x: Double, y: Double) {
            (self.index, self.phase, self.edge, self.x, self.y) = (index, phase, edge, x, y)
        }
    }

    public enum Event: Equatable, Sendable {
        case touch(display: UInt32, contacts: [Contact])
        case key(usagePage: UInt32, usage: UInt32, down: Bool)
        case button(usagePage: UInt32, usage: UInt32, down: Bool)
        case keyboardAttach(Bool)
        case orientation(UInt32)
        case hingeAngle(UInt32)
        case deviceOrientation(UInt32)
        case crownRotation(Double, axis: UInt32 = 0)
        case watchGesture(UInt32)
        case visionPose(SpatialPose)
        case visionSelection(SpatialSelection)
    }

    public struct WatchGestureEvent: Equatable, Sendable {
        public static let eventType: UInt32 = 39
        public static let gestureTypeField: UInt32 = 39 << 16
        public static let tapCountField: UInt32 = 39 << 16 | 1
        public static let phaseEnded: UInt32 = 4
        public static let eventFlags: UInt32 = phaseEnded << 24

        public var gestureType: UInt32
        public var tapCount: UInt32?

        public init(gestureType: UInt32, tapCount: UInt32?) { (self.gestureType, self.tapCount) = (gestureType, tapCount) }

        public static func forGesture(_ gesture: UInt32) -> WatchGestureEvent? {
            switch gesture {
            case 0: WatchGestureEvent(gestureType: 2, tapCount: 2)
            case 1: WatchGestureEvent(gestureType: 8, tapCount: nil)
            default: nil
            }
        }
    }

    public static func watchGesture(named name: String) -> UInt32? {
        switch name.lowercased() {
        case "double-tap", "doubletap", "0": 0
        case "flick", "1": 1
        case "tap", "single-tap", "2": 2
        default: UInt32(name).flatMap { $0 <= 5 ? $0 : nil }
        }
    }

    let host: MachHostTask
    let log: (String) -> Void
    public let servicePort: UInt32
    private let lock = NSLock()
    private var client: UInt32?
    private var sequence: UInt64 = 0
    private var stopping = false
    public private(set) var registrations = 0

    public init(host: MachHostTask, log: @escaping (String) -> Void) throws {
        self.host = host
        self.log = log
        servicePort = try host.makePort(sendRight: true, qlimit: 64)
    }

    public func start() {
        let t = Thread { [self] in run() }
        t.name = "swiftcode-hid"
        t.start()
    }

    public func stop() { lock.withLock { stopping = true } }

    public var lastSequence: UInt64 { lock.withLock { sequence } }

    public var isRegistered: Bool { lock.withLock { client != nil } }

    public var snapshotClient: UInt32? { lock.withLock { client } }

    public func restoreRegistration(client name: UInt32) {
        let old = lock.withLock { () -> UInt32? in
            defer { client = name; registrations += 1 }
            return client
        }
        if let old, old != name { try? host.deallocate(old) }
        log("hid: the registration of the saved run is used again (port 0x\(String(name, radix: 16)))")
    }

    private func run() {
        while !lock.withLock({ stopping }) {
            let m: MachHostReceivedMessage
            do {
                m = try host.receive(on: servicePort, timeout: 200_000_000, tracked: true)
            } catch let e as MachHostError where e == .timedOut || e == .interrupted {
                continue
            } catch {
                if !lock.withLock({ stopping }) { log("hid: receive failed: \(error); stopping") }
                return
            }
            handle(m)
            host.finishedMessage()
        }
    }

    func handle(_ m: MachHostReceivedMessage) {
        guard m.id == Self.registerID, m.descriptors.count == 1, case let .port(port, type) = m.descriptors[0],
              type == MachMsgType.portSend, m.body.count >= 8 else {
            log("hid: unexpected message \(m.id) on the service port; dropped")
            drop(m)
            return
        }
        let version = m.body.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
        guard version == 1 else {
            log("hid: registration with protocol version \(version); dropped")
            drop(m)
            return
        }
        let old = lock.withLock { () -> UInt32? in
            defer { client = port; registrations += 1 }
            return client
        }
        if let old, old != port { try? host.deallocate(old) }
        log("hid: the guest's HID bundle registered (pid \(m.sender?.pid ?? -1))")
    }

    private func drop(_ m: MachHostReceivedMessage) {
        var names: [UInt32] = []
        if MachPortName.isValid(m.replyPort) { names.append(m.replyPort) }
        for d in m.descriptors { if case let .port(name, _) = d { names.append(name) } }
        for name in names where MachPortName.isValid(name) { try? host.deallocate(name) }
    }

    public static func body(_ event: Event, sequence: UInt64, age: UInt32 = 0) -> [UInt8] {
        var b: [UInt8] = []
        func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { b += $0 } }
        func u64(_ v: UInt64) { withUnsafeBytes(of: v.littleEndian) { b += $0 } }
        func f64(_ v: Double) { u64(v.bitPattern) }
        let kind: Kind
        switch event {
        case .touch: kind = .touch
        case .key: kind = .key
        case .button: kind = .button
        case .keyboardAttach: kind = .keyboardAttach
        case .orientation: kind = .orientation
        case .hingeAngle: kind = .hingeAngle
        case .deviceOrientation: kind = .deviceOrientation
        case .crownRotation: kind = .crownRotation
        case .watchGesture: kind = .watchGesture
        case .visionPose: kind = .visionPose
        case .visionSelection: kind = .visionSelection
        }
        u32(1)
        u32(kind.rawValue)
        u64(sequence)
        switch event {
        case .touch(let display, let contacts):
            u32(display)
            u32(UInt32(contacts.count))
            for c in contacts {
                u32(c.index)
                u32(c.phase.rawValue)
                u32(c.edge.rawValue)
                u32(age)
                f64(min(1, max(0, c.x)))
                f64(min(1, max(0, c.y)))
            }
        case .key(let page, let usage, let down), .button(let page, let usage, let down):
            u32(page)
            u32(usage)
            u32(down ? 1 : 0)
            u32(age)
        case .keyboardAttach(let attached):
            u32(attached ? 1 : 0)
            u32(0)
        case .orientation(let o):
            u32(o)
            u32(0)
        case .hingeAngle(let degrees):
            u32(min(180, degrees))
            u32(0)
        case .deviceOrientation(let o):
            u32(o)
            u32(0)
        case .crownRotation(let delta, let axis):
            f64(delta.isFinite ? delta : 0)
            u32(axis <= 3 ? axis : 0)
            u32(0)
        case .watchGesture(let g):
            u32(g)
            u32(0)
        case .visionPose(let pose):
            func finite(_ v: Double) -> Double { v.isFinite ? v : 0 }
            let q = pose.rotation.normalized
            for v in [pose.position.x, pose.position.y, pose.position.z, q.w, q.x, q.y, q.z] { f64(finite(v)) }
        case .visionSelection(let sel):
            func finite(_ v: Double) -> Double { v.isFinite ? v : 0 }
            let hands = sel.hasHands
            u32(hands ? 1 : 0)
            u32(0)
            for v in [sel.rayOrigin.x, sel.rayOrigin.y, sel.rayOrigin.z, sel.rayDirection.x, sel.rayDirection.y, sel.rayDirection.z] { f64(finite(v)) }
            for h in [sel.left ?? SpatialHand(), sel.right ?? SpatialHand()] {
                let q = h.rotation.normalized
                u32(hands && h.pinching ? 1 : 0)
                u32(hands && h.allowDirect ? 1 : 0)
                u32(0)
                u32(0)
                for v in [h.position.x, h.position.y, h.position.z, q.w, q.x, q.y, q.z] { f64(finite(v)) }
            }
        }
        return b
    }

    @discardableResult
    public func send(_ event: Event, age: UInt32 = 0) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let port = client else { return false }
        sequence += 1
        let message = MachHostOutgoingMessage(remotePort: port, remoteDisposition: MachMsgType.copySend, id: Self.eventID,
                                              body: Self.body(event, sequence: sequence, age: age))
        do {
            try host.send(message, timeout: 250_000_000)
            if sequence <= 5 { log("hid: event \(sequence) sent (\(message.body.count) bytes)") }
            return true
        } catch let e as MachHostError where e == MachHostError(MachMsgReturn.sendTimedOut) {
            log("hid: the guest is not taking input (queue full); event dropped")
            return false
        } catch {
            log("hid: send failed (\(error)); the bundle must register again")
            try? host.deallocate(port)
            client = nil
            return false
        }
    }
}
