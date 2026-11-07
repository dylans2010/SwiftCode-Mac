import Foundation
import Synchronization
import YcodeDarwinABI

extension DarwinKernel {
    nonisolated(unsafe) public static var ipcFastTrapsEnabled = getenv("SWIFTCODE_IPC_FAST").map { String(cString: $0) != "0" } ?? true

    nonisolated(unsafe) public static var fastPathsWhileTracing = DarwinSystem.splitForTests

    public static func isIPCFastTrap(_ number: Int32) -> Bool {
        switch number {
        case -47, -31, -32, 368, 374, 375: true
        default: portRoutineFastEnabled && (isPortRoutineFastTrap(number) || routineFastLocks(number) != nil)
        }
    }

    nonisolated(unsafe) public static var portRoutineFastEnabled =
        getenv("SWIFTCODE_PORT_ROUTINES_FAST").map { String(cString: $0) != "0" } ?? true

    @inline(__always) static func isPortRoutineFastTrap(_ number: Int32) -> Bool {
        switch number {
        case -16, -18, -19, -20, -21, -22, -23, -24, -25, -26, -27, -28, -29, -40, -41, -42, -50, -70, -72, -76, -77: true
        default: false
        }
    }

    enum RoutineLocks { case ports, eventsAndPorts }
    @inline(__always) static func routineFastLocks(_ number: Int32) -> RoutineLocks? {
        switch UInt32(bitPattern: number) {
        case MachIPC.Routine.makeMemoryEntry, MachIPC.Routine.vmMapObject, MachIPC.Routine.vmRemap,
             MachIPC.Routine.portGetContext, MachIPC.Routine.portSetContext: .ports
        case MachIPC.Routine.threadGetState, MachIPC.Routine.taskThreads: .eventsAndPorts
        default: nil
        }
    }

    public static let portRoutineFastServed = Atomic<UInt64>(0)

    public static let ipcFastServed = Atomic<UInt64>(0)
    public static let ipcFastDeclined = Atomic<UInt64>(0)
    public static let ipcFastDeclinedDescriptors = Atomic<UInt64>(0)
    public static let ipcFastDeclinedCall = Atomic<UInt64>(0)
    public static let ipcFastDeclinedKernelObject = Atomic<UInt64>(0)

    static let debugDescriptorCandidates = getenv("SWIFTCODE_DEBUG_DESCRIPTOR_CANDIDATES").map { String(cString: $0) == "1" } ?? false
    static let descriptorDeclines = Mutex<[String: (declined: UInt64, withCandidate: UInt64)]>([:])

    private func noteDescriptorDecline(_ events: KernelLock) {
        let candidate = events.withLock { () -> Bool in
            allKQueues.contains { kq in
                kq.descriptorKnotes > 0 && kq.knotes.contains {
                    EVFilter.isReadiness($0.filter) && !$0.dropped && $0.active && !$0.suppressed
                        && ($0.enabled || $0.syntheticDelete)
                }
            }
        }
        let name = executableHostPath.map { String($0.split(separator: "/").last ?? "?") } ?? "pid \(pid)"
        Self.descriptorDeclines.withLock {
            var e = $0[name] ?? (0, 0)
            e.declined &+= 1
            if candidate { e.withCandidate &+= 1 }
            $0[name] = e
        }
    }

    static var descriptorDeclineReport: String {
        guard debugDescriptorCandidates else { return "" }
        return "descriptor-knote declines by program (declined/with a reportable descriptor knote): "
            + descriptorDeclines.withLock { $0 }.sorted { $0.value.declined > $1.value.declined }.prefix(20)
            .map { "\($0.key) \($0.value.declined)/\($0.value.withCandidate)" }.joined(separator: ", ")
    }

    static let fastKEventFilters: Set<Int16> = [EVFilter.machport, EVFilter.workloop, EVFilter.user, EVFilter.timer]

    public var hasIPCFastPaths: Bool { eventLock != nil && Self.ipcFastTrapsEnabled }

