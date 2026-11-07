import Foundation
import Synchronization
import SwiftCodeDarwinABI
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

public typealias TrapOutcome = DarwinKernel.Outcome

public enum KernelClock {
    public static func now() -> UInt64 { MachTimebase.hostMonotonicNanoseconds() }

    public static func deadline(afterNanoseconds ns: UInt64) -> UInt64 {
        let (d, overflow) = now().addingReportingOverflow(ns)
        return overflow ? UInt64.max : d
    }
}

public enum WaitResult: Equatable, Sendable {
    case woken
    case timedOut
    case interrupted
}

public final class KernelLock: @unchecked Sendable {
    fileprivate let mutex: UnsafeMutablePointer<pthread_mutex_t>
    fileprivate let owner = Atomic<UInt>(0)
    public let splitEnabled: Bool
    public let root: KernelLock?
    public let level: Int
    @inline(__always) var isSplit: Bool { splitEnabled || root != nil }
    @inline(__always) var splitRoot: KernelLock? { root ?? (splitEnabled ? self : nil) }
    private var fineLocks: [WeakKernelLock] = []
    private let fineLocksMutex = NSLock()
    @inline(__always) fileprivate static var threadToken: UInt {
        #if canImport(Darwin)
        UInt(bitPattern: pthread_self())
        #else
        UInt(pthread_self())
        #endif
    }
    fileprivate var depth = 0
    fileprivate var waiters: [ObjectIdentifier: WaitQueue.Waiter] = [:]
    private var deferredWakes: [WaitQueue.Waiter] = []
    nonisolated(unsafe) public static var wakeAfterUnlock: Bool = {
        for name in ["SWIFTCODE_WAKE_AFTER_UNLOCK", "SWIFTCODE_DEFERRED_WAKE"] {
            if let v = getenv(name) { return String(cString: v) != "0" }
        }
        return true
    }()

    fileprivate func deferSignal(_ w: WaitQueue.Waiter) { deferredWakes.append(w) }

    @inline(__always) fileprivate func takeDeferredWakes() -> [WaitQueue.Waiter]? {
        guard !deferredWakes.isEmpty else { return nil }
        let wakes = deferredWakes
        deferredWakes = []
        return wakes
    }

    @inline(__always) fileprivate static func signal(_ wakes: [WaitQueue.Waiter]?) {
        guard let wakes else { return }
        for w in wakes { pthread_cond_signal(w.cond) }
    }

    public static let wakeLatency = LatencyHistogram("wake")

    public internal(set) var currentContext: ThreadContext?
    public fileprivate(set) var isTerminated = false
    var blockingObserver: ((_ context: ThreadContext, _ blocking: Bool) -> Void)?

    public private(set) var totalHeldNanoseconds: UInt64 = 0
    public private(set) var acquisitions: UInt64 = 0
    fileprivate var posted: [() -> Void] = []
    fileprivate let postedCount = Atomic<Int>(0)
    fileprivate let postedMutex = NSLock()
    fileprivate var fineContended: UInt64 = 0
    fileprivate var fineWaitNanoseconds: UInt64 = 0
    public var slowHoldNanoseconds: UInt64 = 0
    public var slowHoldReporter: ((_ context: ThreadContext?, _ nanoseconds: UInt64) -> Void)?
    private var holdStart: UInt64 = 0
    public var profileHolds = false
    public private(set) var holdProfile: [Int64: (ns: UInt64, count: UInt64)] = [:]
    let trapProfile: TrapProfile?

    @inline(__always) fileprivate func lockMutex(for context: ThreadContext?) {
        let gate = admission
        let tracking = gate || tracksContention
        let traced = KernelTrace.lockWaited
        let timed = trapProfile != nil || (Self.profileProcesses && root == nil) || traced != nil
        let promoting = HostSched.promoting
        guard timed || tracking || promoting else {
            pthread_mutex_lock(mutex)
            return
        }
        let cls = gate ? (context?.schedClass ?? SchedClass.interactive) : SchedClass.default
        let start = timed ? KernelClock.now() : 0
        if gate, cls < SchedClass.interactive { admit(cls) }
        var contended = false
        if pthread_mutex_trylock(mutex) != 0 {
            contended = true
            if tracking {
                if cls >= SchedClass.default, context != nil { lastHighContentionStore.store(KernelClock.now(), ordering: .relaxed) }
                contending.wrappingAdd(Self.unit(cls), ordering: .sequentiallyConsistent)
            }
            if promoting { lockPromoting(context) } else { pthread_mutex_lock(mutex) }
            if tracking {
                contending.wrappingSubtract(Self.unit(cls), ordering: .sequentiallyConsistent)
                if gateWaiters.load(ordering: .sequentiallyConsistent) > 0 { wakeGate() }
            }
        }
        if timed {
            let waited = KernelClock.now() &- start
            trapProfile?.noteWait(TrapProfile.key(for: context), waited, contended: contended)
            if contended, let traced { traced(Int32(level), waited) }
            if Self.profileProcesses, let kernel = context?.kernel { kernel.profileLockWaitNanoseconds &+= waited }
        }
    }

    public var admission = SchedPolicy.gateActive
    public var tracksContention = SchedPolicy.holdEnabled

    private let contending = Atomic<UInt64>(0)
    private let gateWaiters = Atomic<Int>(0)
    private let gateMutex: UnsafeMutablePointer<pthread_mutex_t>
    private let gateCond: UnsafeMutablePointer<pthread_cond_t>
    private let lastHighContentionStore = Atomic<UInt64>(0)
    public var lastHighContention: UInt64 { lastHighContentionStore.load(ordering: .relaxed) }
    private let gateWaits = Atomic<UInt64>(0)
    private let gateWaitNanoseconds = Atomic<UInt64>(0)
    private let gateBoundHits = Atomic<UInt64>(0)

    @inline(__always) static func unit(_ cls: Int) -> UInt64 { 1 << (16 * UInt64(cls)) }

