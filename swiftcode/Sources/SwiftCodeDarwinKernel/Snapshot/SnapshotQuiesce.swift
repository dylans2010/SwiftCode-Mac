import SwiftCodeDarwinABI

public enum SnapshotThreadKind: UInt64, Sendable {
    case pendingTrap = 1
    case resume = 2
    case blocked = 3
    case suspended = 4
    case unstarted = 5
}

public struct SnapshotMainStart: Sendable, Equatable {
    public var pc: UInt64, sp: UInt64, tpidrro: UInt64, tpidr: UInt64
    public var registers: [UInt64]
    public init(pc: UInt64, sp: UInt64, registers: [UInt64], tpidrro: UInt64, tpidr: UInt64) {
        self.pc = pc
        self.sp = sp
        self.registers = registers
        self.tpidrro = tpidrro
        self.tpidr = tpidr
    }
}

public struct SnapshotParkedThread: Sendable {
    public var kind: SnapshotThreadKind
    public var frame: TrapFrame
    public var fp: [UInt8]

    public init(kind: SnapshotThreadKind, frame: TrapFrame, fp: [UInt8]) {
        self.kind = kind
        self.frame = frame
        self.fp = fp
    }
}

public struct SnapshotBlockedThread: Sendable {
    public var frame: TrapFrame
    public var note: String
    public var idleWorker: Bool
    public var savedSignalMask: UInt32?
    public var queuedSend = false
    public var completed = false
}

public struct SnapshotClassification: Sendable {
    public var settled: Bool { unsettled.isEmpty && refused.isEmpty }
    public var unsettled: [String] = []
    public var refused: [String] = []
    public var blocked: [ObjectIdentifier: SnapshotBlockedThread] = [:]
    public var counts: [String: Int] = [:]
}

public enum KernelSnapshotQuiesce {
    public static func classify(system: DarwinSystem, kernels: [DarwinKernel],
                                parked: Set<ObjectIdentifier>,
                                unstarted: Set<ObjectIdentifier> = []) -> SnapshotClassification {
        precondition(system.lock.isHeldByCurrentThread, "classify needs the kernel lock")
        var out = SnapshotClassification()
        var sleeping = Set<ObjectIdentifier>()
        for w in system.lock.snapshotWaiterStates {
            guard let c = w.context else { continue }
            if w.woken {
                out.unsettled.append("pid \(c.kernel?.pid ?? -1) thread \(c.threadID): woken, not yet returned")
            } else {
                sleeping.insert(ObjectIdentifier(c))
            }
        }
        for k in kernels {
            if k.isTerminating {
                out.unsettled.append("pid \(k.pid): image ending")
                continue
            }
            let spaces = k.system.snapshotSpaces()
            for t in k.threadsByPort.values.sorted(by: { $0.threadID < $1.threadID }) {
                let id = ObjectIdentifier(t)
                if parked.contains(id) {
                    out.counts["parked", default: 0] += 1
                } else if sleeping.contains(id) {
                    switch blockedVerdict(t, kernel: k, spaces: spaces) {
                    case let .success(v):
                        out.blocked[id] = v
                        out.counts["blocked", default: 0] += 1
                        out.counts["blocked " + v.note, default: 0] += 1
                    case let .failure(e):
                        out.refused.append("pid \(k.pid) thread \(t.threadID): \(e.message)")
                    }
                } else if t.suspendedStart != nil {
                    out.counts["suspended", default: 0] += 1
                } else if unstarted.contains(id) {
                    out.counts["unstarted", default: 0] += 1
                } else {
                    let trap = t.trapInProgress.map { String(Int32(truncatingIfNeeded: $0.x16)) } ?? "-"
                    out.unsettled.append("pid \(k.pid) thread \(t.threadID): running (trap \(trap))")
                }
            }
        }
        return out
    }

