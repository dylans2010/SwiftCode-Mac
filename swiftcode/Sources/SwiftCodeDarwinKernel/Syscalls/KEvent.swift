import Foundation
import Synchronization
import SwiftCodeDarwinABI

enum KEventFormat {
    case legacy
    case k64
    case qos

    var size: Int {
        switch self {
        case .legacy: 32
        case .k64: 48
        case .qos: 72
        }
    }
}

struct KEventRecord: Equatable {
    var ident: UInt64 = 0
    var filter: Int16 = 0
    var flags: UInt16 = 0
    var fflags: UInt32 = 0
    var data: Int64 = 0
    var udata: UInt64 = 0
    var qos: UInt32 = 0
    var xflags: UInt32 = 0
    var ext: [UInt64] = [0, 0, 0, 0]

    init(ident: UInt64 = 0, filter: Int16 = 0, flags: UInt16 = 0, fflags: UInt32 = 0, data: Int64 = 0,
         udata: UInt64 = 0, qos: UInt32 = 0, ext: [UInt64] = [0, 0, 0, 0]) {
        self.ident = ident
        self.filter = filter
        self.flags = flags
        self.fflags = fflags
        self.data = data
        self.udata = udata
        self.qos = qos
        self.ext = ext + [UInt64](repeating: 0, count: max(0, 4 - ext.count))
    }

    init(decoding b: [UInt8], at o: Int, format: KEventFormat) {
        ident = b.readLE(UInt64.self, at: o)
        filter = b.readLE(Int16.self, at: o + 8)
        flags = b.readLE(UInt16.self, at: o + 10)
        switch format {
        case .legacy:
            fflags = b.readLE(UInt32.self, at: o + 12)
            data = b.readLE(Int64.self, at: o + 16)
            udata = b.readLE(UInt64.self, at: o + 24)
        case .k64:
            fflags = b.readLE(UInt32.self, at: o + 12)
            data = b.readLE(Int64.self, at: o + 16)
            udata = b.readLE(UInt64.self, at: o + 24)
            ext[0] = b.readLE(UInt64.self, at: o + 32)
            ext[1] = b.readLE(UInt64.self, at: o + 40)
        case .qos:
            qos = b.readLE(UInt32.self, at: o + 12)
            udata = b.readLE(UInt64.self, at: o + 16)
            fflags = b.readLE(UInt32.self, at: o + 24)
            xflags = b.readLE(UInt32.self, at: o + 28)
            data = b.readLE(Int64.self, at: o + 32)
            for i in 0..<4 { ext[i] = b.readLE(UInt64.self, at: o + 40 + 8 * i) }
        }
    }

    func encoded(_ format: KEventFormat) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: format.size)
        b.putLE(ident, at: 0)
        b.putLE(filter, at: 8)
        b.putLE(flags, at: 10)
        switch format {
        case .legacy:
            b.putLE(fflags, at: 12)
            b.putLE(data, at: 16)
            b.putLE(udata, at: 24)
        case .k64:
            b.putLE(fflags, at: 12)
            b.putLE(data, at: 16)
            b.putLE(udata, at: 24)
            b.putLE(ext[0], at: 32)
            b.putLE(ext[1], at: 40)
        case .qos:
            b.putLE(qos, at: 12)
            b.putLE(udata, at: 16)
            b.putLE(fflags, at: 24)
            b.putLE(UInt32(0), at: 28)
            b.putLE(data, at: 32)
            for i in 0..<4 { b.putLE(ext[i], at: 40 + 8 * i) }
        }
        return b
    }
}

enum KEventFlag {
    static let immediate: UInt32 = 0x000001
    static let errorEvents: UInt32 = 0x000002
    static let stackData: UInt32 = 0x000008
    static let workq: UInt32 = 0x000020
    static let workloop: UInt32 = 0x000400
    static let parking: UInt32 = 0x000800
    static let dynamicKQMustExist: UInt32 = 0x020000
    static let dynamicKQMustNotExist: UInt32 = 0x040000
    static let userSet: UInt32 = immediate | errorEvents | stackData | workq | workloop | dynamicKQMustExist
        | dynamicKQMustNotExist
}

enum EV {
    static let add: UInt16 = 0x0001
    static let delete: UInt16 = 0x0002
    static let enable: UInt16 = 0x0004
    static let disable: UInt16 = 0x0008
    static let oneshot: UInt16 = 0x0010
    static let clear: UInt16 = 0x0020
    static let receipt: UInt16 = 0x0040
    static let dispatch: UInt16 = 0x0080
    static let udataSpecific: UInt16 = 0x0100
    static let dispatch2: UInt16 = 0x0180
    static let vanished: UInt16 = 0x0200
    static let sysFlags: UInt16 = 0xF000
    static let error: UInt16 = 0x4000
    static let eof: UInt16 = 0x8000
    static let actionBits: UInt16 = add | delete | enable | disable | receipt
}

enum EVFilter {
    static let read: Int16 = -1, write: Int16 = -2, aio: Int16 = -3, vnode: Int16 = -4, proc: Int16 = -5,
               signal: Int16 = -6, timer: Int16 = -7, machport: Int16 = -8, fs: Int16 = -9, user: Int16 = -10,
               vm: Int16 = -12, sock: Int16 = -13, memorystatus: Int16 = -14, except: Int16 = -15,
               nwChannel: Int16 = -16, workloop: Int16 = -17, exclaves: Int16 = -18

    static let names: [Int16: String] = [
        -1: "EVFILT_READ", -2: "EVFILT_WRITE", -3: "EVFILT_AIO", -4: "EVFILT_VNODE", -5: "EVFILT_PROC",
        -6: "EVFILT_SIGNAL", -7: "EVFILT_TIMER", -8: "EVFILT_MACHPORT", -9: "EVFILT_FS", -10: "EVFILT_USER",
        -12: "EVFILT_VM", -13: "EVFILT_SOCK", -14: "EVFILT_MEMORYSTATUS", -15: "EVFILT_EXCEPT",
        -16: "EVFILT_NW_CHANNEL", -17: "EVFILT_WORKLOOP", -18: "EVFILT_EXCLAVES_NOTIFICATION",
    ]

    @inline(__always) static func isReadiness(_ f: Int16) -> Bool { f == read || f == write || f == sock }
}

enum NoteUser {
    static let trigger: UInt32 = 0x0100_0000
    static let controlMask: UInt32 = 0xC000_0000
    static let and: UInt32 = 0x4000_0000
    static let or: UInt32 = 0x8000_0000
    static let copy: UInt32 = 0xC000_0000
    static let flagsMask: UInt32 = 0x00FF_FFFF
}

enum NoteTimer {
    static let seconds: UInt32 = 0x01
    static let useconds: UInt32 = 0x02
    static let nseconds: UInt32 = 0x04
    static let absolute: UInt32 = 0x08
    static let leeway: UInt32 = 0x10
    static let critical: UInt32 = 0x20
    static let background: UInt32 = 0x40
    static let machContinuousTime: UInt32 = 0x80
    static let machTime: UInt32 = 0x100
    static let unitMask: UInt32 = seconds | useconds | nseconds | machTime
}

enum NoteWorkloop {
    static let threadRequest: UInt32 = 0x01
    static let syncWait: UInt32 = 0x04
    static let syncWake: UInt32 = 0x08
    static let updateQoS: UInt32 = 0x10
    static let endOwnership: UInt32 = 0x20
    static let discoverOwner: UInt32 = 0x80
    static let ignoreESTALE: UInt32 = 0x100
    static let syncIPC: UInt32 = 0x8000_0000
    static let syncMask: UInt32 = syncWait | syncWake | syncIPC
}

enum MachRcv {
    static let msg: UInt32 = 0x0000_0002
    static let large: UInt32 = 0x0000_0004
    static let largeIdentity: UInt32 = 0x0000_0008
}

final class Knote {
    let ident: UInt64
    let filter: Int16
    var flags: UInt16
    var fflags: UInt32
    var data: Int64
    var udata: UInt64
    var qos: UInt32
    var ext: [UInt64]
    var enabled = true
    var active = false
    var suppressed = false
    var deletePending = false
    var syntheticDelete = false
    var dropped = false
    weak var kq: KQueue?
    var bucket = 0
    var userFlags: UInt32 = 0
    var timerDeadline: UInt64?
    var timerInterval: UInt64 = 0
    var timerFires: Int64 = 0
    var syncWoken = false
    let syncWaiters = WaitQueue()
    var receiveGone = false
    var history: [String] = []
    func note(_ text: @autoclosure () -> String) {
        guard DarwinKernel.recordKnoteHistory else { return }
        if history.count == 10 { history.removeFirst() }
        history.append("\(KernelClock.now() / 1_000_000 % 1_000_000): " + text())
    }
    var requestsVanish = false
    var procFired: UInt32 = 0
    var procData: Int64 = 0
    var procExited = false
    var signalCount: Int64 = 0
    weak var object: (any KernelDescriptorObject)?
    var observerToken: Int?
    var hostDescriptor = false
    var sockDelivered: UInt32 = 0
    var vnodeFired: UInt32 = 0
    var vnodeRevoked = false
    var vnodeWatch: VnodeKnoteWatch?