    func contendingCount(_ cls: Int) -> UInt64 {
        (contending.load(ordering: .sequentiallyConsistent) >> (16 * UInt64(cls))) & 0xFFFF
    }

    func higherContending(_ cls: Int) -> UInt64 {
        contending.load(ordering: .sequentiallyConsistent) >> (16 * UInt64(cls + 1))
    }

    private func admit(_ cls: Int) {
        guard higherContending(cls) != 0 else { return }
        let bounds = SchedPolicy.admissionBoundNanoseconds
        let bound = cls < bounds.count ? bounds[cls] : 0
        guard bound > 0 else { return }
        let start = KernelClock.now()
        let deadline = start &+ bound
        gateWaiters.wrappingAdd(1, ordering: .sequentiallyConsistent)
        pthread_mutex_lock(gateMutex)
        var hitBound = false
        while higherContending(cls) != 0 {
            let now = KernelClock.now()
            if now >= deadline {
                hitBound = true
                break
            }
            let slice = min(deadline - now, 1_000_000)
            #if canImport(Darwin)
            var ts = timespec(tv_sec: 0, tv_nsec: Int(slice))
            _ = pthread_cond_timedwait_relative_np(gateCond, gateMutex, &ts)
            #else
            let until = now + slice
            var ts = timespec(tv_sec: Int(until / 1_000_000_000), tv_nsec: Int(until % 1_000_000_000))
            _ = pthread_cond_timedwait(gateCond, gateMutex, &ts)
            #endif
        }
        pthread_mutex_unlock(gateMutex)
        gateWaiters.wrappingSubtract(1, ordering: .sequentiallyConsistent)
        gateWaits.wrappingAdd(1, ordering: .relaxed)
        gateWaitNanoseconds.wrappingAdd(KernelClock.now() &- start, ordering: .relaxed)
        if hitBound { gateBoundHits.wrappingAdd(1, ordering: .relaxed) }
    }

    private func wakeGate() {
        pthread_mutex_lock(gateMutex)
        pthread_cond_broadcast(gateCond)
        pthread_mutex_unlock(gateMutex)
    }

    public var admissionReport: String {
        "lock admission: \(gateWaits.load(ordering: .relaxed)) gate waits, "
            + "\(gateWaitNanoseconds.load(ordering: .relaxed) / 1_000_000) ms, "
            + "\(gateBoundHits.load(ordering: .relaxed)) at the bound"
    }

    nonisolated(unsafe) public static var profileProcesses = false

    private var holdUsage: TrapProfile.ThreadUsage?
    private let holderTID = Atomic<Int>(0)
    public var holderThreadID: Int { holderTID.load(ordering: .relaxed) }
    private let holderKey = Atomic<Int64>(0)
    public var holderTrapKey: Int64 { holderKey.load(ordering: .relaxed) }
    private let holderSequence = Atomic<UInt64>(0)
    public var holdSequence: UInt64 { holderSequence.load(ordering: .acquiring) }

    private let holderWord = Atomic<UInt64>(0)
    private let promotersInFlight = Atomic<Int>(0)
    private var holderGeneration: UInt64 = 0

    @inline(__always) private func publishHolder() {
        guard let tid = HostSched.currentTID() else { return }
        holderGeneration &+= 1
        let applied = UInt64(max(-1, min(SchedClass.interactive, HostSched.appliedClass())) + 1)
        let word = UInt64(UInt32(bitPattern: tid)) | applied << 32 | (holderGeneration & 0xFF_FFFF) << 40
        holderWord.store(word, ordering: .sequentiallyConsistent)
    }

    @inline(__always) private func withdrawHolder() {
        let old = holderWord.exchange(0, ordering: .sequentiallyConsistent)
        let raised = Int((old >> 36) & 0xF) - 1
        guard raised >= 0 else { return }
        var spins = 0
        while promotersInFlight.load(ordering: .sequentiallyConsistent) > 0 {
            spins += 1
            if spins > 64 { sched_yield() }
        }
        let applied = Int((old >> 32) & 0xF) - 1
        if HostSched.raisesGroup(applied) {
            HostSched.lowerGroup(applied)
        } else {
            HostSched.setAppliedClass(raised)
        }
        HostSched.promotionRestores.wrappingAdd(1, ordering: .relaxed)
    }

    nonisolated(unsafe) static var promotionDelayNanoseconds: UInt64 =
        UInt64(getenv("SWIFTCODE_LOCK_PROMOTION_DELAY_US").flatMap { Double(String(cString: $0)) } ?? 200) * 1000

    private func lockPromoting(_ context: ThreadContext?) {
        let delay = Self.promotionDelayNanoseconds
        if delay > 0 {
            #if os(Linux)
            var now = timespec()
            clock_gettime(CLOCK_REALTIME, &now)
            let total = UInt64(now.tv_nsec) + delay
            var until = timespec(tv_sec: now.tv_sec + Int(total / 1_000_000_000), tv_nsec: Int(total % 1_000_000_000))
            if pthread_mutex_timedlock(mutex, &until) == 0 { return }
            #else
            let deadline = KernelClock.now() &+ delay
            while KernelClock.now() < deadline {
                if pthread_mutex_trylock(mutex) == 0 { return }
                usleep(50)
            }
            #endif
            HostSched.promotionWaits.wrappingAdd(1, ordering: .relaxed)
        }
        promoteHolder(to: context?.hostClass ?? SchedClass.interactive)
        pthread_mutex_lock(mutex)
    }

