import Foundation
import Synchronization
import YcodeDarwinABI

public enum SchedPolicy {
    static func env(_ name: String) -> String? { getenv(name).map { String(cString: $0) } }
    static func flag(_ name: String, _ fallback: Bool) -> Bool {
        guard let v = env(name) else { return fallback }
        return v == "1" || v == "yes" || v == "on"
    }
    static func number(_ name: String, _ fallback: Double) -> Double {
        env(name).flatMap(Double.init) ?? fallback
    }

    nonisolated(unsafe) public static var holdEnabled = flag("SWIFTCODE_ADAPTIVE_HOLD", true)
    nonisolated(unsafe) public static var qosEnabled = flag("SWIFTCODE_SCHED_QOS", false)
    nonisolated(unsafe) public static var admissionEnabled = flag("SWIFTCODE_LOCK_ADMISSION", false)
    nonisolated(unsafe) public static var sendPushEnabled = flag("SWIFTCODE_SEND_PUSH", true)
    nonisolated(unsafe) public static var classOffL0 = flag("SWIFTCODE_SCHED_CLASS_OFF_L0", true)
    public static var importanceEnabled: Bool { holdEnabled || qosEnabled }

    nonisolated(unsafe) public static var holdSkipsDemand = flag("SWIFTCODE_ADAPTIVE_HOLD_DEMAND", true)
    nonisolated(unsafe) public static var holdMaxNanoseconds = UInt64(number("SWIFTCODE_ADAPTIVE_HOLD_MAX_S", 300) * 1e9)
    nonisolated(unsafe) public static var holdQuietNanoseconds = UInt64(number("SWIFTCODE_ADAPTIVE_HOLD_QUIET_MS", 250) * 1e6)
    nonisolated(unsafe) public static var holdBusyFraction = number("SWIFTCODE_ADAPTIVE_HOLD_BUSY_PERCENT", 25) / 100
    nonisolated(unsafe) public static var holdWindowNanoseconds = UInt64(number("SWIFTCODE_ADAPTIVE_HOLD_WINDOW_MS", 2000) * 1e6)
    nonisolated(unsafe) public static var holdCPUFraction = number("SWIFTCODE_ADAPTIVE_HOLD_CPU_PERCENT", 25) / 100
    nonisolated(unsafe) public static var holdTrace = flag("SWIFTCODE_ADAPTIVE_HOLD_TRACE", false)
    nonisolated(unsafe) public static var admissionBoundNanoseconds: [UInt64] = {
        let parts = env("SWIFTCODE_LOCK_ADMISSION_BOUND_MS")?.split(separator: ",").compactMap { Double($0) } ?? []
        let defaults: [Double] = [250, 150, 75]
        return (0..<3).map { UInt64((($0 < parts.count) ? parts[$0] : defaults[$0]) * 1e6) }
    }()

    static var gateActive: Bool { qosEnabled && admissionEnabled }
}

public enum SchedClass {
    public static let background = 0
    public static let utility = 1
    public static let `default` = 2
    public static let interactive = 3
    public static let count = 4

    public static func of(qos: Int) -> Int {
        switch qos {
        case 1, 2: background
        case 3: utility
        case 5...: interactive
        default: `default`
        }
    }

    public static func name(_ c: Int) -> String {
        ["bg", "ut", "df", "ui"][max(0, min(3, c))]
    }
}

public enum ProcessTypeCode {
    public static let appDefault: UInt32 = 0x100
    public static let appNonUI: UInt32 = 0x200
    public static let daemonStandard: UInt32 = 0x300
    public static let daemonInteractive: UInt32 = 0x400
    public static let daemonBackground: UInt32 = 0x500
    public static let daemonAdaptive: UInt32 = 0x600

    public static func primordialQoS(_ apptype: UInt32) -> Int {
        switch apptype & 0xF00 {
        case appDefault: 6
        case appNonUI, daemonStandard, daemonInteractive, daemonAdaptive, 0x700: 4
        case daemonBackground: 2
        default: 0
        }
    }

    public static func name(_ apptype: UInt32) -> String {
        switch apptype & 0xF00 {
        case appDefault: "App"
        case appNonUI: "AppNonUI"
        case daemonStandard: "Standard"
        case daemonInteractive: "Interactive"
        case daemonBackground: "Background"
        case daemonAdaptive: "Adaptive"
        case 0: "none"
        default: hx(apptype)
        }
    }
}

