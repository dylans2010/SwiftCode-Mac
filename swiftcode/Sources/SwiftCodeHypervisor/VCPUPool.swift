import SwiftCodeDarwinABI

public enum VCPUSlots {
    public static let baseGPA: UInt64 = 0x4100_0000
    public static let slotSize: UInt64 = 0x1_0000
    public static let lowCount = 64
    public static let count = 512
    public static let regionSize: UInt64 = slotSize * UInt64(lowCount)
    public static let highBaseGPA: UInt64 = 0x4600_0000
    public static let highRegionSize: UInt64 = slotSize * UInt64(count - lowCount)
    public static let bootInfoOffset: UInt64 = 0x0000
    public static let frameOffset: UInt64 = 0x4000
    public static let stackOffset: UInt64 = 0x8000

    public static func slotGPA(_ index: Int) -> UInt64 {
        index < lowCount ? baseGPA + UInt64(index) * slotSize : highBaseGPA + UInt64(index - lowCount) * slotSize
    }
    public static func bootInfoGPA(_ index: Int) -> UInt64 { slotGPA(index) + bootInfoOffset }
    public static func frameGPA(_ index: Int) -> UInt64 { slotGPA(index) + frameOffset }
    public static func stackTop(_ index: Int) -> UInt64 { slotGPA(index) + slotSize }

    public static let region = VMLayout.Region(name: "vcpu-slots", va: baseGPA, size: regionSize,
                                               attributes: PageAttributes(access: .el1ReadWrite))
    public static let highRegion = VMLayout.Region(name: "vcpu-slots-2", va: highBaseGPA, size: highRegionSize,
                                                   attributes: PageAttributes(access: .el1ReadWrite))
    public static let regions = [region, highRegion]
}

public struct VCPUStartState: Sendable, Equatable, CustomStringConvertible {
    public var pc: UInt64
    public var sp: UInt64
    public var registers: [UInt64]
    public var tpidrro: UInt64
    public var tpidr: UInt64

    public init(pc: UInt64, sp: UInt64, registers: [UInt64] = [], tpidrro: UInt64 = 0, tpidr: UInt64 = 0) {
        self.pc = pc
        self.sp = sp
        self.registers = registers
        self.tpidrro = tpidrro
        self.tpidr = tpidr
    }

    public var description: String {
        func h(_ v: UInt64) -> String { "0x" + String(v, radix: 16) }
        let used = (registers.lastIndex { $0 != 0 } ?? -1) + 1
        return "pc \(h(pc)) sp \(h(sp)) x0-x\(max(0, used - 1)) [\(registers.prefix(used).map(h).joined(separator: " "))] tpidrro \(h(tpidrro))"
    }
}

#if os(Linux) && arch(arm64)
import CKVM
import Glibc
import Synchronization

public final class VCPUPool: @unchecked Sendable {
    public enum Disposition: Sendable {
        case resume
        case park
        case terminate(status: Int32, message: String)
        case end(message: String)
    }

    public struct Termination: Sendable {
        public enum Kind: Sendable, Equatable {
            case terminated
            case ended
            case stopped
        }
        public var kind: Kind
        public var status: Int32
        public var message: String
        public var vcpuIndex: Int?
    }

    public final class Worker: @unchecked Sendable {
        public let index: Int
        public let vcpu: VCPU
        public var bootInfoGPA: UInt64 { VCPUSlots.bootInfoGPA(index) }
        public var frameGPA: UInt64 { VCPUSlots.frameGPA(index) }
        public internal(set) var context: AnyObject?
        public internal(set) var gate: GuestThreadGate?
        public internal(set) var threadCPUBaseNanoseconds: UInt64 = 0
        public internal(set) var threadCount = 0
        public let lastTrapX16 = Atomic<UInt64>(0)
        public let lastTrapELR = Atomic<UInt64>(0)
        public let inHandler = Atomic<Bool>(false)
        public let handlerSince = Atomic<UInt64>(0)
        public let lastTrapKind = Atomic<UInt64>(0)
        public let lastTrapESR = Atomic<UInt64>(0)
        public let lastExitMs = Atomic<UInt64>(0)
        public let sampleRequested = Atomic<Bool>(false)
        public let samplePC = Atomic<UInt64>(0)
        public let sampleLR = Atomic<UInt64>(0)
        public let sampleFP = Atomic<UInt64>(0)
        public var sampleStack: [UInt64] = []
        public let samplePSTATE = Atomic<UInt64>(0)
        public let sampleELR1 = Atomic<UInt64>(0)
        public let sampleESR1 = Atomic<UInt64>(0)
        public let sampleCount = Atomic<UInt64>(0)
        public let sampleCostNanoseconds = Atomic<UInt64>(0)
        public let hostTID = Atomic<UInt64>(0)

        fileprivate unowned let pool: VCPUPool
        public fileprivate(set) var runNanoseconds: UInt64 = 0
        public fileprivate(set) var handlerNanoseconds: UInt64 = 0
        fileprivate var startRequestedAt: UInt64 = 0
        fileprivate var startKind = StartKind.parked
        fileprivate var pending: VCPUStartState?
        fileprivate var running = false
        fileprivate var started = false
        fileprivate var hostThread = pthread_t()
        fileprivate var joined = false
        fileprivate let wakeup = HostCondition()
        fileprivate var stepping = false
        fileprivate var watchGeneration = 0
        fileprivate var watching = false
        fileprivate var stepAtStart = false

        fileprivate init(index: Int, vcpu: VCPU, pool: VCPUPool) {
            self.index = index
            self.vcpu = vcpu
            self.pool = pool
        }
    }

    public typealias TrapHandler = (Worker, inout TrapFrame) -> Disposition
    public typealias ExitHandler = (Worker, VCPUExit) -> Disposition

    public let vm: VirtualMachine
    public let capacity: Int
    public let bootTemplate: BootInfo
    public let maxExitsPerVCPU: Int
    public var trapHandler: TrapHandler = { _, _ in .terminate(status: 71, message: "no trap handler") }
    public var exitHandler: ExitHandler = { _, exit in .terminate(status: 71, message: "unexpected VM exit: \(exit)") }
    public var shouldStop: () -> Bool = { false }
    public var onEnd: (Termination) -> Void = { _ in }
    public var onFinished: () -> Void = {}
    public var preBootCleanRanges: () -> [(gpa: UInt64, count: Int)] = { [] }
    public var sampleStackReader: ((UInt64) -> [UInt64])?
    public var log: (String) -> Void = { _ in }

    public static let kickSignal = SIGUSR2
    static let resumeFPTouch: UInt64 = 1 << 1
    static let resumeKeepICache: UInt64 = 1 << 2
    public static let hostHasDIC = (ckvm_host_ctr_el0() >> 29) & 1 == 1
    public static let flushKeepsICache = hostHasDIC
        && (getenv("SWIFTCODE_TLB_FLUSH_ICACHE").map { String(cString: $0) != "1" } ?? true)
    public static let tlbFlushResumes = Atomic<UInt64>(0)
    public static let tlbFlushByVAResumes = Atomic<UInt64>(0)
    static let trapFrameCopy = getenv("SWIFTCODE_TRAP_FRAME_COPY").map { String(cString: $0) == "1" } ?? false
    static let shimFPTouch = getenv("SWIFTCODE_SHIM_FP_TOUCH").map { String(cString: $0) != "0" } ?? true