    private func promoteHolder(to cls: Int) {
        guard cls > SchedClass.background else { return }
        promotersInFlight.wrappingAdd(1, ordering: .sequentiallyConsistent)
        defer { promotersInFlight.wrappingSubtract(1, ordering: .sequentiallyConsistent) }
        var word = holderWord.load(ordering: .sequentiallyConsistent)
        while word != 0 {
            let applied = Int((word >> 32) & 0xF) - 1
            let raised = Int((word >> 36) & 0xF) - 1
            guard applied >= 0, cls > max(applied, raised) else { return }
            let new = (word & ~(UInt64(0xF) << 36)) | UInt64(cls + 1) << 36
            let (exchanged, original) = holderWord.compareExchange(expected: word, desired: new, ordering: .sequentiallyConsistent)
            if exchanged {
                if HostSched.raisesGroup(applied) {
                    if raised < 0 { HostSched.raiseGroup(applied, to: cls) } else { HostSched.raiseGroup(applied, to: cls); HostSched.lowerGroup(applied) }
                } else {
                    HostSched.move(Int32(truncatingIfNeeded: word & 0xFFFF_FFFF), to: cls)
                }
                HostSched.promotions.wrappingAdd(1, ordering: .relaxed)
                return
            }
            word = original
        }
    }

    nonisolated(unsafe) public static var fineLockSpin = getenv("SWIFTCODE_FINE_LOCK_SPIN").map { String(cString: $0) != "0" } ?? true

    public var tracksHolder = false

    fileprivate func noteAcquired() {
        if trapProfile != nil || tracksHolder {
            if root == nil, let probe = TrapProfile.threadUsage { holdUsage = probe() }
            holderKey.store(TrapProfile.key(for: currentContext), ordering: .relaxed)
            if let tid = TrapProfile.currentThreadID { holderTID.store(tid(), ordering: .relaxed) }
            holderSequence.wrappingAdd(1, ordering: .releasing)
        }
        holdStart = KernelClock.now()
        acquisitions &+= 1
        if HostSched.promoting { publishHolder() }
    }

    fileprivate func noteReleasing() {
        if HostSched.promoting { withdrawHolder() }
        let held = KernelClock.now() &- holdStart
        if trapProfile != nil || tracksHolder {
            holderTID.store(0, ordering: .relaxed)
            holderSequence.wrappingAdd(1, ordering: .releasing)
        }
        totalHeldNanoseconds &+= held
        if Self.profileProcesses, root == nil, let kernel = currentContext?.kernel {
            kernel.profileLockHeldNanoseconds &+= held
            kernel.profileLockAcquisitions &+= 1
        }
        if profileHolds {
            let key = currentContext?.trapInProgress.map { Int64(bitPattern: $0.x16) } ?? Int64.min
            let old = holdProfile[key] ?? (0, 0)
            holdProfile[key] = (old.ns &+ held, old.count &+ 1)
        }
        if let trapProfile {
            var usage: TrapProfile.ThreadUsage?
            if let start = holdUsage, let probe = TrapProfile.threadUsage {
                let end = probe()
                usage = .init(faults: end.faults &- start.faults,
                              voluntarySwitches: end.voluntarySwitches &- start.voluntarySwitches,
                              involuntarySwitches: end.involuntarySwitches &- start.involuntarySwitches)
            }
            trapProfile.noteHold(TrapProfile.key(for: currentContext), held, usage: usage)
        }
        if slowHoldNanoseconds > 0, held >= slowHoldNanoseconds, let r = slowHoldReporter { r(currentContext, held) }
    }

    public convenience init() {
        self.init(ipcLocks: false)
    }

    public convenience init(ipcLocks: Bool) {
        self.init(split: ipcLocks, root: nil, level: 0, name: "kernel lock (L0)")
    }

    public convenience init(fineLockOf root: KernelLock, level: Int, name: String) {
        precondition(root.splitEnabled && (level == 1 || level == 2))
        self.init(split: false, root: root, level: level, name: name)
        admission = false
        tracksContention = false
        root.fineLocksMutex.lock()
        root.fineLocks.removeAll { $0.lock == nil }
        root.fineLocks.append(WeakKernelLock(self))
        root.fineLocksMutex.unlock()
    }

    private init(split: Bool, root: KernelLock?, level: Int, name: String) {
        splitEnabled = split
        self.root = root
        self.level = level
        trapProfile = root == nil ? TrapProfile.shared : (level == 2 ? TrapProfile.portLock : TrapProfile.eventLocks)
        mutex = .allocate(capacity: 1)
        var attr = pthread_mutexattr_t()
        pthread_mutexattr_init(&attr)
        #if os(Linux)
        if root != nil, Self.fineLockSpin {
            pthread_mutexattr_settype(&attr, Int32(PTHREAD_MUTEX_ADAPTIVE_NP))
        }
        #endif
        pthread_mutex_init(mutex, &attr)
        pthread_mutexattr_destroy(&attr)
        TrapProfile.nameLock(UnsafeMutableRawPointer(mutex), name)
        gateMutex = .allocate(capacity: 1)
        pthread_mutex_init(gateMutex, nil)
        gateCond = .allocate(capacity: 1)
        var cattr = pthread_condattr_t()
        pthread_condattr_init(&cattr)
        #if !canImport(Darwin)
        pthread_condattr_setclock(&cattr, CLOCK_MONOTONIC)
        #endif
        pthread_cond_init(gateCond, &cattr)
        pthread_condattr_destroy(&cattr)
    }

    deinit {
        pthread_mutex_destroy(mutex)
        mutex.deallocate()
        pthread_cond_destroy(gateCond)
        gateCond.deallocate()
        pthread_mutex_destroy(gateMutex)
        gateMutex.deallocate()
    }

    public var isHeldByCurrentThread: Bool {
        owner.load(ordering: .relaxed) == Self.threadToken
    }

    public func withLock<T>(_ body: () throws -> T) rethrows -> T {
        try withLock(context: nil, body)
    }

    public func withLock<T>(context: ThreadContext?, _ body: () throws -> T) rethrows -> T {
        if isHeldByCurrentThread {
            depth += 1
            defer { depth -= 1 }
            return try body()
        }
        if isSplit { return try withSplitLock(context: context, body) }
        KernelThreadLocks.checkNoLeaf(self)
        lockMutex(for: context)
        owner.store(Self.threadToken, ordering: .relaxed)
        depth = 1
        currentContext = context
        noteAcquired()
        defer {
            noteReleasing()
            currentContext = nil
            depth = 0
            owner.store(0, ordering: .relaxed)
            let wakes = takeDeferredWakes()
            pthread_mutex_unlock(mutex)
            Self.signal(wakes)
        }
        return try body()
    }