enum DarwinPriority {
    static let prioDarwinThread: Int32 = 3
    static let prioDarwinProcess: Int32 = 4
    static let prioDarwinBG: Int32 = 0x1000
}

extension DarwinProcess {
    var typeCode: UInt32 { processType & 0xF00 }

    var isImportanceReceiver: Bool { typeCode == ProcessTypeCode.daemonAdaptive }

    var isImportanceDonor: Bool {
        switch typeCode {
        case ProcessTypeCode.daemonBackground: false
        case ProcessTypeCode.daemonAdaptive: importanceBoosts > 0
        default: !isDarwinBG
        }
    }

    var isDarwinBG: Bool {
        if typeCode == ProcessTypeCode.daemonBackground { return true }
        if typeCode == ProcessTypeCode.daemonAdaptive && importanceBoosts == 0 { return true }
        return qosClamp >= 2 || darwinRole == 6 || requestedDarwinBG
    }

    var clampQoS: Int {
        switch qosClamp {
        case 1: 3
        case 2: 2
        case 3: 1
        default: 0
        }
    }

    func changeImportance(_ delta: Int, reason: StaticString = "") {
        guard delta != 0 else { return }
        let wasBG = isDarwinBG
        importanceBoosts = max(0, importanceBoosts + delta)
        let release = importanceBoosts > 0 && holdActive.load(ordering: .acquiring)
        let flipped = wasBG != isDarwinBG && SchedPolicy.qosEnabled
        guard release || flipped, let k = kernel else { return }
        k.lock.deferIfFast(.kernelLock(k.lock), tag: "importance hold/class") { [weak self] in
            guard let self, let k = self.kernel else { return }
            if self.importanceBoosts > 0, self.holdStart != nil, !k.system.waitsForShell(self) {
                k.system.releaseStartHold(self, reason: "boost")
            }
            if flipped { k.refreshSchedClasses() }
        }
    }
}

extension ThreadContext {
    public var schedClass: Int { schedClassStore.load(ordering: .relaxed) }

    var baseQoS: Int {
        if let w = worker, requestedQoS == 0 { return w.qos >= 7 ? 4 : w.qos }
        return requestedQoS
    }

    var overrideQoS: Int {
        max(dispatchOverrideQoS, maxExplicitOverride)
    }

    public var hostClass: Int {
        let c = schedClass
        guard let k = kernel else { return c }
        return max(c, k.sendPushClass)
    }

}

public struct SchedInputs: Equatable, Sendable {
    public var baseQoS: Int
    public var overrideQoS: Int = 0
    public var clampQoS: Int = 0
    public var darwinBG: Bool = false
    public var push: Int = -1

    public init(baseQoS: Int, overrideQoS: Int = 0, clampQoS: Int = 0, darwinBG: Bool = false, push: Int = -1) {
        self.baseQoS = baseQoS
        self.overrideQoS = overrideQoS
        self.clampQoS = clampQoS
        self.darwinBG = darwinBG
        self.push = push
    }

    public var schedClass: Int {
        var q = max(baseQoS, overrideQoS)
        if clampQoS > 0 { q = min(q == 0 ? 4 : q, clampQoS) }
        var c = SchedClass.of(qos: q)
        if darwinBG { c = SchedClass.background }
        return max(c, push)
    }
}

extension DarwinKernel {
    @inline(__always) public var sendPushClass: Int {
        let w = sendPushCounts.load(ordering: .relaxed)
        if w == 0 { return -1 }
        if w >> 48 != 0 { return 3 }
        if w >> 32 != 0 { return 2 }
        if w >> 16 != 0 { return 1 }
        return 0
    }

    func addSendPush(_ cls: Int) {
        sendPushCounts.wrappingAdd(KernelLock.unit(cls), ordering: .relaxed)
    }

    func removeSendPush(_ cls: Int) {
        sendPushCounts.wrappingSubtract(KernelLock.unit(cls), ordering: .relaxed)
    }

