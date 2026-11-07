import Foundation
import SwiftCodeDarwinABI

public struct MachHostError: Error, Equatable, Sendable, CustomStringConvertible {
    public var code: UInt32
    public init(_ code: UInt32) { self.code = code }
    public var description: String { MachMsgReturn.name(code) }

    public static let timedOut = MachHostError(MachMsgReturn.rcvTimedOut)
    public static let portChanged = MachHostError(MachMsgReturn.rcvPortChanged)
    public static let interrupted = MachHostError(MachMsgReturn.rcvInterrupted)
    public static let invalidName = MachHostError(MachMsgReturn.rcvInvalidName)
}

public enum MachHostDescriptor: Equatable, Sendable {
    case port(name: UInt32, disposition: UInt32)
    case ool(data: [UInt8], copy: UInt8 = 1, volatile: Bool = false)
    case oolPorts(names: [UInt32], disposition: UInt32)
}

public struct MachHostOutgoingMessage: Equatable, Sendable {
    public var remotePort: UInt32
    public var remoteDisposition: UInt32
    public var localPort: UInt32
    public var localDisposition: UInt32
    public var id: Int32
    public var descriptors: [MachHostDescriptor]
    public var body: [UInt8]
    public var complex: Bool?

    public init(remotePort: UInt32, remoteDisposition: UInt32 = MachMsgType.copySend, localPort: UInt32 = 0,
                localDisposition: UInt32 = 0, id: Int32, descriptors: [MachHostDescriptor] = [], body: [UInt8] = [],
                complex: Bool? = nil) {
        self.remotePort = remotePort
        self.remoteDisposition = remoteDisposition
        self.localPort = localPort
        self.localDisposition = localDisposition
        self.id = id
        self.descriptors = descriptors
        self.body = body
        self.complex = complex
    }

    public var isComplex: Bool { complex ?? !descriptors.isEmpty }
}

public enum MachHostReceivedDescriptor: Equatable, Sendable {
    case port(name: UInt32, type: UInt32)
    case ool(data: [UInt8], copy: UInt8, volatile: Bool)
    case oolPorts(names: [UInt32], type: UInt32)
    case guardedPort(name: UInt32, flags: UInt16, type: UInt32)
}

public struct MachAuditToken: Equatable, Sendable {
    public var words: [UInt32]
    public init(words: [UInt32]) { self.words = words }
    public var auid: UInt32 { words[0] }
    public var euid: UInt32 { words[1] }
    public var egid: UInt32 { words[2] }
    public var ruid: UInt32 { words[3] }
    public var rgid: UInt32 { words[4] }
    public var pid: Int32 { Int32(bitPattern: words[5]) }
    public var auditSessionID: UInt32 { words[6] }
    public var pidVersion: UInt32 { words[7] }
}

public struct MachHostReceivedMessage: Equatable, Sendable {
    public var bits: UInt32
    public var replyPort: UInt32
    public var replyType: UInt32
    public var localPort: UInt32
    public var voucher: UInt32
    public var id: Int32
    public var descriptors: [MachHostReceivedDescriptor]
    public var body: [UInt8]
    public var size: UInt32
    public var seqno: UInt32
    public var context: UInt64
    public var sender: MachAuditToken?

    public var isComplex: Bool { bits & MachMsgBits.complex != 0 }
    public var isFromKernel: Bool { sender == nil }
    public var replyDisposition: UInt32 { replyType }

    public var wireImage: [UInt8] {
        var out = le32(bits) + le32(size) + le32(replyPort) + le32(localPort) + le32(voucher)
            + le32(UInt32(bitPattern: id))
        if isComplex {
            out += le32(UInt32(descriptors.count))
            for d in descriptors {
                switch d {
                case let .port(name, type):
                    out += le32(name) + le32(0) + [0, 0, UInt8(truncatingIfNeeded: type), MachMsgDescriptor.port]
                case let .ool(data, copy, volatile):
                    out += le64(0) + [copy == MachMsgDescriptor.virtualCopy ? 1 : 0, copy, 0,
                                      volatile ? MachMsgDescriptor.oolVolatile : MachMsgDescriptor.ool]
                        + le32(UInt32(data.count))
                case let .oolPorts(names, type):
                    out += le64(0) + [1, MachMsgDescriptor.virtualCopy, UInt8(truncatingIfNeeded: type),
                                      MachMsgDescriptor.oolPorts] + le32(UInt32(names.count))
                case let .guardedPort(name, flags, type):
                    out += le64(0) + [UInt8(flags & 0xFF), UInt8(flags >> 8), UInt8(truncatingIfNeeded: type),
                                      MachMsgDescriptor.guardedPort] + le32(name)
                }
            }
        }
        return out + body
    }
}