    static let kickOnlyInRun = getenv("SWIFTCODE_KICK_ONLY_IN_RUN").map { String(cString: $0) == "1" } ?? false
    static let debugNoKick = getenv("SWIFTCODE_DEBUG_NO_KICK").map { String(cString: $0) == "1" } ?? false

    private let lock = HostMutex(name: "vCPU pool")
    private let terminated = HostCondition()
    private var workers: [Worker] = []
    private var idle: [Worker] = []
    private var nextIndex = 0
    private var creating = 0
    private var warming: [InFlight] = []
    private var termination: Termination?
    private let ending = Atomic<Bool>(false)
    private var watchRegisters: [HardwareWatchpoint] = []
    private var watchSlotsUsed = 0
    private let watchGeneration = Atomic<Int>(0)
    private var reportStops = false
    private var stopReports: [Int: String] = [:]
    private var activeThreads = 0
    private var liveHostThreads = 0
    private var finished = false
    public private(set) var peakThreads = 0
    public private(set) var hostThreadsCreated = 0

    nonisolated(unsafe) public static var profiling = false

    public struct HostStats: Sendable {
        public var threads = 0
        public var userTicks: UInt64 = 0
        public var systemTicks: UInt64 = 0
        public var guestTicks: UInt64 = 0
        public var minorFaults: UInt64 = 0
        public var majorFaults: UInt64 = 0
        public var cpuNanoseconds: UInt64 = 0
        public var runQueueNanoseconds: UInt64 = 0
        public var runNanoseconds: UInt64 = 0
        public var handlerNanoseconds: UInt64 = 0
        public var userExits: UInt64 = 0
        public var kvmExits: UInt64 = 0
        public var wfxExits: UInt64 = 0
        public var starts: UInt64 = 0
        public var startWaitNanoseconds: UInt64 = 0
        public var maxStartWaitNanoseconds: UInt64 = 0

        public init() {}

        public mutating func add(_ o: HostStats) {
            threads += o.threads
            userTicks &+= o.userTicks; systemTicks &+= o.systemTicks; guestTicks &+= o.guestTicks
            minorFaults &+= o.minorFaults; majorFaults &+= o.majorFaults
            cpuNanoseconds &+= o.cpuNanoseconds; runQueueNanoseconds &+= o.runQueueNanoseconds
            runNanoseconds &+= o.runNanoseconds; handlerNanoseconds &+= o.handlerNanoseconds
            userExits &+= o.userExits; kvmExits &+= o.kvmExits; wfxExits &+= o.wfxExits
            starts &+= o.starts; startWaitNanoseconds &+= o.startWaitNanoseconds
            maxStartWaitNanoseconds = max(maxStartWaitNanoseconds, o.maxStartWaitNanoseconds)
        }
    }
    private var stats = HostStats()
    public var hostStats: HostStats { lock.withLock { stats } }
    public let firstRunNanoseconds = Atomic<UInt64>(0)
    public func kickForPCSamples() -> [Worker] {
        let list = lock.withLock { workers.filter { $0.running && $0.context != nil } }
        var kicked: [Worker] = []
        for w in list where !w.inHandler.load(ordering: .relaxed) {
            w.sampleRequested.store(true, ordering: .relaxed)
            _ = ckvm_kick_thread(UInt(w.hostThread), Self.kickSignal)
            kicked.append(w)
        }
        return kicked
    }

    public func activeWorkers() -> [Worker] {
        lock.withLock { workers.filter { $0.running && $0.context != nil } }
    }

    public func kickForSample(_ w: Worker) {
        w.sampleRequested.store(true, ordering: .relaxed)
        _ = ckvm_kick_thread(UInt(w.hostThread), Self.kickSignal)
    }

    public var hostThreadIDs: [Int] {
        lock.withLock { workers.map { Int($0.hostTID.load(ordering: .relaxed)) }.filter { $0 != 0 } }
    }

    private static let kvmStatNames = ["exits", "wfe_exit_stat", "wfi_exit_stat"]

    private func recordThreadEnd(_ worker: Worker) {
        var t = [UInt64](repeating: 0, count: 8)
        _ = ckvm_task_stats(ckvm_gettid(), &t)
        let k = worker.vcpu.kvmStatistics(Self.kvmStatNames)
        var s = HostStats()
        s.threads = 1
        s.userTicks = t[0]; s.systemTicks = t[1]; s.guestTicks = t[2]
        s.minorFaults = t[3]; s.majorFaults = t[4]
        s.cpuNanoseconds = t[5]; s.runQueueNanoseconds = t[6]
        s.runNanoseconds = worker.runNanoseconds; s.handlerNanoseconds = worker.handlerNanoseconds
        s.userExits = UInt64(worker.vcpu.exitCount); s.kvmExits = k[0]; s.wfxExits = k[1] &+ k[2]
        lock.withLock { stats.add(s) }
    }

    private func noteStarted(_ worker: Worker) {
        guard worker.startRequestedAt != 0 else { return }
        let waited = monotonicNanoseconds() &- worker.startRequestedAt
        worker.startRequestedAt = 0
        Self.startLatency[worker.startKind.rawValue].add(waited)
        lock.withLock {
            stats.starts &+= 1
            stats.startWaitNanoseconds &+= waited
            stats.maxStartWaitNanoseconds = max(stats.maxStartWaitNanoseconds, waited)
        }
    }

    public init(vm: VirtualMachine, bootTemplate: BootInfo, limit: Int = VCPUSlots.count, maxExitsPerVCPU: Int = 0) throws {
        self.vm = vm
        self.capacity = max(1, min(vm.maxVCPUs, limit, VCPUSlots.count))
        vm.vcpuIDLimit = capacity
        self.bootTemplate = bootTemplate
        self.maxExitsPerVCPU = maxExitsPerVCPU
        try kvmCheck(ckvm_kick_install(Self.kickSignal), "sigaction (vCPU kick signal)")
    }

    public var snapshotWorkers: (workers: [Worker], pendingCreations: Int) { lock.withLock { (workers, creating) } }

    public var vcpuCount: Int { lock.withLock { workers.count } }
    public var parkedCount: Int { lock.withLock { idle.count } }
    public var debugState: (contexts: [AnyObject?], creating: Int, warming: Int, nextIndex: Int, active: Int) {
        lock.withLock { (workers.map(\.context), creating, warming.count, nextIndex, activeThreads) }
    }
    public var currentTermination: Termination? { lock.withLock { termination } }
    public var isEnding: Bool { ending.load(ordering: .acquiring) }
    public var isFinished: Bool { lock.withLock { finished || (ending.load(ordering: .relaxed) && liveHostThreads == 0) } }
    public var liveHostThreadCount: Int { lock.withLock { liveHostThreads } }
    public var exitCount: Int { lock.withLock { workers.reduce(0) { $0 + $1.vcpu.exitCount } } }

