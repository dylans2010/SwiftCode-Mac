import Foundation
import SwiftCodeDarwinABI

extension DarwinKernel.Private {
    public static let threadSuspend: UInt32 = 0x7963_0020
    public static let threadResume: UInt32 = 0x7963_0021
    public static let threadAbort: UInt32 = 0x7963_0022
    public static let threadSetState: UInt32 = 0x7963_0023
    public static let taskSuspend: UInt32 = 0x7963_0024
    public static let taskResume: UInt32 = 0x7963_0025
}

extension DarwinKernel {
    enum ARMThreadState {
        static let unified: UInt32 = 1
        static let thread64: UInt32 = 6
        static let exception64: UInt32 = 7
        static let unifiedCount: UInt32 = 70
        static let thread64Count: UInt32 = 68
        static let exception64Count: UInt32 = 4
    }

    static let threadStateRetry: UInt64 = 0x7963_0000

    func refreshGate(_ t: ThreadContext) {
        if t.suspendCount > 0 || taskSuspendCount > 0 || t.debugHold {
            if !t.gate.isClosed { t.gate.close() }
            threadHost?.kickThread(t)
        } else if t.gate.isClosed {
            t.gate.open()
        }
    }

    func isStopped(_ t: ThreadContext) -> Bool {
        !t.isAlive || isTerminating || !t.gate.attached.load(ordering: .acquiring)
            || t.entryFrame != nil || t.gate.parked != nil
    }

    func waitUntilStopped(_ targets: [(ThreadContext, DarwinKernel)]) {
        let began = GuestThreadGate.now()
        var rounds = 0
        var reported = false
        while !isTerminating {
            let pending = targets.filter { t, k in t.gate.isClosed && !k.isStopped(t) }
            guard let first = pending.first else { return }
            if rounds > 0 { for (t, k) in pending { k.threadHost?.kickThread(t) } }
            rounds += 1
            lock.unlocked { _ = first.0.gate.waitUntilParked(deadline: GuestThreadGate.now() + 1_000_000) }
            if !reported, GuestThreadGate.now() &- began > 2_000_000_000 {
                reported = true
                log("note: thread_suspend: \(pending.count) thread(s) not stopped after 2 s "
                    + pending.map { "\($0.1.pid)/\($0.0.threadID)" }.joined(separator: " ") + "; still waiting")
            }
        }
    }

    func lookupThread(named name: UInt32) -> Result<(ThreadContext, DarwinKernel), KernError> {
        guard let ipc = machIPC as? MachIPC else { return .failure(KernError(MachKern.failure)) }
        return withPorts {
            guard let (port, object) = ipc.kernelObject(named: name) else {
                return .failure(KernError(MachMsgReturn.sendInvalidDest))
            }
            guard case .thread = object else { return .failure(KernError(MachKern.invalidArgument)) }
            guard port.active, let owner = port.task, let k = owner.kernel,
                  let t = k.threadsByPort.values.first(where: { owner.kernelObject(named: $0.portName)?.0 === port }),
                  t.isAlive else {
                return .failure(KernError(UInt32(KernReturn.terminated)))
            }
            return .success((t, k))
        }
    }

    func lookupTaskImage(named name: UInt32) -> Result<DarwinKernel, KernError> {
        guard let ipc = machIPC as? MachIPC else { return .failure(KernError(MachKern.failure)) }
        return withPorts {
            guard let (port, object) = ipc.kernelObject(named: name) else {
                return .failure(KernError(MachMsgReturn.sendInvalidDest))
            }
            guard object == .task || object == .taskRead else { return .failure(KernError(MachKern.invalidArgument)) }
            guard port.active, let task = port.task, !task.isTerminated, let k = task.kernel, !k.isTerminating else {
                return .failure(KernError(MachMsgReturn.sendInvalidDest))
            }
            return .success(k)
        }
    }

