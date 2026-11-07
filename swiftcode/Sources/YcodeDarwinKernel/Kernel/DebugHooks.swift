import Foundation
import YcodeDarwinABI

public struct KernelDebugStop: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case breakpoint(immediate: UInt16)
        case step
        case watchpoint(address: UInt64, write: Bool)
        case fault(signal: Int32, description: String)
    }
    public var kind: Kind
    public var pc: UInt64
}

public enum KernelDebugDecision: Equatable, Sendable {
    case stop
    case retry
    case decline
}

public protocol KernelDebugger: AnyObject {
    func kernelDebugException(_ kernel: DarwinKernel, thread: ThreadContext, stop: KernelDebugStop) -> KernelDebugDecision
}

extension DarwinKernel {

    func debugException(_ frame: inout TrapFrame) -> Outcome? {
        let syndrome = frame.syndrome
        guard let hook = debugHook else {
            return syndrome.exceptionClass == .softwareStepLowerEL || syndrome.exceptionClass == .watchpointLowerEL ? .resume : nil
        }
        let t = current
        let stop: KernelDebugStop
        switch syndrome.exceptionClass {
        case .brk?:
            stop = KernelDebugStop(kind: .breakpoint(immediate: UInt16(truncatingIfNeeded: frame.esr & 0xFFFF)), pc: frame.elr)
        case .softwareStepLowerEL?:
            stop = KernelDebugStop(kind: .step, pc: frame.elr)
        case .watchpointLowerEL?:
            stop = KernelDebugStop(kind: .watchpoint(address: frame.far, write: frame.esr & (1 << 6) != 0), pc: frame.elr)
        default:
            if t.debugDeliversFault {
                t.debugDeliversFault = false
                return nil
            }
            stop = KernelDebugStop(kind: .fault(signal: Self.faultSignal(frame), description: Self.faultDescription(frame)), pc: frame.elr)
        }
        switch hook.kernelDebugException(self, thread: t, stop: stop) {
        case .decline: return nil
        case .retry: return .resume
        case .stop:
            t.debugStop = stop
            holdAllForDebugger()
            return .resume
        }
    }

    func debuggerImageNotification(_ frame: inout TrapFrame, unloading: Bool, count: Int, addresses: UInt64, paths: UInt64,
                                   _ mem: any KernelGuestMemory) -> Bool {
        guard let notify = try? readU64(allImageInfosAddress + UInt64(DyldAllImageInfos.Offset.notification), mem), notify != 0 else {
            return false
        }
        let n = min(count, 1 << 14)
        guard let loads = try? mem.read(va: addresses, count: 8 * n), let names = try? mem.read(va: paths, count: 8 * n) else { return false }
        var entries: [UInt8] = []
        entries.reserveCapacity(24 * n)
        for i in 0..<n {
            entries.appendLE(loads.readLE(UInt64.self, at: 8 * i))
            entries.appendLE(names.readLE(UInt64.self, at: 8 * i))
            entries.appendLE(UInt64(0))
        }
        let array = (frame.spEL0 &- 128 &- UInt64(entries.count)) & ~UInt64(15)
        guard (try? mem.write(va: array, bytes: entries)) != nil else { return false }
        frame.x[0] = unloading ? 1 : 0
        frame.x[1] = UInt64(n)
        frame.x[2] = array
        frame.carry = false
        frame.elr = notify
        return true
    }

    public var debugDyldMainCalled: Bool { lock.withLock { dyldMainCalled } }

    static func faultDescription(_ frame: TrapFrame) -> String {
        let s = frame.syndrome
        let what = s.exceptionClass.map { "\($0)" } ?? "ESR \(hx(s.raw))"
        switch s.exceptionClass {
        case .dataAbortLowerEL?, .instructionAbortLowerEL?:
            return "\(Signal.name(faultSignal(frame))): \(what) at address \(hx(frame.far))"
        default:
            return "\(Signal.name(faultSignal(frame))): \(what)"
        }
    }

