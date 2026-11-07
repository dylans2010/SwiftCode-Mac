import Foundation
import YcodeDarwinABI

public enum PthreadPriority {
    public static let overcommit: UInt32 = 0x8000_0000
    public static let schedPri: UInt32 = 0x2000_0000
    public static let cooperative: UInt32 = 0x0800_0000
    public static let eventManager: UInt32 = 0x0200_0000
    public static let needsUnbind: UInt32 = 0x0100_0000

    public static func qos(_ pp: UInt32) -> Int? {
        guard pp & (schedPri | eventManager) == 0 else { return nil }
        let bits = (pp >> 8) & 0x3F
        guard bits != 0 else { return nil }
        return bits.trailingZeroBitCount + 1
    }

    public static func relativePriority(_ pp: UInt32) -> Int { Int(Int8(bitPattern: UInt8(pp & 0xFF))) + 1 }

    public static func make(qos: Int, relpri: Int = 0) -> UInt32 {
        UInt32(1 << (8 + qos - 1)) | UInt32(UInt8(bitPattern: Int8(relpri - 1)))
    }
}

enum WorkRequest {
    case plain(qos: Int, overcommit: Bool, cooperative: Bool = false)
    case bucket(Int)
    case workloop(KQueue)

    var traceTarget: String {
        switch self {
        case .plain: ""
        case let .bucket(b): ", bucket \(b)"
        case let .workloop(wl): ", workloop \(hx(wl.workloopID))"
        }
    }

    var qos: Int {
        switch self {
        case let .plain(q, _, _): q
        case let .bucket(b): b
        case let .workloop(wl): wl.requestQoS
        }
    }
}

final class WorkerState {
    enum Phase { case running, idle, exiting }

    let base: UInt64
    var phase = Phase.running
    var firstRun = true
    var qos = 4
    var constrained = false
    var cooperative = false
    var assignment: WorkRequest?
    var boundQueue: KQueue?
    var boundBucket: Int?
    var keventRun = false
    var delivered: [Knote] = []
    let park = WaitQueue()

    init(base: UInt64) { self.base = base }

    static let allocationSize: UInt64 = 560 << 10
    var selfAddress: UInt64 { base + (540 << 10) }
    var stackBottom: UInt64 { base + (16 << 10) }
    var eventList: UInt64 { selfAddress - 1152 }
}

struct WorkqueueState {
    var isOpen = false
    var dispatchConfig: (version: UInt32, serialOffset: UInt64, labelOffset: UInt64)?
    var newSPIOffset: UInt32 = 0
    var managerPriority: UInt32 = 0
    var workers: [UInt64: ThreadContext] = [:]
    var idle: [ThreadContext] = []
    var plainPending: [PlainKey: Int] = [:]
    var pendingWorkloops: [KQueue] = []
    var startFailureLogged = false

    struct PlainKey: Hashable {
        var qos: Int
        var overcommit: Bool
        var cooperative = false
    }

    static let parallelism = GuestCPUs.count
    static let cooperativeWidth = GuestCPUs.count
    static let maxThreads = 512
    static let maxConstrained = max(64, 5 * GuestCPUs.count)
    var idleTimeoutNanoseconds: UInt64 = 5_000_000_000
}

extension DarwinKernel {
    enum WorkqOp {
        static let threadReturn: UInt32 = 0x004
        static let newSPISupport: UInt32 = 0x010
        static let reqThreads: UInt32 = 0x020
        static let reqThreads2: UInt32 = 0x030
        static let keventReturn: UInt32 = 0x040
        static let setEventManagerPriority: UInt32 = 0x080
        static let workloopReturn: UInt32 = 0x100
        static let shouldNarrow: UInt32 = 0x200
        static let setupDispatch: UInt32 = 0x400
    }

    public enum WorkqUpcall {
        public static let prioQoS: UInt64 = 0x0000_4000
        public static let prioSched: UInt64 = 0x0000_8000
        public static let overcommit: UInt64 = 0x0001_0000
        public static let reuse: UInt64 = 0x0002_0000
        public static let newSPI: UInt64 = 0x0004_0000
        public static let kevent: UInt64 = 0x0008_0000
        public static let eventManager: UInt64 = 0x0010_0000
        public static let tsdBaseSet: UInt64 = 0x0020_0000
        public static let workloop: UInt64 = 0x0040_0000
        public static let outsideQoS: UInt64 = 0x0080_0000
        public static let cooperative: UInt64 = 0x0100_0000
    }