    public func createWorker() throws -> Worker {
        var warm: [InFlight] = []
        let worker: Worker = try lock.withLock {
            guard !ending.load(ordering: .relaxed) else { throw KVMError("vCPU pool", detail: "the pool has ended") }
            guard nextIndex < capacity else { throw KVMError("vCPU pool", detail: "all \(capacity) vCPUs exist") }
            let worker = try makeWorkerLocked()
            idle.insert(worker, at: 0)
            warm = refillLocked(extra: idle.count)
            return worker
        }
        submit(warm)
        return worker
    }

    private func makeWorkerLocked() throws -> Worker {
        let vcpu = try vm.makeVCPU(id: nextIndex)
        let worker = Worker(index: nextIndex, vcpu: vcpu, pool: self)
        try spawn(worker)
        nextIndex += 1
        workers.append(worker)
        return worker
    }

    @discardableResult
    public func start(_ state: VCPUStartState, context: AnyObject?) throws -> Int? {
        var toSubmit: [InFlight] = []
        let index: Int? = try lock.withLock {
            if ending.load(ordering: .relaxed) { return nil }
            let requestedAt = Self.profiling ? monotonicNanoseconds() : 0
            if !idle.isEmpty {
                let i = idle.indices.min { idle[$0].index < idle[$1].index }!
                let worker = idle.remove(at: i)
                worker.startKind = worker.threadCount > 0 ? .parked : worker.index == 0 ? .main : .warm
                activateLocked(worker, state, context: context)
                toSubmit = refillLocked()
                return worker.index
            }
            if !warming.isEmpty {
                let f = warming.removeFirst()
                f.claim = Claim(state: state, context: context, requestedAt: requestedAt, kind: .claimedWarm)
                (context as? GuestThreadGated)?.gate.attached.store(true, ordering: .releasing)
                f.urgent.store(true, ordering: .relaxed)
                activeThreads += 1
                peakThreads = max(peakThreads, activeThreads)
                toSubmit = refillLocked()
                return f.index
            }
            guard nextIndex < capacity else { return nil }
            guard VCPUCreator.shared != nil else {
                let worker = try makeWorkerLocked()
                worker.startKind = .created
                activateLocked(worker, state, context: context)
                return worker.index
            }
            let f = newCreationLocked()
            f.claim = Claim(state: state, context: context, requestedAt: requestedAt, kind: .created)
            (context as? GuestThreadGated)?.gate.attached.store(true, ordering: .releasing)
            f.urgent.store(true, ordering: .relaxed)
            activeThreads += 1
            peakThreads = max(peakThreads, activeThreads)
            toSubmit = [f] + refillLocked()
            return f.index
        }
        submit(toSubmit)
        return index
    }

    private func activateLocked(_ worker: Worker, _ state: VCPUStartState, context: AnyObject?) {
        attachLocked(worker, context)
        worker.pending = state
        worker.threadCount += 1
        if Self.profiling { worker.startRequestedAt = max(1, monotonicNanoseconds()) }
        activeThreads += 1
        peakThreads = max(peakThreads, activeThreads)
        worker.wakeup.signal()
    }

    private func attachLocked(_ worker: Worker, _ context: AnyObject?) {
        worker.context = context
        worker.gate = (context as? GuestThreadGated)?.gate
        worker.gate?.attached.store(true, ordering: .releasing)
    }

    private func detachLocked(_ worker: Worker) {
        worker.gate?.attached.store(false, ordering: .releasing)
        worker.gate = nil
        worker.context = nil
    }

    public func kickThread(context: AnyObject) {
        lock.withLock {
            guard !ending.load(ordering: .relaxed),
                  let w = workers.first(where: { $0.context === context }), w.running else { return }
            w.vcpu.setImmediateExit(true)
            if !w.inHandler.load(ordering: .relaxed), !Self.debugNoKick, pthread_equal(w.hostThread, pthread_self()) == 0 {
                _ = ckvm_kick_thread(UInt(w.hostThread), Self.kickSignal)
            }
        }
    }

    public var hasRoom: Bool {
        lock.withLock { !ending.load(ordering: .relaxed) && (!idle.isEmpty || !warming.isEmpty || nextIndex < capacity) }
    }

    public enum StartKind: Int, Sendable, CaseIterable {
        case parked
        case warm
        case claimedWarm
        case created
        case main
    }

    public static let startLatency: [LatencyHistogram] = StartKind.allCases.map { LatencyHistogram("start.\($0)") }
    public static let creationPhases: [LatencyHistogram] = ["queue", "create_vcpu", "vcpu_init", "pthread"].map { LatencyHistogram("creation.\($0)") }

    final class Claim {
        let state: VCPUStartState
        let context: AnyObject?
        let requestedAt: UInt64
        let kind: StartKind
        init(state: VCPUStartState, context: AnyObject?, requestedAt: UInt64, kind: StartKind) {
            self.state = state
            self.context = context
            self.requestedAt = requestedAt
            self.kind = kind
        }
    }

    final class InFlight: @unchecked Sendable {
        let index: Int
        var claim: Claim?
        var queuedAt: UInt64 = 0
        let urgent = Atomic<Bool>(false)
        init(index: Int) { self.index = index }
    }

    public static let warmTarget = getenv("SWIFTCODE_VCPU_WARM").flatMap { Int(String(cString: $0)) }.map { max(0, min($0, 16)) } ?? 0

    private func newCreationLocked() -> InFlight {
        let f = InFlight(index: nextIndex)
        nextIndex += 1
        creating += 1
        liveHostThreads += 1
        return f
    }

    private func refillLocked(extra: Int = 0) -> [InFlight] {
        guard Self.warmTarget > 0, VCPUCreator.shared != nil, !ending.load(ordering: .relaxed) else { return [] }
        var out: [InFlight] = []
        while idle.count + warming.count < Self.warmTarget + extra, nextIndex < capacity {
            let f = newCreationLocked()
            warming.append(f)
            out.append(f)
        }
        return out
    }

    private func submit(_ creations: [InFlight]) {
        guard !creations.isEmpty, let creator = VCPUCreator.shared else { return }
        for f in creations {
            if Self.profiling { f.queuedAt = monotonicNanoseconds() }
            creator.submit(self, f)
        }
    }

    public static let deferredCreations = Atomic<UInt64>(0)
    public static let deferredCreationNanoseconds = Atomic<UInt64>(0)
    public static let deferredCreateVCPUNanoseconds = Atomic<UInt64>(0)
    public static let deferredInitNanoseconds = Atomic<UInt64>(0)
    public static let deferredThreadNanoseconds = Atomic<UInt64>(0)

