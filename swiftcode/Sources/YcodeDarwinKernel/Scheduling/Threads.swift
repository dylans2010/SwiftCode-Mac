import Foundation
import Synchronization
import YcodeDarwinABI

public final class ThreadContext: @unchecked Sendable, CustomStringConvertible, GuestThreadGated {
    public enum Kind: Equatable, Sendable {
        case main
        case pthread
        case workqueue
    }

    public let threadID: UInt64
    public internal(set) var portName: UInt32
    public var vcpuIndex: Int
    public let kind: Kind
    public internal(set) var pthreadAddress: UInt64
    public internal(set) var isAlive = true
    public internal(set) var blockedInKernel = false
    public var trapInProgress: (x16: UInt64, args: TrapRegisters)?
    public internal(set) var entryFrame: TrapFrame? {
        get { entryFrameStore.withLock { $0 } }
        set { entryFrameStore.withLock { $0 = newValue } }
    }
    private let entryFrameStore = Mutex<TrapFrame?>(nil)
    public var arrivingTrap: UInt64?
    public var traceTag: UInt32 = 0
    public var traceHostTID: Int32 = 0
    public var trapCount = 0
    public var hostCPUBaseNanoseconds: UInt64 = 0
    public let trapRing = TrapRing()
    public var recentTraps: [(UInt64, UInt64, UInt64, UInt64)] { trapRing.entries }
    public internal(set) weak var kernel: DarwinKernel?

    var signalMask: UInt32 = 0
    var worker: WorkerState?
    var suspendedStart: ThreadStartState?
    public let gate = GuestThreadGate()
    var suspendCount = 0
    var debugHold = false
    public internal(set) var debugStop: KernelDebugStop?
    var debugDeliversFault = false
    var snapshotSigsuspendSavedMask: UInt32?

    var requestedQoS = 0
    var dispatchOverrideQoS = 0
    private let explicitOverridesStore = Mutex<[UInt64: Int]>([:])

    func setExplicitOverride(_ qos: Int, for resource: UInt64) {
        explicitOverridesStore.withLock { $0[resource] = qos }
    }

    func removeExplicitOverride(for resource: UInt64) -> Bool {
        explicitOverridesStore.withLock { $0.removeValue(forKey: resource) != nil }
    }

    func removeAllExplicitOverrides() {
        explicitOverridesStore.withLock { $0.removeAll() }
    }

    var maxExplicitOverride: Int { explicitOverridesStore.withLock { $0.values.max() ?? 0 } }
    struct SchedPushes {
        var ulock: [UInt64: Int] = [:]
        var ipc = -1
        var maxClass: Int { max(ipc, ulock.values.max() ?? -1) }
    }
    let schedPushes = Mutex<SchedPushes>(SchedPushes())
    var ipcPushClass: Int {
        get { schedPushes.withLock { $0.ipc } }
        set { schedPushes.withLock { $0.ipc = newValue } }
    }
    func setULockPush(_ cls: Int, for addr: UInt64) -> Bool {
        schedPushes.withLock {
            let old = $0.ulock[addr] ?? -1
            guard old != cls else { return false }
            $0.ulock[addr] = cls < 0 ? nil : cls
            return true
        }
    }
    var carriedImportance: DarwinProcess?
    var threadDarwinBG = false
    var workInterval: KernelWorkInterval?
    let schedClassStore = Atomic<Int>(SchedClass.default)

    public init(threadID: UInt64, portName: UInt32, vcpuIndex: Int, kind: Kind, pthreadAddress: UInt64 = 0) {
        self.threadID = threadID
        self.portName = portName
        self.vcpuIndex = vcpuIndex
        self.kind = kind
        self.pthreadAddress = pthreadAddress
    }

    public var description: String {
        "thread \(threadID) port \(hx(portName)) vcpu \(vcpuIndex) \(kind)"
    }
}

public struct ThreadStartState: Equatable, Sendable {
    public var x: [UInt64]
    public var pc: UInt64
    public var sp: UInt64
    public var tpidrro: UInt64
    public var tpidr: UInt64