public final class MachHostTask: @unchecked Sendable {
    public let lock: KernelLock
    public let system: MachIPCSystem
    let ipc: MachIPC
    public let bootstrapPort: UInt32

    init(lock: KernelLock, system: MachIPCSystem, log: @escaping (String) -> Void) {
        self.lock = system.portLock ?? lock
        self.system = system
        ipc = MachIPC(lock: lock, log: log, pid: 0, uid: 0, gid: 0, system: system)
        let (kr, name) = ipc.portAllocate(right: MachPortRight.receive)
        precondition(kr == 0)
        bootstrapPort = name
        system.hostBootstrapObject = ipc.entries[Int(name >> 8)].port
    }

    public func debugPortState(_ name: UInt32) -> String {
        lock.withLock {
            let i = Int(name >> 8)
            guard i < ipc.entries.count, ipc.entries[i].inUse, let p = ipc.entries[i].port else { return "no port" }
            return "active \(p.active), receiver pid \(p.receiver?.pid ?? -1), \(p.messages.count) queued, "
                + "\(p.waitingReceivers) receivers waiting, sets \(p.sets.map { "\($0.name):\($0.waitingReceivers)w" }), "
                + "srights \(p.srights), seqno \(p.seqno)"
        }
    }

    public var pid: Int32 {
        get { lock.withLock { ipc.pid } }
        set { lock.withLock { ipc.pid = newValue } }
    }
    public var uid: UInt32 {
        get { lock.withLock { ipc.uid } }
        set { lock.withLock { ipc.uid = newValue } }
    }
    public var gid: UInt32 {
        get { lock.withLock { ipc.gid } }
        set { lock.withLock { ipc.gid = newValue } }
    }
    public var log: (String) -> Void {
        get { lock.withLock { ipc.log } }
        set { lock.withLock { ipc.log = newValue } }
    }

    public func makePort(sendRight: Bool = false, qlimit: Int? = nil) throws -> UInt32 {
        try lock.withLock {
            let flags = (sendRight ? MachPortConstruct.insertSendRight : 0) | (qlimit != nil ? MachPortConstruct.qlimit : 0)
            let (kr, name) = ipc.portConstruct(MachPortOptions(flags: flags, qlimit: UInt32(qlimit ?? 0)), context: 0)
            guard kr == 0 else { throw MachHostError(kr) }
            return name
        }
    }

    public func makeFileport(_ file: DarwinOpenFile) throws -> UInt32 {
        try lock.withLock {
            let p = ipc.newPort()
            p.kernelObject = .fileport(serial: p.serial)
            p.fileportFile = file
            p.srights = 1
            let (name, ok) = ipc.copyout(.send(p))
            guard ok else { throw MachHostError(MachKern.noSpace) }
            return name
        }
    }

    public func makeMemoryEntry(_ object: SharedMemoryObject) throws -> UInt32 {
        try lock.withLock {
            guard let (p, name) = ipc.makeKernelObjectName(.memoryEntry(serial: ipc.nextSerial())) else {
                throw MachHostError(MachKern.noSpace)
            }
            p.memoryEntry = MachMemoryEntry(object: object, offset: 0, size: object.size, protection: .readWrite)
            return name
        }
    }

    public func memoryEntry(_ name: UInt32) -> (object: SharedMemoryObject, offset: UInt64, size: UInt64)? {
        lock.withLock {
            guard let e = ipc.memoryEntry(named: name) else { return nil }
            return (e.object, e.offset, e.size)
        }
    }

    public func makePortSet() throws -> UInt32 {
        try lock.withLock {
            let (kr, name) = ipc.portAllocate(right: MachPortRight.portSet)
            guard kr == 0 else { throw MachHostError(kr) }
            return name
        }
    }

    public func addMember(_ port: UInt32, to set: UInt32) throws {
        try check(lock.withLock { ipc.portInsertMember(port, set: set) })
    }