    private func holdAllForDebugger() {
        debugAllHeld = true
        for t in threadsByPort.values where t.isAlive {
            t.debugHold = true
            refreshGate(t)
        }
    }

    public func debugAttach(_ debugger: any KernelDebugger) -> Bool {
        lock.withLock {
            guard debugHook == nil, !isTerminating else { return false }
            debugHook = debugger
            for t in threadsByPort.values { t.debugStop = nil }
            holdAllForDebugger()
            return true
        }
    }

    public func debugDetach() {
        lock.withLock {
            debugHook = nil
            debugAllHeld = false
            for t in threadsByPort.values {
                t.debugStop = nil
                t.debugDeliversFault = false
                t.gate.cancelStep()
                if t.debugHold {
                    t.debugHold = false
                    if t.isAlive { refreshGate(t) }
                }
            }
        }
    }

    public func isDebugged(by debugger: any KernelDebugger) -> Bool {
        lock.withLock { debugHook === debugger }
    }

    public func debugStopAll() {
        lock.withLock { holdAllForDebugger() }
    }

    public enum DebugResume: Equatable, Sendable {
        case stay
        case run(deliverSignal: Bool)
        case step
    }

    public func debugResume(_ actions: [UInt64: DebugResume], others: DebugResume) {
        lock.withLock {
            debugAllHeld = false
            for t in threadsByPort.values where t.isAlive {
                let action = actions[t.threadID] ?? others
                t.debugStop = nil
                t.debugDeliversFault = false
                switch action {
                case .stay:
                    t.debugHold = true
                case let .run(deliver):
                    t.debugDeliversFault = deliver
                    t.debugHold = false
                case .step:
                    t.gate.requestStep()
                    t.debugHold = false
                }
                refreshGate(t)
            }
        }
    }

    public func debugRequestFlush() {
        lock.withLock { for t in threadsByPort.values where t.isAlive { t.gate.requestFlush() } }
    }

    public var debugThreads: [ThreadContext] {
        lock.withLock { threadsByPort.values.filter(\.isAlive).sorted { $0.threadID < $1.threadID } }
    }

    public func debugAllStopped() -> Bool {
        lock.withLock {
            isTerminating || threadsByPort.values.allSatisfy { t in
                guard t.isAlive, t.debugHold else { return true }
                guard isStopped(t) else { return false }
                return t.debugStop == nil || t.gate.parked != nil || !t.gate.attached.load(ordering: .acquiring)
            }
        }
    }

    public func debugKickRunning() {
        lock.withLock {
            for t in threadsByPort.values where t.isAlive && t.debugHold && !isStopped(t) { threadHost?.kickThread(t) }
        }
    }

    public func debugRegisters(_ t: ThreadContext) -> TrapFrame? {
        lock.withLock {
            if let (frame, _) = t.gate.parked { return frame }
            if let entry = t.entryFrame { return entry }
            if let start = t.suspendedStart {
                var f = TrapFrame()
                for (i, v) in start.x.prefix(TrapFrame.registerCount).enumerated() { f.x[i] = v }
                f.elr = start.pc
                f.spEL0 = start.sp
                return f
            }
            return nil
        }
    }

    public func debugSetRegisters(_ t: ThreadContext, _ frame: TrapFrame) -> Bool {
        lock.withLock { isStopped(t) && applyThreadState(frame, to: t) != nil }
    }

    public func debugIsParked(_ t: ThreadContext) -> Bool { lock.withLock { t.gate.parked != nil } }

    public func debugStopOf(_ t: ThreadContext) -> KernelDebugStop? { lock.withLock { t.debugStop } }

    public var debugTerminationStatus: Int32? {
        lock.withLock { termination.map { waitStatus(for: $0).status } }
    }

    public func debugLocked<T>(_ body: () throws -> T) rethrows -> T { try lock.withLock(body) }

    public var debugParentPID: Int32 { lock.withLock { processRecord?.ppid ?? 1 } }

    public func debugKill() {
        lock.withLock { postSignal(Signal.sigkill) }
    }
}
