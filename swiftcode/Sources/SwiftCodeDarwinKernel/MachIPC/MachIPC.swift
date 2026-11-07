import Foundation
import SwiftCodeDarwinABI

public final class MachIPC: MachIPCHandling, @unchecked Sendable {

    public let lock: KernelLock
    public var log: (String) -> Void
    var tracesCalls: Bool {
        (kernel.map { traceTextWanted($0.tracing) } ?? true) && !lock.callerIsFast
    }
    @inline(__always) func trace(_ line: @autoclosure () -> String) {
        if tracesCalls { log(line()) }
    }
    public var messageQueuedHandler: ((_ name: UInt32) -> Void)? {
        get { kernelGone ? nil : queuedHook }
        set { queuedHook = newValue }
    }
    public var receiveRightGoneHandler: ((_ name: UInt32) -> Void)? {
        get { kernelGone ? nil : goneHook }
        set { goneHook = newValue }
    }
    private var queuedHook: ((_ name: UInt32) -> Void)?
    private var goneHook: ((_ name: UInt32) -> Void)?
    private var attachedToKernel = false
    var kernelGone: Bool { attachedToKernel && kernel == nil }
    public var pid: Int32
    public var pidVersion: UInt32 = 0
    public var uid: UInt32
    public var gid: UInt32
    public let system: MachIPCSystem
    public internal(set) weak var kernel: DarwinKernel?
    let spaceID: UInt64
    var pendingWatchPorts: [IPCPort] = []
    public internal(set) var isTerminated = false
    public var systemClock: () -> (seconds: UInt64, nanoseconds: UInt64)
    public var calendarClock: () -> (seconds: UInt64, nanoseconds: UInt64)

    var entries: [IPCEntry] = [IPCEntry()]
    var freeList: [Int] = []
    var nextFresh = 1
    var reverse: [ObjectIdentifier: UInt32] = [:]

    let taskPort: IPCPort
    let taskNamePort: IPCPort
    var taskReadPort: IPCPort?
    var taskInspectPort: IPCPort?
    var hostPort: IPCPort { system.hostPort }
    var bootstrapPort: IPCPort { system.bootstrapPort }
    let mainThreadPort: IPCPort
    var clockPorts: [Int32: IPCPort] = [:]
    var slots = TaskPortSlots()
    var ownedKernelPorts: [IPCPort] = []
    var specialReplyPorts: [UInt64: IPCPort] = [:]
    var threadExceptions: [ObjectIdentifier: [ExceptionSlot]] = [:]

    public static let taskName: UInt32 = 0x103
    public static let mainThreadName: UInt32 = 0x203
    public static let hostName: UInt32 = 0x303
    public static let bootstrapName: UInt32 = 0x503

    public init(lock: KernelLock, log: @escaping (String) -> Void = { _ in },
                pid: Int32 = VMLayout.guestPID, uid: UInt32 = DarwinFileSystem.guestUID,
                gid: UInt32 = DarwinFileSystem.guestGID, system: MachIPCSystem? = nil) {
        let system = system ?? MachIPCSystem()
        self.system = system
        self.lock = system.portLock ?? lock
        self.log = log
        self.pid = pid
        self.uid = uid
        self.gid = gid
        spaceID = system.nextSpaceID()
        let start = KernelClock.now()
        systemClock = {
            let ns = KernelClock.now() &- start
            return (ns / 1_000_000_000, ns % 1_000_000_000)
        }
        calendarClock = {
            let t = Date().timeIntervalSince1970
            let s = t.rounded(.down)
            return (UInt64(max(0, s)), UInt64(max(0, (t - s) * 1e9)))
        }
        func kobject(_ o: MachKernelObject) -> IPCPort {
            let p = IPCPort(serial: system.nextSerial())
            p.kernelObject = o
            return p
        }
        taskPort = kobject(.task)
        mainThreadPort = kobject(.thread(serial: 0))
        taskNamePort = kobject(.taskName)
        taskPort.task = self
        mainThreadPort.task = self
        taskNamePort.task = self
        seed(taskPort, index: 1)
        seed(mainThreadPort, index: 2)
        seed(system.hostPort, index: 3)
        let bootstrap = system.defaultBootstrapPort
        seed(bootstrap, index: 5)
        nextFresh = 6
        freeList = [4]
        system.hostPort.srights += 1
        slots.host = .send(system.hostPort)
        bootstrap.srights += 1
        slots.bootstrap = .send(bootstrap)
    }