    func handleThreadControl(_ number: UInt32, _ frame: inout TrapFrame, _ mem: any KernelGuestMemory) -> Outcome {
        let a = frame.x.prefixArray(4)
        let name = UInt32(truncatingIfNeeded: a[0])
        var call = CallText(tracing)
        func kr(_ value: UInt64, _ extra: String = "") -> Outcome {
            frame.x[0] = value
            frame.carry = false
            trace("trap yc \(hx(number & 0xFFFF)) \(call) -> \(KernReturn.name(value))\(extra)")
            return .resume
        }
        switch number {
        case Private.threadSuspend:
            call.set("thread_suspend(\(hx(name)))")
            switch lookupThread(named: name) {
            case let .failure(e): return kr(UInt64(e.code))
            case let .success((t, k)):
                t.suspendCount += 1
                k.refreshGate(t)
                if t !== current { waitUntilStopped([(t, k)]) }
                return kr(KernReturn.success, " [thread \(k.pid)/\(t.threadID) count \(t.suspendCount)]")
            }

        case Private.threadResume:
            call.set("thread_resume(\(hx(name)))")
            switch lookupThread(named: name) {
            case let .failure(e): return kr(UInt64(e.code))
            case let .success((t, k)):
                guard t.suspendCount > 0 else { return kr(KernReturn.failure, " [not suspended]") }
                t.suspendCount -= 1
                k.refreshGate(t)
                if t.suspendCount == 0, let start = t.suspendedStart {
                    guard let host = k.threadHost, let index = try? host.startThread(start, context: t) else {
                        t.suspendCount = 1
                        return kr(KernReturn.failure, " [cannot start]")
                    }
                    t.vcpuIndex = index
                    t.suspendedStart = nil
                    return kr(KernReturn.success, " [thread \(k.pid)/\(t.threadID) started]")
                }
                return kr(KernReturn.success, " [thread \(k.pid)/\(t.threadID) count \(t.suspendCount)]")
            }

        case Private.threadAbort:
            let safely = a[1] != 0
            call.set("\(safely ? "thread_abort_safely" : "thread_abort")(\(hx(name)))")
            switch lookupThread(named: name) {
            case let .failure(e): return kr(UInt64(e.code))
            case let .success((t, k)):
                let woke = t === current ? false : k.lock.interrupt(t)
                return kr(KernReturn.success, woke ? " [wait interrupted]" : "")
            }

        case Private.threadSetState:
            let flavor = UInt32(truncatingIfNeeded: a[1]), count = UInt32(truncatingIfNeeded: a[3])
            call.set("thread_set_state(\(hx(name)), flavor=\(flavor), state=\(hx(a[2])), count=\(count))")
            switch lookupThread(named: name) {
            case let .failure(e): return kr(UInt64(e.code))
            case let .success((t, k)):
                let parsed = Self.parseThreadState(flavor: flavor, count: count, address: a[2], memory: mem)
                switch parsed {
                case let .failure(e): return kr(UInt64(e.code))
                case .success(nil): return kr(KernReturn.success, " [no effect]")
                case let .success(state?):
                    if t === current {
                        frame.takeUserState(of: state)
                        return kr(KernReturn.success, " [own state, pc \(hx(state.elr))]")
                    }
                    t.suspendCount += 1
                    k.refreshGate(t)
                    waitUntilStopped([(t, k)])
                    let how = k.applyThreadState(state, to: t)
                    t.suspendCount -= 1
                    k.refreshGate(t)
                    guard let how else { return kr(KernReturn.failure, " [thread not running]") }
                    return kr(KernReturn.success, " [thread \(k.pid)/\(t.threadID) \(how)]")
                }
            }

        case Private.taskSuspend:
            call.set("task_suspend(\(hx(name)))")
            switch lookupTaskImage(named: name) {
            case let .failure(e): return kr(UInt64(e.code))
            case let .success(k):
                k.taskSuspendCount += 1
                let threads = k.threadsByPort.values.filter(\.isAlive)
                for t in threads { k.refreshGate(t) }
                waitUntilStopped(threads.filter { $0 !== current }.map { ($0, k) })
                return kr(KernReturn.success, " [pid \(k.pid) count \(k.taskSuspendCount)]")
            }

        case Private.taskResume:
            call.set("task_resume(\(hx(name)))")
            switch lookupTaskImage(named: name) {
            case let .failure(e): return kr(UInt64(e.code))
            case let .success(k):
                guard k.taskSuspendCount > 0 else { return kr(KernReturn.failure, " [not suspended]") }
                k.taskResumed()
                return kr(KernReturn.success, " [pid \(k.pid) count \(k.taskSuspendCount)]")
            }

        default:
            return kr(KernReturn.failure)
        }
    }

    func taskResumed() {
        guard taskSuspendCount > 0 else { return }
        taskSuspendCount -= 1
        guard taskSuspendCount == 0 else { return }
        for t in threadsByPort.values where t.isAlive { refreshGate(t) }
        if mainStartPending {
            mainStartPending = false
            if let p = processRecord {
                if p.state == .stopped { p.state = .running }
                p.image?.resume()
            }
        }
    }

    func startedSuspended() {
        taskSuspendCount += 1
        mainStartPending = true
    }

    func applyThreadState(_ state: TrapFrame, to t: ThreadContext) -> String? {
        if t.gate.modifyParked({ $0.takeUserState(of: state) }) { return "parked thread changed" }
        if t.gate.attached.load(ordering: .acquiring) {
            t.gate.setReplacement(state)
            return "applied at the end of its trap"
        }
        if var start = t.suspendedStart {
            start.x = Array(state.x)
            start.pc = state.elr
            start.sp = state.spEL0
            t.suspendedStart = start
            return "start state changed"
        }
        return nil
    }

    static func parseThreadState(flavor: UInt32, count: UInt32, address: UInt64,
                                 memory: any KernelGuestMemory) -> Result<TrapFrame?, KernError> {
        var skip = 0
        switch flavor {
        case ARMThreadState.unified:
            guard count == ARMThreadState.unifiedCount else { return .failure(KernError(MachKern.invalidArgument)) }
            skip = 8
        case ARMThreadState.thread64:
            guard count == ARMThreadState.thread64Count else { return .failure(KernError(MachKern.invalidArgument)) }
        case ARMThreadState.exception64:
            guard count == ARMThreadState.exception64Count else { return .failure(KernError(MachKern.invalidArgument)) }
            return .success(nil)
        default:
            return .failure(KernError(MachKern.invalidArgument))
        }
        guard let bytes = try? memory.read(va: address, count: Int(count) * 4) else {
            return .failure(KernError(MachKern.invalidAddress))
        }
        if skip > 0 {
            guard bytes.readLE(UInt32.self, at: 0) == ARMThreadState.thread64,
                  bytes.readLE(UInt32.self, at: 4) == ARMThreadState.thread64Count else {
                return .failure(KernError(MachKern.invalidArgument))
            }
        }
        var f = TrapFrame()
        for r in 0..<29 { f.x[r] = bytes.readLE(UInt64.self, at: skip + 8 * r) }
        f.x[29] = bytes.readLE(UInt64.self, at: skip + 8 * 29)
        f.x[30] = bytes.readLE(UInt64.self, at: skip + 8 * 30)
        f.spEL0 = bytes.readLE(UInt64.self, at: skip + 8 * 31)
        f.elr = bytes.readLE(UInt64.self, at: skip + 8 * 32)
        f.spsr = UInt64(bytes.readLE(UInt32.self, at: skip + 8 * 33))
        return .success(f)
    }
}