    public func removeMember(_ port: UInt32, from set: UInt32) throws {
        try check(lock.withLock { ipc.portExtractMember(port, set: set) })
    }

    public func insertRight(_ name: UInt32, from poly: UInt32, disposition: UInt32) throws {
        try check(lock.withLock { ipc.portInsertRight(name, poly: poly, polyPoly: disposition) })
    }

    public func destroyPort(_ name: UInt32) throws {
        try check(lock.withLock { ipc.portDestroy(name) })
    }

    public func deallocate(_ name: UInt32) throws {
        try check(lock.withLock { ipc.portDeallocate(name) })
    }

    public func modRefs(_ name: UInt32, right: UInt32, delta: Int32) throws {
        try check(lock.withLock { ipc.portModRefs(name, right: right, delta: delta) })
    }

    public func rights(of name: UInt32) -> (type: UInt32, urefs: UInt32)? { ipc.entry(name) }

    @discardableResult
    public func requestNotification(_ name: UInt32, id: Int32, sync: UInt32 = 0, notifyPort: UInt32) throws -> UInt32 {
        try lock.withLock {
            var notify: CarriedRight = .null
            if MachPortName.isValid(notifyPort) {
                switch ipc.copyin(notifyPort, MachMsgType.makeSendOnce, slot: .routine, apply: true) {
                case .failure(.noEntry): throw MachHostError(MachKern.invalidName)
                case .failure(.noRight): throw MachHostError(MachKern.invalidRight)
                case let .success(r): notify = r
                }
            }
            let (kr, previous) = ipc.portRequestNotification(name, id: id, sync: sync, notify: notify)
            guard kr == 0 else {
                if case let .sendOnce(so) = notify { ipc.releaseSendOnceQuietly(so) }
                throw MachHostError(kr)
            }
            return ipc.copyout(previous).name
        }
    }

    public func send(_ message: MachHostOutgoingMessage, timeout: UInt64? = nil) throws {
        let code = lock.withLock { ipc.hostSend(message, timeout: timeout) }
        guard code == 0 else { throw MachHostError(code) }
    }

    public func receive(on name: UInt32, timeout: UInt64? = nil) throws -> MachHostReceivedMessage {
        try receive(on: name, timeout: timeout, tracked: false)
    }

    public func receive(on name: UInt32, timeout: UInt64?, tracked: Bool) throws -> MachHostReceivedMessage {
        let result = lock.withLock { () -> Result<MachHostReceivedMessage, MachHostError> in
            let r = ipc.hostReceive(name, timeout: timeout)
            if tracked, case .success = r { inHand += 1 }
            return r.mapError { MachHostError($0.code) }
        }
        return try result.get()
    }

    public func finishedMessage() { lock.withLock { inHand = max(0, inHand - 1) } }

    public var messagesInHandLocked: Int { inHand }
    private var inHand = 0

    public func reply(to request: MachHostReceivedMessage, id: Int32? = nil, descriptors: [MachHostDescriptor] = [],
                      body: [UInt8] = [], timeout: UInt64? = 0) throws {
        guard MachPortName.isValid(request.replyPort) else { throw MachHostError(MachMsgReturn.sendInvalidDest) }
        try send(MachHostOutgoingMessage(remotePort: request.replyPort, remoteDisposition: request.replyDisposition,
                                         id: id ?? request.id &+ 100, descriptors: descriptors, body: body),
                 timeout: timeout)
    }

    public func discard(_ message: MachHostReceivedMessage) {
        lock.withLock {
            var names: [UInt32] = [message.replyPort]
            for d in message.descriptors {
                switch d {
                case let .port(name, _), let .guardedPort(name, _, _): names.append(name)
                case let .oolPorts(list, _): names += list
                case .ool: break
                }
            }
            for name in names where MachPortName.isValid(name) {
                guard let (type, _) = ipc.entry(name) else { continue }
                if type & MachPortType.receive != 0 {
                    _ = ipc.portModRefs(name, right: MachPortRight.receive, delta: -1)
                } else {
                    _ = ipc.portDeallocate(name)
                }
            }
        }
    }