    public convenience init(kernel: DarwinKernel) {
        self.init(lock: kernel.lock, log: { [weak kernel] in kernel?.log($0) }, pid: kernel.pid,
                  system: kernel.system.mach)
        self.kernel = kernel
        attachedToKernel = true
        pidVersion = kernel.pidVersion
        systemClock = { [weak kernel] in
            guard let kernel else { return (0, 0) }
            let ticks = kernel.counter() &- kernel.bootCounter
            let f = max(kernel.counterFrequency, 1)
            return (ticks / f, (ticks % f) * 1_000_000_000 / f)
        }
        let hostCalendar = calendarClock
        calendarClock = { [weak kernel] in
            guard let kernel else { return hostCalendar() }
            let w = kernel.wallClock()
            return (UInt64(max(0, w.seconds)), UInt64(max(0, w.nanoseconds)))
        }
    }

    func seed(_ p: IPCPort, index: Int) {
        while entries.count <= index { entries.append(IPCEntry()) }
        if let k = freeList.lastIndex(of: index) { freeList.remove(at: k) }
        entries[index].generation = 0
        entries[index].inUse = true
        entries[index].bits = MachPortType.send
        entries[index].urefs = 1
        entries[index].port = p
        entries[index].set = nil
        p.srights += 1
        reverse[ObjectIdentifier(p)] = nameOf(index)
    }

    func nextSerial() -> UInt64 { system.nextSerial() }

    func nextStamp() -> UInt64 { system.nextStamp() }

    func dn(_ name: UInt32) -> DNKey { DNKey(space: spaceID, name: name) }

    func requestTypeBits(_ p: IPCPort, _ name: UInt32) -> UInt32 {
        guard p.dnRequests[dn(name)] != nil else { return 0 }
        guard let armed = p.spRequests[dn(name)] else { return MachPortType.dnRequest }
        return MachPortType.dnRequest | MachPortType.spRequest | (armed ? 0 : MachPortType.spRequestDelayed)
    }

    func armSendPossible(_ p: IPCPort, name: UInt32) {
        guard p.active, !p.isKernelObject, p.spRequests[dn(name)] == false,
              p.occupiedSlots >= p.qlimit else { return }
        p.spRequests[dn(name)] = true
    }

    func fireSendPossible(_ p: IPCPort) {
        guard p.hasArmedSendPossible else { return }
        for (key, armed) in p.spRequests.sorted(by: { $0.key < $1.key }) where armed {
            p.spRequests[key] = nil
            guard let so = p.dnRequests.removeValue(forKey: key) else { continue }
            sendNotification(to: so, id: MachNotify.sendPossible, body: machNDRRecord + le32(key.name))
        }
    }

    var senderIdentity: MachSenderIdentity {
        MachSenderIdentity(uid: uid, gid: gid, pid: kernel?.pid ?? pid, pidVersion: kernel?.pidVersion ?? pidVersion,
                           auditSessionID: system.auditSessionID)
    }

    func newPort() -> IPCPort { IPCPort(serial: nextSerial()) }

    func nameOf(_ index: Int) -> UInt32 {
        UInt32(index) << 8 | entries[index].generation << 2 | 3
    }

    func slot(of name: UInt32) -> Int? {
        let i = Int(name >> 8)
        guard i > 0, i < entries.count, entries[i].inUse, nameOf(i) == name else { return nil }
        return i
    }

    func lookup(_ name: UInt32) -> Int? {
        guard MachPortName.isValid(name), let i = slot(of: name) else { return nil }
        convertIfDead(i)
        return i
    }