    fileprivate func createReserved(_ f: InFlight) {
        var failure: Error?
        var worker: Worker?
        if !ending.load(ordering: .acquiring) {
            let began = monotonicNanoseconds()
            if Self.profiling, f.queuedAt != 0 { Self.creationPhases[0].add(began &- f.queuedAt) }
            do {
                let created = Worker(index: f.index, vcpu: try vm.makeVCPU(id: f.index), pool: self)
                let threadBegan = monotonicNanoseconds()
                try startHostThread(created)
                Self.deferredThreadNanoseconds.wrappingAdd(monotonicNanoseconds() &- threadBegan, ordering: .relaxed)
                if Self.profiling { Self.creationPhases[3].add(monotonicNanoseconds() &- threadBegan) }
                worker = created
            } catch {
                failure = error
            }
            Self.deferredCreations.wrappingAdd(1, ordering: .relaxed)
            Self.deferredCreationNanoseconds.wrappingAdd(monotonicNanoseconds() &- began, ordering: .relaxed)
        }
        lock.lock()
        creating -= 1
        if let i = warming.firstIndex(where: { $0 === f }) { warming.remove(at: i) }
        let claim = f.claim
        if let worker {
            workers.append(worker)
            hostThreadsCreated += 1
            var parkedNow = false
            if ending.load(ordering: .relaxed) {
                if let claim {
                    activeThreads -= 1
                    (claim.context as? GuestThreadGated)?.gate.attached.store(false, ordering: .releasing)
                }
            } else if let claim {
                attachLocked(worker, claim.context)
                worker.pending = claim.state
                worker.threadCount = 1
                worker.startRequestedAt = claim.requestedAt
                worker.startKind = claim.kind
            } else {
                idle.append(worker)
                parkedNow = true
            }
            worker.wakeup.signal()
            let parked = parkedNow ? parkedHandler : nil
            lock.unlock()
            parked?()
            return
        }
        lock.unlock()
        if let failure {
            log("vCPU \(f.index): cannot create: \(failure)")
            if claim != nil {
                terminate(status: 1, message: "vCPU \(f.index): cannot create: \(failure)", vcpuIndex: f.index)
            }
        }
        lock.lock()
        if let claim {
            activeThreads -= 1
            (claim.context as? GuestThreadGated)?.gate.attached.store(false, ordering: .releasing)
        }
        hostThreadReturnedLocked()
    }

    public var onParked: (() -> Void)? {
        get { lock.withLock { parkedHandler } }
        set { lock.withLock { parkedHandler = newValue } }
    }
    private var parkedHandler: (() -> Void)?

    static let debugStackGuardMB = getenv("SWIFTCODE_DEBUG_STACK_GUARD_MB").flatMap { Int(String(cString: $0)) }.flatMap { $0 > 0 ? $0 : nil }

    private func spawn(_ worker: Worker) throws {
        try startHostThread(worker)
        liveHostThreads += 1
        hostThreadsCreated += 1
    }

    private func startHostThread(_ worker: Worker) throws {
        var attributes = pthread_attr_t()
        pthread_attr_init(&attributes)
        defer { pthread_attr_destroy(&attributes) }
        pthread_attr_setstacksize(&attributes, 16 << 20)
        if let mb = Self.debugStackGuardMB { pthread_attr_setguardsize(&attributes, mb << 20) }
        let box = Unmanaged.passRetained(worker).toOpaque()
        let result = pthread_create(&worker.hostThread, &attributes, { argument in
            let worker = Unmanaged<VCPUPool.Worker>.fromOpaque(argument!).takeRetainedValue()
            worker.pool.threadMain(worker)
            return nil
        }, box)
        if result != 0 {
            Unmanaged<Worker>.fromOpaque(box).release()
            throw KVMError("pthread_create (vCPU \(worker.index))", errno: result)
        }
    }

    private func hostThreadReturnedLocked() {
        liveHostThreads -= 1
        let last = liveHostThreads == 0
        if last { finished = true }
        terminated.broadcast()
        lock.unlock()
        if last { onFinished() }
    }

    private enum RunEnd { case parked, ended }

    private func threadMain(_ worker: Worker) {
        worker.hostTID.store(UInt64(ckvm_gettid()), ordering: .relaxed)
        PostTrapWork.setCurrentVM(vm)
        _ = ckvm_hostprof_thread_start()
        if Self.kickOnlyInRun {
            let r = ckvm_kick_mask_outside_run(worker.vcpu.fd, Self.kickSignal)
            if r != 0 { var t = "swiftcode-simd: KVM_SET_SIGNAL_MASK failed (\(r))\n"; _ = t.withUTF8 { write(2, $0.baseAddress, $0.count) } }
        }
        while true {
            lock.lock()
            while worker.pending == nil && !ending.load(ordering: .relaxed) { worker.wakeup.wait(lock) }
            if ending.load(ordering: .relaxed) {
                if worker.pending != nil {
                    worker.pending = nil
                    activeThreads -= 1
                    detachLocked(worker)
                }
                lock.unlock()
                break
            }
            var state = worker.pending!
            worker.pending = nil
            worker.running = true
            lock.unlock()
            worker.threadCPUBaseNanoseconds = hostThreadCPUNanoseconds()
            if Self.profiling { noteStarted(worker) }

            var end = RunEnd.ended
            do {
                let fresh = !worker.started
                if let gate = worker.gate, gate.isClosed { state = parkAtStart(worker, gate, state, fresh: fresh) }
                try begin(worker, state)
                end = try runLoop(worker, slotFrameCurrent: !fresh)
            } catch {
                terminate(status: 1, message: "vCPU \(worker.index): \(error)", vcpuIndex: worker.index)
            }

            lock.lock()
            worker.running = false
            detachLocked(worker)
            activeThreads -= 1
            if case .parked = end, !ending.load(ordering: .relaxed) {
                idle.append(worker)
                let parked = parkedHandler
                lock.unlock()
                parked?()
                continue
            }
            lock.unlock()
            break
        }
        if Self.profiling { recordThreadEnd(worker) }
        lock.lock()
        worker.context = nil
        hostThreadReturnedLocked()
    }

    nonisolated(unsafe) public static var guestCPUCount = 1

    private func cpuNumber(_ worker: Worker, _ state: VCPUStartState) -> UInt64 {
        state.tpidr != 0 ? state.tpidr : UInt64(worker.index % max(1, Self.guestCPUCount))
    }

    private func begin(_ worker: Worker, _ state: VCPUStartState) throws {
        if worker.stepping || worker.stepAtStart {
            worker.stepping = false
            worker.stepAtStart = false
            try writeMDSCR(worker)
        }
        if !worker.started {
            worker.started = true
            var info = bootTemplate
            info.el0EntryPC = state.pc
            info.el0InitialSP = state.sp
            info.trapFrameAddress = worker.frameGPA
            info.tpidrroEL0 = state.tpidrro
            info.tpidrEL0 = cpuNumber(worker, state)
            if state.registers.dropFirst(8).contains(where: { $0 != 0 }) {
                throw KVMError("vCPU \(worker.index) start", detail: "a fresh vCPU can start only with x0-x7 set: \(state)")
            }
            info.el0Registers = Array(state.registers.prefix(8))
            info.el1StackTop = VCPUSlots.stackTop(worker.index)
            try vm.zero(gpa: worker.frameGPA, count: TrapFrame.byteCount)
            try vm.write(gpa: worker.bootInfoGPA, bytes: info.encoded())
            try vm.cleanDataCache(gpa: worker.bootInfoGPA, count: Int(VCPUSlots.stackOffset))
            for range in preBootCleanRanges() { try vm.cleanDataCache(gpa: range.gpa, count: range.count) }
            try worker.vcpu.set(.pc, VMLayout.shimEntryGPA)
            try worker.vcpu.set(.pstate, VMLayout.el1BootPSTATE)
            try worker.vcpu.set(.x(0), worker.bootInfoGPA)
            if let gate = worker.gate, gate.takeStepRequest() {
                worker.stepping = true
                worker.stepAtStart = true
                try writeMDSCR(worker)
            }
            log("vCPU \(worker.index): first thread, \(state)")
        } else {
            var frame = TrapFrame()
            for (i, value) in state.registers.prefix(TrapFrame.registerCount).enumerated() { frame.x[i] = value }
            frame.spEL0 = state.sp
            frame.elr = state.pc
            frame.spsr = VMLayout.el0InitialSPSR
            frame.tpidrro = state.tpidrro
            frame.tpidr = cpuNumber(worker, state)
            frame.flushTLB = true
            if Self.flushKeepsICache { frame.resumeFlags |= Self.resumeKeepICache }
            if Self.shimFPTouch { frame.resumeFlags |= Self.resumeFPTouch }
            try vm.write(gpa: worker.frameGPA, bytes: frame.encoded())
            var zero: UInt32 = 0
            let fpcr = ckvm_set_one_reg_bytes(worker.vcpu.fd, ckvm_reg_fpcr(), &zero)
            let fpsr = ckvm_set_one_reg_bytes(worker.vcpu.fd, ckvm_reg_fpsr(), &zero)
            if fpcr < 0 || fpsr < 0 { throw KVMError("KVM_SET_ONE_REG FPCR/FPSR", errno: -min(fpcr, fpsr)) }
            log("vCPU \(worker.index): thread #\(worker.threadCount), \(state)")
        }
    }