    public func setSpecialPort(of task: MachIPC, which: Int32, to name: UInt32) throws {
        try lock.withLock {
            let disposition: UInt32
            guard let (type, _) = ipc.entry(name) else { throw MachHostError(MachKern.invalidName) }
            disposition = type & MachPortType.send != 0 ? MachMsgType.copySend : MachMsgType.makeSend
            guard case let .success(r) = ipc.copyin(name, disposition, slot: .body, apply: true) else {
                throw MachHostError(MachKern.invalidRight)
            }
            let kr = task.setSpecialPort(which, r)
            guard kr == 0 else {
                ipc.release(r)
                throw MachHostError(kr)
            }
            if which == TaskSpecialPort.bootstrap { task.syncWellKnownNames() }
        }
    }

    public func give(_ name: UInt32, disposition: UInt32, to task: MachIPC) throws -> UInt32 {
        try lock.withLock {
            guard MachMsgType.isPortDisposition(disposition) else { throw MachHostError(MachKern.invalidValue) }
            switch ipc.copyin(name, disposition, slot: .body, apply: true) {
            case .failure(.noEntry): throw MachHostError(MachKern.invalidName)
            case .failure(.noRight): throw MachHostError(MachKern.invalidRight)
            case let .success(r): return task.copyout(r).name
            }
        }
    }

    public func shutdown() {
        lock.withLock {
            ipc.terminateTask()
            if system.hostTask === self {
                system.hostTask = nil
                system.hostBootstrapObject = nil
            }
        }
    }

    private func check(_ kr: UInt32) throws {
        guard kr == 0 else { throw MachHostError(kr) }
    }
}

extension MachIPCSystem {
    @discardableResult
    public func makeHostTask(lock: KernelLock, log: @escaping (String) -> Void = { _ in }) -> MachHostTask {
        lock.withLock {
            if let hostTask { return hostTask }
            let t = MachHostTask(lock: lock, system: self, log: log)
            hostTask = t
            return t
        }
    }
}

extension DarwinSystem {
    public var hostTask: MachHostTask { mach.makeHostTask(lock: lock) }
}

extension MachIPC {
    func hostSend(_ out: MachHostOutgoingMessage, timeout: UInt64?) -> UInt32 {
        let complex = out.isComplex
        guard out.body.count % 4 == 0 else { return MachMsgReturn.sendMsgTooSmall }
        var size = 24 + out.body.count
        if complex {
            size += 4
            for d in out.descriptors {
                if case .port = d { size += 12 } else { size += 16 }
            }
        } else if !out.descriptors.isEmpty {
            return MachMsgReturn.sendTooLarge
        }
        guard size <= Int(MachIPCLimits.maxSendSize) else { return MachMsgReturn.sendTooLarge }
        let bits = MachMsgBits.make(remote: out.remoteDisposition, local: out.localDisposition)
            | (complex ? MachMsgBits.complex : 0)
        let request = MachSendRequest(bits: bits, size: size, remote: out.remotePort, local: out.localPort,
                                      voucher: 0, id: out.id, descriptorCount: UInt32(out.descriptors.count), body: [])
        var m: KMessage
        switch copyinHeader(request) {
        case let .failure(e): return e.code
        case let .success(header): m = header
        }
        m.complex = complex
        m.inline = out.body
        m.sender = senderIdentity
        var rights = 0, oolBytes: UInt64 = 0
        func right(_ name: UInt32, _ disposition: UInt32) -> CarriedRight? {
            guard MachPortName.isValid(name) else { return name == 0 ? .null : .dead }
            guard case let .success(r) = copyin(name, disposition, slot: .body, apply: true) else { return nil }
            return r
        }
        for d in out.descriptors {
            switch d {
            case let .port(name, disposition):
                rights += 1
                guard MachMsgType.isPortDisposition(disposition), rights <= MachIPCLimits.maxRightsPerMessage else {
                    destroyMessage(m)
                    return MachMsgReturn.sendInvalidType
                }
                guard let r = right(name, disposition) else {
                    destroyMessage(m)
                    return MachMsgReturn.sendInvalidRight
                }
                m.items.append(.port(r, type: MachMsgType.received(disposition)))
            case let .ool(data, copy, volatile):
                oolBytes += UInt64(data.count)
                guard copy <= MachMsgDescriptor.virtualCopy, oolBytes <= MachIPCLimits.maxOOLBytes else {
                    destroyMessage(m)
                    return copy > MachMsgDescriptor.virtualCopy ? MachMsgReturn.sendInvalidType : MachMsgReturn.vmKernel
                }
                m.items.append(.ool(data: data, copy: copy, volatile: volatile))
            case let .oolPorts(names, disposition):
                rights += names.count
                guard MachMsgType.isPortDisposition(disposition), rights <= MachIPCLimits.maxRightsPerMessage else {
                    destroyMessage(m)
                    return MachMsgReturn.sendInvalidType
                }
                var list: [CarriedRight] = []
                for name in names {
                    guard let r = right(name, disposition) else {
                        list.forEach(release)
                        destroyMessage(m)
                        return MachMsgReturn.sendInvalidRight
                    }
                    list.append(r)
                }
                m.items.append(.oolPorts(list, type: MachMsgType.received(disposition), copy: MachMsgDescriptor.virtualCopy))
            }
        }
        if isCircular(m) {
            destroyMessage(m)
            log("host send id \(out.id) -> MACH_MSG_SUCCESS [circular: destroyed]")
            return MachMsgReturn.success
        }
        var options = MachMsgOption.sendMsg
        var ms: UInt32 = 0
        if let timeout {
            options |= MachMsgOption.sendTimeout
            ms = UInt32(min((timeout + 999_999) / 1_000_000, UInt64(UInt32.max)))
        }
        let (code, pseudo, note) = deliver(m, options: options, timeout: ms, msg2: false)
        if let pseudo {
            _ = copyout(pseudo.destination)
            _ = copyout(pseudo.reply)
            for item in pseudo.items {
                switch item {
                case let .port(r, _), let .guarded(r, _, _): _ = copyout(r)
                case let .oolPorts(list, _, _): list.forEach { _ = copyout($0) }
                case .ool: break
                }
            }
        }
        log("host send id \(out.id) to \(hx(out.remotePort)) -> \(MachMsgReturn.name(code))\(note)")
        return code
    }