    public init(x: [UInt64] = [], pc: UInt64, sp: UInt64, tpidrro: UInt64, tpidr: UInt64 = 0) {
        var regs = Array(x.prefix(TrapFrame.registerCount))
        regs += [UInt64](repeating: 0, count: TrapFrame.registerCount - regs.count)
        self.x = regs
        self.pc = pc
        self.sp = sp
        self.tpidrro = tpidrro
        self.tpidr = tpidr
    }

    public var frame: TrapFrame {
        TrapFrame(x: x, spEL0: sp, elr: pc, spsr: 0, tpidrro: tpidrro, tpidr: tpidr,
                  kind: TrapFrame.Kind.svc.rawValue)
    }

    public func apply(to frame: inout TrapFrame) {
        frame.x = TrapRegisters(x)
        frame.spEL0 = sp
        frame.elr = pc
        frame.spsr = 0
        frame.tpidrro = tpidrro
        frame.tpidr = tpidr
    }
}

extension ThreadHost {
    public var canStartThread: Bool { true }
}

public protocol ThreadHost: AnyObject {
    func startThread(_ start: ThreadStartState, context: ThreadContext) throws -> Int

    var canStartThread: Bool { get }

    func stopAllThreads()

    func kickThread(_ context: ThreadContext)
}

extension ThreadHost {
    public func stopAllThreads() {}
    public func kickThread(_ context: ThreadContext) {}
}

public protocol MachIPCHandling: AnyObject {
    func handleTrap(x16: Int64, frame: inout TrapFrame, context: ThreadContext,
                    memory: any GuestVirtualMemory) -> TrapOutcome?
    func allocateThreadPort() -> UInt32
    func deallocate(name: UInt32)
    func messageQueued(on port: UInt32) -> Bool
    var messageQueuedHandler: ((_ name: UInt32) -> Void)? { get set }
    func semaphore(named name: UInt32) -> KernelSemaphore?
    func receiveForKevent(port: UInt32, options: UInt32, buffer: UInt64, size: UInt64,
                          context: ThreadContext, memory: any GuestVirtualMemory) -> KeventMachReceive?
}

extension MachIPCHandling {
    public func receiveForKevent(port: UInt32, options: UInt32, buffer: UInt64, size: UInt64,
                                 context: ThreadContext, memory: any GuestVirtualMemory) -> KeventMachReceive? { nil }
}

public struct KeventMachReceive: Equatable, Sendable {
    public var returnCode: UInt32
    public var size: UInt64
    public var priorityAndQoS: UInt64
    public var auxiliarySize: UInt64
    public var data: UInt64

    public init(returnCode: UInt32, size: UInt64, priorityAndQoS: UInt64 = 0, auxiliarySize: UInt64 = 0, data: UInt64 = 0) {
        self.returnCode = returnCode
        self.size = size
        self.priorityAndQoS = priorityAndQoS
        self.auxiliarySize = auxiliarySize
        self.data = data
    }
}

extension DarwinKernel {
    public enum PthreadStart {
        public static let custom: UInt32 = 0x0100_0000
        public static let setSched: UInt32 = 0x0200_0000
        public static let qosClass: UInt32 = 0x0800_0000
        public static let tsdBaseSet: UInt32 = 0x1000_0000
        public static let suspended: UInt32 = 0x2000_0000
    }

    func allocateThreadPort() -> UInt32 {
        guard let ipc = machIPC else { preconditionFailure("DarwinKernel.machIPC is not attached") }
        return ipc.allocateThreadPort()
    }

    func deallocateThreadPort(_ name: UInt32) {
        machIPC?.deallocate(name: name)
    }

    func threadPortTerminated(_ ctx: ThreadContext) {
        if let ipc = machIPC as? MachIPC { ipc.threadTerminated(ctx) } else { deallocateThreadPort(ctx.portName) }
    }

    func makeThread(kind: ThreadContext.Kind, pthread: UInt64) -> ThreadContext {
        let ctx = ThreadContext(threadID: nextThreadID, portName: allocateThreadPort(), vcpuIndex: -1, kind: kind,
                                pthreadAddress: pthread)
        nextThreadID += 1
        ctx.kernel = self
        ctx.debugHold = debugAllHeld
        if taskSuspendCount > 0 || debugAllHeld { ctx.gate.close() }
        withEvents { threadsByPort[ctx.portName] = ctx }
        return ctx
    }