    private func runLoop(_ worker: Worker, slotFrameCurrent startsInSlot: Bool) throws -> RunEnd {
        let vcpu = worker.vcpu
        let gate = worker.gate
        var slotFrameCurrent = startsInSlot
        while true {
            if ending.load(ordering: .acquiring) {
                acknowledgeStop(worker, .interrupted)
                return .ended
            }
            if let gate, gate.needsAttention { try gateBeforeEntry(worker, gate, slotFrameCurrent: slotFrameCurrent) }
            if worker.watchGeneration != watchGeneration.load(ordering: .relaxed) { try loadWatchpoints(worker) }
            if shouldStop() {
                endPool(Termination(kind: .stopped, status: 0, message: "stopped", vcpuIndex: nil))
                return .ended
            }
            if maxExitsPerVCPU > 0, vcpu.exitCount >= maxExitsPerVCPU {
                terminate(status: 71, message: "vCPU \(worker.index) exceeded \(maxExitsPerVCPU) VM exits", vcpuIndex: worker.index)
                return .ended
            }
            let exit: VCPUExit
            if Self.profiling {
                let began = monotonicNanoseconds()
                if firstRunNanoseconds.load(ordering: .relaxed) == 0 {
                    _ = firstRunNanoseconds.compareExchange(expected: 0, desired: began, ordering: .relaxed)
                }
                exit = try vcpu.runOnce()
                worker.runNanoseconds &+= monotonicNanoseconds() &- began
            } else {
                exit = try vcpu.runOnce()
            }
            slotFrameCurrent = false
            let exitMs = monotonicMillisecondsCoarse()
            worker.lastExitMs.store(exitMs, ordering: .relaxed)
            if case .interrupted = exit {
                if !ending.load(ordering: .acquiring) { vcpu.setImmediateExit(false) }
                if worker.sampleRequested.exchange(false, ordering: .relaxed) {
                    let sampleBegan = monotonicNanoseconds()
                    worker.samplePC.store((try? vcpu.get(.pc)) ?? 0, ordering: .relaxed)
                    worker.sampleLR.store((try? vcpu.get(.x(30))) ?? 0, ordering: .relaxed)
                    worker.sampleFP.store((try? vcpu.get(.x(29))) ?? 0, ordering: .relaxed)
                    worker.samplePSTATE.store((try? vcpu.get(.pstate)) ?? 0, ordering: .relaxed)
                    worker.sampleELR1.store((try? vcpu.get(.elrEL1)) ?? 0, ordering: .relaxed)
                    worker.sampleESR1.store((try? vcpu.get(SystemRegister.esrEL1)) ?? 0, ordering: .relaxed)
                    if let reader = sampleStackReader {
                        worker.sampleStack = reader(worker.sampleFP.load(ordering: .relaxed))
                    }
                    worker.sampleCostNanoseconds.store(monotonicNanoseconds() &- sampleBegan, ordering: .relaxed)
                    worker.sampleCount.wrappingAdd(1, ordering: .releasing)
                }
                continue
            }
            if ending.load(ordering: .acquiring) {
                acknowledgeStop(worker, exit)
                return .ended
            }
            let disposition: Disposition
            let doorbellFrame: UInt64?
            switch exit {
            case let .mmio(.write, address, frameAddress, 8) where address == VMLayout.doorbellGPA && frameAddress == worker.frameGPA:
                doorbellFrame = frameAddress
            case let .hypercall(function, flags)
                where function == UInt64(VirtualMachine.hvcDoorbellFunction) && flags & 1 == 0 && bootTemplate.doorbellAddress == 0:
                doorbellFrame = worker.frameGPA
            default:
                doorbellFrame = nil
            }
            switch doorbellFrame {
            case let frameAddress?:
                let framePointer = Self.trapFrameCopy ? nil : try vm.writableHostPointer(gpa: frameAddress, count: TrapFrame.byteCount)
                if TrapFrame.peelLevel == 1, let p = framePointer,
                   TrapFrame.peels(at: 1, x16: p.load(fromByteOffset: TrapFrame.Offset.x0 + 8 * 16, as: UInt64.self)),
                   p.load(fromByteOffset: TrapFrame.Offset.kind, as: UInt64.self) == TrapFrame.Kind.svc.rawValue {
                    p.storeBytes(of: UInt64(1), toByteOffset: TrapFrame.Offset.x0, as: UInt64.self)
                    let spsr = p.load(fromByteOffset: TrapFrame.Offset.spsr, as: UInt64.self)
                    p.storeBytes(of: spsr & ~(UInt64(1) << 29), toByteOffset: TrapFrame.Offset.spsr, as: UInt64.self)
                    p.storeBytes(of: Self.shimFPTouch ? Self.resumeFPTouch : 0, toByteOffset: TrapFrame.Offset.resumeFlags, as: UInt64.self)
                    continue
                }
                var frame = try framePointer.map { TrapFrame(decodingFrameAt: $0) }
                    ?? TrapFrame(decoding: vm.read(gpa: frameAddress, count: TrapFrame.byteCount))
                if worker.stepAtStart, frame.syndrome.exceptionClass == .softwareStepLowerEL {
                    worker.stepAtStart = false
                    frame.spsr |= Self.spsrSS
                    if framePointer != nil {
                        frame.encode(into: try vm.writableHostPointer(gpa: frameAddress, count: TrapFrame.byteCount))
                    } else { try vm.write(gpa: frameAddress, bytes: frame.encoded()) }
                    slotFrameCurrent = true
                    continue
                }
                if worker.stepping, frame.syndrome.exceptionClass == .softwareStepLowerEL { try endStep(worker, &frame) }
                if let gate, gate.isClosed { _ = gate.park(frame, at: .trapEntry) }
                worker.lastTrapX16.store(frame.x[16], ordering: .relaxed)
                worker.lastTrapELR.store(frame.elr, ordering: .relaxed)
                worker.lastTrapKind.store(UInt64(frame.kind), ordering: .relaxed)
                worker.lastTrapESR.store(frame.esr, ordering: .relaxed)
                worker.handlerSince.store(exitMs, ordering: .relaxed)
                worker.inHandler.store(true, ordering: .relaxed)
                if TrapFrame.peelLevel == 2, frame.kind == TrapFrame.Kind.svc.rawValue, TrapFrame.peels(at: 2, x16: frame.x[16]) {
                    frame.answerPeeled()
                    disposition = .resume
                } else if Self.profiling {
                    let began = monotonicNanoseconds()
                    disposition = trapHandler(worker, &frame)
                    worker.handlerNanoseconds &+= monotonicNanoseconds() &- began
                } else {
                    disposition = trapHandler(worker, &frame)
                }
                worker.inHandler.store(false, ordering: .relaxed)
                PostTrapWork.drain()
                if case .resume = disposition {
                    if Self.shimFPTouch { frame.resumeFlags |= Self.resumeFPTouch }
                    if frame.flushTLB {
                        Self.tlbFlushResumes.wrappingAdd(1, ordering: .relaxed)
                        if frame.resumeFlags & TrapFrame.ResumeFlag.byVA != 0 {
                            Self.tlbFlushByVAResumes.wrappingAdd(1, ordering: .relaxed)
                        }
                        if Self.flushKeepsICache { frame.resumeFlags |= Self.resumeKeepICache }
                    }
                    if framePointer != nil {
                        frame.encode(into: try vm.writableHostPointer(gpa: frameAddress, count: TrapFrame.byteCount))
                    } else { try vm.write(gpa: frameAddress, bytes: frame.encoded()) }
                    slotFrameCurrent = true
                }
            default:
                disposition = exitHandler(worker, exit)
            }
            switch disposition {
            case .resume:
                continue
            case .park:
                return .parked
            case let .terminate(status, message):
                terminate(status: status, message: message, vcpuIndex: worker.index)
                return .ended
            case let .end(message):
                endPool(Termination(kind: .ended, status: 0, message: message, vcpuIndex: worker.index))
                return .ended
            }
        }
    }