    func hostReceive(_ name: UInt32, timeout: UInt64?) -> Result<MachHostReceivedMessage, KernError> {
        guard let i = lookup(name) else { return .failure(KernError(MachMsgReturn.rcvInvalidName)) }
        let set = entries[i].set
        let port: IPCPort? = set == nil && entries[i].bits & T.receive != 0 ? entries[i].port : nil
        guard set != nil || port != nil else { return .failure(KernError(MachMsgReturn.rcvInvalidName)) }
        let deadline = timeout.map { KernelClock.deadline(afterNanoseconds: $0) }
        let source: IPCPort
        switch awaitMessage(name: name, slot: i, port: port, set: set, deadline: deadline, mayBlock: timeout != 0) {
        case let .failure(e): return .failure(e)
        case let .success(p): source = p
        }
        let (m, seqno) = dequeue(source)
        let (replyName, _) = copyout(m.reply)
        let local: UInt32 = !source.active ? MachPortName.dead
            : (source.receiver === self ? reverse[ObjectIdentifier(source)] ?? 0 : 0)
        consumeDestination(m.destination)
        var descriptors: [MachHostReceivedDescriptor] = []
        for item in m.items {
            switch item {
            case let .port(r, type): descriptors.append(.port(name: copyout(r).name, type: type))
            case let .guarded(r, flags, type): descriptors.append(.guardedPort(name: copyout(r).name, flags: flags, type: type))
            case let .ool(data, copy, volatile): descriptors.append(.ool(data: data, copy: copy, volatile: volatile))
            case let .oolPorts(rights, type, _): descriptors.append(.oolPorts(names: rights.map { copyout($0).name }, type: type))
            }
        }
        let bits = (m.complex ? MachMsgBits.complex : 0) | MachMsgBits.make(remote: m.replyType, local: m.destinationType)
        let sender: MachAuditToken? = m.fromKernel ? nil : MachAuditToken(words: (m.sender ?? senderIdentity).auditToken)
        let received = MachHostReceivedMessage(
            bits: bits, replyPort: replyName, replyType: m.reply.port == nil && replyName == 0 ? 0 : m.replyType,
            localPort: local, voucher: m.voucherRaw, id: m.id, descriptors: descriptors, body: m.inline,
            size: UInt32(m.size), seqno: seqno, context: source.context, sender: sender)
        log("host receive on \(hx(name)) -> id \(m.id) size \(m.size) seqno \(seqno)"
            + (sender.map { " from pid \($0.pid)" } ?? " from kernel"))
        return .success(received)
    }
}