    public func handleIPCFast(_ frame: inout TrapFrame, context: ThreadContext, memory: any KernelGuestMemory) -> Outcome? {
        guard let events = eventLock, Self.ipcFastTrapsEnabled, !tracing || Self.fastPathsWhileTracing, frame.trapKind == .svc,
              frame.x.count >= TrapFrame.registerCount, context.kernel === self, !isTerminating,
              let ipc = machIPC as? MachIPC else { return nil }
        let number = Int32(truncatingIfNeeded: frame.x[16])
        guard Self.isIPCFastTrap(number) else { return nil }
        let threadLocks = KernelThreadLocks.current
        guard threadLocks.held.isEmpty, !threadLocks.isFast else { return nil }
        if tracing, Self.isPortRoutineFastTrap(number) || Self.routineFastLocks(number) != nil { return nil }
        if number >= 0, number < 1000, !Self.descriptorEscalation, descriptorKnoteCount.load(ordering: .relaxed) > 0 {
            Self.ipcFastDeclined.wrappingAdd(1, ordering: .relaxed)
            Self.ipcFastDeclinedDescriptors.wrappingAdd(1, ordering: .relaxed)
            if Self.debugDescriptorCandidates { noteDescriptorDecline(events) }
            return nil
        }
        let generation = memory.tlbGeneration
        let profile = lock.trapProfile
        let start = profile != nil ? KernelClock.now() : 0
        var outcome: Outcome?
        defer {
            if let profile, outcome != nil {
                profile.noteHandler(TrapProfile.filtered(Int64(number), kernel: self), KernelClock.now() &- start)
            }
        }
        lock.withFastPath(context: context) {
            guard !isTerminating else { return }
            context.entryFrame = frame
            defer { context.entryFrame = nil }
            if let locks = Self.routineFastLocks(number) {
                if locks == .eventsAndPorts {
                    events.withLock(context: context) {
                        outcome = ipc.handleFastPortRoutine(Int(number), &frame, context: context, memory: memory)
                    }
                } else {
                    outcome = ipc.handleFastPortRoutine(Int(number), &frame, context: context, memory: memory)
                }
                Self.portRoutineFastServed.wrappingAdd(1, ordering: .relaxed)
                return
            }
            if number < 0, Self.isPortRoutineFastTrap(number) {
                outcome = ipc.handleFastPortRoutine(Int(number), &frame, context: context, memory: memory)
                Self.portRoutineFastServed.wrappingAdd(1, ordering: .relaxed)
                return
            }
            if number < 0 {
                outcome = ipc.handleFastMachMsg(Int(number), &frame, context: context, memory: memory)
                if outcome == nil { Self.ipcFastDeclinedKernelObject.wrappingAdd(1, ordering: .relaxed) }
                return
            }
            events.withLock(context: context) {
                do {
                    let a = frame.x.prefixArray(8)
                    guard fastEventCallAllowed(number, a, memory) else {
                        Self.ipcFastDeclinedCall.wrappingAdd(1, ordering: .relaxed)
                        return
                    }
                    outcome = handleFastEventCall(Int(number), a, &frame, memory)
                }
            }
        }
        if outcome != nil, memory.tlbGeneration != generation { frame.requestTLBInvalidation(memory.tlbRange(since: generation)) }
        if outcome != nil {
            Self.ipcFastServed.wrappingAdd(1, ordering: .relaxed)
        } else {
            Self.ipcFastDeclined.wrappingAdd(1, ordering: .relaxed)
        }
        precondition(outcome == nil || outcome == .resume, "IPC fast path ended with \(String(describing: outcome))")
        return outcome
    }
}

extension DarwinKernel {
    @inline(__always) func withEvents<T>(_ body: () throws -> T) rethrows -> T {
        guard let events = eventLock else { return try body() }
        return try events.withLock(body)
    }

    @inline(__always) func withPorts<T>(_ body: () throws -> T) rethrows -> T {
        guard let ports = system.mach.portLock else { return try body() }
        return try ports.withLock(body)
    }

    func fastEventCallAllowed(_ n: Int32, _ a: [UInt64], _ mem: any KernelGuestMemory) -> Bool {
        guard Self.descriptorEscalation || descriptorKnoteCount.load(ordering: .relaxed) == 0 else { return false }
        let flags = UInt32(truncatingIfNeeded: a[7])
        switch n {
        case 375:
            guard flags & KEventFlag.workloop != 0, flags & KEventFlag.workq == 0 else { return false }
        case 374:
            guard flags & KEventFlag.workq != 0, flags & KEventFlag.workloop == 0 else { return false }
        case 368:
            switch UInt32(truncatingIfNeeded: a[0]) {
            case WorkqOp.threadReturn, WorkqOp.reqThreads, WorkqOp.reqThreads2, WorkqOp.shouldNarrow:
                return true
            case WorkqOp.keventReturn, WorkqOp.workloopReturn:
                break
            default:
                return false
            }
        default:
            return false
        }
        let count = Int(Int32(truncatingIfNeeded: a[2]))
        guard count > 0 else { return count == 0 }
        guard count <= 64, let changes = try? readKEvents(a[1], count: count, format: .qos, mem) else { return false }
        return changes.allSatisfy { Self.fastKEventFilters.contains($0.filter) }
    }