    static let managerQoS = 8

    public var workqueueThreads: [ThreadContext] {
        lock.withLock { withEvents { workqueue.workers.values.sorted { $0.threadID < $1.threadID } } }
    }

    public var idleWorkqueueThreads: [ThreadContext] { lock.withLock { withEvents { workqueue.idle } } }

    func workqKernreturn(_ a: [UInt64], _ call: inout CallText, _ mem: any KernelGuestMemory) throws -> BSDResult {
        let op = UInt32(truncatingIfNeeded: a[0])
        let arg2 = Int32(truncatingIfNeeded: a[2]), arg3 = UInt32(truncatingIfNeeded: a[3])
        let names: [UInt32: String] = !call.enabled ? [:] : [0x004: "THREAD_RETURN", 0x010: "QUEUE_NEWSPISUPP", 0x020: "QUEUE_REQTHREADS",
                                       0x030: "QUEUE_REQTHREADS2", 0x040: "THREAD_KEVENT_RETURN",
                                       0x080: "SET_EVENT_MANAGER_PRIORITY", 0x100: "THREAD_WORKLOOP_RETURN",
                                       0x200: "SHOULD_NARROW", 0x400: "SETUP_DISPATCH"]
        call.set("workq_kernreturn(\(names[op] ?? hx(op)), item=\(hx(a[1])), arg2=\(arg2), arg3=\(hx(arg3)))")
        guard threadRegistration != nil else { throw Failure(errno: Errno.EINVAL) }
        switch op {
        case WorkqOp.setupDispatch:
            let size = Int(min(UInt64(UInt32(truncatingIfNeeded: a[2])), 24))
            guard size >= 8 else { throw Failure(errno: Errno.EINVAL) }
            var b = try mem.read(va: a[1], count: size)
            b += [UInt8](repeating: 0, count: 24 - size)
            let version = b.readLE(UInt32.self, at: 0), flags = b.readLE(UInt32.self, at: 4)
            guard flags == 0, version >= 1 else { throw Failure(errno: Errno.ENOTSUP) }
            workqueue.dispatchConfig = (version, b.readLE(UInt64.self, at: 8), version >= 2 ? b.readLE(UInt64.self, at: 16) : 0)
            return .value(0)

        case WorkqOp.newSPISupport:
            workqueue.newSPIOffset = UInt32(bitPattern: arg2)
            return .value(0)

        case WorkqOp.reqThreads:
            guard workqueue.isOpen, arg2 > 0, arg2 <= 65535, let qos = PthreadPriority.qos(arg3) else {
                throw Failure(errno: Errno.EINVAL)
            }
            let key = WorkqueueState.PlainKey(qos: qos, overcommit: arg3 & PthreadPriority.overcommit != 0)
            workqueue.plainPending[key, default: 0] += Int(arg2)
            call += " [qos \(qos)\(key.overcommit ? " overcommit" : ""), \(workqueue.plainPending[key]!) pending]"
            pumpWorkqueue(mem)
            return .value(0)

        case WorkqOp.reqThreads2:
            guard workqueue.isOpen, arg2 > 0, arg2 <= 65535, let qos = PthreadPriority.qos(arg3),
                  arg3 & PthreadPriority.overcommit == 0 else { throw Failure(errno: Errno.EINVAL) }
            guard arg2 == 1 else { throw Failure(errno: Errno.ENOTSUP) }
            let key = WorkqueueState.PlainKey(qos: qos, overcommit: false, cooperative: true)
            workqueue.plainPending[key, default: 0] += 1
            if call.enabled { call += " [qos \(qos) cooperative, \(workqueue.plainPending[key]!) pending]" }
            pumpWorkqueue(mem)
            return .value(0)

        case WorkqOp.setEventManagerPriority:
            guard workqueue.isOpen else { throw Failure(errno: Errno.EINVAL) }
            let pp: UInt32
            if arg3 == 0, UInt32(bitPattern: arg2) & PthreadPriority.schedPri != 0 {
                pp = UInt32(bitPattern: arg2) & (PthreadPriority.schedPri | 0xFFFF)
            } else {
                let v = UInt32(bitPattern: arg2)
                if v & PthreadPriority.schedPri != 0 {
                    pp = v & (PthreadPriority.schedPri | 0xFFFF)
                } else {
                    guard let qos = PthreadPriority.qos(v), (-15...0).contains(PthreadPriority.relativePriority(v)) else {
                        throw Failure(errno: Errno.EINVAL)
                    }
                    pp = PthreadPriority.make(qos: qos, relpri: PthreadPriority.relativePriority(v))
                }
            }
            workqueue.managerPriority = max(workqueue.managerPriority, pp)
            return .value(0)

        case WorkqOp.shouldNarrow:
            let ctx = current
            guard let w = ctx.worker, w.constrained, w.phase == .running, PthreadPriority.qos(UInt32(bitPattern: arg2)) != nil else {
                throw Failure(errno: Errno.EINVAL)
            }
            return .value(0)

        case WorkqOp.threadReturn, WorkqOp.keventReturn, WorkqOp.workloopReturn:
            return try workerReturn(op: op, changes: a[1], count: Int(arg2), &call, mem)

        default:
            throw Failure(errno: Errno.EINVAL)
        }
    }