    public func terminate() {
        precondition(isHeldByCurrentThread, "KernelLock.terminate needs the kernel lock")
        isTerminated = true
        forEachRegistry { lock in
            for w in lock.waiters.values { w.finish(.interrupted) }
            lock.waiters.removeAll()
        }
    }

    private func forEachRegistry(_ body: (KernelLock) -> Void) {
        body(self)
        for lock in liveFineLocks {
            if lock.isHeldByCurrentThread { body(lock) } else { lock.withLock { body(lock) } }
        }
    }

    public func terminate(kernel: DarwinKernel) {
        precondition(isHeldByCurrentThread, "KernelLock.terminate needs the kernel lock")
        forEachRegistry { lock in
            for (key, w) in lock.waiters where w.context?.kernel === kernel {
                w.finish(.interrupted)
                lock.waiters[key] = nil
            }
        }
    }

    @discardableResult
    public func interrupt(_ context: ThreadContext) -> Bool {
        precondition(isHeldByCurrentThread, "KernelLock.interrupt needs the kernel lock")
        var any = false
        forEachRegistry { lock in
            for (key, w) in lock.waiters where w.context === context {
                w.finish(.interrupted)
                lock.waiters[key] = nil
                any = true
            }
        }
        return any
    }

    public func withAllFineLocks<T>(_ body: () throws -> T) rethrows -> T {
        guard splitEnabled else { return try body() }
        precondition(isHeldByCurrentThread, "withAllFineLocks needs the kernel lock")
        let locks = liveFineLocks.sorted { ($0.level, ObjectIdentifier($0)) < ($1.level, ObjectIdentifier($1)) }
            .filter { !$0.isHeldByCurrentThread }
        let threadLocks = KernelThreadLocks.current
        let wasQuiesced = threadLocks.quiesced
        threadLocks.quiesced = true
        for lock in locks {
            lock.acquireRaw(depth: 1, context: currentContext)
            threadLocks.held.append(lock)
        }
        defer {
            for lock in locks.reversed() {
                threadLocks.held.removeAll { $0 === lock }
                lock.releaseRaw()
            }
            threadLocks.quiesced = wasQuiesced
            if !threadLocks.deferred.isEmpty { threadLocks.runDeferredWork() }
        }
        return try body()
    }

    var liveFineLocks: [KernelLock] {
        guard splitEnabled else { return [] }
        fineLocksMutex.lock()
        defer { fineLocksMutex.unlock() }
        return fineLocks.compactMap(\.lock)
    }

    public func yield() {
        precondition(isHeldByCurrentThread && depth == 1, "KernelLock.yield needs the lock at depth 1")
        if isSplit {
            guard root == nil, KernelThreadLocks.current.held.last === self else { sched_yield(); return }
            KernelThreadLocks.current.held.removeLast()
            defer { KernelThreadLocks.current.held.append(self) }
        }
        let saved = currentContext
        noteReleasing()
        owner.store(0, ordering: .relaxed)
        depth = 0
        currentContext = nil
        let wakes = takeDeferredWakes()
        pthread_mutex_unlock(mutex)
        Self.signal(wakes)
        sched_yield()
        lockMutex(for: saved)
        owner.store(Self.threadToken, ordering: .relaxed)
        depth = 1
        currentContext = saved
        noteAcquired()
    }

    static let neverUnlock = getenv("SWIFTCODE_DEBUG_NO_UNLOCK").map { String(cString: $0) == "1" } ?? false

    public func unlocked<T>(_ body: () throws -> T) rethrows -> T {
        guard isHeldByCurrentThread, depth == 1, !Self.neverUnlock else { return try body() }
        if isSplit {
            guard root == nil, KernelThreadLocks.current.held.last === self else { return try body() }
            KernelThreadLocks.current.held.removeLast()
        }
        defer { if isSplit { KernelThreadLocks.current.held.append(self) } }
        let saved = currentContext
        noteReleasing()
        owner.store(0, ordering: .relaxed)
        depth = 0
        currentContext = nil
        let wakes = takeDeferredWakes()
        pthread_mutex_unlock(mutex)
        Self.signal(wakes)
        defer {
            lockMutex(for: saved)
            owner.store(Self.threadToken, ordering: .relaxed)
            depth = 1
            currentContext = saved
            noteAcquired()
        }
        return try body()
    }

    var snapshotWaiterStates: [(context: ThreadContext?, woken: Bool)] {
        var states: [(context: ThreadContext?, woken: Bool)] = []
        forEachRegistry { lock in
            states += lock.waiters.values.map { ($0.context, $0.result != nil) }
            if WaitQueue.Waiter.recordStacks {
                for w in lock.waiters.values where w.result == nil && w.context?.trapInProgress == nil {
                    FileHandle.standardError.write(Data(("wait without a trap on \(lock.name), thread \(w.context?.threadID ?? 0):\n"
                        + (w.debugStack ?? []).prefix(14).joined(separator: "\n") + "\n").utf8))
                }
            }
        }
        return states
    }

    fileprivate func register(_ w: WaitQueue.Waiter) { waiters[ObjectIdentifier(w)] = w }

    fileprivate func unregister(_ w: WaitQueue.Waiter) { waiters[ObjectIdentifier(w)] = nil }

    fileprivate func sleep(on cond: UnsafeMutablePointer<pthread_cond_t>, deadline: UInt64?) -> Bool {
        precondition(depth == 1, "WaitQueue.wait inside a nested withLock")
        Self.signal(takeDeferredWakes())
        let saved = currentContext
        noteReleasing()
        owner.store(0, ordering: .relaxed)
        depth = 0
        currentContext = nil
        let rc = Self.conditionWait(cond, mutex, deadline: deadline)
        owner.store(Self.threadToken, ordering: .relaxed)
        depth = 1
        currentContext = saved
        noteAcquired()
        return rc != ETIMEDOUT
    }