    func handleFastEventCall(_ n: Int, _ a: [UInt64], _ frame: inout TrapFrame, _ mem: any KernelGuestMemory) -> Outcome {
        var call = CallText(false)
        do {
            let result: BSDResult = n == BSD2.workqKernreturn ? try workqKernreturn(a, &call, mem)
                : .value(try keventCall(n, a, &call, mem))
            switch result {
            case let .value(v):
                frame.x[0] = v
                frame.x[1] = 0
                frame.carry = false
            case let .values(v0, v1):
                frame.x[0] = v0
                frame.x[1] = v1
                frame.carry = false
            case let .restart(start):
                start.apply(to: &frame)
            default:
                preconditionFailure("fast event call \(n) ended with \(result)")
            }
        } catch {
            frame.x[0] = UInt64(UInt32(bitPattern: errno(of: error, default: Errno.EINVAL)))
            frame.x[1] = 0
            frame.carry = true
        }
        return .resume
    }
}

extension MachIPC {
    func handleFastMachMsg(_ n: Int, _ frame: inout TrapFrame, context: ThreadContext,
                           memory: any GuestVirtualMemory) -> TrapOutcome? {
        let threadLocks = KernelThreadLocks.current
        prefetchSend(n, frame, memory, threadLocks)
        threadLocks.deferReceiveWrite = true
        defer {
            threadLocks.deferReceiveWrite = false
            threadLocks.prefetchedSend = nil
        }
        let outcome = lock.withLock(context: context) { () -> TrapOutcome? in
            guard fastSendAllowed(n, frame, memory) else { return nil }
            return handleTrapLocked(x16: Int64(n), frame: &frame, context: context, memory: memory)
        }
        if let w = threadLocks.pendingReceiveWrite {
            threadLocks.pendingReceiveWrite = nil
            if (try? w.memory.write(va: w.va, bytes: w.bytes)) == nil {
                frame.x[0] = UInt64(MachMsgReturn.rcvInvalidData)
            }
        }
        return outcome
    }

    func handleFastPortRoutine(_ n: Int, _ frame: inout TrapFrame, context: ThreadContext,
                               memory: any GuestVirtualMemory) -> TrapOutcome? {
        lock.withLock(context: context) {
            handleTrapLocked(x16: Int64(n), frame: &frame, context: context, memory: memory)
        }
    }

    private func prefetchSend(_ n: Int, _ frame: TrapFrame, _ memory: any GuestVirtualMemory,
                              _ threadLocks: KernelThreadLocks) {
        let options = UInt64(truncatingIfNeeded: frame.x[1])
        guard options & MachMsgOption.sendMsg != 0 else { return }
        let va: UInt64, count: Int
        if n == Trap.machMsg2 {
            guard options & MachMsgOption.msgVector == 0 else { return }
            let bits = UInt32(truncatingIfNeeded: frame.x[2]) & MachMsgBits.user
            let size = Int(UInt32(truncatingIfNeeded: frame.x[2] >> 32))
            let bodyStart = bits & MachMsgBits.complex != 0 ? 28 : 24
            guard size >= bodyStart, size <= Int(MachIPCLimits.maxSendSize) else { return }
            va = frame.x[0] &+ UInt64(bodyStart)
            count = size - bodyStart
        } else {
            let size = Int(UInt32(truncatingIfNeeded: frame.x[2]))
            guard size >= 24, size <= Int(MachIPCLimits.maxSendSize) else { return }
            va = frame.x[0]
            count = size
        }
        if let bytes = try? memory.read(va: va, count: count) { threadLocks.prefetchedSend = (va, bytes) }
    }

    func readSendBytes(_ memory: any GuestVirtualMemory, _ va: UInt64, _ count: Int) -> [UInt8]? {
        if lock.root != nil {
            let threadLocks = KernelThreadLocks.current
            if let p = threadLocks.prefetchedSend, p.va == va, p.bytes.count == count {
                threadLocks.prefetchedSend = nil
                return p.bytes
            }
        }
        return try? memory.read(va: va, count: count)
    }

    func writeReceived(_ memory: any GuestVirtualMemory, _ va: UInt64, _ bytes: [UInt8]) -> Bool {
        if lock.root != nil {
            let threadLocks = KernelThreadLocks.current
            if threadLocks.deferReceiveWrite, threadLocks.pendingReceiveWrite == nil {
                threadLocks.pendingReceiveWrite = (memory, va, bytes)
                return true
            }
        }
        return (try? memory.write(va: va, bytes: bytes)) != nil
    }

    private func fastSendAllowed(_ n: Int, _ frame: TrapFrame, _ memory: any GuestVirtualMemory) -> Bool {
        let options = UInt64(truncatingIfNeeded: frame.x[1])
        guard options & MachMsgOption.sendMsg != 0 else { return true }
        let remote: UInt32
        if n == Trap.machMsg2 {
            remote = UInt32(truncatingIfNeeded: frame.x[3])
        } else {
            guard let bytes = try? memory.read(va: frame.x[0] + 8, count: 4) else { return true }
            remote = bytes.readLE(UInt32.self, at: 0)
        }
        guard MachPortName.isValid(remote), let i = slot(of: remote), let p = entries[i].port else { return true }
        return !p.isKernelObject
    }
}