    public func shutdown(status: Int32 = 0) {
        lock.withLock {
            if termination == nil, let p = system.record(of: self) {
                system.exitProcess(p, waitStatus: (status & 0xFF) << 8, outcome: .exit(status: status))
                return
            }
            if termination == nil { termination = .exit(status: status) }
            lock.terminate()
            withEvents { kevents.timerWake.wakeAll() }
        }
    }

    public func resumeSuspendedThread(port: UInt32) -> Bool {
        lock.withLock {
            guard let ctx = threadsByPort[port], let start = ctx.suspendedStart, let host = threadHost else { return false }
            guard let index = try? host.startThread(start, context: ctx) else { return false }
            ctx.vcpuIndex = index
            ctx.suspendedStart = nil
            ctx.suspendCount = 0
            refreshGate(ctx)
            return true
        }
    }

    func bsdthreadCreate(_ a: [UInt64], _ call: inout CallText, _ mem: any KernelGuestMemory) throws -> BSDResult {
        let flags = UInt32(truncatingIfNeeded: a[4])
        call.set("bsdthread_create(func=\(hx(a[0])), arg=\(hx(a[1])), stack=\(hx(a[2])), pthread=\(hx(a[3])), flags=\(hx(flags)))")
        guard let reg = threadRegistration else { throw Failure(errno: Errno.EINVAL) }
        guard flags & PthreadStart.custom != 0 else { throw Failure(errno: Errno.EINVAL) }
        if flags & PthreadStart.qosClass != 0 {
            let pp = flags & 0x00FF_FFFF
            guard PthreadPriority.qos(pp) != nil, (-15...0).contains(PthreadPriority.relativePriority(pp)) else {
                throw Failure(errno: Errno.EINVAL)
            }
        }
        let pthread = a[3], stack = a[2]
        let ctx = makeThread(kind: .pthread, pthread: pthread)
        if SchedPolicy.qosEnabled {
            ctx.requestedQoS = flags & PthreadStart.qosClass != 0
                ? PthreadPriority.qos(flags & 0x00FF_FFFF) ?? 0 : current.baseQoS
            refreshSchedClass(ctx)
        }
        func undo() {
            withEvents { threadsByPort[ctx.portName] = nil }
            ctx.isAlive = false
            deallocateThreadPort(ctx.portName)
        }
        var outFlags = flags & ~PthreadStart.suspended
        var tpidrro: UInt64 = 0
        if reg.tsdOffset != 0 {
            tpidrro = pthread &+ UInt64(reg.tsdOffset)
            outFlags |= PthreadStart.tsdBaseSet
        }
        if reg.machThreadSelfOffset != 0 {
            do {
                try writeU64(pthread &+ UInt64(reg.tsdOffset) &+ UInt64(reg.machThreadSelfOffset), UInt64(ctx.portName), mem)
            } catch {
                undo()
                throw error
            }
        }
        let start = ThreadStartState(x: [pthread, UInt64(ctx.portName), a[0], a[1], stack, UInt64(outFlags)],
                                     pc: reg.threadStart, sp: stack, tpidrro: tpidrro)
        if flags & PthreadStart.suspended != 0 {
            ctx.suspendedStart = start
            ctx.suspendCount = 1
            call += " [\(ctx), suspended]"
            return .value(pthread)
        }
        guard let host = threadHost else {
            undo()
            trace("note: bsdthread_create: no thread host; EAGAIN")
            throw Failure(errno: Self.EAGAIN)
        }
        do {
            ctx.vcpuIndex = try host.startThread(start, context: ctx)
        } catch {
            undo()
            trace("note: bsdthread_create: cannot start a vCPU (\(error)); EAGAIN")
            throw Failure(errno: Self.EAGAIN)
        }
        call += " [\(ctx)]"
        return .value(pthread)
    }

    static let EAGAIN: Int32 = 35