    func refreshSchedClass(_ t: ThreadContext) {
        guard SchedPolicy.qosEnabled else { return }
        let p: DarwinProcess?
        if lock.callerIsFast {
            guard SchedPolicy.classOffL0, let cached = schedProcessCache, cached.kernel === self else {
                lock.deferIfFast(.kernelLock(lock), tag: "class refresh") { [weak self] in self?.refreshSchedClass(t) }
                return
            }
            p = cached
            SchedStats.fastRefreshes.wrappingAdd(1, ordering: .relaxed)
        } else {
            p = schedProcess
        }
        t.schedPushes.withLock { pushes in
            let inputs = SchedInputs(baseQoS: t.baseQoS, overrideQoS: t.overrideQoS, clampQoS: p?.clampQoS ?? 0,
                                     darwinBG: (p?.isDarwinBG ?? false) || t.threadDarwinBG, push: pushes.maxClass)
            let c = inputs.schedClass
            if t.schedClassStore.exchange(c, ordering: .relaxed) != c {
                SchedStats.classChanges.wrappingAdd(1, ordering: .relaxed)
            }
        }
    }

    func refreshSchedClasses() {
        guard SchedPolicy.qosEnabled else { return }
        for t in threadsByPort.values { refreshSchedClass(t) }
        refreshSchedClass(mainThread)
    }

    var schedProcess: DarwinProcess? {
        if let p = schedProcessCache, p.kernel === self { return p }
        if eventLock != nil, !lock.isHeldByCurrentThread { return nil }
        let p = system.record(of: self)
        schedProcessCache = p
        return p
    }

    func applySpawnPolicy(_ attributes: SpawnAttributes, record: DarwinProcess, isExec: Bool) {
        if !isExec || attributes.apptype & 0xF00 != 0 {
            record.processType = attributes.apptype
            record.qosClamp = Int(attributes.qosClamp)
            record.darwinRole = attributes.darwinRole
        }
        schedProcessCache = record
        mainThread.requestedQoS = ProcessTypeCode.primordialQoS(record.processType)
        refreshSchedClass(mainThread)
    }

    func endServicing(_ t: ThreadContext) {
        if let p = t.carriedImportance {
            t.carriedImportance = nil
            p.changeImportance(-1)
        }
        if t.ipcPushClass >= 0 {
            t.ipcPushClass = -1
            refreshSchedClass(t)
        }
    }

    func refreshULockPush(addr: UInt64, queue: ULockQueue) {
        guard SchedPolicy.qosEnabled else { return }
        let waiters = queue.waiters.waitingContexts
        let target = waiters.isEmpty ? nil : queue.owner
        if let old = queue.pushedOwner, old !== target {
            _ = old.setULockPush(-1, for: addr)
            old.kernel?.refreshSchedClass(old)
            queue.pushedOwner = nil
        }
        guard let target, target.isAlive else { return }
        let push = waiters.map(\.schedClass).max() ?? -1
        if target.setULockPush(push, for: addr) {
            target.kernel?.refreshSchedClass(target)
        }
        queue.pushedOwner = target
    }
}

extension MachIPC {
    func importanceTarget(_ p: IPCPort) -> DarwinProcess? {
        if let r = p.receiver?.kernel?.schedProcess, r.isImportanceReceiver, !r.isZombie { return r }
        if let w = p.watchProcess, w.isImportanceReceiver, !w.isZombie, w.kernel != nil { return w }
        return nil
    }

    func rebalanceImportance(_ p: IPCPort) {
        let target = importanceTarget(p)
        guard target !== p.creditedProcess else { return }
        let old = p.creditedProcess
        p.creditedProcess = target
        if p.importanceCount > 0 {
            old?.changeImportance(-p.importanceCount)
            target?.changeImportance(p.importanceCount)
        }
    }

    func annotateForScheduling(_ m: inout KMessage, options: UInt64) {
        let ctx = SchedPolicy.qosEnabled ? lock.callerContext : nil
        if SchedPolicy.importanceEnabled, options & MachMsgOption.sendNoImportance == 0,
           let proc = kernel?.schedProcess, proc.isImportanceDonor, let p = m.destination.port, !p.isKernelObject {
            if p.importanceDonation {
                m.importance = true
                kernel?.system.schedStats.importanceMessages &+= 1
            } else {
                kernel?.system.schedStats.refusedByPort &+= 1
            }
        }
        if SchedPolicy.qosEnabled, options & MachMsgOption.rcvMsg != 0, case .sendOnce = m.reply, let ctx {
            m.pushClass = Int8(ctx.schedClass)
        }
    }