    private func constrainedRoom(qos: Int) -> Bool {
        var running = 0, scheduled = 0
        for t in workqueue.workers.values {
            guard let w = t.worker, w.constrained, w.phase == .running else { continue }
            scheduled += 1
            if !t.blockedInKernel && w.qos == qos { running += 1 }
        }
        return running < WorkqueueState.parallelism && scheduled < WorkqueueState.maxConstrained
    }

    private func cooperativeRoom(qos: Int) -> Bool {
        var total = 0, atQoS = 0
        for t in workqueue.workers.values {
            guard let w = t.worker, w.cooperative, w.phase == .running else { continue }
            total += 1
            if w.qos == qos { atQoS += 1 }
        }
        return total < WorkqueueState.cooperativeWidth || atQoS == 0
    }

    private var managerBound: Bool {
        kevents.workq?.buckets[Self.managerQoS]?.boundWorker != nil
    }

    func takeWorkRequest() -> WorkRequest? {
        var best: (qos: Int, rank: Int, request: WorkRequest)?
        func consider(_ r: WorkRequest, rank: Int) {
            if best == nil || r.qos > best!.qos || (r.qos == best!.qos && rank > best!.rank) { best = (r.qos, rank, r) }
        }
        if let kq = kevents.workq {
            for (b, state) in kq.buckets where state.requested && state.boundWorker == nil {
                if b == Self.managerQoS && managerBound { continue }
                consider(.bucket(b), rank: 3)
            }
        }
        for wl in workqueue.pendingWorkloops { consider(.workloop(wl), rank: 2) }
        for (key, n) in workqueue.plainPending where n > 0 {
            if key.overcommit { consider(.plain(qos: key.qos, overcommit: true), rank: 1) }
            else if key.cooperative {
                if cooperativeRoom(qos: key.qos) { consider(.plain(qos: key.qos, overcommit: false, cooperative: true), rank: 0) }
            } else if constrainedRoom(qos: key.qos) { consider(.plain(qos: key.qos, overcommit: false), rank: 0) }
        }
        guard let chosen = best?.request else { return nil }
        switch chosen {
        case let .plain(qos, overcommit, cooperative):
            let key = WorkqueueState.PlainKey(qos: qos, overcommit: overcommit, cooperative: cooperative)
            workqueue.plainPending[key]! -= 1
            if workqueue.plainPending[key] == 0 { workqueue.plainPending[key] = nil }
        case let .bucket(b):
            kevents.workq!.buckets[b]!.requested = false
        case let .workloop(wl):
            workqueue.pendingWorkloops.removeAll { $0 === wl }
            wl.requested = false
            wl.logRequest(.taken)
        }
        return chosen
    }