    func bsdthreadTerminate(_ a: [UInt64], _ call: inout CallText, _ mem: any KernelGuestMemory) throws -> BSDResult {
        let ctx = current
        var port = UInt32(truncatingIfNeeded: a[2])
        var semaphoreName = UInt32(truncatingIfNeeded: a[3])
        call.set("bsdthread_terminate(stack=\(hx(a[0])), size=\(hx(a[1])), port=\(hx(port)), sema_or_ulock=\(hx(a[3])))")
        if ctx.kind == .workqueue { withEvents { workqueueThreadTerminating(ctx) } }
        var gate: (address: UInt64, port: UInt32)?
        if a[3] != 0, a[3] | 3 != a[3] {
            gate = (a[3], port)
            port = 0
            semaphoreName = 0
        }
        if a[0] != 0, a[1] != 0 {
            lock.unlocked {
                if ctx.kind == .main {
                    let size = (a[1] - 1) & ~Self.pageMask
                    if size > 0 { try? mem.protect(va: a[0] & ~Self.pageMask, size: size, protection: []) }
                } else {
                    let start = a[0] & ~Self.pageMask
                    try? mem.unmap(va: start, size: roundUp(a[1] + (a[0] - start), to: Self.pageSize))
                }
            }
        }
        ctx.isAlive = false
        withEvents { threadsByPort[ctx.portName] = nil }
        if ctx.carriedImportance != nil { withPorts { endServicing(ctx) } }
        if semaphoreName != 0 { semaphore(named: semaphoreName)?.signal() }
        if port != 0, port != ctx.portName { deallocateThreadPort(port) }
        if let gate {
            try? writeU32(gate.address, gate.port & ~3, mem)
            let (_, woke) = ulockWakeCore(operation: ULock.unfairLock | ULockFlag.wakeAll | ULockFlag.wakeAllowNonOwner,
                                          addr: gate.address, wakeValue: 0)
            if gate.port != 0, gate.port != ctx.portName { deallocateThreadPort(gate.port) }
            call += " [join gate \(hx(gate.address)) = \(hx(gate.port & ~3)), woke \(woke)]"
        }
        threadPortTerminated(ctx)
        withEvents { pumpWorkqueue(mem) }
        if threadsByPort.isEmpty {
            call += " [last thread]"
            return .exit(0)
        }
        return .threadExit
    }

    func bsdthreadCtl(_ a: [UInt64], _ call: inout CallText, _ mem: any KernelGuestMemory) throws -> UInt64 {
        let cmd = UInt32(truncatingIfNeeded: a[0])
        call.set("bsdthread_ctl(cmd=\(hx(cmd)), \(hx(a[1])), \(hx(a[2])), \(hx(a[3])))")
        switch cmd {
        case 0x10, 0x401, 0x402:
            throw Failure(errno: Errno.ENOTSUP)
        case 0x40, 0x400:
            if SchedPolicy.qosEnabled, let t = threadsByPort[UInt32(truncatingIfNeeded: a[1])],
               let q = PthreadPriority.qos(UInt32(truncatingIfNeeded: a[2])) {
                if cmd == 0x40 { t.setExplicitOverride(q, for: a[3]) } else { t.dispatchOverrideQoS = max(t.dispatchOverrideQoS, q) }
                refreshSchedClass(t)
            }
            return 0
        case 0x80:
            if SchedPolicy.qosEnabled, let t = threadsByPort[UInt32(truncatingIfNeeded: a[1])],
               t.removeExplicitOverride(for: a[2]) {
                refreshSchedClass(t)
            }
            return 0
        case 0x200:
            if SchedPolicy.qosEnabled, current.dispatchOverrideQoS != 0 {
                current.dispatchOverrideQoS = 0
                refreshSchedClass(current)
            }
            return 0
        case 0x1000, 0x2000, 0x4000:
            return 0
        case 0x800:
            return UInt64(WorkqueueState.parallelism)
        case 0x100:
            let ctx = current
            let flags = UInt32(truncatingIfNeeded: a[3])
            if flags & 0x01 != 0 {
                guard let q = PthreadPriority.qos(UInt32(truncatingIfNeeded: a[1])) else { throw Failure(errno: Errno.EINVAL) }
                if SchedPolicy.qosEnabled, ctx.requestedQoS != q {
                    ctx.requestedQoS = q
                    refreshSchedClass(ctx)
                }
            }
            if flags & 0x10 != 0 {
                try withEvents {
                    guard let w = ctx.worker, w.boundBucket != Self.managerQoS, !(w.boundQueue?.kind == .workloop) else {
                        throw Failure(errno: Errno.EINVAL)
                    }
                    guard w.boundQueue != nil else { throw Failure(errno: Self.EALREADY) }
                    unbindWorker(ctx, release: false)
                }
                call += " [kevent unbind]"
            }
            return 0
        default:
            throw Failure(errno: Errno.EINVAL)
        }
    }