    func pegAdd(_ urefs: UInt32, _ delta: UInt32) -> UInt32 {
        let sum = UInt64(urefs) + UInt64(delta)
        return sum >= UInt64(MachPortName.urefsMax) ? MachPortName.urefsMax : UInt32(sum)
    }

    func convertIfDead(_ i: Int) {
        guard let p = entries[i].port, !p.active,
              entries[i].bits & (MachPortType.send | MachPortType.sendOnce) != 0 else { return }
        let name = nameOf(i)
        var urefs: UInt32
        if entries[i].bits & MachPortType.send != 0 {
            p.srights -= 1
            urefs = entries[i].urefs
            if reverse[ObjectIdentifier(p)] == name { reverse[ObjectIdentifier(p)] = nil }
        } else {
            p.sorights -= 1
            urefs = 1
        }
        if p.deadNameNotified.remove(dn(name)) != nil { urefs = pegAdd(urefs, 1) }
        entries[i].bits = MachPortType.deadName
        entries[i].urefs = urefs
        entries[i].port = nil
    }

    func allocateSlot() -> Int? {
        if let i = freeList.popLast() { return i }
        while nextFresh < entries.count && entries[nextFresh].inUse { nextFresh += 1 }
        guard nextFresh <= MachIPCLimits.maxIndex else { return nil }
        if nextFresh == entries.count { entries.append(IPCEntry()) }
        let i = nextFresh
        nextFresh += 1
        return i
    }

    func newEntry(bits: UInt32, urefs: UInt32, port: IPCPort? = nil, set: IPCPortSet? = nil) -> UInt32? {
        guard let i = allocateSlot() else { return nil }
        entries[i].generation = (entries[i].generation + 1) & 63
        return fill(i, bits: bits, urefs: urefs, port: port, set: set)
    }

    private func fill(_ i: Int, bits: UInt32, urefs: UInt32, port: IPCPort?, set: IPCPortSet?) -> UInt32 {
        entries[i].inUse = true
        entries[i].bits = bits
        entries[i].urefs = urefs
        entries[i].port = port
        entries[i].set = set
        let name = nameOf(i)
        if let port, bits & (MachPortType.send | MachPortType.receive) != 0 {
            reverse[ObjectIdentifier(port)] = name
        }
        set?.name = name
        return name
    }

    enum NameClaim { case free(Int), sameName(Int) }

    func claim(name: UInt32) -> Result<NameClaim, KernError> {
        guard MachPortName.isValid(name), name & 3 == 3 else { return .failure(KernError(MachKern.invalidValue)) }
        let i = Int(name >> 8)
        guard i > 0 else { return .failure(KernError(MachKern.failure)) }
        guard i <= MachIPCLimits.maxIndex else { return .failure(KernError(MachKern.noSpace)) }
        if i < entries.count, entries[i].inUse {
            return nameOf(i) == name ? .success(.sameName(i)) : .failure(KernError(MachKern.failure))
        }
        return .success(.free(i))
    }

    func newEntry(at i: Int, name: UInt32, bits: UInt32, urefs: UInt32, port: IPCPort? = nil,
                  set: IPCPortSet? = nil) -> UInt32 {
        while entries.count <= i { entries.append(IPCEntry()) }
        if let k = freeList.lastIndex(of: i) { freeList.remove(at: k) }
        entries[i].generation = (name & 0xFF) >> 2
        return fill(i, bits: bits, urefs: urefs, port: port, set: set)
    }

    func freeName(_ i: Int) {
        let name = nameOf(i)
        if let p = entries[i].port {
            p.spRequests[dn(name)] = nil
            if let so = p.dnRequests.removeValue(forKey: dn(name)) {
                if p.active {
                    sendNotification(to: so, id: MachNotify.portDeleted, body: machNDRRecord + le32(name))
                } else {
                    releaseSendOnceQuietly(so)
                }
            }
            p.deadNameNotified.remove(dn(name))
            if reverse[ObjectIdentifier(p)] == name { reverse[ObjectIdentifier(p)] = nil }
        }
        let generation = entries[i].generation
        entries[i] = IPCEntry()
        entries[i].generation = generation
        if i < nextFresh { freeList.append(i) }
    }