    init(_ c: KEventRecord) {
        ident = c.ident
        filter = c.filter
        flags = c.flags & ~(EV.actionBits | EV.vanished)
        requestsVanish = c.flags & EV.vanished != 0
        fflags = c.fflags
        data = c.data
        udata = c.udata
        qos = c.qos
        ext = c.ext
    }

    var udataSpecific: Bool { flags & EV.udataSpecific != 0 }
    var isSyncKnote: Bool { filter == EVFilter.workloop && fflags & NoteWorkloop.syncMask != 0 }
}

struct KQBucket {
    var requested = false
    var boundWorker: ThreadContext?
}

final class KQueue {
    enum Kind: Equatable {
        case descriptor(Int32)
        case workq
        case workloop
    }

    let kind: Kind
    var knotes: [Knote] = []
    var descriptorKnotes = 0
    weak var object: KQueueObject?
    let waiters = WaitQueue()
    var legacyFormat: Bool?
    var buckets: [Int: KQBucket] = [:]
    var workloopID: UInt64 = 0
    var servicer: ThreadContext?
    var owner: ThreadContext?
    var requested = false
    var requestQoS = 4
    var requestOvercommit = false
    var fixedPriority = false
    var createReference = false
    var requestLog: [(ms: UInt64, what: RequestEvent, thread: UInt64)] = []
    enum RequestEvent: String {
        case requested, cleared, taken, returned, bound, unbound, restored, repaired
    }
    func logRequest(_ what: RequestEvent, thread: UInt64 = 0) {
        if requestLog.count == 12 { requestLog.removeFirst() }
        requestLog.append((KernelClock.now() / 1_000_000 % 10_000_000, what, thread))
    }
    var requestLogText: String {
        requestLog.map { "\($0.ms) \($0.what.rawValue)\($0.thread == 0 ? "" : " t\($0.thread)")" }.joined(separator: ", ")
    }

    init(kind: Kind, workloopID: UInt64 = 0) {
        self.kind = kind
        self.workloopID = workloopID
    }

    var isDescriptor: Bool {
        if case .descriptor = kind { return true }
        return false
    }

    func find(ident: UInt64, filter: Int16, udata: UInt64?) -> Knote? {
        knotes.first { k in
            k.ident == ident && k.filter == filter
                && (udata == nil ? !k.udataSpecific : (k.udataSpecific && k.udata == udata!))
        }
    }
}

struct KEventDataArea {
    var base: UInt64
    var size: UInt64
    var stackData: Bool
}

struct KEventState {
    var workq: KQueue?
    var workloops: [UInt64: KQueue] = [:]
    var descriptorQueues: [Int32: KQueue] = [:]
    var objectQueues: [ObjectIdentifier: KQueue] = [:]
    var timers: [ObjectIdentifier: Knote] = [:]
    var mkTimers: [ObjectIdentifier: MachTimer] = [:]
    let timerWake = WaitQueue()
    var timerThreadStarted = false
    var loggedFilters: Set<Int16> = []
    var stats = KEventStats()
    var machportIndex: [UInt32: [Knote]]?
}

struct KEventStats {
    static let enabled = getenv("SWIFTCODE_DEBUG_KEVENT_STATS").map { String(cString: $0) == "1" } ?? false
    static let reportEvery: UInt64 = 20000
    static let slowNanoseconds: UInt64 = 50_000_000

    var calls: UInt64 = 0
    var kinds: [String: UInt64] = [:]
    var zeroEventReturns: UInt64 = 0
    var eventReturns: UInt64 = 0
    var scanWaits: UInt64 = 0
    var emptyScanWakeups: UInt64 = 0
    var scanTimeouts: UInt64 = 0
    var syncWaits: UInt64 = 0
    var syncWokenByWake: UInt64 = 0
    var syncWokenByDrop: UInt64 = 0
    var syncInterrupted: UInt64 = 0
    var syncOnExistingKnote: UInt64 = 0
    var syncWaitNs: UInt64 = 0
    var syncHistogram: [UInt64] = [0, 0, 0, 0, 0]
    var syncWakes: UInt64 = 0
    var syncWakesWithWaiter: UInt64 = 0
    var pumpNs: UInt64 = 0
    var pumps: UInt64 = 0
    var waitNsByThread: [ObjectIdentifier: UInt64] = [:]
    var heldNs: UInt64 = 0
    var maxHeldNs: UInt64 = 0

    static func histogramIndex(_ ns: UInt64) -> Int {
        ns < 100_000 ? 0 : ns < 1_000_000 ? 1 : ns < 10_000_000 ? 2 : ns < 100_000_000 ? 3 : 4
    }

    static func kind(_ n: Int, _ changes: [KEventRecord], nevents: Int32, flags: UInt32) -> String {
        var s = "\(n)"
        if let c = changes.first {
            s += " " + (EVFilter.names[c.filter].map { String($0.dropFirst(7)) } ?? "filter \(c.filter)")
            if c.filter == EVFilter.workloop {
                let f = c.fflags
                if f & NoteWorkloop.threadRequest != 0 { s += " thread-request" }
                if f & NoteWorkloop.syncWait != 0 { s += " sync-wait" }
                if f & NoteWorkloop.syncWake != 0 { s += " sync-wake" }
                if f & NoteWorkloop.endOwnership != 0 { s += " end-ownership" }
            }
            if c.flags & EV.delete != 0 { s += " delete" }
            if changes.count > 1 { s += " +\(changes.count - 1)" }
        } else {
            s += " no-change"
        }
        if nevents > 0 && flags & KEventFlag.errorEvents == 0 { s += flags & KEventFlag.immediate != 0 ? " poll" : " scan" }
        return s
    }
}

extension DarwinKernel {
    static let ESTALE: Int32 = 70
    static let EINPROGRESS: Int32 = 36
    static let EXDEV: Int32 = 18
    static let EEXIST: Int32 = 17

    func installDescriptorKQueue(_ fd: Int32) {
        withEvents { installDescriptorKQueueLocked(fd) }
    }

    private func installDescriptorKQueueLocked(_ fd: Int32) {
        kevents.descriptorQueues[fd] = KQueue(kind: .descriptor(fd))
        kevents.machportIndex = nil
    }

    func keventCall(_ n: Int, _ a: [UInt64], _ call: inout CallText, _ mem: any KernelGuestMemory) throws -> UInt64 {
        guard KEventStats.enabled else { return try keventBody(n, a, &call, mem) }
        let ctxID = ObjectIdentifier(current)
        let t0 = KernelClock.now()
        let pump0 = kevents.stats.pumpNs
        let workers0 = workqueue.workers.count
        kevents.stats.waitNsByThread[ctxID] = 0
        var events: UInt64 = 0
        var failure: Error?
        do { events = try keventBody(n, a, &call, mem) } catch { failure = error }
        let total = KernelClock.now() &- t0
        let waited = kevents.stats.waitNsByThread.removeValue(forKey: ctxID) ?? 0
        let held = total > waited ? total - waited : 0
        kevents.stats.calls += 1
        kevents.stats.heldNs &+= held
        if failure == nil { if events == 0 { kevents.stats.zeroEventReturns += 1 } else { kevents.stats.eventReturns += 1 } }
        if held > kevents.stats.maxHeldNs { kevents.stats.maxHeldNs = held }
        if held >= KEventStats.slowNanoseconds {
            let format: KEventFormat = n == BSD2.kevent ? .legacy : n == BSD2.kevent64 ? .k64 : .qos
            let count = Int(max(0, min(Int32(truncatingIfNeeded: a[2]), 16)))
            let changes = (try? readKEvents(a[1], count: count, format: format, mem)) ?? []
            let kind = KEventStats.kind(n, changes, nevents: Int32(truncatingIfNeeded: a[4]),
                                        flags: n >= BSD2.keventQos ? UInt32(truncatingIfNeeded: a[7]) : 0)
            keventStatsLine("slow call: pid \(pid) (\(processRecord?.comm ?? "?")) thread \(current.threadID) [\(kind)]: "
                + "held \(held / 1_000_000) ms (total \(total / 1_000_000) ms, waited \(waited / 1_000_000) ms), "
                + "pumping \((kevents.stats.pumpNs &- pump0) / 1_000_000) ms, workers \(workers0) -> \(workqueue.workers.count)")
        }
        if kevents.stats.calls % KEventStats.reportEvery == 0 { reportKEventStats() }
        if let failure { throw failure }
        return events
    }

    private func keventStatsLine(_ text: String) {
        FileHandle.standardError.write(Data(("swiftcode-kevent-stats: " + text + "\n").utf8))
    }

    func reportKEventStats() {
        let s = kevents.stats
        let kinds = s.kinds.sorted { $0.value > $1.value }.prefix(8).map { "\($0.key): \($0.value)" }.joined(separator: ", ")
        keventStatsLine("pid \(pid) (\(processRecord?.comm ?? "?")): \(s.calls) calls, held \(s.heldNs / 1_000_000) ms "
            + "(max \(s.maxHeldNs / 1_000_000) ms), returns 0 events \(s.zeroEventReturns) / events \(s.eventReturns); "
            + "scan waits \(s.scanWaits) (empty wakeups \(s.emptyScanWakeups), timeouts \(s.scanTimeouts)); "
            + "sync waits \(s.syncWaits), on an existing knote \(s.syncOnExistingKnote) (woken by wake \(s.syncWokenByWake), "
            + "by drop \(s.syncWokenByDrop), interrupted \(s.syncInterrupted); \(s.syncWaitNs / 1_000_000) ms; "
            + "<100us/<1ms/<10ms/<100ms/more \(s.syncHistogram.map(String.init).joined(separator: "/"))); "
            + "sync wakes \(s.syncWakes) (with a waiter \(s.syncWakesWithWaiter)); pumps \(s.pumps) "
            + "\(s.pumpNs / 1_000_000) ms; kinds: \(kinds)")
    }