    func importanceQueued(on p: IPCPort, id: Int32 = 0) {
        rebalanceImportance(p)
        p.importanceCount += 1
        if let target = p.creditedProcess, target.holdActive.load(ordering: .acquiring) {
            let sender = kernel?.schedProcess
            target.holdBoostSource = "from pid \(sender?.pid ?? 0) \(sender?.name ?? "?"), message id \(id)"
        }
        p.creditedProcess?.changeImportance(1)
    }

    func importanceDequeued(from p: IPCPort) {
        guard p.importanceCount > 0 else { return }
        p.importanceCount -= 1
        p.creditedProcess?.changeImportance(-1)
        if p.importanceCount == 0 { p.creditedProcess = nil }
    }

    func receivedForScheduling(_ m: KMessage, by context: ThreadContext?) {
        guard let context, let k = context.kernel else { return }
        if m.importance, let p = k.schedProcess, p.isImportanceReceiver {
            if let old = context.carriedImportance { old.changeImportance(-1) }
            context.carriedImportance = p
            p.changeImportance(1)
        }
        if m.pushClass >= 0, SchedPolicy.qosEnabled {
            context.ipcPushClass = Int(m.pushClass)
            k.refreshSchedClass(context)
        }
    }

    func bindImportanceWatchPorts(_ ports: [IPCPort], to child: DarwinProcess) {
        guard child.isImportanceReceiver else { return }
        for p in ports where p.active {
            guard p.tempOwner else {
                p.watchProcess = child
                continue
            }
            if let old = p.creditedProcess, p.importanceCount > 0 { old.changeImportance(-p.importanceCount) }
            p.creditedProcess = nil
            p.watchProcess = child
            rebalanceImportance(p)
        }
    }
}

public struct SchedStats: Sendable {
    public var holds = 0
    public var releasedByBoost = 0
    public var releasedQuiet = 0
    public var releasedTimeout = 0
    public var releasedExit = 0
    public var releasedShellReady = 0
    public var demandStarts = 0
    public var heldNanoseconds: UInt64 = 0
    public static let classChanges = Atomic<UInt64>(0)
    public static let fastRefreshes = Atomic<UInt64>(0)
    public static let sendPushes = Atomic<UInt64>(0)
    public var donationPorts = 0
    public var tempOwnerPorts = 0
    public var importanceMessages: UInt64 = 0
    public var refusedByPort: UInt64 = 0
}

extension DarwinSystem {
    func startHold(_ p: DarwinProcess, label: String) {
        p.holdStart = KernelClock.now()
        p.holdLabel = label
        heldProcesses.append(p)
        schedStats.holds += 1
        holdLog?("pid \(p.pid) \(label): start held (\(ProcessTypeCode.name(p.processType)), unboosted)")
        if !holdThreadRunning {
            holdThreadRunning = true
            let t = Thread { [weak self] in self?.holdLoop() }
            t.name = "swiftcode start hold"
            t.start()
        } else {
            holdWake.wakeAll()
        }
    }

    func waitsForShell(_ p: DarwinProcess) -> Bool {
        !shellReady && !shellReadyHoldLabels.isEmpty && shellReadyHoldLabels.contains(p.holdLabel)
    }

    public func markShellReady(reason: String) {
        lock.withLock {
            guard !shellReady else { return }
            shellReady = true
            guard !shellReadyHoldLabels.isEmpty else { return }
            holdLog?("shell ready (\(reason)): releasing the holds that waited for it")
            for p in heldProcesses where shellReadyHoldLabels.contains(p.holdLabel) {
                releaseStartHold(p, reason: "shell ready")
            }
        }
    }

    func releaseStartHold(_ p: DarwinProcess, reason: String) {
        guard let start = p.holdStart else { return }
        p.holdStart = nil
        heldProcesses.removeAll { $0 === p }
        let held = KernelClock.now() &- start
        schedStats.heldNanoseconds &+= held
        switch reason {
        case "boost": schedStats.releasedByBoost += 1
        case "quiet": schedStats.releasedQuiet += 1
        case "timeout": schedStats.releasedTimeout += 1
        case "shell ready": schedStats.releasedShellReady += 1
        default: schedStats.releasedExit += 1
        }
        var source = reason == "boost" && !p.holdBoostSource.isEmpty ? " (\(p.holdBoostSource))" : ""
        if reason != "boost", !p.holdBoostSource.isEmpty, shellReadyHoldLabels.contains(p.holdLabel) {
            source = " (boosted while waiting for the shell, last \(p.holdBoostSource))"
        }
        holdLog?("pid \(p.pid) \(p.holdLabel): start hold released (\(reason)) after \(held / 1_000_000) ms\(source)")
        if reason != "exit", p.state != .zombie, !p.exiting { p.image?.resume() }
    }