    func dropReceive(_ i: Int) {
        guard let p = entries[i].port else { return }
        let name = nameOf(i)
        entries[i].bits &= ~MachPortType.receive
        p.receiver = nil
        removeFromAllSets(p)
        p.changeStamp = nextStamp()
        p.receiveWaiters.wakeAll()
        if entries[i].bits & MachPortType.send == 0 {
            freeName(i)
        }
        hookReceiveGone(self, name)
    }

    @inline(__always) func hookQueued(_ space: MachIPC, _ name: UInt32) {
        guard let handler = space.messageQueuedHandler else { return }
        runHook(space, handler, name)
    }

    @inline(__always) func hookReceiveGone(_ space: MachIPC, _ name: UInt32) {
        guard let handler = space.receiveRightGoneHandler else { return }
        runHook(space, handler, name)
    }

    private func runHook(_ space: MachIPC, _ handler: @escaping (UInt32) -> Void, _ name: UInt32) {
        if let events = space.kernel?.eventLock {
            lock.deferIfFast(.fineLock(events)) { handler(name) }
        } else {
            handler(name)
        }
    }

    func releasePayload(_ release: @escaping () -> Void) {
        guard let l0 = lock.root else { release(); return }
        lock.deferIfFast(.kernelLock(l0), tag: "port payload release", release)
    }

    func copyout(_ right: CarriedRight) -> (name: UInt32, ok: Bool) {
        switch right {
        case .null: return (MachPortName.null, true)
        case .dead: return (MachPortName.dead, true)
        case let .send(p):
            if !p.active {
                p.srights -= 1
                return (MachPortName.dead, true)
            }
            if let name = reverse[ObjectIdentifier(p)], let i = slot(of: name) {
                if entries[i].bits & MachPortType.send != 0 {
                    p.srights -= 1
                } else {
                    entries[i].bits |= MachPortType.send
                }
                entries[i].urefs = pegAdd(entries[i].urefs, 1)
                return (name, true)
            }
            guard let name = newEntry(bits: MachPortType.send, urefs: 1, port: p) else {
                releaseSend(p)
                return (0, false)
            }
            return (name, true)
        case let .sendOnce(p):
            if !p.active {
                p.sorights -= 1
                return (MachPortName.dead, true)
            }
            guard let name = newEntry(bits: MachPortType.sendOnce, urefs: 1, port: p) else {
                destroySendOnce(p)
                return (0, false)
            }
            return (name, true)
        case let .receive(p):
            p.transitHolder = nil
            if let name = reverse[ObjectIdentifier(p)], let i = slot(of: name) {
                entries[i].bits |= MachPortType.receive
                p.receiver = self
                return (name, true)
            }
            guard let name = newEntry(bits: MachPortType.receive, urefs: 0, port: p) else {
                destroyReceive(p)
                return (0, false)
            }
            p.receiver = self
            return (name, true)
        }
    }

    func release(_ right: CarriedRight) {
        switch right {
        case .null, .dead: break
        case let .send(p): releaseSend(p)
        case let .sendOnce(p): destroySendOnce(p)
        case let .receive(p):
            p.transitHolder = nil
            destroyReceive(p)
        }
    }

    func releaseSend(_ p: IPCPort) {
        p.srights -= 1
        checkNoSenders(p)
        if p.srights <= 0, p.fileportFile != nil || p.memoryEntry != nil { portDeath(p) }
    }

    func checkNoSenders(_ p: IPCPort) {
        guard p.srights == 0, p.active, let ns = p.nsRequest else { return }
        p.nsRequest = nil
        sendNotification(to: ns, id: MachNotify.noSenders, body: machNDRRecord + le32(p.mscount))
    }

    func destroySendOnce(_ p: IPCPort) {
        if p.active, !p.isKernelObject, p.messages.count < MachIPCLimits.qlimitKernel {
            sendNotification(to: p, id: MachNotify.sendOnce, body: [])
        } else {
            p.sorights -= 1
        }
    }

    func releaseSendOnceQuietly(_ p: IPCPort) {
        p.sorights -= 1
    }