    func returnWorkRequest(_ r: WorkRequest) {
        switch r {
        case let .plain(qos, overcommit, cooperative):
            workqueue.plainPending[.init(qos: qos, overcommit: overcommit, cooperative: cooperative), default: 0] += 1
        case let .bucket(b):
            kevents.workq?.buckets[b]?.requested = true
        case let .workloop(wl):
            if !wl.requested {
                wl.requested = true
                workqueue.pendingWorkloops.append(wl)
            }
            wl.logRequest(.returned)
        }
    }

    public func retryPendingWorkqueue() {
        lock.withLock { withEvents {
            guard termination == nil, !workqueue.plainPending.isEmpty || !workqueue.pendingWorkloops.isEmpty
                || (kevents.workq?.buckets.values.contains { $0.requested && $0.boundWorker == nil } ?? false) else { return }
            pumpWorkqueue(nil)
        } }
    }

    func pumpWorkqueue(_ mem: (any KernelGuestMemory)?) {
        eventLock?.checkHeld("the workqueue")
        guard threadRegistration != nil else { return }
        while let request = takeWorkRequest() {
            if let worker = workqueue.idle.popLast(), let w = worker.worker {
                w.assignment = request
                w.phase = .running
                setWorkerQoS(w, for: request, ctx: worker)
                switch request {
                case let .bucket(b): if let kq = kevents.workq { bindWorker(worker, to: kq, bucket: b) }
                case let .workloop(wl): bindWorker(worker, to: wl, bucket: nil)
                case .plain: break
                }
                w.park.wake(count: 1)
                continue
            }
            guard let mem = mem ?? lastMemory else { returnWorkRequest(request); return }
            if lock.callerIsFast {
                returnWorkRequest(request)
                lock.deferIfFast(.kernelLock(lock), tag: "new workqueue thread") { [weak self] in self?.retryPendingWorkqueue() }
                return
            }
            guard workqueue.workers.count < WorkqueueState.maxThreads, threadHost != nil else {
                returnWorkRequest(request)
                if !workqueue.startFailureLogged {
                    workqueue.startFailureLogged = true
                    trace("note: workqueue request pending: \(threadHost == nil ? "no thread host" : "512 workers exist")")
                }
                return
            }
            if !startNewWorker(for: request, mem) { return }
        }
    }

    private func setWorkerQoS(_ w: WorkerState, for request: WorkRequest, ctx: ThreadContext) {
        w.qos = request.qos
        if SchedPolicy.qosEnabled {
            ctx.requestedQoS = 0
            ctx.dispatchOverrideQoS = 0
            ctx.removeAllExplicitOverrides()
            refreshSchedClass(ctx)
        }
        if case let .plain(_, overcommit, cooperative) = request {
            w.constrained = !overcommit && !cooperative
            w.cooperative = cooperative
        } else {
            w.constrained = false
            w.cooperative = false
        }
    }

    private func startNewWorker(for request: WorkRequest, _ mem: any KernelGuestMemory) -> Bool {
        guard threadHost?.canStartThread ?? false else {
            returnWorkRequest(request)
            if !workqueue.startFailureLogged {
                workqueue.startFailureLogged = true
                trace("note: workqueue: no free vCPU for a new worker; request pending")
            }
            return false
        }
        let base: UInt64
        do {
            base = try mem.mapAnonymous(at: nil, size: WorkerState.allocationSize, protection: [.read, .write],
                                        hint: mainStackTop & ~Self.pageMask)
            try mem.protect(va: base, size: Self.pageSize, protection: [])
        } catch {
            returnWorkRequest(request)
            trace("note: workqueue: no memory for a new worker (\(error))")
            return false
        }
        let w = WorkerState(base: base)
        let ctx = makeThread(kind: .workqueue, pthread: w.selfAddress)
        ctx.worker = w
        setWorkerQoS(w, for: request, ctx: ctx)
        workqueue.workers[ctx.threadID] = ctx
        guard let start = upcall(for: request, worker: ctx, mem) else {
            discardUnstartedWorker(ctx, mem)
            return true
        }
        do {
            ctx.vcpuIndex = try threadHost!.startThread(start, context: ctx)
            w.firstRun = false
            workqueue.startFailureLogged = false
            trace("note: workqueue: started \(ctx) for qos \(request.qos)")
            return true
        } catch {
            unbindWorker(ctx, release: true)
            returnWorkRequest(request)
            discardUnstartedWorker(ctx, mem)
            if !workqueue.startFailureLogged {
                workqueue.startFailureLogged = true
                trace("note: workqueue: cannot start a worker (\(error)); request pending")
            }
            return false
        }
    }