    private func holdLoop() {
        lock.withLock {
            var samples: [(UInt64, UInt64, UInt64)] = []
            let cpus = Double(max(1, ProcessInfo.processInfo.activeProcessorCount))
            var lastTrace: UInt64 = 0
            while true {
                for p in heldProcesses where p.state == .zombie || p.exiting { releaseStartHold(p, reason: "exit") }
                let now = KernelClock.now()
                samples.append((now, lock.totalHeldNanoseconds, Self.processCPUNanoseconds()))
                while samples.count > 1, now &- samples[1].0 >= SchedPolicy.holdWindowNanoseconds { samples.removeFirst() }
                let span = now &- samples[0].0
                let busy = span == 0 ? 1 : Double(lock.totalHeldNanoseconds &- samples[0].1) / Double(span)
                let cpuBusy = span == 0 ? 1 : Double(samples[samples.count - 1].2 &- samples[0].2) / Double(span) / cpus
                let cpuQuiet = SchedPolicy.holdCPUFraction <= 0 || cpuBusy < SchedPolicy.holdCPUFraction
                let windowFull = span >= SchedPolicy.holdWindowNanoseconds
                let lastContention = lock.lastHighContention
                let contentionAge = now > lastContention ? now - lastContention : 0
                if SchedPolicy.holdTrace, now &- lastTrace >= 1_000_000_000 {
                    lastTrace = now
                    holdLog?("hold inputs: lock busy \(Int(busy * 100))%, CPU \(Int(cpuBusy * 100))% of \(Int(cpus)) over \(span / 1_000_000) ms, "
                        + "last contention \(contentionAge / 1_000_000) ms ago, \(heldProcesses.count) held")
                }
                for p in heldProcesses where now &- (p.holdStart ?? now) >= SchedPolicy.holdMaxNanoseconds {
                    releaseStartHold(p, reason: "timeout")
                }
                if windowFull, busy < SchedPolicy.holdBusyFraction, cpuQuiet, contentionAge >= SchedPolicy.holdQuietNanoseconds {
                    for p in heldProcesses where now &- (p.holdStart ?? now) >= SchedPolicy.holdQuietNanoseconds && !waitsForShell(p) {
                        releaseStartHold(p, reason: "quiet")
                    }
                }
                if heldProcesses.isEmpty { break }
                _ = holdWake.wait(on: lock, deadline: KernelClock.deadline(afterNanoseconds: 50_000_000))
            }
            holdThreadRunning = false
        }
    }

    static func processCPUNanoseconds() -> UInt64 {
        var ts = timespec()
        guard clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &ts) == 0 else { return 0 }
        return UInt64(ts.tv_sec) &* 1_000_000_000 &+ UInt64(ts.tv_nsec)
    }

    public var schedReport: String {
        lock.withLock {
            let s = schedStats
            var line = "start holds \(s.holds) (boost \(s.releasedByBoost), quiet \(s.releasedQuiet), "
                + "timeout \(s.releasedTimeout), exit \(s.releasedExit)\(s.releasedShellReady > 0 ? ", shell ready \(s.releasedShellReady)" : ""), still held \(heldProcesses.count); not held on demand \(s.demandStarts)), "
                + "\(s.heldNanoseconds / 1_000_000) ms held in all; class changes \(SchedStats.classChanges.load(ordering: .relaxed)) "
                + "(\(SchedStats.fastRefreshes.load(ordering: .relaxed)) recomputations without L0); "
                + "importance: \(s.donationPorts) receiving ports, \(s.tempOwnerPorts) temporary owners, "
                + "\(s.importanceMessages) messages, \(s.refusedByPort) donor sends to other ports; "
                + "send pushes \(SchedStats.sendPushes.load(ordering: .relaxed))"
            line += "; " + lock.admissionReport
            return line
        }
    }
}