    fileprivate static func conditionWait(_ cond: UnsafeMutablePointer<pthread_cond_t>,
                                          _ mutex: UnsafeMutablePointer<pthread_mutex_t>, deadline: UInt64?) -> Int32 {
        guard let deadline else { return pthread_cond_wait(cond, mutex) }
        let now = KernelClock.now()
        if now >= deadline { return ETIMEDOUT }
        #if canImport(Darwin)
        let remaining = deadline - now
        var ts = timespec(tv_sec: Int(remaining / 1_000_000_000), tv_nsec: Int(remaining % 1_000_000_000))
        return pthread_cond_timedwait_relative_np(cond, mutex, &ts)
        #else
        var ts = timespec(tv_sec: Int(deadline / 1_000_000_000), tv_nsec: Int(deadline % 1_000_000_000))
        return pthread_cond_timedwait(cond, mutex, &ts)
        #endif
    }
}

public struct WaitQueue: @unchecked Sendable {
    final class Waiter {
        let cond: UnsafeMutablePointer<pthread_cond_t>
        unowned let lock: KernelLock
        let context: ThreadContext?
        let tag: UInt64
        var result: WaitResult?
        weak var storage: Storage?
        var debugStack: [String]?
        static let recordStacks = getenv("SWIFTCODE_DEBUG_WAIT_STACKS").map { String(cString: $0) == "1" } ?? false
        var wokenAt: UInt64 = 0

        init(lock: KernelLock, context: ThreadContext?, tag: UInt64) {
            self.lock = lock
            self.context = context
            self.tag = tag
            cond = .allocate(capacity: 1)
            var attr = pthread_condattr_t()
            pthread_condattr_init(&attr)
            #if !canImport(Darwin)
            pthread_condattr_setclock(&attr, CLOCK_MONOTONIC)
            #endif
            pthread_cond_init(cond, &attr)
            pthread_condattr_destroy(&attr)
        }

        deinit {
            pthread_cond_destroy(cond)
            cond.deallocate()
        }

        func finish(_ r: WaitResult) {
            guard result == nil else { return }
            if r == .woken, let hook = KernelTrace.wake { hook(context) }
            if lock.isSplit, !lock.isHeldByCurrentThread {
                pthread_mutex_lock(lock.mutex)
                result = r
                storage?.remove(self)
                pthread_cond_signal(cond)
                pthread_mutex_unlock(lock.mutex)
                return
            }
            result = r
            storage?.remove(self)
            if KernelLock.profileProcesses { wokenAt = KernelClock.now() }
            if KernelLock.wakeAfterUnlock, lock.isHeldByCurrentThread {
                lock.deferSignal(self)
            } else {
                pthread_cond_signal(cond)
            }
        }
    }

    final class Storage {
        var waiters: [Waiter] = []
        var bound: KernelLock?
        func remove(_ w: Waiter) { waiters.removeAll { $0 === w } }
    }

    fileprivate let storage = Storage()

    public init() {}

    public var count: Int { storage.waiters.count }
    public var isEmpty: Bool { storage.waiters.isEmpty }

    public var waitingContexts: [ThreadContext] { storage.waiters.compactMap(\.context) }

    public func wait(on lock: KernelLock, deadline: UInt64?) -> WaitResult {
        wait(on: lock, deadline: deadline, tag: 0, beforeSleeping: nil)
    }

    public func wait(on lock: KernelLock, deadline: UInt64?, tag: UInt64,
                     beforeSleeping: (() -> Void)?) -> WaitResult {
        if lock.isSplit { return splitWait(on: lock, deadline: deadline, tag: tag, beforeSleeping: beforeSleeping) }
        precondition(lock.isHeldByCurrentThread, "WaitQueue.wait needs the kernel lock")
        let context = lock.currentContext
        let w = Waiter(lock: lock, context: context, tag: tag)
        w.storage = storage
        if lock.isTerminated { return .interrupted }
        if let k = context?.kernel, k.isTerminating { return .interrupted }
        storage.waiters.append(w)
        lock.register(w)
        beforeSleeping?()
        if w.result == nil, let context {
            context.blockedInKernel = true
            lock.blockingObserver?(context, true)
            KernelTrace.blocking?(context, true)
        }
        while w.result == nil {
            if !lock.sleep(on: w.cond, deadline: deadline), w.result == nil {
                w.result = .timedOut
                storage.remove(w)
            }
        }
        lock.unregister(w)
        if w.wokenAt != 0, w.result == .woken { KernelLock.wakeLatency.add(KernelClock.now() &- w.wokenAt) }
        if let context, context.blockedInKernel {
            context.blockedInKernel = false
            lock.blockingObserver?(context, false)
            KernelTrace.blocking?(context, false)
        }
        return w.result!
    }

    @inline(__always) private func checkBound() {
        if KernelThreadLocks.checkOrder, let bound = storage.bound { bound.checkHeld("a wait queue") }
    }

    @discardableResult
    public func wake(count: Int) -> Int {
        checkBound()
        var n = 0
        while n < count, let w = storage.waiters.first {
            w.finish(.woken)
            n += 1
        }
        return n
    }

    @discardableResult
    public func wakeAll() -> Int { wake(count: Int.max) }

    @discardableResult
    public func wake(limit: Int = Int.max, where match: (ThreadContext?, UInt64) -> Bool) -> Int {
        checkBound()
        var n = 0
        for w in storage.waiters where n < limit && match(w.context, w.tag) {
            w.finish(.woken)
            n += 1
        }
        return n
    }

    public func contains(_ context: ThreadContext) -> Bool {
        storage.waiters.contains { $0.context === context }
    }
}