    private func discardUnstartedWorker(_ ctx: ThreadContext, _ mem: any KernelGuestMemory) {
        workqueue.workers[ctx.threadID] = nil
        threadsByPort[ctx.portName] = nil
        ctx.isAlive = false
        deallocateThreadPort(ctx.portName)
        if let w = ctx.worker { try? mem.unmap(va: w.base, size: WorkerState.allocationSize) }
    }

    func upcall(for request: WorkRequest, worker ctx: ThreadContext, _ mem: any KernelGuestMemory) -> ThreadStartState? {
        guard let w = ctx.worker, let reg = threadRegistration else { return nil }
        var flags = WorkqUpcall.newSPI
        var events: [UInt8] = []
        var count = 0
        var used: UInt64 = 0
        w.keventRun = false
        switch request {
        case let .plain(qos, overcommit, cooperative):
            flags |= WorkqUpcall.prioQoS | UInt64(qos)
            if overcommit { flags |= WorkqUpcall.overcommit }
            if cooperative { flags |= WorkqUpcall.cooperative }
        case let .bucket(b):
            guard let kq = kevents.workq else { return nil }
            flags |= WorkqUpcall.kevent | WorkqUpcall.prioQoS | UInt64(b)
            flags |= b == Self.managerQoS ? WorkqUpcall.eventManager : WorkqUpcall.overcommit
            bindWorker(ctx, to: kq, bucket: b)
        case let .workloop(wl):
            flags |= WorkqUpcall.kevent | WorkqUpcall.workloop
            flags |= wl.fixedPriority ? WorkqUpcall.outsideQoS : WorkqUpcall.prioQoS | UInt64(wl.requestQoS)
            if wl.requestOvercommit { flags |= WorkqUpcall.overcommit }
            bindWorker(ctx, to: wl, bucket: nil)
            used = 8
        }
        if let kq = w.boundQueue {
            w.keventRun = true
            var area = KEventDataArea(base: w.eventList - 32768, size: 32768 - used, stackData: true)
            let delivered = scanForDelivery(kq, bucket: w.boundBucket, max: 16, area: &area, context: ctx, mem)
            if delivered.isEmpty {
                unbindWorker(ctx, release: true)
                return nil
            }
            count = delivered.count
            for e in delivered { events += e.encoded(.qos) }
            used = w.eventList - (area.base + area.size)
            if case let .workloop(wl) = request { try? writeU64(w.eventList - 8, wl.workloopID, mem) }
            try? mem.write(va: w.eventList, bytes: events)
        }
        if w.firstRun {
            if reg.tsdOffset != 0 { flags |= WorkqUpcall.tsdBaseSet }
        } else {
            flags |= WorkqUpcall.reuse
        }
        let keventFlag = flags & WorkqUpcall.kevent != 0
        let sp = keventFlag ? (w.eventList - used) & ~15 : w.selfAddress & ~15
        let tsd = reg.tsdOffset != 0 ? UInt64(reg.tsdOffset) : 224
        return ThreadStartState(
            x: [w.selfAddress, UInt64(ctx.portName), w.stackBottom, keventFlag ? w.eventList : 0, flags,
                keventFlag ? UInt64(count) : 0],
            pc: reg.startWorkqueueThread, sp: sp, tpidrro: w.selfAddress + tsd)
    }

    func exitUpcall(worker ctx: ThreadContext) -> ThreadStartState? {
        guard let w = ctx.worker, let reg = threadRegistration else { return nil }
        let flags = WorkqUpcall.newSPI | WorkqUpcall.prioQoS | UInt64(min(w.qos, 4)) | WorkqUpcall.reuse
        let tsd = reg.tsdOffset != 0 ? UInt64(reg.tsdOffset) : 224
        return ThreadStartState(x: [w.selfAddress, UInt64(ctx.portName), w.stackBottom, 0, flags, UInt64.max],
                                pc: reg.startWorkqueueThread, sp: w.selfAddress & ~15, tpidrro: w.selfAddress + tsd)
    }