    func consumeDestination(_ right: CarriedRight) {
        switch right {
        case let .send(p): releaseSend(p)
        case let .sendOnce(p): p.sorights -= 1
        default: break
        }
    }

    func destroyMessage(_ m: KMessage, consumeDestination consume: Bool = false) {
        for p in m.receiveRights { p.transitHolder = nil }
        if consume { consumeDestination(m.destination) } else { release(m.destination) }
        release(m.reply)
        for item in m.items {
            switch item {
            case let .port(r, _), let .guarded(r, _, _): release(r)
            case let .oolPorts(rights, _, _): rights.forEach(release)
            case .ool: break
            }
        }
    }

    func destroyReceive(_ p: IPCPort) {
        p.receiver = nil
        if let pd = p.pdRequest {
            p.pdRequest = nil
            if pd.active && pd !== p {
                p.guarded = false
                p.strict = false
                p.context = 0
                removeFromAllSets(p)
                p.changeStamp = nextStamp()
                p.receiveWaiters.wakeAll()
                var m = KMessage(complex: true, destination: .sendOnce(pd), destinationType: MachMsgType.portSendOnce,
                                 reply: .null, replyType: 0, id: MachNotify.portDestroyed)
                m.items = [.port(.receive(p), type: MachMsgType.portReceive)]
                m.fromKernel = true
                sendKernelMessage(m)
                return
            }
            releaseSendOnceQuietly(pd)
        }
        portDeath(p)
    }

    func portDeath(_ p: IPCPort) {
        guard p.active else { return }
        p.active = false
        p.receiver = nil
        p.transitHolder = nil
        p.changeStamp = nextStamp()
        removeFromAllSets(p)
        let queued = p.messages.removeAll()
        if p.importanceCount > 0 {
            p.creditedProcess?.changeImportance(-p.importanceCount)
            p.importanceCount = 0
            p.creditedProcess = nil
        }
        for m in queued { destroyMessage(m) }
        p.receiveWaiters.wakeAll()
        p.sendWaiters.wakeAll()
        if let ns = p.nsRequest {
            p.nsRequest = nil
            destroySendOnce(ns)
        }
        for (key, so) in p.dnRequests.sorted(by: { $0.key < $1.key }) {
            p.deadNameNotified.insert(key)
            sendNotification(to: so, id: MachNotify.deadName, body: machNDRRecord + le32(key.name))
        }
        p.dnRequests = [:]
        p.spRequests = [:]
        if let s = p.semaphore {
            p.semaphore = nil
            releasePayload { s.destroy() }
        }
        if p.fileportFile != nil || p.memoryEntry != nil {
            var payload: (DarwinOpenFile?, MachMemoryEntry?) = (p.fileportFile, p.memoryEntry)
            p.fileportFile = nil
            p.memoryEntry = nil
            releasePayload { payload = (nil, nil) }
            _ = payload
        }
        p.mkTimer?.deadline = nil
        p.mkTimer = nil
    }

    func removeFromAllSets(_ p: IPCPort) {
        for s in p.sets {
            s.members.removeAll { $0 === p }
            s.waiters.wakeAll()
        }
        p.sets = []
    }

    func destroySet(_ s: IPCPortSet) {
        s.active = false
        for p in s.members {
            p.sets.removeAll { $0 === s }
            p.changeStamp = nextStamp()
            p.receiveWaiters.wakeAll()
        }
        s.members = []
        s.changeStamp = nextStamp()
        s.waiters.wakeAll()
    }

    func sendNotification(to so: IPCPort, id: Int32, body: [UInt8]) {
        var m = KMessage(complex: false, destination: .sendOnce(so), destinationType: MachMsgType.portSendOnce,
                         reply: .null, replyType: 0, id: id)
        m.inline = body
        m.fromKernel = true
        sendKernelMessage(m)
    }

    func sendKernelMessage(_ m: KMessage) {
        guard let p = m.destination.port, p.active, !p.isKernelObject,
              p.messages.count < MachIPCLimits.qlimitKernel else {
            destroyMessage(m)
            return
        }
        if case .send = m.destination, p.messages.count >= p.qlimit {
            destroyMessage(m)
            return
        }
        enqueue(m, on: p)
    }