    private func parkAtStart(_ worker: Worker, _ gate: GuestThreadGate, _ state: VCPUStartState, fresh: Bool) -> VCPUStartState {
        var regs = TrapRegisters()
        for (i, v) in state.registers.prefix(TrapFrame.registerCount).enumerated() { regs[i] = v }
        let frame = TrapFrame(x: Array(regs), spEL0: state.sp, elr: state.pc, spsr: VMLayout.el0InitialSPSR,
                              tpidrro: state.tpidrro, tpidr: cpuNumber(worker, state), kind: TrapFrame.Kind.svc.rawValue)
        guard let changed = gate.park(frame, at: .start) else { return state }
        var registers = Array(changed.x)
        if fresh, registers.dropFirst(8).contains(where: { $0 != 0 }) {
            log("vCPU \(worker.index): thread_set_state before the first instruction of a new vCPU: x8-x30 dropped")
            for i in 8..<registers.count { registers[i] = 0 }
        }
        return VCPUStartState(pc: changed.elr, sp: changed.spEL0, registers: registers, tpidrro: state.tpidrro, tpidr: state.tpidr)
    }

    private func gateBeforeEntry(_ worker: Worker, _ gate: GuestThreadGate, slotFrameCurrent: Bool) throws {
        let vcpu = worker.vcpu
        if slotFrameCurrent {
            let p = try vm.writableHostPointer(gpa: worker.frameGPA, count: TrapFrame.byteCount)
            var frame = TrapFrame(decodingFrameAt: p)
            var dirty = false
            if let replacement = gate.takeReplacement() {
                let x0 = frame.x[0], x1 = frame.x[1], carry = frame.carry
                frame.takeUserState(of: replacement)
                frame.x[0] = x0
                frame.x[1] = x1
                frame.carry = carry
                dirty = true
            }
            if gate.isClosed, let changed = gate.park(frame, at: .afterTrap) {
                frame.takeUserState(of: changed)
                dirty = true
            }
            if try applyStep(worker, gate, spsr: &frame.spsr) { dirty = true }
            if gate.takeFlushRequest() {
                frame.requestTLBInvalidation(nil)
                if Self.flushKeepsICache { frame.resumeFlags |= Self.resumeKeepICache }
                dirty = true
            }
            if dirty { frame.encode(into: try vm.writableHostPointer(gpa: worker.frameGPA, count: TrapFrame.byteCount)) }
        } else if gate.isClosed {
            let pstate = try vcpu.get(.pstate)
            if pstate & 0xF == 0 {
                var frame = TrapFrame()
                for n in 0..<TrapFrame.registerCount { frame.x[n] = try vcpu.get(.x(n)) }
                frame.spEL0 = try vcpu.get(.spEL0)
                frame.elr = try vcpu.get(.pc)
                frame.spsr = pstate
                frame.tpidrro = try vcpu.get(SystemRegister.tpidrroEL0)
                frame.tpidr = try vcpu.get(SystemRegister.tpidrEL0)
                frame.kind = TrapFrame.Kind.svc.rawValue
                if let changed = gate.park(frame, at: .guest) {
                    for n in 0..<TrapFrame.registerCount where changed.x[n] != frame.x[n] { try vcpu.set(.x(n), changed.x[n]) }
                    if changed.spEL0 != frame.spEL0 { try vcpu.set(.spEL0, changed.spEL0) }
                    if changed.elr != frame.elr { try vcpu.set(.pc, changed.elr) }
                    let flags = (pstate & ~UInt64(0xF000_0000)) | (changed.spsr & 0xF000_0000)
                    if flags != pstate { try vcpu.set(.pstate, flags) }
                }
                var now = try vcpu.get(.pstate)
                if try applyStep(worker, gate, spsr: &now) { try vcpu.set(.pstate, now) }
            }
        }
        if !ending.load(ordering: .acquiring) { vcpu.setImmediateExit(false) }
    }

    static let mdscrEL1 = SystemRegister(op0: 2, op1: 0, crn: 0, crm: 2, op2: 2)
    static let spsrSS: UInt64 = 1 << 21

    private func applyStep(_ worker: Worker, _ gate: GuestThreadGate, spsr: inout UInt64) throws -> Bool {
        if gate.takeStepRequest() {
            if !worker.stepping {
                worker.stepping = true
                try writeMDSCR(worker)
            }
            guard spsr & Self.spsrSS == 0 else { return false }
            spsr |= Self.spsrSS
            return true
        }
        guard worker.stepping else { return false }
        worker.stepping = false
        try writeMDSCR(worker)
        guard spsr & Self.spsrSS != 0 else { return false }
        spsr &= ~Self.spsrSS
        return true
    }

    private func endStep(_ worker: Worker, _ frame: inout TrapFrame) throws {
        worker.stepping = false
        try writeMDSCR(worker)
        frame.spsr &= ~Self.spsrSS
    }