    func bindWorker(_ ctx: ThreadContext, to kq: KQueue, bucket: Int?) {
        guard let w = ctx.worker else { return }
        w.boundQueue = kq
        w.boundBucket = bucket
        if bucket == nil, let other = kq.servicer, other !== ctx {
            trace("note: workloop \(hx(kq.workloopID)) bound to thread \(ctx.threadID) while thread \(other.threadID) services it")
        }
        if let bucket { kq.buckets[bucket, default: .init()].boundWorker = ctx } else {
            kq.servicer = ctx
            kq.logRequest(.bound, thread: ctx.threadID)
        }
    }

    func unbindWorker(_ ctx: ThreadContext, release: Bool) {
        guard let w = ctx.worker else { return }
        let released = release ? releaseDelivered(w) : []
        guard let kq = w.boundQueue else {
            reevaluateReleased(released)
            return
        }
        if let b = w.boundBucket {
            if kq.buckets[b]?.boundWorker === ctx { kq.buckets[b]?.boundWorker = nil }
        } else if kq.servicer === ctx {
            kq.servicer = nil
            kq.logRequest(.unbound, thread: ctx.threadID)
        }
        w.boundQueue = nil
        let bucket = w.boundBucket
        w.boundBucket = nil
        reevaluateRequests(kq, bucket: bucket)
        for (q, b) in released where !(q === kq && b == bucket) { reevaluateRequests(q, bucket: b) }
    }

    @discardableResult
    func releaseDelivered(_ w: WorkerState) -> [(KQueue, Int?)] {
        var out: [(KQueue, Int?)] = []
        for k in w.delivered {
            k.suppressed = false
            k.note("released (servicer returned)")
            if let q = k.kq, !out.contains(where: { $0.0 === q && $0.1 == (q.kind == .workq ? k.bucket : nil) }) {
                out.append((q, q.kind == .workq ? k.bucket : nil))
            }
        }
        w.delivered.removeAll()
        return out
    }

    func reevaluateReleased(_ released: [(KQueue, Int?)]) {
        for (q, b) in released { reevaluateRequests(q, bucket: b) }
    }

    static let returnEventCapacity = 16