struct WeakKernelLock {
    weak var lock: KernelLock?
    init(_ lock: KernelLock) { self.lock = lock }
}

public struct DeferredKernelWork {
    enum Need {
        case kernelLock(KernelLock)
        case fineLock(KernelLock)
    }

    let need: Need
    let run: () -> Void
}

public final class KernelThreadLocks {
    var held: [KernelLock] = []
    fileprivate var fastDepth = 0
    var bsdFast = false
    var context: ThreadContext?
    var deferred: [DeferredKernelWork] = []
    var prefetchedSend: (va: UInt64, bytes: [UInt8])?
    var deferReceiveWrite = false
    var pendingReceiveWrite: (memory: any GuestVirtualMemory, va: UInt64, bytes: [UInt8])?
    var quiesced = false
    private var draining = false

    var isFast: Bool { fastDepth > 0 }

    nonisolated(unsafe) public static var checkOrder = getenv("SWIFTCODE_LOCK_ORDER_CHECK").map { String(cString: $0) == "1" } ?? false {
        didSet { LeafLockCheck.enabled = checkOrder }
    }

    @inline(__always) static func checkNoLeaf(_ lock: KernelLock) {
        guard LeafLockCheck.enabled, LeafLockCheck.depth > 0 else { return }
        FileHandle.standardError.write(Data(Thread.callStackSymbols.joined(separator: "\n").utf8))
        fatalError("kernel lock order: taking \(lock.name) while holding a leaf lock (bsd-locking.md §3)")
    }

    private static let key: pthread_key_t = {
        var key = pthread_key_t()
        pthread_key_create(&key) { raw in
            #if canImport(Darwin)
            Unmanaged<KernelThreadLocks>.fromOpaque(raw).release()
            #else
            if let raw { Unmanaged<KernelThreadLocks>.fromOpaque(raw).release() }
            #endif
        }
        return key
    }()

    public static var current: KernelThreadLocks {
        if let raw = pthread_getspecific(key) { return Unmanaged<KernelThreadLocks>.fromOpaque(raw).takeUnretainedValue() }
        let record = KernelThreadLocks()
        pthread_setspecific(key, Unmanaged.passRetained(record).toOpaque())
        return record
    }

    var highestLevel: Int { held.last?.level ?? -1 }

    func canAcquire(_ lock: KernelLock) -> Bool { highestLevel < lock.level }

    @inline(__always) func checkAcquire(_ lock: KernelLock) {
        Self.checkNoLeaf(lock)
        guard Self.checkOrder, !quiesced, !canAcquire(lock) else { return }
        FileHandle.standardError.write(Data(Thread.callStackSymbols.joined(separator: "\n").utf8))
        fatalError("kernel lock order: taking \(lock.name) (level \(lock.level)) while holding "
            + held.map { "\($0.name) (\($0.level))" }.joined(separator: ", ") + " (mach-ipc-locking.md §4.1)")
    }

    var inheritedContext: ThreadContext? {
        for lock in held.reversed() { if let c = lock.currentContext { return c } }
        return context
    }

    struct Saved {
        var locks: [(lock: KernelLock, depth: Int, context: ThreadContext?)] = []
    }

    func releaseAll() -> Saved { releaseAbove(nil) }

    func releaseAbove(_ lock: KernelLock?) -> Saved {
        var saved = Saved()
        while let top = held.last, top !== lock {
            saved.locks.append((top, top.depth, top.currentContext))
            top.releaseRaw()
            held.removeLast()
            if top.postedCount.load(ordering: .sequentiallyConsistent) > 0 { top.drainPosted(self) }
        }
        saved.locks.reverse()
        return saved
    }

    func reacquireAll(_ saved: Saved) {
        for entry in saved.locks {
            entry.lock.acquireRaw(depth: entry.depth, context: entry.context)
            held.append(entry.lock)
        }
    }

    private func satisfiable(_ need: DeferredKernelWork.Need) -> Bool {
        switch need {
        case let .kernelLock(l0): return l0.isHeldByCurrentThread ? held.last === l0 : held.isEmpty
        case let .fineLock(fine): return fine.isHeldByCurrentThread ? held.last === fine : canAcquire(fine)
        }
    }

    func runDeferredWork() {
        guard !draining, !deferred.isEmpty else { return }
        draining = true
        let savedDefer = deferReceiveWrite
        deferReceiveWrite = false
        defer {
            draining = false
            deferReceiveWrite = savedDefer
        }
        var progress = true
        while progress, !deferred.isEmpty {
            progress = false
            var keep: [DeferredKernelWork] = []
            let batch = deferred
            deferred = []
            for item in batch {
                guard satisfiable(item.need) else { keep.append(item); continue }
                progress = true
                switch item.need {
                case let .kernelLock(l0): l0.withLock { item.run() }
                case let .fineLock(fine): fine.runOrPost(item.run)
                }
            }
            deferred = keep + deferred
        }
    }
}

extension KernelLock {
    var name: String { root == nil ? "kernel lock (L0)" : (level == 2 ? "port lock (G)" : "event lock (L_P)") }

    func withSplitLock<T>(context: ThreadContext?, _ body: () throws -> T) rethrows -> T {
        let threadLocks = KernelThreadLocks.current
        threadLocks.checkAcquire(self)
        acquireRaw(depth: 1, context: context ?? threadLocks.inheritedContext)
        threadLocks.held.append(self)
        defer {
            if threadLocks.held.last === self { threadLocks.held.removeLast() } else {
                threadLocks.held.removeAll { $0 === self }
            }
            releaseRaw()
            if postedCount.load(ordering: .sequentiallyConsistent) > 0 { drainPosted(threadLocks) }
            if !threadLocks.deferred.isEmpty { threadLocks.runDeferredWork() }
        }
        return try body()
    }