    func enqueue(_ m: KMessage, on p: IPCPort) {
        if MachTrafficStats.enabled { MachTrafficStats.count(from: self, to: p, id: m.id, inline: m.inline) }
        for r in m.receiveRights { r.transitHolder = p }
        if p.messages.isEmpty { p.readyStamp = nextStamp() }
        p.messages.append(m)
        if m.importance { importanceQueued(on: p, id: m.id) }
        p.receiveWaiters.wakeAll()
        for s in p.sets { s.waiters.wakeAll() }
        if let space = p.receiver, space.messageQueuedHandler != nil,
           let name = space.reverse[ObjectIdentifier(p)] {
            hookQueued(space, name)
            for s in p.sets where s.active { hookQueued(space, s.name) }
        }
    }

    nonisolated(unsafe) static var slotHandoff = getenv("SWIFTCODE_PORT_SLOT_HANDOFF").map { String(cString: $0) != "0" } ?? true

    func dequeue(_ p: IPCPort) -> (KMessage, seqno: UInt32) {
        let m = p.messages.popFirst()!
        if m.importance { importanceDequeued(from: p) }
        let seqno = p.seqno
        p.seqno &+= 1
        if !p.messages.isEmpty { p.readyStamp = nextStamp() }
        for r in m.receiveRights { r.transitHolder = nil }
        if Self.slotHandoff {
            if p.occupiedSlots < p.qlimit, p.sendWaiters.wake(count: 1) == 1 { p.grantedSlots += 1 }
        } else {
            p.sendWaiters.wakeAll()
        }
        fireSendPossible(p)
        return (m, seqno)
    }

    func makeKernelObjectName(_ object: MachKernelObject) -> (IPCPort, UInt32)? {
        let p = newPort()
        p.kernelObject = object
        p.srights = 1
        let (name, ok) = copyout(.send(p))
        return ok ? (p, name) : nil
    }

    func copyoutNewSend(_ p: IPCPort) -> UInt32 {
        p.srights += 1
        return copyout(.send(p)).name
    }

    func kernelObject(named name: UInt32) -> (IPCPort, MachKernelObject)? {
        guard let i = lookup(name), entries[i].bits & MachPortType.send != 0,
              let p = entries[i].port, let o = p.kernelObject else { return nil }
        return (p, o)
    }

    func isTaskSelf(_ name: UInt32) -> Bool {
        guard let (p, _) = kernelObject(named: name) else { return false }
        return p === taskPort
    }

    public func allocateThreadPort() -> UInt32 {
        lock.withLock {
            guard let (p, name) = makeKernelObjectName(.thread(serial: nextSerial())) else { return 0 }
            own(p)
            return name
        }
    }

    func own(_ p: IPCPort) {
        p.task = self
        if ownedKernelPorts.count >= 64 { ownedKernelPorts.removeAll { !$0.active } }
        ownedKernelPorts.append(p)
    }

    public func deallocate(name: UInt32) {
        lock.withLock { _ = portDeallocate(name) }
    }

    public func threadTerminated(_ context: ThreadContext) {
        lock.withLock {
            let thread = kernelObject(named: context.portName)?.0
            if let thread, let slots = threadExceptions.removeValue(forKey: ObjectIdentifier(thread)) {
                slots.forEach { release($0.port) }
            }
            _ = portDeallocate(context.portName)
            if let thread, thread !== mainThreadPort { portDeath(thread) }
            specialReplyPorts[context.threadID] = nil
        }
    }

    public func messageQueued(on port: UInt32) -> Bool {
        lock.withLock {
            guard let i = lookup(port) else { return false }
            if let s = entries[i].set { return s.members.contains { !$0.messages.isEmpty } }
            guard entries[i].bits & MachPortType.receive != 0, let p = entries[i].port else { return false }
            return !p.messages.isEmpty
        }
    }