    private func writeMDSCR(_ worker: Worker) throws {
        try worker.vcpu.set(Self.mdscrEL1, (worker.stepping ? 1 : 0) | (worker.watching ? Self.mdscrMDE : 0))
    }

    public struct HardwareWatchpoint: Equatable, Sendable {
        public var value: UInt64
        public var control: UInt64
        public init(value: UInt64, control: UInt64) {
            self.value = value
            self.control = control
        }
    }

    static let mdscrMDE: UInt64 = 1 << 15
    static let idAA64DFR0EL1 = SystemRegister(op0: 3, op1: 0, crn: 0, crm: 5, op2: 0)
    static func dbgwvr(_ n: Int) -> SystemRegister { SystemRegister(op0: 2, op1: 0, crn: 0, crm: UInt32(n), op2: 6) }
    static func dbgwcr(_ n: Int) -> SystemRegister { SystemRegister(op0: 2, op1: 0, crn: 0, crm: UInt32(n), op2: 7) }

    private var cachedWatchpointCount: Int?

    public var hardwareWatchpointCount: Int {
        lock.withLock {
            if let n = cachedWatchpointCount { return n }
            guard let v = workers.first?.vcpu, let dfr0 = try? v.get(Self.idAA64DFR0EL1) else { return 0 }
            let n = Int((dfr0 >> 20) & 0xF) + 1
            cachedWatchpointCount = n
            return n
        }
    }

    public func setHardwareWatchpoints(_ list: [HardwareWatchpoint]) {
        lock.withLock {
            watchRegisters = list
            watchSlotsUsed = max(watchSlotsUsed, list.count)
        }
        watchGeneration.wrappingAdd(1, ordering: .releasing)
    }

    private func loadWatchpoints(_ worker: Worker) throws {
        let generation = watchGeneration.load(ordering: .acquiring)
        let (list, slots) = lock.withLock { (watchRegisters, watchSlotsUsed) }
        for n in 0..<slots {
            let w = n < list.count ? list[n] : HardwareWatchpoint(value: 0, control: 0)
            try worker.vcpu.set(Self.dbgwcr(n), 0)
            try worker.vcpu.set(Self.dbgwvr(n), w.value)
            if w.control != 0 { try worker.vcpu.set(Self.dbgwcr(n), w.control) }
        }
        worker.watching = list.contains { $0.control & 1 != 0 }
        try writeMDSCR(worker)
        worker.watchGeneration = generation
    }

    public func terminate(status: Int32, message: String, vcpuIndex: Int?) {
        endPool(Termination(kind: .terminated, status: status, message: message, vcpuIndex: vcpuIndex))
    }

    public func longGuestRuns(atLeast ms: UInt64) -> [Worker] {
        let now = monotonicMilliseconds()
        let list = lock.withLock { workers.filter { $0.running } }
        let stuck = list.filter {
            !$0.inHandler.load(ordering: .relaxed) && $0.lastExitMs.load(ordering: .relaxed) != 0
                && now &- $0.lastExitMs.load(ordering: .relaxed) >= ms
        }
        for w in stuck {
            w.sampleRequested.store(true, ordering: .relaxed)
            _ = ckvm_kick_thread(UInt(w.hostThread), Self.kickSignal)
        }
        return stuck
    }

    public func workerStates() -> [String] {
        let now = monotonicMilliseconds()
        return lock.withLock { workers }.map { w in
            "vCPU \(w.index) tid \(w.hostTID.load(ordering: .relaxed)) running \(w.running) inHandler \(w.inHandler.load(ordering: .relaxed)) "
                + "x16 \(Int64(bitPattern: w.lastTrapX16.load(ordering: .relaxed))) handler age \(now &- w.handlerSince.load(ordering: .relaxed)) ms "
                + "last exit \(now &- w.lastExitMs.load(ordering: .relaxed)) ms ago, context \(w.context.map { "\($0)" } ?? "none")"
        }
    }

    public func longHandlers(atLeast ms: UInt64) -> [Worker] {
        let now = monotonicMilliseconds()
        return lock.withLock { workers }.filter {
            $0.inHandler.load(ordering: .relaxed) && now &- $0.handlerSince.load(ordering: .relaxed) >= ms
        }
    }

    public func requestStop(_ message: String = "stopped") {
        endPool(Termination(kind: .stopped, status: 0, message: message, vcpuIndex: nil))
    }

    private func endPool(_ reason: Termination) {
        let recorded: Termination? = lock.withLock {
            var changed: Termination?
            if termination == nil || (termination!.kind == .stopped && reason.kind != .stopped) {
                termination = reason
                changed = reason
            }
            if ending.exchange(true, ordering: .acquiringAndReleasing) {
                terminated.broadcast()
                return changed
            }
            let me = pthread_self()
            for worker in workers {
                worker.vcpu.setImmediateExit(true)
                worker.wakeup.broadcast()
                worker.gate?.release()
                if worker.running, !worker.inHandler.load(ordering: .relaxed), pthread_equal(worker.hostThread, me) == 0,
                   !Self.debugNoKick {
                    _ = ckvm_kick_thread(UInt(worker.hostThread), Self.kickSignal)
                }
            }
            terminated.broadcast()
            return changed
        }
        if let recorded { onEnd(recorded) }
    }

    public func waitForTermination(timeoutMilliseconds: UInt64) -> Termination {
        lock.lock()
        let deadline = monotonicMilliseconds() + timeoutMilliseconds
        while termination == nil {
            let now = monotonicMilliseconds()
            if now >= deadline { break }
            terminated.wait(lock, milliseconds: deadline - now)
        }
        if let termination {
            lock.unlock()
            return termination
        }
        lock.unlock()
        let report = stopAll()
        return Termination(kind: .stopped, status: 71,
                           message: "watchdog: guest still running after \(timeoutMilliseconds) ms\n" + report, vcpuIndex: nil)
    }

    public func stopAll(milliseconds: UInt64 = 1000) -> String {
        lock.withLock { reportStops = true }
        endPool(Termination(kind: .stopped, status: 71, message: "stopped by the supervisor", vcpuIndex: nil))
        lock.lock()
        let snapshot = workers
        let deadline = monotonicMilliseconds() + milliseconds
        while monotonicMilliseconds() < deadline,
              snapshot.contains(where: { $0.running && !$0.inHandler.load(ordering: .relaxed) && stopReports[$0.index] == nil }) {
            terminated.wait(lock, milliseconds: 50)
        }
        var lines: [String] = []
        func h(_ v: UInt64) -> String { "0x" + String(v, radix: 16) }
        for worker in snapshot {
            if let report = stopReports[worker.index] {
                lines.append(report)
            } else if worker.running {
                let x16 = Int32(truncatingIfNeeded: worker.lastTrapX16.load(ordering: .relaxed))
                let where_ = worker.inHandler.load(ordering: .relaxed) ? "blocked in trap x16=\(x16)" : "did not stop"
                lines.append("  vCPU \(worker.index): \(where_) (ELR \(h(worker.lastTrapELR.load(ordering: .relaxed))), threads run \(worker.threadCount))")
            } else {
                lines.append("  vCPU \(worker.index): parked (threads run \(worker.threadCount))")
            }
        }
        lock.unlock()
        return lines.joined(separator: "\n")
    }