    static func blockedVerdict(_ t: ThreadContext, kernel k: DarwinKernel,
                               spaces: [MachIPC]) -> Result<SnapshotBlockedThread, SnapshotError> {
        guard var frame = t.entryFrame else {
            let trap = t.trapInProgress.map { String(Int32(truncatingIfNeeded: $0.x16)) } ?? "-"
            return .failure(SnapshotError("blocked without an entry frame (trap \(trap), \(t.kind))"))
        }
        let x16 = Int32(truncatingIfNeeded: frame.x[16])
        var n = Int(x16)
        var argBase = 0
        if n == 0 {
            n = Int(frame.x[0] & 0xFFFF)
            argBase = 1
        }
        func plain(_ what: String) -> Result<SnapshotBlockedThread, SnapshotError> {
            .success(SnapshotBlockedThread(frame: frame, note: what, idleWorker: false))
        }
        func refuse(_ why: String) -> Result<SnapshotBlockedThread, SnapshotError> {
            .failure(SnapshotError("trap \(n): \(why)"))
        }
        if n < 0 {
            switch n {
            case MachIPC.Trap.machMsg, MachIPC.Trap.machMsgOverwrite, MachIPC.Trap.machMsg2:
                let options = frame.x[1]
                let inReceive = spaces.contains { s in s.snapshotReceiveWaiters(contains: t) }
                if !inReceive {
                    guard spaces.contains(where: { $0.snapshotPendingSend(of: t) }) else {
                        return refuse("mach_msg send blocked without its message")
                    }
                    if options & MachMsgOption.rcvMsg != 0 {
                        frame.x[1] = options & ~MachMsgOption.sendMsg
                        return .success(SnapshotBlockedThread(frame: frame, note: "mach_msg send queued, receive restarts",
                                                              idleWorker: false, queuedSend: true))
                    }
                    frame.x[0] = 0
                    return .success(SnapshotBlockedThread(frame: frame, note: "mach_msg send queued", idleWorker: false,
                                                          queuedSend: true, completed: true))
                }
                if options & MachMsgOption.sendMsg != 0 {
                    frame.x[1] = options & ~MachMsgOption.sendMsg
                    return plain("mach_msg receive (send done)")
                }
                return plain("mach_msg receive")
            case DarwinKernel.Mach.semaphoreWait, DarwinKernel.Mach.semaphoreTimedwait:
                return plain("semaphore_wait")
            case DarwinKernel.Mach.semaphoreWaitSignal:
                frame.x[16] = UInt64(bitPattern: Int64(DarwinKernel.Mach.semaphoreWait))
                return plain("semaphore_wait_signal (signal done)")
            case DarwinKernel.Mach.semaphoreTimedwaitSignal:
                frame.x[16] = UInt64(bitPattern: Int64(DarwinKernel.Mach.semaphoreTimedwait))
                frame.x[1] = frame.x[2]
                frame.x[2] = frame.x[3]
                return plain("semaphore_timedwait_signal (signal done)")
            case DarwinKernel.Mach.waitUntil:
                return plain("mach_wait_until")
            case DarwinKernel.Mach.threadSwitch:
                return plain("thread_switch")
            default:
                return refuse("Mach trap without a restart rule")
            }
        }
        let bsd = DarwinKernel.BSD.self, b2 = DarwinKernel.BSD2.self
        switch n {
        case 3, 396, 120, 411, 27, 401, 29, 403:
            return plain("read/recv")
        case 7, 400, 173, 416:
            return plain("wait4/waitid")
        case 30, 404, 98, 409:
            return plain("accept/connect")
        case 93, 407, 394, 395, 230, 417:
            return plain("select/poll")
        case 131, 271, 420:
            return plain("flock/sem_wait")
        case bsd.fcntl, 406:
            return plain("fcntl")
        case b2.ulockWait, b2.ulockWait2:
            return plain("ulock_wait")
        case b2.semwaitSignal, b2.semwaitSignalNocancel:
            frame.x[argBase + 1] = 0
            return plain("__semwait_signal")
        case 297, 298, 300, 301, 305, 306, 307:
            return plain("psynch wait")
        case b2.kevent, b2.kevent64, b2.keventQos, b2.keventId:
            if k.snapshotSyncKnote(waitedOnBy: t) != nil {
                return plain("kevent workloop sync wait (knote re-made)")
            }
            frame.x[argBase + 2] = 0
            return plain("kevent scan (changes applied)")
        case b2.workqKernreturn:
            guard let w = t.worker, w.phase == .idle, k.workqueue.idle.contains(where: { $0 === t }) else {
                return refuse("workq_kernreturn blocked outside an idle park")
            }
            return .success(SnapshotBlockedThread(frame: frame, note: "workq idle park", idleWorker: true))
        case b2.sigsuspend, b2.sigsuspendNocancel:
            guard let saved = t.snapshotSigsuspendSavedMask else { return refuse("sigsuspend without its saved mask") }
            return .success(SnapshotBlockedThread(frame: frame, note: "sigsuspend", idleWorker: false, savedSignalMask: saved))
        case 4, 397, 121, 412, 28, 402, 133, 413:
            return refuse("write/send blocked (partial transfer unknown)")
        default:
            return refuse("BSD call without a restart rule")
        }
    }
}

extension DarwinSystem {
    func snapshotSpaces() -> [MachIPC] {
        processes.values.compactMap { $0.kernel?.machIPC as? MachIPC }
    }
}

extension MachIPC {
    func snapshotReceiveWaiters(contains t: ThreadContext) -> Bool {
        for e in entries where e.inUse {
            if let p = e.port, e.bits & MachPortType.receive != 0, p.receiveWaiters.contains(t) { return true }
            if let s = e.set, s.waiters.contains(t) { return true }
        }
        return false
    }
}

extension MachIPC {
    func snapshotPendingSend(of t: ThreadContext) -> Bool {
        let key = ObjectIdentifier(t)
        return entries.contains { e in
            e.inUse && (e.port?.snapshotPendingSends.contains { $0.context == key } ?? false)
        }
    }
}

extension DarwinKernel {
    func snapshotSyncKnote(waitedOnBy t: ThreadContext) -> UInt64? {
        for kq in kevents.workloops.values {
            for kn in kq.knotes where kn.syncWaiters.contains(t) { return kn.ident }
        }
        return nil
    }
}