    func handleThreadSwitch(_ n: Int, _ frame: inout TrapFrame) -> Outcome? {
        if n == Mach.swtchPri || n == Mach.swtch {
            lock.yield()
            frame.x[0] = 0
            trace("trap mach \(n) \(n == Mach.swtch ? "swtch" : "swtch_pri")(\(Int32(truncatingIfNeeded: frame.x[0]))) -> 0 [yield]")
            return .resume
        }
        guard n == Mach.threadSwitch else { return nil }
        let option = Int32(truncatingIfNeeded: frame.x[1])
        let ms = UInt64(UInt32(truncatingIfNeeded: frame.x[2]))
        if (option == 1 || option == 2) && ms > 0 {
            _ = WaitQueue().wait(on: lock, deadline: KernelClock.deadline(afterNanoseconds: min(ms, 10_000) * 1_000_000))
        } else {
            lock.yield()
        }
        frame.x[0] = KernReturn.success
        trace("trap mach \(n) thread_switch(thread=\(hx(UInt32(truncatingIfNeeded: frame.x[0]))), option=\(option), time=\(ms)) -> KERN_SUCCESS")
        return .resume
    }
}

extension DarwinKernel {
    func threadGetState(_ a: [UInt64], ipc: MachIPC, memory: any GuestVirtualMemory) -> (UInt32, String) {
        let name = UInt32(truncatingIfNeeded: a[0]), flavor = UInt32(truncatingIfNeeded: a[1])
        guard let (port, object) = ipc.kernelObject(named: name), case .thread = object else {
            return (MachKern.invalidArgument, " [not a thread of this task]")
        }
        guard let thread = threadsByPort.values.first(where: { ipc.kernelObject(named: $0.portName)?.0 === port }),
              thread.isAlive else {
            return (MachKern.invalidArgument, " [not a thread of this task]")
        }
        guard let capacityBytes = try? memory.read(va: a[3], count: 4) else { return (MachKern.invalidAddress, "") }
        let capacity = capacityBytes.readLE(UInt32.self, at: 0)
        let needed: UInt32
        switch flavor {
        case 1: needed = 70
        case 6: needed = 68
        case 7: needed = 4
        default: return (MachKern.invalidArgument, " [flavor \(flavor) not kept]")
        }
        guard capacity >= needed else { return (MachKern.invalidArgument, " [count \(capacity) < \(needed)]") }
        var f: TrapFrame
        if let parked = thread.gate.parked?.frame {
            f = parked
        } else if let entry = thread.entryFrame {
            f = entry
        } else if let start = thread.suspendedStart {
            f = start.frame
        } else if thread.gate.isClosed, thread.gate.attached.load(ordering: .acquiring), !isTerminating {
            return (UInt32(truncatingIfNeeded: Self.threadStateRetry), " [thread \(thread.threadID) moving to its gate]")
        } else {
            return (MachKern.failure, " [thread \(thread.threadID) is running]")
        }
        if let r = thread.gate.pendingReplacement { f.takeUserState(of: r) }
        var out: [UInt8] = []
        switch flavor {
        case 7:
            out.appendLE(f.far)
            out.appendLE(UInt32(truncatingIfNeeded: f.esr))
            out.appendLE(UInt32(truncatingIfNeeded: f.esr >> 26))
        default:
            if flavor == 1 { out.appendLE(UInt32(6)); out.appendLE(UInt32(68)) }
            for r in 0..<29 { out.appendLE(f.x[r]) }
            out.appendLE(f.x[29])
            out.appendLE(f.x[30])
            out.appendLE(f.spEL0)
            out.appendLE(f.elr)
            out.appendLE(UInt32(truncatingIfNeeded: f.spsr))
            out.appendLE(UInt32(0))
        }
        guard (try? memory.write(va: a[2], bytes: out)) != nil,
              (try? memory.write(va: a[3], bytes: le32(needed))) != nil else { return (MachKern.invalidAddress, "") }
        return (MachKern.success, " [thread \(thread.threadID) pc \(hx(f.elr))]")
    }
}