    private func acknowledgeStop(_ worker: Worker, _ exit: VCPUExit) {
        guard lock.withLock({ reportStops }) else { return }
        let vcpu = worker.vcpu
        func h(_ v: UInt64) -> String { "0x" + String(v, radix: 16) }
        func reg(_ r: CoreRegister) -> String { (try? vcpu.get(r)).map(h) ?? "?" }
        let pstate = (try? vcpu.get(.pstate)) ?? 0
        var line = "  vCPU \(worker.index): stopped (\(exit)) pc \(reg(.pc)) pstate \(h(pstate))"
        if pstate & 0xF == 0 {
            line += " [EL0] sp \(reg(.spEL0)) lr \(reg(.x(30)))"
        } else {
            line += " [EL1] elr \(reg(.elrEL1)) sp_el0 \(reg(.spEL0))"
        }
        line += "; last trap x16=\(Int32(truncatingIfNeeded: worker.lastTrapX16.load(ordering: .relaxed))) ELR \(h(worker.lastTrapELR.load(ordering: .relaxed))); threads run \(worker.threadCount)"
        lock.withLock {
            stopReports[worker.index] = line
            terminated.broadcast()
        }
    }

    @discardableResult
    public func waitUntilFinished(milliseconds: UInt64?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let deadline = milliseconds.map { monotonicMilliseconds() + $0 }
        while !(ending.load(ordering: .relaxed) && liveHostThreads == 0) {
            if let deadline {
                let now = monotonicMilliseconds()
                if now >= deadline { return false }
                terminated.wait(lock, milliseconds: deadline - now)
            } else {
                terminated.wait(lock)
            }
        }
        return true
    }

    public func joinThreads() {
        let snapshot: [Worker] = lock.withLock { workers.filter { !$0.joined } }
        for worker in snapshot {
            pthread_join(worker.hostThread, nil)
            lock.withLock { worker.joined = true }
        }
        lock.withLock {
            idle.removeAll()
            for worker in workers { worker.context = nil }
        }
        trapHandler = { _, _ in .terminate(status: 71, message: "pool torn down") }
        exitHandler = { _, _ in .terminate(status: 71, message: "pool torn down") }
        shouldStop = { true }
        onEnd = { _ in }
        onFinished = {}
        preBootCleanRanges = { [] }
        sampleStackReader = nil
        log = { _ in }
    }

    public func shutdown() {
        requestStop("shut down")
        waitUntilFinished(milliseconds: nil)
        joinThreads()
    }
}

final class VCPUCreator: @unchecked Sendable {
    static let shared: VCPUCreator? = {
        let n = getenv("SWIFTCODE_VCPU_CREATORS").flatMap { Int(String(cString: $0)) } ?? 2
        return n <= 0 ? nil : VCPUCreator(threads: min(n, 16))
    }()

    private let lock = HostMutex(name: "vCPU creator queue")
    private let wake = HostCondition()
    private var queue: [(pool: VCPUPool, creation: VCPUPool.InFlight)] = []
    private let threadLimit: Int
    private var threads = 0
    private var idleThreads = 0

    init(threads: Int) { threadLimit = threads }

    func submit(_ pool: VCPUPool, _ creation: VCPUPool.InFlight) {
        lock.lock()
        queue.append((pool, creation))
        let startThread = idleThreads == 0 && threads < threadLimit
        if startThread { threads += 1 }
        wake.signal()
        lock.unlock()
        if startThread { startCreatorThread() }
    }

    private func startCreatorThread() {
        var attributes = pthread_attr_t()
        pthread_attr_init(&attributes)
        defer { pthread_attr_destroy(&attributes) }
        pthread_attr_setdetachstate(&attributes, Int32(PTHREAD_CREATE_DETACHED))
        let box = Unmanaged.passRetained(self).toOpaque()
        var thread = pthread_t()
        let result = pthread_create(&thread, &attributes, { argument in
            let creator = Unmanaged<VCPUCreator>.fromOpaque(argument!).takeRetainedValue()
            creator.run()
            return nil
        }, box)
        if result != 0 {
            Unmanaged<VCPUCreator>.fromOpaque(box).release()
            let none: Bool = lock.withLock {
                threads -= 1
                return threads == 0
            }
            if none { drainInline() }
        }
    }

    private func drainInline() {
        while let next = take(waiting: false) { next.pool.createReserved(next.creation) }
    }

    private func take(waiting: Bool) -> (pool: VCPUPool, creation: VCPUPool.InFlight)? {
        lock.lock()
        defer { lock.unlock() }
        while queue.isEmpty {
            guard waiting else { return nil }
            idleThreads += 1
            wake.wait(lock)
            idleThreads -= 1
        }
        let i = queue.firstIndex { $0.creation.urgent.load(ordering: .relaxed) } ?? 0
        return queue.remove(at: i)
    }

    private func run() {
        while let next = take(waiting: true) { next.pool.createReserved(next.creation) }
    }
}

public func hostThreadUsage() -> (faults: UInt64, voluntarySwitches: UInt64, involuntarySwitches: UInt64) {
    var c: (Int, Int, Int, Int) = (0, 0, 0, 0)
    withUnsafeMutablePointer(to: &c) { $0.withMemoryRebound(to: Int.self, capacity: 4) { ckvm_thread_usage($0) } }
    return (UInt64(c.0 + c.1), UInt64(c.2), UInt64(c.3))
}

public func hostThreadTimes() -> (userMicros: UInt64, systemMicros: UInt64, minorFaults: UInt64) {
    var c: (UInt64, UInt64, UInt64) = (0, 0, 0)
    withUnsafeMutablePointer(to: &c) { $0.withMemoryRebound(to: CUnsignedLongLong.self, capacity: 3) { ckvm_thread_times($0) } }
    return (c.0, c.1, c.2)
}

public func hostThreadCPUNanoseconds() -> UInt64 {
    var t = timespec()
    guard clock_gettime(CLOCK_THREAD_CPUTIME_ID, &t) == 0 else { return 0 }
    return UInt64(t.tv_sec) * 1_000_000_000 + UInt64(t.tv_nsec)
}

public func ckvmThreadID() -> Int { ckvm_gettid() }

public func hostTaskStats(_ tid: Int) -> [UInt64]? {
    var out = [UInt64](repeating: 0, count: 8)
    return ckvm_task_stats(tid, &out) == 0 ? out : nil
}

public let hostClockTicks = UInt64(max(1, ckvm_clock_ticks()))

public func monotonicNanoseconds() -> UInt64 {
    var now = timespec()
    clock_gettime(CLOCK_MONOTONIC, &now)
    return UInt64(now.tv_sec) * 1_000_000_000 + UInt64(now.tv_nsec)
}

public func monotonicMillisecondsCoarse() -> UInt64 {
    var now = timespec()
    clock_gettime(CLOCK_MONOTONIC_COARSE, &now)
    return UInt64(now.tv_sec) * 1000 + UInt64(now.tv_nsec) / 1_000_000
}

public func monotonicMilliseconds() -> UInt64 {
    var now = timespec()
    clock_gettime(CLOCK_MONOTONIC, &now)
    return UInt64(now.tv_sec) * 1000 + UInt64(now.tv_nsec) / 1_000_000
}
#endif