    func runOrPost(_ work: @escaping () -> Void) {
        if isHeldByCurrentThread { work(); return }
        let threadLocks = KernelThreadLocks.current
        if tryWithLock(threadLocks, work) { return }
        postedMutex.lock()
        posted.append(work)
        postedCount.wrappingAdd(1, ordering: .sequentiallyConsistent)
        postedMutex.unlock()
        drainPosted(threadLocks)
    }

    private func tryWithLock(_ threadLocks: KernelThreadLocks, _ body: () -> Void) -> Bool {
        guard threadLocks.canAcquire(self), pthread_mutex_trylock(mutex) == 0 else { return false }
        owner.store(Self.threadToken, ordering: .relaxed)
        depth = 1
        currentContext = threadLocks.inheritedContext
        noteAcquired()
        threadLocks.held.append(self)
        body()
        threadLocks.held.removeLast()
        releaseRaw()
        if postedCount.load(ordering: .sequentiallyConsistent) > 0 { drainPosted(threadLocks) }
        if !threadLocks.deferred.isEmpty { threadLocks.runDeferredWork() }
        return true
    }

    fileprivate func drainPosted(_ threadLocks: KernelThreadLocks) {
        while postedCount.load(ordering: .sequentiallyConsistent) > 0 {
            guard threadLocks.canAcquire(self), pthread_mutex_trylock(mutex) == 0 else { return }
            owner.store(Self.threadToken, ordering: .relaxed)
            depth = 1
            currentContext = nil
            noteAcquired()
            threadLocks.held.append(self)
            while true {
                postedMutex.lock()
                let batch = posted
                posted = []
                postedCount.wrappingSubtract(batch.count, ordering: .sequentiallyConsistent)
                postedMutex.unlock()
                if batch.isEmpty { break }
                for work in batch { work() }
            }
            threadLocks.held.removeLast()
            releaseRaw()
        }
    }

    fileprivate func acquireRaw(depth newDepth: Int, context: ThreadContext?) {
        if root == nil {
            lockMutex(for: context)
        } else if pthread_mutex_trylock(mutex) != 0 {
            let start = KernelClock.now()
            if HostSched.promoting { lockPromoting(context) } else { pthread_mutex_lock(mutex) }
            let waited = KernelClock.now() &- start
            fineContended &+= 1
            fineWaitNanoseconds &+= waited
            trapProfile?.noteWait(TrapProfile.key(for: context), waited, contended: true)
            if let traced = KernelTrace.lockWaited { traced(Int32(level), waited) }
        } else if let trapProfile {
            trapProfile.noteWait(TrapProfile.key(for: context), 0, contended: false)
        }
        owner.store(Self.threadToken, ordering: .relaxed)
        depth = newDepth
        currentContext = context
        noteAcquired()
    }

    fileprivate func releaseRaw() {
        noteReleasing()
        currentContext = nil
        depth = 0
        owner.store(0, ordering: .relaxed)
        let wakes = takeDeferredWakes()
        pthread_mutex_unlock(mutex)
        Self.signal(wakes)
    }

    public func withoutFineLock<T>(_ body: () throws -> T) rethrows -> T {
        guard root != nil, isHeldByCurrentThread, depth == 1 else { return try body() }
        let threadLocks = KernelThreadLocks.current
        guard threadLocks.held.last === self else { return try body() }
        let context = currentContext
        threadLocks.held.removeLast()
        releaseRaw()
        defer {
            threadLocks.checkAcquire(self)
            acquireRaw(depth: 1, context: context)
            threadLocks.held.append(self)
        }
        return try body()
    }

    public func withFastPath<T>(context: ThreadContext?, _ body: () throws -> T) rethrows -> T {
        guard splitEnabled else { return try withLock(context: context, body) }
        let threadLocks = KernelThreadLocks.current
        precondition(threadLocks.held.isEmpty && threadLocks.fastDepth == 0,
                     "a fast path starts with no kernel lock held (mach-ipc-locking.md §4.3)")
        let savedContext = threadLocks.context
        threadLocks.fastDepth = 1
        threadLocks.context = context
        defer {
            threadLocks.runDeferredWork()
            threadLocks.fastDepth = 0
            threadLocks.context = savedContext
        }
        return try body()
    }

    func escalateToKernelLock<T>(_ body: () throws -> T) rethrows -> T? {
        guard let l0 = root, level == 1, !l0.isHeldByCurrentThread else { return nil }
        let threadLocks = KernelThreadLocks.current
        guard threadLocks.held.count == 1, threadLocks.held[0] === self else { return nil }
        let context = currentContext
        let saved = threadLocks.releaseAll()
        if !threadLocks.deferred.isEmpty { threadLocks.runDeferredWork() }
        defer { threadLocks.reacquireAll(saved) }
        KernelLock.escalations.wrappingAdd(1, ordering: .relaxed)
        return try l0.withLock(context: context) { () throws -> T in
            threadLocks.reacquireAll(saved)
            defer { _ = threadLocks.releaseAbove(l0) }
            return try body()
        }
    }

    static let escalations = Atomic<UInt64>(0)

    func deferIfFast(_ need: DeferredKernelWork.Need, tag: StaticString = "other", _ work: @escaping () -> Void) {
        guard isSplit else { work(); return }
        let threadLocks = KernelThreadLocks.current
        switch need {
        case let .kernelLock(l0):
            if l0.isHeldByCurrentThread { work(); return }
        case let .fineLock(fine):
            if fine.isHeldByCurrentThread { work(); return }
            if threadLocks.canAcquire(fine) { fine.runOrPost(work); return }
        }
        if case .kernelLock = need { Self.countDeferredL0(tag) }
        threadLocks.deferred.append(DeferredKernelWork(need: need, run: work))
    }

    static let deferredL0 = Mutex<[String: UInt64]>([:])
    static func countDeferredL0(_ tag: StaticString) {
        deferredL0.withLock { $0["\(tag)", default: 0] &+= 1 }
    }

    var callerContext: ThreadContext? {
        if !isSplit || isHeldByCurrentThread { return currentContext }
        return KernelThreadLocks.current.inheritedContext
    }