    private func workerReturn(op: UInt32, changes: UInt64, count: Int, _ call: inout CallText,
                              _ mem: any KernelGuestMemory) throws -> BSDResult {
        let ctx = current
        guard ctx.kind == .workqueue, let w = ctx.worker, w.phase == .running else { throw Failure(errno: Errno.EINVAL) }
        if ctx.carriedImportance != nil || ctx.ipcPushClass >= 0 {
            if let ports = system.mach.portLock {
                ports.withLock { endServicing(ctx) }
            } else {
                endServicing(ctx)
            }
        }
        var errors: [KEventRecord] = []
        if op != WorkqOp.threadReturn {
            guard count >= 0, count == 0 || w.keventRun else { throw Failure(errno: Errno.EINVAL) }
            if count > 0, let kq = w.boundQueue ?? (op == WorkqOp.keventReturn ? kevents.workq : nil) {
                let list = try readKEvents(changes, count: count, format: .qos, mem)
                if let e = applyChanges(list, to: kq, outputCapacity: Self.returnEventCapacity, output: &errors, context: ctx,
                                        flags: KEventFlag.stackData | KEventFlag.immediate, mem) {
                    throw Failure(errno: e)
                }
                if !errors.isEmpty {
                    call += " [\(errors.count) change errors: " + errors.map { "filter \($0.filter) ident \(hx($0.ident)) errno \($0.data)" }.joined(separator: ", ") + "]"
                }
            }
            let released = releaseDelivered(w)
            if w.boundQueue == nil { reevaluateReleased(released) }
            if let kq = w.boundQueue {
                var area = KEventDataArea(base: w.eventList - 32768, size: 32768 - (w.boundBucket == nil ? 8 : 0),
                                          stackData: true)
                let room = Self.returnEventCapacity - errors.count
                let again = errors + (room > 0 ? scanForDelivery(kq, bucket: w.boundBucket, max: room, area: &area, context: ctx, mem) : [])
                if !again.isEmpty {
                    var flags = WorkqUpcall.newSPI | WorkqUpcall.kevent | WorkqUpcall.reuse
                    if let b = w.boundBucket {
                        flags |= WorkqUpcall.prioQoS | UInt64(b)
                        flags |= b == Self.managerQoS ? WorkqUpcall.eventManager : WorkqUpcall.overcommit
                    } else {
                        flags |= WorkqUpcall.workloop
                        flags |= kq.fixedPriority ? WorkqUpcall.outsideQoS : WorkqUpcall.prioQoS | UInt64(w.qos)
                        if kq.requestOvercommit { flags |= WorkqUpcall.overcommit }
                        try? writeU64(w.eventList - 8, kq.workloopID, mem)
                    }
                    var bytes: [UInt8] = []
                    for e in again { bytes += e.encoded(.qos) }
                    try mem.write(va: w.eventList, bytes: bytes)
                    let used = w.eventList - (area.base + area.size)
                    let reg = threadRegistration!
                    let tsd = reg.tsdOffset != 0 ? UInt64(reg.tsdOffset) : 224
                    call += " [\(again.count) more events]"
                    return .restart(ThreadStartState(
                        x: [w.selfAddress, UInt64(ctx.portName), w.stackBottom, w.eventList, flags, UInt64(again.count)],
                        pc: reg.startWorkqueueThread, sp: (w.eventList - used) & ~15, tpidrro: w.selfAddress + tsd))
                }
            }
        }
        unbindWorker(ctx, release: true)
        w.keventRun = false
        ctx.signalMask = Self.workqueueSignalMask
        w.constrained = false
        w.cooperative = false
        while true {
            if let request = takeWorkRequest() {
                setWorkerQoS(w, for: request, ctx: ctx)
                if let start = upcall(for: request, worker: ctx, mem) {
                    call += " [next: qos \(request.qos)\(request.traceTarget)]"
                    return .restart(start)
                }
                continue
            }
            w.phase = .idle
            w.constrained = false
            w.cooperative = false
            workqueue.idle.append(ctx)
            pumpWorkqueue(mem)
            let result = w.park.wait(on: eventWaitLock, deadline: KernelClock.deadline(afterNanoseconds: workqueue.idleTimeoutNanoseconds))
            if let request = w.assignment {
                w.assignment = nil
                w.phase = .running
                if let start = upcall(for: request, worker: ctx, mem) {
                    call += " [parked, then qos \(request.qos)\(request.traceTarget)]"
                    return .restart(start)
                }
                continue
            }
            workqueue.idle.removeAll { $0 === ctx }
            if result == .interrupted { return .value(0) }
            w.phase = .exiting
            call += " [idle 5 s: exit]"
            if let start = exitUpcall(worker: ctx) { return .restart(start) }
            return .value(0)
        }
    }

    static let workqueueSignalMask: UInt32 = {
        let open: [UInt32] = [4, 5, 7, 8, 10, 11, 12, 13, 9, 17, 27]
        return open.reduce(UInt32.max) { $0 & ~(1 << ($1 - 1)) }
    }()

    func workqueueThreadTerminating(_ ctx: ThreadContext) {
        ctx.worker?.cooperative = false
        unbindWorker(ctx, release: true)
        workqueue.idle.removeAll { $0 === ctx }
        workqueue.workers[ctx.threadID] = nil
        ctx.worker?.phase = .exiting
    }

    func threadBlockingChanged(_ ctx: ThreadContext, blocking: Bool) {
        guard blocking, let w0 = ctx.worker, w0.constrained else { return }
        let pump = { [weak self] in
            guard let self, let w = ctx.worker, w.phase == .running, w.constrained else { return }
            pumpWorkqueue(nil)
        }
        if let events = eventLock { lock.deferIfFast(.fineLock(events), pump) } else { pump() }
    }
}