    func keventWait(_ queue: WaitQueue, deadline: UInt64?) -> WaitResult {
        guard KEventStats.enabled else { return queue.wait(on: eventWaitLock, deadline: deadline) }
        let t = KernelClock.now()
        let r = queue.wait(on: eventWaitLock, deadline: deadline)
        let ns = KernelClock.now() &- t
        let id = ObjectIdentifier(current)
        if let w = kevents.stats.waitNsByThread[id] { kevents.stats.waitNsByThread[id] = w &+ ns }
        return r
    }

    private func keventPump() {
        guard KEventStats.enabled else { return pumpWorkqueue(nil) }
        let t = KernelClock.now()
        pumpWorkqueue(nil)
        kevents.stats.pumpNs &+= KernelClock.now() &- t
        kevents.stats.pumps += 1
    }

    private func keventBody(_ n: Int, _ a: [UInt64], _ call: inout CallText, _ mem: any KernelGuestMemory) throws -> UInt64 {
        let format: KEventFormat = n == BSD2.kevent ? .legacy : n == BSD2.kevent64 ? .k64 : .qos
        let nchanges = Int32(truncatingIfNeeded: a[2]), nevents = Int32(truncatingIfNeeded: a[4])
        var flags: UInt32 = 0
        var timeoutPointer: UInt64 = 0
        var dataOut: UInt64 = 0, dataAvailable: UInt64 = 0
        switch n {
        case BSD2.kevent:
            timeoutPointer = a[5]
            call.set("kevent(\(Int32(truncatingIfNeeded: a[0])), changes=\(hx(a[1])), nchanges=\(nchanges), events=\(hx(a[3])), "
                + "nevents=\(nevents), timeout=\(hx(a[5])))")
        case BSD2.kevent64:
            flags = UInt32(truncatingIfNeeded: a[5])
            timeoutPointer = a[6]
            call.set("kevent64(\(Int32(truncatingIfNeeded: a[0])), changes=\(hx(a[1])), nchanges=\(nchanges), events=\(hx(a[3])), "
                + "nevents=\(nevents), flags=\(hx(flags)), timeout=\(hx(a[6])))")
        default:
            dataOut = a[5]
            dataAvailable = a[6]
            flags = UInt32(truncatingIfNeeded: a[7])
            call.set("\(n == BSD2.keventQos ? "kevent_qos(\(Int32(truncatingIfNeeded: a[0]))" : "kevent_id(\(hx(a[0]))"), "
                + "changes=\(hx(a[1])), nchanges=\(nchanges), events=\(hx(a[3])), nevents=\(nevents), "
                + "data_out=\(hx(a[5])), data_available=\(hx(a[6])), flags=\(hx(flags)))")
        }
        flags &= KEventFlag.userSet
        guard nchanges >= 0, nevents >= 0 else { throw Failure(errno: Errno.EINVAL) }
        let errorEvents = flags & KEventFlag.errorEvents != 0
        let ctx = current

        let kq: KQueue
        switch n {
        case BSD2.kevent, BSD2.kevent64, BSD2.keventQos:
            if flags & (KEventFlag.workloop | KEventFlag.dynamicKQMustExist | KEventFlag.dynamicKQMustNotExist) != 0 {
                throw Failure(errno: Errno.EINVAL)
            }
            if n == BSD2.keventQos, flags & KEventFlag.workq != 0 {
                if nevents > 0 && !errorEvents { throw Failure(errno: Errno.EINVAL) }
                if kevents.workq == nil { kevents.workq = KQueue(kind: .workq); kevents.machportIndex = nil }
                kq = kevents.workq!
            } else {
                guard let q = descriptorKQueue(Int32(truncatingIfNeeded: a[0])) else { throw Failure(errno: Errno.EBADF) }
                let legacy = n == BSD2.kevent
                if let l = q.legacyFormat, l != legacy { throw Failure(errno: Errno.EINVAL) }
                q.legacyFormat = legacy
                kq = q
            }
        default:
            guard flags & KEventFlag.workloop != 0, flags & KEventFlag.workq == 0 else { throw Failure(errno: Errno.EINVAL) }
            let id = a[0]
            guard id != 0, id != UInt64.max else { throw Failure(errno: Errno.EINVAL) }
            if let wl = kevents.workloops[id] {
                if flags & KEventFlag.dynamicKQMustNotExist != 0 { throw Failure(errno: Self.EEXIST) }
                kq = wl
            } else {
                if flags & KEventFlag.dynamicKQMustExist != 0 { throw Failure(errno: Errno.ENOENT) }
                let wl = KQueue(kind: .workloop, workloopID: id)
                kevents.workloops[id] = wl
                kq = wl
            }
            if nevents > 0 && !errorEvents && kq.servicer !== ctx {
                trace("note: kevent_id on workloop \(hx(id)) by thread \(ctx.threadID), which does not service it "
                    + "(servicer: \(kq.servicer.map { "thread \($0.threadID)" } ?? "none"); thread bound to "
                    + "\(ctx.worker?.boundQueue.map { $0.kind == .workloop ? "workloop \(hx($0.workloopID))" : "the workqueue kqueue" } ?? "nothing")"
                    + "\(ctx.worker?.boundQueue === kq ? ", the same object" : ", another object")): EXDEV")
                maybeFreeWorkloop(kq)
                throw Failure(errno: Self.EXDEV)
            }
        }

        var deadline: UInt64?
        if timeoutPointer != 0 {
            let ts = try mem.read(va: timeoutPointer, count: 16)
            let sec = ts.readLE(Int64.self, at: 0), nsec = ts.readLE(Int64.self, at: 8)
            guard sec >= 0, (0..<1_000_000_000).contains(nsec) else { throw Failure(errno: Errno.EINVAL) }
            let ns = sec > Int64(UInt64.max / 2_000_000_000) ? UInt64.max : UInt64(sec) * 1_000_000_000 + UInt64(nsec)
            deadline = KernelClock.deadline(afterNanoseconds: ns)
        }

        let changes = try readKEvents(a[1], count: Int(nchanges), format: format, mem)
        if KEventStats.enabled {
            kevents.stats.kinds[KEventStats.kind(n, changes, nevents: nevents, flags: flags), default: 0] += 1
        }
        var output: [KEventRecord] = []
        if let e = applyChanges(changes, to: kq, outputCapacity: Int(nevents), output: &output, context: ctx,
                                flags: flags, mem) {
            if kq.kind == .workloop { maybeFreeWorkloop(kq) }
            throw Failure(errno: e)
        }

        var area = KEventDataArea(base: 0, size: 0, stackData: flags & KEventFlag.stackData != 0)
        var available: UInt64 = 0
        if dataOut != 0, dataAvailable != 0 {
            available = try readU64(dataAvailable, mem)
            area = KEventDataArea(base: dataOut, size: available, stackData: flags & KEventFlag.stackData != 0)
        }
        if !errorEvents, nevents > 0, output.isEmpty {
            var woke = false
            while true {
                let found = scanForDelivery(kq, bucket: nil, max: Int(nevents), area: &area, context: ctx, mem)
                if !found.isEmpty {
                    output = found
                    break
                }
                if KEventStats.enabled, woke { kevents.stats.emptyScanWakeups += 1 }
                if flags & KEventFlag.immediate != 0 { break }
                if let deadline, deadline <= KernelClock.now() { break }
                if KEventStats.enabled { kevents.stats.scanWaits += 1 }
                let r = keventWait(kq.waiters, deadline: deadline)
                woke = true
                if r == .interrupted { throw Failure(errno: Self.EINTR) }
                if r == .timedOut {
                    if KEventStats.enabled { kevents.stats.scanTimeouts += 1 }
                    break
                }
            }
        }
        if dataOut != 0, dataAvailable != 0, area.size != available { try writeU64(dataAvailable, area.size, mem) }
        if !output.isEmpty {
            var bytes: [UInt8] = []
            for e in output { bytes += e.encoded(format) }
            try mem.write(va: a[3], bytes: bytes)
        }
        if kq.kind == .workloop { maybeFreeWorkloop(kq) }
        call += " [\(output.count) events\(output.isEmpty ? "" : ": " + output.map(describe).joined(separator: "; "))]"
        return UInt64(output.count)
    }

    func describe(_ e: KEventRecord) -> String {
        let name = EVFilter.names[e.filter] ?? "filter \(e.filter)"
        var s = "\(name) ident=\(hx(e.ident)) flags=\(hx(e.flags)) fflags=\(hx(e.fflags)) data=\(e.data)"
        if e.flags & EV.error != 0 { s += " (\(Errno.name(Int32(truncatingIfNeeded: e.data))))" }
        return s
    }

    func readKEvents(_ va: UInt64, count: Int, format: KEventFormat, _ mem: any KernelGuestMemory) throws -> [KEventRecord] {
        guard count > 0 else { return [] }
        guard count <= 4096 else { throw Failure(errno: Errno.EINVAL) }
        let bytes = try mem.read(va: va, count: count * format.size)
        return (0..<count).map { KEventRecord(decoding: bytes, at: $0 * format.size, format: format) }
    }

    func applyChanges(_ changes: [KEventRecord], to kq: KQueue, outputCapacity: Int, output: inout [KEventRecord],
                      context: ThreadContext, flags: UInt32, _ mem: any KernelGuestMemory) -> Int32? {
        for (index, change) in changes.enumerated() {
            var c = change
            c.flags &= ~EV.sysFlags
            var result = applyChange(c, to: kq, context: context, flags: flags, changeCount: changes.count - index,
                                     outputCapacity: outputCapacity - output.count, mem)
            if let waiter = result.wait {
                let t = KEventStats.enabled ? KernelClock.now() : 0
                let r = keventWait(waiter.syncWaiters, deadline: nil)
                if r == .interrupted { result.errno = Self.EINTR }
                if KEventStats.enabled {
                    let ns = KernelClock.now() &- t
                    kevents.stats.syncWaits += 1
                    kevents.stats.syncWaitNs &+= ns
                    kevents.stats.syncHistogram[KEventStats.histogramIndex(ns)] += 1
                    if r == .interrupted {
                        kevents.stats.syncInterrupted += 1
                    } else if waiter.dropped {
                        kevents.stats.syncWokenByDrop += 1
                    } else {
                        kevents.stats.syncWokenByWake += 1
                    }
                }
            }
            if result.errno != nil || c.flags & EV.receipt != 0 {
                if output.count < outputCapacity {
                    var e = c
                    e.flags |= EV.error
                    e.data = Int64(result.errno ?? 0)
                    if let loaded = result.loaded { e.ext[3] = loaded }
                    output.append(e)
                } else if let e = result.errno {
                    return e
                }
            }
        }
        return nil
    }

    struct ChangeResult {
        var errno: Int32?
        var loaded: UInt64?
        var wait: Knote?
    }

    private func logFilterOnce(_ filter: Int16, _ text: String) {
        if kevents.loggedFilters.insert(filter).inserted { trace("note: \(EVFilter.names[filter] ?? "filter \(filter)"): \(text)") }
    }

    func applyChange(_ c: KEventRecord, to kq: KQueue, context: ThreadContext, flags: UInt32, changeCount: Int,
                     outputCapacity: Int, _ mem: any KernelGuestMemory) -> ChangeResult {
        let filter = c.filter
        guard (-18 ... -1).contains(filter), filter != -11 else { return ChangeResult(errno: Errno.EINVAL) }
        if filter == EVFilter.memorystatus {
            logFilterOnce(filter, "not supported (ENOTSUP)")
            return ChangeResult(errno: Errno.ENOTSUP)
        }
        if filter == EVFilter.workloop {
            guard kq.kind == .workloop else { return ChangeResult(errno: Errno.ENOTSUP) }
            return applyWorkloopChange(c, to: kq, context: context, flags: flags, changeCount: changeCount,
                                       outputCapacity: outputCapacity, mem)
        }
        let existing = kq.find(ident: c.ident, filter: filter, udata: c.flags & EV.udataSpecific != 0 ? c.udata : nil)
        if c.flags & EV.delete != 0 {
            guard let kn = existing else {
                if kq.kind == .workloop && c.flags & EV.add != 0 { return ChangeResult() }
                return ChangeResult(errno: Errno.ENOENT)
            }
            if kn.flags & EV.dispatch2 == EV.dispatch2 && !kn.enabled && c.flags & EV.enable == 0 {
                kn.deletePending = true
                return ChangeResult(errno: Self.EINPROGRESS)
            }
            drop(kn)
            return ChangeResult()
        }
        let kn: Knote
        if c.flags & EV.add != 0 {
            if c.flags & EV.vanished != 0 && c.flags & EV.dispatch2 != EV.dispatch2 { return ChangeResult(errno: Errno.EINVAL) }
            let enabled = c.flags & EV.disable == 0
            if kq.kind == .workloop, enabled, PthreadPriority.qos(c.qos) == nil {
                return ChangeResult(errno: Errno.ERANGE)
            }
            if let existing {
                if let e = touchFilter(existing, c, mem) { return ChangeResult(errno: e) }
                existing.udata = c.udata
                existing.qos = c.qos
                existing.flags = (existing.flags & (EV.clear | EV.oneshot)) | (c.flags & ~(EV.actionBits | EV.vanished))
                if filter == EVFilter.timer {
                    existing.flags |= EV.clear
                    if existing.fflags & NoteTimer.absolute != 0 { existing.flags |= EV.oneshot }
                }
                kn = existing
            } else {
                let new = Knote(c)
                new.kq = kq
                new.bucket = workqBucket(c.qos)
                let watchesDescriptor = Self.isDescriptorWatch(filter)
                if watchesDescriptor { noteDescriptorWatch(c.ident, 1) }
                if let e = attachFilter(new, c, mem) {
                    if watchesDescriptor { noteDescriptorWatch(c.ident, -1) }
                    return ChangeResult(errno: e)
                }
                kq.knotes.append(new)
                if new.filter == EVFilter.machport { kevents.machportIndex = nil }
                if new.filter == EVFilter.signal { signalKnoteCount.wrappingAdd(1, ordering: .relaxed) }
                if EVFilter.isReadiness(new.filter) {
                    kq.descriptorKnotes += 1
                    descriptorKnoteCount.wrappingAdd(1, ordering: .relaxed)
                }
                if new.filter == EVFilter.timer { armTimer(new) }
                kn = new
            }
            if enabled { enable(kn) } else { kn.enabled = false }
            kn.note("EV_ADD by t\(context.threadID) flags \(hx(UInt64(c.flags))) -> enabled \(kn.enabled) active \(kn.active) suppressed \(kn.suppressed)")
        } else {
            guard let existing else { return ChangeResult(errno: Errno.ENOENT) }
            kn = existing
            if let e = touchFilter(kn, c, mem) { return ChangeResult(errno: e) }
            if c.flags & EV.disable != 0 { kn.enabled = false } else if c.flags & EV.enable != 0 { enable(kn) }
            kn.note("change by t\(context.threadID) flags \(hx(UInt64(c.flags))) -> enabled \(kn.enabled) active \(kn.active) suppressed \(kn.suppressed)")
        }
        if kn.active && kn.enabled { activated(kn) }
        return ChangeResult()
    }

    private func enable(_ kn: Knote) {
        if kn.deletePending && !kn.enabled {
            kn.syntheticDelete = true
            kn.active = true
        }
        kn.enabled = true
    }

    func workqBucket(_ pp: UInt32) -> Int {
        if pp & PthreadPriority.eventManager != 0 { return Self.managerQoS }
        return PthreadPriority.qos(pp) ?? Self.managerQoS
    }

    private func attachFilter(_ kn: Knote, _ c: KEventRecord, _ mem: any KernelGuestMemory) -> Int32? {
        switch kn.filter {
        case EVFilter.user:
            kn.userFlags = userFlagsOperation(0, c.fflags)
            kn.data = c.data
            kn.active = c.fflags & NoteUser.trigger != 0
            return nil
        case EVFilter.timer:
            return setTimer(kn, c, isNew: true)
        case EVFilter.machport:
            if let ipc = machIPC as? MachIPC {
                switch ipc.receiveTarget(of: UInt32(truncatingIfNeeded: c.ident)) {
                case .none: return Errno.ENOENT
                case .notReceivable, .specialReplyPort: return Errno.ENOTSUP
                case .port, .portSet: break
                }
            }
            kn.active = machPortHasMessage(UInt32(truncatingIfNeeded: c.ident))
            return nil
        case EVFilter.proc where system.record(of: self) != nil:
            return attachProcess(kn, c)
        case EVFilter.signal:
            guard (1...31).contains(c.ident) else { return Errno.EINVAL }
            kn.flags |= EV.clear
            return nil
        case EVFilter.read, EVFilter.write:
            return attachDescriptor(kn, c)
        case EVFilter.vnode:
            return attachVnode(kn, c)
        case EVFilter.sock:
            guard let o = try? fileSystem.object(for: Int32(truncatingIfNeeded: c.ident)), o is SocketEventSource else {
                logFilterOnce(kn.filter, "registered on a descriptor that is no socket; it never fires")
                return nil
            }
            return attachDescriptor(kn, c)
        default:
            logFilterOnce(kn.filter, "registered; it never fires in stage 4a")
            return nil
        }
    }

    private func touchFilter(_ kn: Knote, _ c: KEventRecord, _ mem: any KernelGuestMemory) -> Int32? {
        switch kn.filter {
        case EVFilter.user:
            kn.userFlags = userFlagsOperation(kn.userFlags, c.fflags)
            kn.data = c.data
            if c.fflags & NoteUser.trigger != 0 { kn.active = true }
            return nil
        case EVFilter.timer:
            return setTimer(kn, c, isNew: false)
        case EVFilter.machport:
            if (kn.fflags ^ c.fflags) & MachRcv.msg != 0 { return Errno.EINVAL }
            kn.fflags = c.fflags
            kn.ext = c.ext
            kn.active = machPortHasMessage(UInt32(truncatingIfNeeded: c.ident))
            return nil
        default:
            if kn.filter == EVFilter.sock { kn.sockDelivered &= ~((kn.fflags ^ c.fflags) & SocketEvents.levelMask) }
            kn.fflags = c.fflags
            kn.vnodeWatch?.interest.store(c.fflags, ordering: .relaxed)
            kn.data = c.data
            kn.ext = c.ext
            return nil
        }
    }

    private func userFlagsOperation(_ old: UInt32, _ fflags: UInt32) -> UInt32 {
        let bits = fflags & NoteUser.flagsMask
        switch fflags & NoteUser.controlMask {
        case NoteUser.and: return old & bits
        case NoteUser.or: return old | bits
        case NoteUser.copy: return bits
        default: return old
        }
    }

    func machPortHasMessage(_ name: UInt32) -> Bool {
        machIPC?.messageQueued(on: name) ?? false
    }

    func wallClockTimerDeadline(fflags: UInt32, data: Int64) -> UInt64? {
        let units = fflags & NoteTimer.unitMask
        guard fflags & NoteTimer.absolute != 0, units != NoteTimer.machTime, units.nonzeroBitCount <= 1 else { return nil }
        let perUnit: UInt64 = switch units {
        case NoteTimer.seconds: 1_000_000_000
        case NoteTimer.useconds: 1_000
        case NoteTimer.nseconds: 1
        default: 1_000_000
        }
        let (absNs, overflow) = UInt64(max(0, data)).multipliedReportingOverflow(by: perUnit)
        guard !overflow else { return nil }
        let w = wallClock()
        let wallNs = UInt64(max(0, w.seconds)) &* 1_000_000_000 &+ UInt64(max(0, w.nanoseconds))
        return absNs > wallNs ? KernelClock.deadline(afterNanoseconds: absNs - wallNs) : KernelClock.now()
    }

    private func setTimer(_ kn: Knote, _ c: KEventRecord, isNew: Bool) -> Int32? {
        let units = c.fflags & NoteTimer.unitMask
        guard units.nonzeroBitCount <= 1 else { return Errno.EINVAL }
        if !isNew, (kn.fflags ^ c.fflags) & NoteTimer.absolute != 0 { return Errno.EINVAL }
        let absolute = c.fflags & NoteTimer.absolute != 0
        let perUnit: UInt64 = switch units {
        case NoteTimer.seconds: 1_000_000_000
        case NoteTimer.useconds: 1_000
        case NoteTimer.nseconds: 1
        case NoteTimer.machTime: 0
        default: 1_000_000
        }
        func toNanoseconds(_ v: UInt64) -> UInt64? {
            if units == NoteTimer.machTime { return nanoseconds(ticks: v) }
            let (r, o) = v.multipliedReportingOverflow(by: perUnit)
            return o ? nil : r
        }
        let now = KernelClock.now()
        var deadline: UInt64
        var interval: UInt64 = 0
        if absolute {
            if units == NoteTimer.machTime {
                deadline = hostDeadline(machTicks: UInt64(bitPattern: c.data))
            } else {
                guard let d = wallClockTimerDeadline(fflags: c.fflags, data: c.data) else { return Errno.ERANGE }
                deadline = d
            }
        } else if c.data <= 0 {
            deadline = now
        } else {
            guard let ns = toNanoseconds(UInt64(c.data)) else { return Errno.ERANGE }
            interval = ns
            deadline = KernelClock.deadline(afterNanoseconds: ns)
        }
        kn.fflags = c.fflags
        kn.data = c.data
        kn.ext = c.ext
        kn.flags |= EV.clear
        if absolute { kn.flags |= EV.oneshot }
        if c.flags & EV.oneshot != 0 || absolute || c.data <= 0 { interval = 0 }
        kn.timerInterval = interval
        kn.timerFires = 0
        kn.active = false
        kn.timerDeadline = deadline
        if deadline <= now {
            kn.timerFires = 1
            kn.active = true
            if interval > 0 { kn.timerDeadline = deadline + interval } else { kn.timerDeadline = nil }
        }
        if !isNew { armTimer(kn) }
        return nil
    }

    private func armTimer(_ kn: Knote) {
        if kn.timerDeadline == nil {
            kevents.timers[ObjectIdentifier(kn)] = nil
            return
        }
        kevents.timers[ObjectIdentifier(kn)] = kn
        if timerThreadOnEventLock {
            startTimerThreadIfNeeded()
            kevents.timerWake.wakeAll()
            return
        }
        lock.deferIfFast(.kernelLock(lock), tag: "timer thread") { [weak self] in
            guard let self else { return }
            startTimerThreadIfNeeded()
            kevents.timerWake.wakeAll()
        }
    }

    func readinessObserver(for kn: Knote) -> () -> Void {
        { [weak self, weak kn] in
            guard let self, let kn else { return }
            self.withEvents {
                guard !kn.dropped else { return }
                kn.active = true
                self.activated(kn)
            }
        }
    }

    func fireDueTimers() -> UInt64? {
        withEvents { fireDueTimersLocked() }
    }

    private func fireDueTimersLocked() -> UInt64? {
        let now = KernelClock.now()
        var next: UInt64?
        for (key, kn) in kevents.timers {
            guard !kn.dropped, let d = kn.timerDeadline else {
                kevents.timers[key] = nil
                continue
            }
            if d <= now {
                if let hook = KernelTrace.timerFired { hook(pid, now &- d, 1) }
                if kn.timerInterval > 0 {
                    let n = 1 + (now - d) / kn.timerInterval
                    kn.timerFires += Int64(n)
                    kn.timerDeadline = d &+ n &* kn.timerInterval
                } else {
                    kn.timerFires = 1
                    kn.timerDeadline = nil
                    kevents.timers[key] = nil
                }
                kn.active = true
                activated(kn)
            }
            if let d2 = kn.timerDeadline { next = min(next ?? d2, d2) }
        }
        if let d = fireDueMachTimers(now: now) { next = min(next ?? d, d) }
        return next
    }

    func startTimerThreadIfNeeded() {
        let start = withEvents { () -> Bool in
            guard !kevents.timerThreadStarted else { return false }
            kevents.timerThreadStarted = true
            return true
        }
        guard start else { return }
        let box = TimerThreadBox(kernel: self, lock: lock, events: timerThreadOnEventLock ? eventLock : nil,
                                 wake: kevents.timerWake)
        let thread = Thread { box.run() }
        thread.name = "swiftcode-kernel-timers"
        thread.start()
    }

    private func applyWorkloopChange(_ c: KEventRecord, to wl: KQueue, context: ThreadContext, flags: UInt32,
                                     changeCount: Int, outputCapacity: Int, _ mem: any KernelGuestMemory) -> ChangeResult {
        let cmd = c.fflags
        var result = ChangeResult()
        let existing = wl.find(ident: c.ident, filter: EVFilter.workloop, udata: c.flags & EV.udataSpecific != 0 ? c.udata : nil)
        var loaded = c.ext[3]
        if c.ext[1] != 0 {
            guard let v = try? readU64(c.ext[1], mem) else { return ChangeResult(errno: Errno.EFAULT) }
            loaded = v
            result.loaded = v
            if (v & c.ext[2]) != (c.ext[3] & c.ext[2]) {
                if cmd & NoteWorkloop.ignoreESTALE != 0 { return result }
                result.errno = Self.ESTALE
                return result
            }
        }
        var newOwner: ThreadContext??
        if cmd & NoteWorkloop.discoverOwner != 0 {
            let name = UInt32(truncatingIfNeeded: loaded) & ~3
            if name == 0 {
                newOwner = .some(nil)
            } else {
                guard let t = threadsByPort[name | 3] else { result.errno = Self.EOWNERDEAD; return result }
                newOwner = .some(t)
            }
        }
        func finishOwnership() {
            if let o = newOwner { wl.owner = o }
            if cmd & NoteWorkloop.endOwnership != 0, wl.owner === context { wl.owner = nil }
        }

        if cmd & NoteWorkloop.threadRequest != 0 {
            guard c.ident == wl.workloopID else { result.errno = Errno.EINVAL; return result }
            if c.flags & EV.delete != 0 {
                if let kn = existing { drop(kn) } else if c.flags & EV.add == 0 { result.errno = Errno.ENOENT; return result }
                finishOwnership()
                reevaluateRequests(wl, bucket: nil)
                return result
            }
            let kn: Knote
            if let existing {
                kn = existing
            } else {
                guard c.flags & EV.add != 0 else { result.errno = Errno.ENOENT; return result }
                kn = Knote(c)
            }
            let isNew = !wl.knotes.contains { $0 === kn }
            if isNew || cmd & NoteWorkloop.updateQoS != 0 {
                guard PthreadPriority.qos(c.qos) != nil else { result.errno = Errno.ERANGE; return result }
                kn.qos = c.qos
            }
            if isNew {
                kn.kq = wl
                wl.knotes.append(kn)
            }
            kn.fflags = cmd
            kn.udata = c.udata
            kn.flags |= EV.clear
            if c.flags & EV.disable != 0 { kn.enabled = false } else { kn.enabled = true }
            kn.active = true
            finishOwnership()
            reevaluateRequests(wl, bucket: nil)
            return result
        }

        if cmd & NoteWorkloop.syncMask != 0 {
            if c.flags & EV.delete != 0 {
                guard let kn = existing else {
                    if c.flags & EV.add != 0 { finishOwnership(); reevaluateRequests(wl, bucket: nil); return result }
                    result.errno = Errno.ENOENT
                    return result
                }
                guard kn.isSyncKnote else { result.errno = Errno.EINVAL; return result }
                kn.syncWoken = true
                kn.syncWaiters.wakeAll()
                drop(kn)
                finishOwnership()
                reevaluateRequests(wl, bucket: nil)
                return result
            }
            if cmd & NoteWorkloop.syncWait != 0 && cmd & NoteWorkloop.endOwnership != 0 {
                result.errno = Errno.EINVAL
                return result
            }
            let kn: Knote
            if let existing {
                guard existing.isSyncKnote else { result.errno = Errno.EINVAL; return result }
                if c.flags & EV.enable != 0 { result.errno = Errno.EINVAL; return result }
                if cmd & NoteWorkloop.syncWake != 0 {
                    if KEventStats.enabled {
                        kevents.stats.syncWakes += 1
                        if !existing.syncWaiters.isEmpty { kevents.stats.syncWakesWithWaiter += 1 }
                    }
                    existing.syncWoken = true
                    existing.syncWaiters.wakeAll()
                }
                if KEventStats.enabled, cmd & NoteWorkloop.syncWait != 0 { kevents.stats.syncOnExistingKnote += 1 }
                existing.fflags |= cmd & NoteWorkloop.syncMask
                kn = existing
            } else {
                guard c.flags & EV.add != 0 else { result.errno = Errno.ENOENT; return result }
                guard c.flags & EV.disable != 0 else { result.errno = Errno.EINVAL; return result }
                kn = Knote(c)
                kn.kq = wl
                kn.enabled = false
                kn.syncWoken = cmd & NoteWorkloop.syncWake != 0
                wl.knotes.append(kn)
            }
            finishOwnership()
            if cmd & NoteWorkloop.syncWait != 0 && !kn.syncWoken {
                guard changeCount == 1, flags & KEventFlag.errorEvents != 0, flags & KEventFlag.workloop != 0,
                      outputCapacity >= 1 else {
                    if existing == nil { drop(kn) }
                    result.errno = Errno.ENOTSUP
                    return result
                }
                result.wait = kn
            }
            reevaluateRequests(wl, bucket: nil)
            return result
        }
        result.errno = Errno.EINVAL
        return result
    }

    func drop(_ kn: Knote) {
        eventLock?.checkHeld("a knote")
        kn.dropped = true
        kn.active = false
        if let token = kn.observerToken {
            let object = kn.object
            kn.observerToken = nil
            lock.deferIfFast(.kernelLock(lock), tag: "readiness observer removal") { object?.removeReadinessObserver(token) }
        }
        kevents.timers[ObjectIdentifier(kn)] = nil
        if kn.vnodeWatch != nil { detachVnode(kn) }
        if kn.isSyncKnote, !kn.syncWaiters.isEmpty {
            kn.syncWoken = true
            kn.syncWaiters.wakeAll()
        }
        guard let kq = kn.kq else { return }
        let before = kq.knotes.count
        kq.knotes.removeAll { $0 === kn }
        if kn.filter == EVFilter.machport { kevents.machportIndex = nil }
        if kq.knotes.count < before, kn.filter == EVFilter.signal { signalKnoteCount.wrappingSubtract(1, ordering: .relaxed) }
        if kq.knotes.count < before, EVFilter.isReadiness(kn.filter) {
            kq.descriptorKnotes -= 1
            descriptorKnoteCount.wrappingSubtract(1, ordering: .relaxed)
        }
        if kq.knotes.count < before, Self.isDescriptorWatch(kn.filter) {
            noteDescriptorWatch(kn.ident, -1)
        }
        reevaluateRequests(kq, bucket: kq.kind == .workq ? kn.bucket : nil)
    }

    func activated(_ kn: Knote) {
        eventLock?.checkHeld("a knote")
        guard let kq = kn.kq, kn.enabled, !kn.suppressed else { return }
        reevaluateRequests(kq, bucket: kq.kind == .workq ? kn.bucket : nil)
    }

    nonisolated(unsafe) public static var descriptorEscalation = getenv("SWIFTCODE_DESCRIPTOR_ESCALATION").map { String(cString: $0) != "0" } ?? true

    @inline(__always) static func isDescriptorCandidate(_ kn: Knote) -> Bool {
        EVFilter.isReadiness(kn.filter) && !kn.dropped && kn.active && !kn.suppressed
            && (kn.enabled || kn.syntheticDelete)
    }

    func hasDescriptorCandidate(_ kq: KQueue) -> Bool {
        kq.descriptorKnotes > 0 && kq.knotes.contains(where: Self.isDescriptorCandidate)
    }

    private func deliverable(_ kn: Knote, in kq: KQueue) -> Bool {
        guard !kn.dropped, kn.active, !kn.suppressed, kn.enabled || kn.syntheticDelete else { return false }
        if kn.syntheticDelete { return true }
        switch kn.filter {
        case EVFilter.machport: return kn.receiveGone || machPortHasMessage(UInt32(truncatingIfNeeded: kn.ident))
        case EVFilter.timer: return kn.timerFires > 0
        case EVFilter.workloop: return kn.fflags & NoteWorkloop.threadRequest != 0 && kq.owner == nil
        case EVFilter.user: return true
        case EVFilter.proc: return kn.procFired != 0 || kn.procExited
        case EVFilter.signal: return kn.signalCount > 0
        case EVFilter.vnode: return kn.vnodeFired != 0 || kn.vnodeRevoked
        case EVFilter.read, EVFilter.write, EVFilter.sock:
            if eventLock != nil, !lock.isHeldByCurrentThread {
                if let kq = kn.kq, kq.descriptorKnotes > 0 {
                    reevaluateRequests(kq, bucket: kq.kind == .workq ? kn.bucket : nil)
                }
                return false
            }
            let ready = descriptorState(kn).ready
            if !ready, Self.descriptorEscalation,
               kn.object is PipeEnd || kn.object is UnixSocket || kn.object is InetSocket || kn.object is RouteSocket {
                kn.active = false
            }
            return ready
        default: return false
        }
    }

    func reevaluateRequests(_ kq: KQueue, bucket: Int?) {
        eventLock?.checkHeld("a kqueue")
        if kq.descriptorKnotes > 0, eventLock != nil, !lock.isHeldByCurrentThread,
           !Self.descriptorEscalation || hasDescriptorCandidate(kq) {
            lock.deferIfFast(.kernelLock(lock), tag: "descriptor kqueue re-evaluation") { [weak self, weak kq] in
                guard let self, let kq else { return }
                withEvents { reevaluateRequests(kq, bucket: bucket) }
            }
            return
        }
        switch kq.kind {
        case .descriptor:
            if kq.knotes.contains(where: { deliverable($0, in: kq) }) {
                kq.waiters.wakeAll()
                if let object = kq.object {
                    lock.deferIfFast(.kernelLock(lock), tag: "kqueue observers") { object.notifyObservers() }
                }
            }
        case .workq:
            let buckets = bucket.map { [$0] } ?? Array(Set(kq.knotes.map(\.bucket)))
            var pump = false
            for b in buckets {
                var state = kq.buckets[b] ?? KQBucket()
                let has = kq.knotes.contains { $0.bucket == b && deliverable($0, in: kq) }
                if has && !state.requested && state.boundWorker == nil {
                    state.requested = true
                    pump = true
                } else if !has && state.requested {
                    state.requested = false
                }
                kq.buckets[b] = state
            }
            if pump { keventPump() }
        case .workloop:
            if kq.servicer != nil {
                if kq.knotes.contains(where: { deliverable($0, in: kq) }) { kq.waiters.wakeAll() }
                return
            }
            var anyActive = false
            var highest: Int?
            var overcommit = false
            for kn in kq.knotes where deliverable(kn, in: kq) {
                anyActive = true
                if let q = PthreadPriority.qos(kn.qos) { highest = max(highest ?? q, q) }
                if kn.qos & PthreadPriority.overcommit != 0 { overcommit = true }
            }
            if anyActive && kq.owner == nil {
                kq.requestQoS = highest ?? 4
                kq.requestOvercommit = overcommit
                if !kq.requested {
                    kq.requested = true
                    workqueue.pendingWorkloops.append(kq)
                    kq.logRequest(.requested)
                    keventPump()
                }
            } else if kq.requested {
                kq.requested = false
                workqueue.pendingWorkloops.removeAll { $0 === kq }
                kq.logRequest(.cleared)
            }
            maybeFreeWorkloop(kq)
        }
    }

    func maybeFreeWorkloop(_ kq: KQueue) {
        guard kq.kind == .workloop, kq.knotes.isEmpty, kq.servicer == nil, !kq.createReference, !kq.requested,
              kq.waiters.isEmpty, kevents.workloops[kq.workloopID] === kq else { return }
        kevents.workloops[kq.workloopID] = nil
        trace("note: workloop \(hx(kq.workloopID)) freed")
    }

    func scanForDelivery(_ kq: KQueue, bucket: Int?, max: Int, area: inout KEventDataArea, context: ThreadContext,
                         _ mem: any KernelGuestMemory) -> [KEventRecord] {
        if Self.descriptorEscalation, let events = eventLock, !lock.isHeldByCurrentThread, hasDescriptorCandidate(kq) {
            var escalatedArea = area
            if let found = events.escalateToKernelLock({
                scanForDelivery(kq, bucket: bucket, max: max, area: &escalatedArea, context: context, mem)
            }) {
                area = escalatedArea
                return found
            }
        }
        var out: [KEventRecord] = []
        for kn in kq.knotes where out.count < max {
            if let bucket, kn.bucket != bucket { continue }
            guard deliverable(kn, in: kq) else {
                if kn.filter == EVFilter.machport && kn.active && !machPortHasMessage(UInt32(truncatingIfNeeded: kn.ident)) {
                    kn.active = false
                }
                continue
            }
            var e = KEventRecord(ident: kn.ident, filter: kn.filter, flags: kn.flags, fflags: 0, data: 0,
                                 udata: kn.udata, qos: kn.qos, ext: kn.ext)
            if kn.syntheticDelete {
                e.flags = (kn.flags & ~EV.actionBits) | EV.delete | EV.dispatch2 | EV.oneshot
                out.append(e)
                drop(kn)
                continue
            }
            switch kn.filter {
            case EVFilter.user:
                e.fflags = kn.userFlags
                e.data = kn.data
            case EVFilter.timer:
                e.fflags = kn.fflags
                e.data = kn.timerFires
                e.ext[0] = 0
            case EVFilter.machport:
                if kn.receiveGone {
                    if kn.requestsVanish {
                        e.flags = (kn.flags & ~EV.actionBits) | EV.vanished | EV.dispatch2 | EV.oneshot
                    } else {
                        e.flags |= EV.eof | EV.oneshot
                    }
                    e.data = 0
                    out.append(e)
                    drop(kn)
                    continue
                }
                deliverMachPort(kn, into: &e, area: &area, context: context, mem)
            case EVFilter.workloop:
                e.fflags = kn.fflags
                e.data = 0
            case EVFilter.proc:
                e.fflags = kn.procFired
                e.data = 0
                kn.procFired = 0
                if kn.procExited {
                    if kn.fflags & NoteProc.exitStatus != 0 { e.data = kn.procData }
                    if kn.fflags & NoteProc.reap == 0 {
                        e.flags |= EV.eof | EV.oneshot
                        kn.flags |= EV.oneshot
                    }
                    kn.procExited = false
                }
            case EVFilter.signal:
                e.fflags = kn.fflags
                e.data = kn.signalCount
                kn.signalCount = 0
            case EVFilter.vnode:
                deliverVnode(kn, into: &e)
            case EVFilter.read, EVFilter.write:
                let state = descriptorState(kn)
                e.fflags = 0
                e.data = state.data
                if state.eof { e.flags |= EV.eof }
            case EVFilter.sock:
                let state = socketEventState(kn)
                e.fflags = state.fired
                e.data = state.data
                if state.eof { e.flags |= EV.eof }
                kn.sockDelivered |= state.fired & SocketEvents.levelMask
            default:
                continue
            }
            out.append(e)
            if kn.flags & EV.oneshot != 0 {
                if kn.flags & EV.dispatch2 == EV.dispatch2 {
                    kn.enabled = false
                    kn.deletePending = true
                    kn.active = false
                } else {
                    drop(kn)
                    continue
                }
            } else if kn.flags & EV.dispatch != 0 {
                kn.enabled = false
            }
            if kn.flags & EV.clear != 0 {
                kn.active = false
                kn.timerFires = 0
            }
            if !kq.isDescriptor {
                kn.suppressed = true
                context.worker?.delivered.append(kn)
                kn.note("delivered to t\(context.threadID)\(context.worker == nil ? " (not a worker!)" : "") flags \(hx(UInt64(e.flags))) enabled \(kn.enabled)")
            }
        }
        return out
    }

    private func deliverMachPort(_ kn: Knote, into e: inout KEventRecord, area: inout KEventDataArea,
                                 context: ThreadContext, _ mem: any KernelGuestMemory) {
        let port = UInt32(truncatingIfNeeded: kn.ident)
        e.fflags = 0
        e.data = Int64(port)
        guard kn.fflags & MachRcv.msg != 0, let ipc = machIPC else { return }
        var options = kn.fflags
        var buffer = kn.ext[0], size = kn.ext[1]
        let carving = size == 0
        if carving {
            options |= MachRcv.large | MachRcv.largeIdentity
            buffer = area.base
            size = area.size
        }
        guard let r = ipc.receiveForKevent(port: port, options: options, buffer: buffer, size: size, context: context, memory: mem) else {
            logFilterOnce(EVFilter.machport, "MACH_RCV_MSG delivery is not supported by MachIPC; delivered without a message")
            return
        }
        e.fflags = r.returnCode
        e.data = Int64(bitPattern: r.data)
        e.ext[1] = r.size
        e.ext[2] = r.priorityAndQoS
        e.ext[3] = r.auxiliarySize
        e.ext[0] = buffer
        if carving, r.returnCode == 0 {
            let used = min(r.size + r.auxiliarySize, area.size)
            if area.stackData {
                let top = area.base + area.size - used
                if top != buffer, let bytes = try? mem.read(va: buffer, count: Int(used)) { try? mem.write(va: top, bytes: bytes) }
                e.ext[0] = top
                area.size -= used
            } else {
                area.base += used
                area.size -= used
            }
        }
    }

    func machPortMessageQueued(_ name: UInt32) {
        eventLock?.checkHeld("the EVFILT_MACHPORT hook")
        for kn in machportKnotes(named: name) {
            kn.active = true
            activated(kn)
        }
    }

    nonisolated(unsafe) static var machportKnoteIndex = getenv("SWIFTCODE_KNOTE_INDEX").map { String(cString: $0) != "0" } ?? true

    func machportKnotes(named name: UInt32) -> [Knote] {
        guard Self.machportKnoteIndex else {
            return allKQueues.flatMap { kq in
                kq.knotes.filter { $0.filter == EVFilter.machport && UInt32(truncatingIfNeeded: $0.ident) == name }
            }
        }
        if let index = kevents.machportIndex { return index[name] ?? [] }
        var index: [UInt32: [Knote]] = [:]
        for kq in allKQueues {
            for kn in kq.knotes where kn.filter == EVFilter.machport {
                index[UInt32(truncatingIfNeeded: kn.ident), default: []].append(kn)
            }
        }
        kevents.machportIndex = index
        return index[name] ?? []
    }

    func machPortReceiveRightGone(_ name: UInt32) {
        for kn in machportKnotes(named: name) {
            trace("note: receive right or port set \(hx(UInt64(name))) left the space; its knote vanishes")
            kn.receiveGone = true
            kn.active = true
            activated(kn)
        }
    }

    func kqueueWorkloopCtl(_ a: [UInt64], _ call: inout CallText, _ mem: any KernelGuestMemory) throws -> UInt64 {
        let cmd = UInt32(truncatingIfNeeded: a[0])
        call.set("kqueue_workloop_ctl(cmd=\(cmd), options=\(hx(a[1])), params=\(hx(a[2])), size=\(a[3]))")
        let size = Int(min(a[3], 36))
        guard size >= 16 else { throw Failure(errno: Errno.EINVAL) }
        var p = try mem.read(va: a[2], count: size)
        p += [UInt8](repeating: 0, count: 36 - size)
        let flags = p.readLE(Int32.self, at: 4)
        let id = p.readLE(UInt64.self, at: 8)
        guard id != 0, id != UInt64.max else { throw Failure(errno: Errno.EINVAL) }
        switch cmd {
        case 1:
            guard flags & 0x1F != 0 else { throw Failure(errno: Errno.EINVAL) }
            if flags & 1 != 0, !(1...63).contains(p.readLE(Int32.self, at: 16)) { throw Failure(errno: Errno.EINVAL) }
            if flags & 4 != 0 {
                guard (1...100).contains(p.readLE(Int32.self, at: 24)), (1...0xFF_FFFF).contains(p.readLE(Int32.self, at: 28)) else {
                    throw Failure(errno: Errno.EINVAL)
                }
            }
            guard kevents.workloops[id] == nil else { throw Failure(errno: Self.EEXIST) }
            let wl = KQueue(kind: .workloop, workloopID: id)
            wl.createReference = true
            wl.fixedPriority = flags & 1 != 0
            kevents.workloops[id] = wl
            call += " [created \(hx(id))]"
            return 0
        case 2:
            guard let wl = kevents.workloops[id], wl.createReference else { throw Failure(errno: Errno.ENOENT) }
            wl.createReference = false
            maybeFreeWorkloop(wl)
            return 0
        default:
            throw Failure(errno: Errno.EINVAL)
        }
    }
}

final class TimerThreadBox: @unchecked Sendable {
    weak var kernel: DarwinKernel?
    let lock: KernelLock
    let events: KernelLock?
    let wake: WaitQueue

    init(kernel: DarwinKernel, lock: KernelLock, events: KernelLock?, wake: WaitQueue) {
        self.kernel = kernel
        self.lock = lock
        self.events = events
        self.wake = wake
    }

    func run() {
        if let events { return runUnderEventLock(events) }
        lock.withLock {
            while !lock.isTerminated {
                var next: UInt64?
                do {
                    guard let k = kernel, !k.isTerminating else { return }
                    next = k.fireDueTimers()
                    k.withEvents { k.pumpWorkqueue(nil) }
                }
                let cap = KernelClock.deadline(afterNanoseconds: 1_000_000_000)
                _ = wake.wait(on: lock, deadline: min(next ?? cap, cap))
            }
        }
    }

    private func runUnderEventLock(_ events: KernelLock) {
        lock.withFastPath(context: nil) {
            events.withLock {
                while !lock.isTerminated {
                    var next: UInt64?
                    do {
                        guard let k = kernel, !k.isTerminating else { return }
                        next = k.fireDueTimers()
                        k.pumpWorkqueue(nil)
                    }
                    let cap = KernelClock.deadline(afterNanoseconds: 1_000_000_000)
                    _ = wake.wait(on: events, deadline: min(next ?? cap, cap))
                }
            }
        }
    }
}

public enum NoteProc {
    public static let exit: UInt32 = 0x8000_0000
    public static let fork: UInt32 = 0x4000_0000
    public static let exec: UInt32 = 0x2000_0000
    public static let reap: UInt32 = 0x1000_0000
    public static let signal: UInt32 = 0x0800_0000
    public static let exitStatus: UInt32 = 0x0400_0000
    public static let exitDetail: UInt32 = 0x0200_0000
    static let tracking: UInt32 = 0x7
}

final class KQueueObject: KernelDescriptorObject {
    let queue: KQueue
    weak var kernel: DarwinKernel?
    private var observers: [Int: () -> Void] = [:]
    private var nextToken = 1

    init(queue: KQueue, kernel: DarwinKernel) {
        self.queue = queue
        self.kernel = kernel
    }

    var fileType: UInt16 { 0 }
    var isConfined: Bool { true }

    func lastReferenceClosed() {
        kernel?.closeDescriptorKQueue(self)
        observers.removeAll()
    }

    func readReadiness() -> (ready: Bool, data: Int64, eof: Bool) {
        let n = kernel?.deliverableCount(queue) ?? 0
        return (n > 0, Int64(n), false)
    }

    func writeReadiness() -> (ready: Bool, data: Int64, eof: Bool) { (false, 0, false) }

    func addReadinessObserver(_ observer: @escaping () -> Void) -> Int {
        let token = nextToken
        nextToken += 1
        observers[token] = observer
        return token
    }

    func removeReadinessObserver(_ token: Int) { observers[token] = nil }

    func notifyObservers() {
        for o in observers.values { o() }
    }
}

extension DarwinKernel {
    var allKQueues: [KQueue] {
        var queues: [KQueue] = Array(kevents.workloops.values) + Array(kevents.descriptorQueues.values)
            + Array(kevents.objectQueues.values)
        if let w = kevents.workq { queues.append(w) }
        return queues
    }

    func descriptorKQueue(_ fd: Int32) -> KQueue? {
        if let object = (try? fileSystem.object(for: fd)) as? KQueueObject, object.kernel === self {
            return object.queue
        }
        return kevents.descriptorQueues[fd]
    }

    func deliverableCount(_ kq: KQueue) -> Int {
        withEvents { kq.knotes.reduce(0) { $0 + (deliverable($1, in: kq) ? 1 : 0) } }
    }

    func kqueueCall(_ call: inout CallText) throws -> UInt64 {
        eventLock?.checkHeld("the kqueue registry")
        call.set("kqueue()")
        let kq = KQueue(kind: .descriptor(-1))
        let object = KQueueObject(queue: kq, kernel: self)
        kq.object = object
        let fd = try fileSystem.installObject(object, statusFlags: DarwinOpen.O_RDWR, closeOnExec: false)
        kevents.objectQueues[ObjectIdentifier(kq)] = kq
        kevents.machportIndex = nil
        call += " [kqueue fd \(fd)]"
        return UInt64(UInt32(bitPattern: fd))
    }

    func closeDescriptorKQueue(_ object: KQueueObject) {
        withEvents { closeDescriptorKQueueLocked(object) }
    }

    private func closeDescriptorKQueueLocked(_ object: KQueueObject) {
        let kq = object.queue
        for kn in kq.knotes { drop(kn) }
        kq.waiters.wakeAll()
        kevents.objectQueues[ObjectIdentifier(kq)] = nil
        kevents.machportIndex = nil
    }

    func tearDownKEvents() {
        withEvents { tearDownKEventsLocked() }
    }

    private func tearDownKEventsLocked() {
        for kq in allKQueues {
            for kn in kq.knotes {
                kn.dropped = true
                kn.active = false
                if let token = kn.observerToken {
                    kn.object?.removeReadinessObserver(token)
                    kn.observerToken = nil
                }
                if kn.isSyncKnote { kn.syncWaiters.wakeAll() }
                if kn.vnodeWatch != nil { detachVnode(kn) }
            }
            kq.waiters.wakeAll()
        }
        kevents.timers.removeAll()
        kevents.mkTimers.removeAll()
    }

    func descriptorWasClosed(_ fd: Int32) {
        lock.withLock {
            extended.directoryCursors[fd] = nil
            guard !isTerminating else { return }
            guard isDescriptorWatched(fd) else { return }
            withEvents { closeDescriptorKnotes(fd) }
        }
    }

    func noteDescriptorWatch(_ ident: UInt64, _ delta: Int) {
        descriptorWatches.withLock { w in
            let n = (w[ident] ?? 0) + delta
            w[ident] = n > 0 ? n : nil
        }
    }

    func isDescriptorWatched(_ fd: Int32) -> Bool {
        descriptorWatches.withLock { $0[UInt64(UInt32(bitPattern: fd))] != nil }
    }

    static func isDescriptorWatch(_ filter: Int16) -> Bool {
        filter == EVFilter.read || filter == EVFilter.write || filter == EVFilter.vnode || filter == EVFilter.sock
    }

    private func closeDescriptorKnotes(_ fd: Int32) {
        do {
            for kq in allKQueues {
                for kn in kq.knotes where kn.ident == UInt64(UInt32(bitPattern: fd))
                    && (EVFilter.isReadiness(kn.filter) || kn.filter == EVFilter.vnode) {
                    drop(kn)
                }
            }
        }
    }

    func attachProcess(_ kn: Knote, _ c: KEventRecord) -> Int32? {
        guard c.fflags & NoteProc.tracking == 0 else { return Errno.ENOTSUP }
        guard c.ident <= UInt64(Int32.max), let target = system.processes[Int32(c.ident)], target.state != .zombie else {
            return Errno.ESRCH
        }
        let both = NoteProc.exit | NoteProc.exitStatus
        if c.fflags & both == both, target.ppid != pid, !canSignal(target) { return Self.EACCES }
        kn.flags |= EV.clear
        kn.data = 0
        target.watchers.append(ProcessWatch(knote: kn, kernel: self))
        return nil
    }

    static let EACCES: Int32 = 13

    func processEventFired(_ kn: Knote, event: UInt32, data: Int64) {
        withEvents { processEventFiredLocked(kn, event: event, data: data) }
    }

    private func processEventFiredLocked(_ kn: Knote, event: UInt32, data: Int64) {
        guard !kn.dropped else { return }
        var wanted = kn.fflags & event
        if event == NoteProc.exit {
            kn.procExited = true
            if kn.fflags & NoteProc.exitStatus != 0 {
                kn.procData = data
                wanted |= NoteProc.exitStatus
            }
        }
        kn.procFired |= wanted
        if wanted != 0 || event == NoteProc.exit {
            kn.active = true
            activated(kn)
        }
    }

    func countSignalForKEvent(_ signal: Int32) {
        guard signalKnoteCount.load(ordering: .relaxed) > 0 else { return }
        withEvents { countSignalForKEventLocked(signal) }
    }

    private func countSignalForKEventLocked(_ signal: Int32) {
        for kq in allKQueues {
            for kn in kq.knotes where kn.filter == EVFilter.signal && kn.ident == UInt64(signal) && !kn.dropped {
                kn.signalCount += 1
                kn.active = true
                activated(kn)
            }
        }
    }

    private func attachDescriptor(_ kn: Knote, _ c: KEventRecord) -> Int32? {
        guard c.ident <= UInt64(Int32.max) else { return Errno.EBADF }
        let fd = Int32(c.ident)
        let object: DarwinDescriptorObject?
        do {
            _ = try fileSystem.closeOnExec(fd)
            object = try fileSystem.object(for: fd)
        } catch {
            return errno(of: error, default: Errno.EBADF)
        }
        if let o = object as? KernelDescriptorObject {
            kn.object = o
            kn.observerToken = o.addReadinessObserver(readinessObserver(for: kn))
            kn.active = true
        } else if object != nil {
            logFilterOnce(kn.filter, "a descriptor object without readiness never fires")
        } else {
            kn.hostDescriptor = true
            kn.active = true
        }
        return nil
    }

    func descriptorState(_ kn: Knote) -> (ready: Bool, data: Int64, eof: Bool) {
        if kn.filter == EVFilter.sock {
            let s = socketEventState(kn)
            return (s.pending, s.data, s.eof)
        }
        if kn.hostDescriptor {
            if kn.filter == EVFilter.write { return (true, 65536, false) }
            let size = (try? fileSystem.fstat(Int32(truncatingIfNeeded: kn.ident)).size) ?? 0
            return (true, max(0, size), false)
        }
        guard let o = kn.object else { return (false, 0, false) }
        let r = kn.filter == EVFilter.read ? o.readReadiness() : o.writeReadiness()
        return (r.ready || r.eof, r.data, r.eof)
    }
}