    var callerIsFast: Bool {
        guard let l0 = splitRoot else { return false }
        return !l0.isHeldByCurrentThread
    }

    @inline(__always) func checkHeld(_ what: @autoclosure () -> String) {
        guard KernelThreadLocks.checkOrder, isSplit, !isHeldByCurrentThread else { return }
        if KernelThreadLocks.current.quiesced { return }
        FileHandle.standardError.write(Data(Thread.callStackSymbols.joined(separator: "\n").utf8))
        fatalError("\(what()) touched without \(name) (mach-ipc-locking.md §4.2)")
    }

    public var splitReport: String {
        guard splitEnabled else { return "" }
        var parts = ["IPC fast traps: \(DarwinKernel.ipcFastServed.load(ordering: .relaxed)) served, "
            + "\(DarwinKernel.ipcFastDeclined.load(ordering: .relaxed)) fell back (descriptor knotes "
            + "\(DarwinKernel.ipcFastDeclinedDescriptors.load(ordering: .relaxed)), call "
            + "\(DarwinKernel.ipcFastDeclinedCall.load(ordering: .relaxed)), kernel object "
            + "\(DarwinKernel.ipcFastDeclinedKernelObject.load(ordering: .relaxed))); port routines without L0 "
            + "\(DarwinKernel.portRoutineFastServed.load(ordering: .relaxed)); proc_info reads without L0 "
            + "\(DarwinKernel.procInfoReadFast.load(ordering: .relaxed))"]
        var events = (held: UInt64(0), acq: UInt64(0), cont: UInt64(0), wait: UInt64(0), n: 0)
        for lock in liveFineLocks {
            if lock.level == 2 {
                parts.append("port lock: held \(lock.totalHeldNanoseconds / 1_000_000) ms, \(lock.acquisitions) acquisitions, "
                    + "\(lock.fineContended) contended, \(lock.fineWaitNanoseconds / 1_000_000) ms waited")
            } else {
                events.held &+= lock.totalHeldNanoseconds
                events.acq &+= lock.acquisitions
                events.cont &+= lock.fineContended
                events.wait &+= lock.fineWaitNanoseconds
                events.n += 1
            }
        }
        parts.append("BSD fast traps: \(DarwinKernel.bsdFastServed.load(ordering: .relaxed)) served, "
            + "\(DarwinKernel.bsdFastDeclined.load(ordering: .relaxed)) fell back, "
            + "\(DarwinKernel.bsdFastCloseHooks.load(ordering: .relaxed)) closes ran the hook under L0 ("
            + "\(DarwinKernel.bsdFastCloseHooksWatched.load(ordering: .relaxed)) for knotes)")
        parts.append(DarwinKernel.bsdDeclineReport)
        parts.append("escalations from an event lock to L0 (descriptor readiness): \(KernelLock.escalations.load(ordering: .relaxed))")
        if DarwinKernel.debugDescriptorCandidates { parts.append(DarwinKernel.descriptorDeclineReport) }
        parts.append("work deferred to L0: " + KernelLock.deferredL0.withLock { $0 }.sorted { $0.value > $1.value }
            .map { "\($0.key) \($0.value)" }.joined(separator: ", "))
        parts.append("event locks (\(events.n) live): held \(events.held / 1_000_000) ms, \(events.acq) acquisitions, "
            + "\(events.cont) contended, \(events.wait / 1_000_000) ms waited")
        return parts.joined(separator: "; ")
    }
}

extension WaitQueue {
    fileprivate func splitWait(on lock: KernelLock, deadline: UInt64?, tag: UInt64,
                               beforeSleeping: (() -> Void)?) -> WaitResult {
        let threadLocks = KernelThreadLocks.current
        let root = lock.splitRoot!
        var took = false
        if !lock.isHeldByCurrentThread {
            precondition(lock.root != nil, "WaitQueue.wait needs the kernel lock")
            threadLocks.checkAcquire(lock)
            lock.acquireRaw(depth: 1, context: threadLocks.inheritedContext)
            threadLocks.held.append(lock)
            took = true
        }
        defer {
            if took {
                threadLocks.held.removeAll { $0 === lock }
                lock.releaseRaw()
            }
        }
        precondition(lock.depth == 1, "WaitQueue.wait inside a nested withLock")
        storage.bound = lock
        let context = lock.currentContext
        let w = Waiter(lock: lock, context: context, tag: tag)
        w.storage = storage
        if Waiter.recordStacks { w.debugStack = Thread.callStackSymbols }
        if root.isTerminated { return .interrupted }
        if let k = context?.kernel, k.isTerminating { return .interrupted }
        storage.waiters.append(w)
        lock.register(w)
        beforeSleeping?()
        if w.result == nil, let context {
            context.blockedInKernel = true
            root.blockingObserver?(context, true)
            KernelTrace.blocking?(context, true)
        }
        if lock === root {
            let above = threadLocks.releaseAbove(lock)
            while w.result == nil {
                if !lock.sleep(on: w.cond, deadline: deadline) { break }
            }
            threadLocks.reacquireAll(above)
        } else {
            let saved = threadLocks.releaseAll()
            if !threadLocks.deferred.isEmpty { threadLocks.runDeferredWork() }
            pthread_mutex_lock(lock.mutex)
            while w.result == nil {
                if KernelLock.conditionWait(w.cond, lock.mutex, deadline: deadline) == ETIMEDOUT { break }
            }
            pthread_mutex_unlock(lock.mutex)
            threadLocks.reacquireAll(saved)
        }
        if w.result == nil {
            w.result = .timedOut
            storage.remove(w)
        }
        lock.unregister(w)
        if w.wokenAt != 0, w.result == .woken { KernelLock.wakeLatency.add(KernelClock.now() &- w.wokenAt) }
        if let context, context.blockedInKernel {
            context.blockedInKernel = false
            root.blockingObserver?(context, false)
            KernelTrace.blocking?(context, false)
        }
        return w.result!
    }
}