    public func semaphore(named name: UInt32) -> KernelSemaphore? {
        lock.withLock {
            guard let (p, o) = kernelObject(named: name), case .semaphore = o, p.active else { return nil }
            return p.semaphore
        }
    }

    public func receiveTarget(of name: UInt32) -> MachReceiveTarget {
        lock.withLock {
            guard let i = lookup(name) else { return .none }
            if entries[i].set != nil { return .portSet }
            guard entries[i].bits & MachPortType.receive != 0, let p = entries[i].port else { return .notReceivable }
            return p.isSpecialReply ? .specialReplyPort : .port
        }
    }

    public func entry(_ name: UInt32) -> (type: UInt32, urefs: UInt32)? {
        lock.withLock {
            guard let i = lookup(name) else { return nil }
            var type = entries[i].bits
            if let p = entries[i].port { type |= requestTypeBits(p, name) }
            return (type, entries[i].urefs)
        }
    }

    public func portCounters(_ name: UInt32) -> (srights: Int, sorights: Int, mscount: UInt32, seqno: UInt32,
                                                  qlimit: Int, msgcount: Int, active: Bool)? {
        lock.withLock {
            guard let i = slot(of: name), let p = entries[i].port else { return nil }
            return (p.srights, p.sorights, p.mscount, p.seqno, p.qlimit, p.messages.count, p.active)
        }
    }

    public func kernelObjectKind(of name: UInt32) -> MachKernelObject? {
        lock.withLock { kernelObject(named: name)?.1 }
    }

    public var nameCount: Int {
        lock.withLock { entries.reduce(0) { $0 + ($1.inUse ? 1 : 0) } }
    }
}

struct KernError: Error, Equatable {
    var code: UInt32
    init(_ code: UInt32) { self.code = code }
}

func le32(_ v: UInt32) -> [UInt8] {
    [UInt8(truncatingIfNeeded: v), UInt8(truncatingIfNeeded: v >> 8),
     UInt8(truncatingIfNeeded: v >> 16), UInt8(truncatingIfNeeded: v >> 24)]
}

func le64(_ v: UInt64) -> [UInt8] {
    (0..<8).map { UInt8(truncatingIfNeeded: v >> (8 * UInt64($0))) }
}

enum MachTrafficStats {
    static let enabled = getenv("SWIFTCODE_DEBUG_MACH_STATS").map { String(cString: $0) == "1" } ?? false
    static let reportEvery: UInt64 = 100_000
    nonisolated(unsafe) static var total: UInt64 = 0
    nonisolated(unsafe) static var pairs: [String: UInt64] = [:]

    static func name(_ space: MachIPC?) -> String {
        guard let space else { return "none" }
        guard let k = space.kernel else { return space.kernelGone ? "gone" : "host" }
        return k.processRecord?.comm ?? "pid \(k.pid)"
    }

    static let dumpReceiver = getenv("SWIFTCODE_DEBUG_MACH_DUMP").map { String(cString: $0) }
    nonisolated(unsafe) static var dumped = 0

    static func count(from sender: MachIPC, to p: IPCPort, id: Int32, inline: [UInt8] = []) {
        total += 1
        let receiver = name(p.receiver)
        let key = "\(name(sender)) -> \(receiver) id \(id)"
        pairs[key, default: 0] += 1
        if let d = dumpReceiver, d == receiver, dumped < 12 {
            dumped += 1
            var strings: [String] = []
            var run: [UInt8] = []
            for b in inline + [0] {
                if b >= 0x20 && b < 0x7F { run.append(b); continue }
                if run.count >= 3 { strings.append(String(decoding: run, as: UTF8.self)) }
                run = []
            }
            FileHandle.standardError.write(Data("swiftcode-mach-dump: \(key), \(inline.count) bytes: \(strings.joined(separator: " | "))\n".utf8))
        }
        guard total % reportEvery == 0 else { return }
        let top = pairs.sorted { $0.value > $1.value }.prefix(20).map { "\($0.key): \($0.value)" }.joined(separator: "; ")
        FileHandle.standardError.write(Data("swiftcode-mach-stats: \(total) messages; top: \(top)\n".utf8))
    }
}
