#if os(Linux) && arch(arm64)
import Foundation
import Glibc
import Synchronization
import SwiftCodeDarwinABI
import SwiftCodeDarwinKernel
import SwiftCodeHypervisor
import SwiftCodeMachO

let rootPID: Int32 = VMLayout.guestPID

enum LaunchErrno {
    static let ENOENT: Int32 = 2
    static let ENOEXEC: Int32 = 8
    static let ENOMEM: Int32 = 12
    static let EACCES: Int32 = 13
    static let EBADARCH: Int32 = 86
}

final class VMCounters: @unchecked Sendable {
    static let shared = VMCounters()
    private let lock = HostMutex(name: "VM counters")
    private var created = 0
    private var destroyed = 0
    func vmCreated() { lock.withLock { created += 1 } }
    func vmDestroyed() { lock.withLock { destroyed += 1 } }
    var snapshot: (created: Int, destroyed: Int) { lock.withLock { (created, destroyed) } }
}

final class ImageBuildProfile: @unchecked Sendable {
    static let shared: ImageBuildProfile? = TrapProfile.shared == nil ? nil : ImageBuildProfile()
    static let phases = ["VM", "load", "setup", "vCPU 0", "clock", "wire"]
    private let lock = HostMutex()
    private var builds = 0
    private var totals = [UInt64](repeating: 0, count: phases.count)

    struct Timer {
        var last = monotonicNanoseconds()
        var spans: [UInt64] = []
        mutating func mark() {
            let now = monotonicNanoseconds()
            spans.append(now &- last)
            last = now
        }
    }

    func record(_ timer: Timer) {
        lock.withLock {
            builds += 1
            for (i, ns) in timer.spans.enumerated() where i < totals.count { totals[i] &+= ns }
        }
    }

    var report: String {
        lock.withLock {
            let all = totals.reduce(0, &+)
            let parts = zip(Self.phases, totals).map { "\($0) \($1 / 1_000_000) ms (\(builds == 0 ? 0 : $1 / UInt64(builds) / 1000) us)" }
            let deferred = VCPUPool.deferredCreations.load(ordering: .relaxed)
            let deferredNs = VCPUPool.deferredCreationNanoseconds.load(ordering: .relaxed)
            return "Image builds \(builds), \(all / 1_000_000) ms in all: " + parts.joined(separator: ", ")
                + "; vCPUs created off the kernel lock \(deferred) (avg \(deferred == 0 ? 0 : deferredNs / deferred / 1000) us)"
                + "; all vCPU creations: KVM_CREATE_VCPU \(VCPUPool.deferredCreateVCPUNanoseconds.load(ordering: .relaxed) / 1_000_000) ms, "
                + "VCPU_INIT+map \(VCPUPool.deferredInitNanoseconds.load(ordering: .relaxed) / 1_000_000) ms; "
                + "off-lock host threads \(VCPUPool.deferredThreadNanoseconds.load(ordering: .relaxed) / 1_000_000) ms"
        }
    }
}

final class PrebuiltVMs: @unchecked Sendable {
    static let enabled = getenv("SWIFTCODE_VM_PREBUILD").map { String(cString: $0) != "0" } ?? true
    static let async = enabled && (getenv("SWIFTCODE_VM_PREBUILD_ASYNC").map { String(cString: $0) != "0" } ?? true)
    static let limit = 2
    static let asyncLimit = getenv("SWIFTCODE_VM_PREBUILD_READY").flatMap { Int(String(cString: $0)) }.map { max(1, min(16, $0)) } ?? 4
    static let precreateVCPUs = getenv("SWIFTCODE_VCPU_PREBUILT").map { String(cString: $0) != "0" } ?? true

    static func build() -> ProcessBuilder? {
        let t0 = monotonicNanoseconds()
        let builder = try? ProcessBuilder(log: nil)
        let t1 = monotonicNanoseconds()
        if precreateVCPUs { builder?.vm.makeSpareVCPUs(count: VirtualMachine.precreateCount) }
        buildVMNanoseconds.wrappingAdd(t1 &- t0, ordering: .relaxed)
        buildVCPUNanoseconds.wrappingAdd(monotonicNanoseconds() &- t1, ordering: .relaxed)
        return builder
    }
    static let buildVMNanoseconds = Atomic<UInt64>(0)
    static let buildVCPUNanoseconds = Atomic<UInt64>(0)
    static let reuseEnabled = async && (getenv("SWIFTCODE_VM_REUSE").map { String(cString: $0) != "0" } ?? true)
    static let reuseLimit = getenv("SWIFTCODE_VM_REUSE_KEEP").flatMap { Int(String(cString: $0)) }.map { max(1, min(256, $0)) } ?? 64
    private var dirty: [(vm: VirtualMachine, backing: KVMPhysicalBacking)] = []
    let reused = Atomic<UInt64>(0)
    let reuseRefused = Atomic<UInt64>(0)
    let reuseNanoseconds = Atomic<UInt64>(0)

    func recycle(vm: VirtualMachine, backing: KVMPhysicalBacking) -> Bool {
        guard Self.reuseEnabled else { return false }
        let taken: Bool = lock.withLock {
            guard ready.count + dirty.count < Self.reuseLimit else { return false }
            dirty.append((vm, backing))
            wanted.signal()
            return true
        }
        if !taken { reuseRefused.wrappingAdd(1, ordering: .relaxed) }
        return taken
    }

    private static func rebuild(_ vm: VirtualMachine, _ backing: KVMPhysicalBacking) -> ProcessBuilder? {
        guard backing.scrubForReuse(), vm.resetForReuse(), let builder = try? ProcessBuilder(reusing: vm, backing: backing) else {
            vm.close()
            return nil
        }
        return builder
    }

    private let lock = HostMutex(name: "prebuilt VMs")
    private let wanted = HostCondition()
    let takes = Atomic<UInt64>(0)
    let hits = Atomic<UInt64>(0)
    let inlineBuilds = Atomic<UInt64>(0)
    let inlineBuildNanoseconds = Atomic<UInt64>(0)
    let builderBuilds = Atomic<UInt64>(0)
    let builderNanoseconds = Atomic<UInt64>(0)

    var report: String {
        let b = builderBuilds.load(ordering: .relaxed), i = inlineBuilds.load(ordering: .relaxed)
        return "prebuilt VMs: \(takes.load(ordering: .relaxed)) taken, \(hits.load(ordering: .relaxed)) ready; "
            + "inline builds \(i) (avg \(i == 0 ? 0 : inlineBuildNanoseconds.load(ordering: .relaxed) / i / 1000) us); "
            + "builder builds \(b) (avg \(b == 0 ? 0 : builderNanoseconds.load(ordering: .relaxed) / b / 1000) us); "
            + "all builds: ProcessBuilder \(Self.buildVMNanoseconds.load(ordering: .relaxed) / 1_000_000) ms, "
            + "spare vCPUs \(Self.buildVCPUNanoseconds.load(ordering: .relaxed) / 1_000_000) ms; "
            + "KVM_CREATE_VM \(VirtualMachine.createVMCount.load(ordering: .relaxed)) "
            + "(\(VirtualMachine.createVMNanoseconds.load(ordering: .relaxed) / 1_000_000) ms); "
            + "VM closes \(VirtualMachine.closeCount.load(ordering: .relaxed)) "
            + "(\(VirtualMachine.closeNanoseconds.load(ordering: .relaxed) / 1_000_000) ms); "
            + "reused \(reused.load(ordering: .relaxed)) (avg \(reused.load(ordering: .relaxed) == 0 ? 0 : reuseNanoseconds.load(ordering: .relaxed) / reused.load(ordering: .relaxed) / 1000) us), "
            + "refused \(reuseRefused.load(ordering: .relaxed))"
    }
    private var ready: [ProcessBuilder] = []
    private var building = 0
    private var builderStarted = false

    func prepare() {
        guard Self.enabled else { return }
        if Self.async {
            startBuilder()
            let start: Bool = lock.withLock {
                if !ready.isEmpty { return false }
                building += 1
                return true
            }
            guard start else { return }
            let t0 = monotonicNanoseconds()
            let builder = Self.build()
            inlineBuilds.wrappingAdd(1, ordering: .relaxed)
            inlineBuildNanoseconds.wrappingAdd(monotonicNanoseconds() &- t0, ordering: .relaxed)
            lock.withLock {
                building -= 1
                if let builder { ready.append(builder) }
            }
            return
        }
        let start: Bool = lock.withLock {
            guard ready.count + building < Self.limit else { return false }
            building += 1
            return true
        }
        guard start else { return }
        let builder = Self.build()
        lock.withLock {
            building -= 1
            if let builder { ready.append(builder) }
        }
    }

    func startBuilder() {
        guard Self.async else { return }
        let start: Bool = lock.withLock {
            if builderStarted { return false }
            builderStarted = true
            return true
        }
        guard start else { return }
        let thread = Thread { [self] in builderLoop() }
        thread.name = "swiftcode VM prebuild"
        thread.start()
    }

    func take() -> ProcessBuilder? {
        lock.withLock {
            let b = ready.popLast()
            takes.wrappingAdd(1, ordering: .relaxed)
            if b != nil { hits.wrappingAdd(1, ordering: .relaxed) }
            if Self.async { wanted.signal() }
            return b
        }
    }

    private func builderLoop() {
        while true {
            lock.lock()
            while ready.count >= Self.asyncLimit && dirty.isEmpty { wanted.wait(lock, milliseconds: 1000) }
            let recycled = dirty.isEmpty ? nil : dirty.removeFirst()
            lock.unlock()
            if let recycled {
                let t0 = monotonicNanoseconds()
                if let builder = Self.rebuild(recycled.vm, recycled.backing) {
                    reused.wrappingAdd(1, ordering: .relaxed)
                    reuseNanoseconds.wrappingAdd(monotonicNanoseconds() &- t0, ordering: .relaxed)
                    lock.withLock { ready.append(builder) }
                }
                continue
            }
            let t0 = monotonicNanoseconds()
            guard let builder = Self.build() else { usleep(100_000); continue }
            builderBuilds.wrappingAdd(1, ordering: .relaxed)
            builderNanoseconds.wrappingAdd(monotonicNanoseconds() &- t0, ordering: .relaxed)
            lock.withLock { ready.append(builder) }
        }
    }
}

let spawnTrapStart = PerThreadNanoseconds()

let trapPrefix = PerThreadString()

nonisolated(unsafe) var keptVMsForDebugging: [VirtualMachine]? =
    getenv("SWIFTCODE_DEBUG_NO_VM_CLOSE").map { String(cString: $0) == "1" } ?? false ? [] : nil
let keptVMsLock = NSLock()

final class ImageRecord: @unchecked Sendable {
    let serial: Int
    let pid: Int32
    let executable: String
    var end: VCPUPool.Termination?
    var finalSummary: String?
    var finalUnimplemented: String?
    var tornDown = false
    var image: GuestImageInstance?
    var ppid: Int32 = 0
    var launchNs: UInt64 = 0
    var requestNs: UInt64 = 0
    var vmReadyNs: UInt64 = 0
    var loadedNs: UInt64 = 0
    var vcpuReadyNs: UInt64 = 0
    var activatedNs: UInt64 = 0
    var prebuiltVM = 0
    var builtNs: UInt64 = 0
    var milestoneNs: UInt64 = 0
    var endNs: UInt64 = 0
    var tornDownNs: UInt64 = 0
    var hostStats: VCPUPool.HostStats?
    var lockHeldNs: UInt64 = 0
    var lockWaitNs: UInt64 = 0
    var lockAcquisitions: UInt64 = 0
    var firstRunNs: UInt64 = 0
    var traps = 0
    var taskLocalTraps = 0
    var vcpus = 0
    var milestoneTraps = 0
    var milestoneLockWaitNs: UInt64 = 0
    var milestoneLockHeldNs: UInt64 = 0
    var milestoneCPUNs: UInt64 = 0
    var milestoneGuestTicks: UInt64 = 0
    var milestoneSystemTicks: UInt64 = 0
    var milestoneRunNs: UInt64 = 0
    var milestoneHandlerNs: UInt64 = 0
    var milestoneTopTraps = ""
    var milestoneKVMExits: UInt64 = 0
    var milestoneUserExits: UInt64 = 0
    var milestoneWFxExits: UInt64 = 0
    var milestoneMinorFaults: UInt64 = 0

    init(serial: Int, pid: Int32, executable: String) {
        self.serial = serial
        self.pid = pid
        self.executable = executable
    }

    var endDescription: String {
        guard let end else { return "running" }
        switch end.kind {
        case .terminated: return end.message.hasPrefix("guest exited") ? "exit \(end.status)" : "ended with status \(end.status)"
        case .ended: return end.message
        case .stopped: return "stopped"
        }
    }
}

final class LaunchHandle: LaunchedImage {
    weak var image: GuestImageInstance?
    init(_ image: GuestImageInstance) { self.image = image }
    func resume() { image?.resumeSuspended() }
}

final class VMMLauncher: ProcessLauncher, @unchecked Sendable {
    let config: ExecConfiguration
    private let lock = HostMutex(name: "VMM launcher")
    private let changed = HostCondition()
    private var live: [GuestImageInstance] = []
    private var finishedImages: [GuestImageInstance] = []
    private(set) var records: [ImageRecord] = []
    private var waitStatuses: [Int32: Int32] = [:]
    private var rootExitSeen: UInt64?
    private var abortRequest: (status: Int32, message: String)?
    private var serial = 0
    let multiImage = Atomic<Bool>(false)
    private var systemCounterOffset: UInt64?
    private var systemBootHostCounter: UInt64 = 0
    private var systemCounterFrequency: UInt64 = 0

    var snapshotSystemClock: (guestCounter: UInt64, bootCounter: UInt64, frequency: UInt64)? {
        lock.withLock {
            guard let offset = systemCounterOffset else { return nil }
            return (Hypervisor.hostCounter() &- offset, systemBootHostCounter &- offset, systemCounterFrequency)
        }
    }
    private(set) var lastLaunchFailure: String?
    let prebuilt = PrebuiltVMs()

    init(config: ExecConfiguration) {
        self.config = config
        if !config.trace { prebuilt.startBuilder() }
    }

    func tag(_ pid: Int32) -> String { multiImage.load(ordering: .relaxed) ? "[pid \(pid)] " : "" }

    func launch(_ request: ProcessImageRequest, kernel: DarwinKernel) throws -> any LaunchedImage {
        let image = try build(request, kernel: kernel)
        return try register(image, startSuspended: request.startSuspended)
    }

    final class Prepared: PreparedImage {
        let image: GuestImageInstance
        init(_ image: GuestImageInstance) { self.image = image }
    }

    func prepare(_ request: ProcessImageRequest, kernel: DarwinKernel) throws -> (any PreparedImage)? {
        Prepared(try build(request, kernel: kernel))
    }

    func activate(_ prepared: any PreparedImage, startSuspended: Bool) throws -> any LaunchedImage {
        try register((prepared as! Prepared).image, startSuspended: startSuspended)
    }

    func discard(_ prepared: any PreparedImage) {
        (prepared as! Prepared).image.abandon()
    }

    private func noteFailure(_ text: String) -> String {
        lock.withLock { lastLaunchFailure = text }
        return text
    }

    private func build(_ request: ProcessImageRequest, kernel: DarwinKernel) throws -> GuestImageInstance {
        let number: Int = lock.withLock {
            serial += 1
            if serial > 1 { multiImage.store(true, ordering: .relaxed) }
            return serial
        }
        do {
            return try GuestImageInstance(launcher: self, serial: number, request: request, kernel: kernel)
        } catch let error as DarwinErrnoError {
            let text = noteFailure("\(request.executablePath): \(error)")
            if config.trace || number == 1 { stderrLine("swiftcode-simd: \(tag(kernel.pid))cannot launch \(text)") }
            throw error
        } catch {
            let text = noteFailure("\(request.executablePath): \(error)")
            stderrLine("swiftcode-simd: \(tag(kernel.pid))cannot build a VM for \(text)")
            throw DarwinErrnoError(LaunchErrno.ENOMEM)
        }
    }

    private func register(_ image: GuestImageInstance, startSuspended: Bool) throws -> any LaunchedImage {
        let kernel = image.kernel
        if BootProfile.shared != nil {
            image.record.ppid = kernel.system.process(pid: kernel.pid)?.ppid ?? 0
            image.record.activatedNs = monotonicNanoseconds()
        }
        lock.withLock {
            live.append(image)
            records.append(image.record)
        }
        if FrameProfile.active.load(ordering: .relaxed), let fp = FrameProfile.shared {
            fp.imageLaunched(pid: kernel.pid, serial: image.record.serial, executable: image.record.executable, suspended: startSuspended)
        }
        SimDebugServer.shared?.imageWillStart(image)
        if !startSuspended {
            do {
                try image.startMainThread()
            } catch {
                let text = noteFailure("\(image.record.executable): \(error)")
                stderrLine("swiftcode-simd: \(tag(kernel.pid))cannot start \(text)")
                image.abandon()
                lock.withLock {
                    live.removeAll { $0 === image }
                    finishedImages.removeAll { $0 === image }
                    records.removeAll { $0 === image.record }
                }
                throw DarwinErrnoError(LaunchErrno.ENOMEM)
            }
        }
        return LaunchHandle(image)
    }

    var snapshotLiveImages: [GuestImageInstance] { lock.withLock { live } }
    func snapshotPresetSystemClock(offset: UInt64, bootHostCounter: UInt64) {
        lock.withLock {
            systemCounterOffset = offset
            systemBootHostCounter = bootHostCounter
        }
    }

    func systemClock(for vcpu: VCPU, frequency: UInt64, log: (String) -> Void) throws -> (offset: UInt64, bootCounter: UInt64) {
        try systemClock(for: vcpu, vm: nil, frequency: frequency, log: log).clock
    }

    func systemClock(for vcpu: VCPU, vm: VirtualMachine?, frequency: UInt64, log: (String) -> Void) throws
        -> (clock: (offset: UInt64, bootCounter: UInt64), direct: Bool) {
        let own = try vcpu.counterOffset()
        lock.withLock { systemCounterFrequency = frequency }
        if FastTraps.enabled, let vm, vm.supportsCounterOffset {
            let system: UInt64 = lock.withLock {
                if systemCounterOffset == nil {
                    systemCounterOffset = own
                    systemBootHostCounter = Hypervisor.hostCounter()
                }
                return systemCounterOffset!
            }
            do {
                try vm.setCounterOffset(system)
                let boot = lock.withLock { systemBootHostCounter } &- system
                return ((system, boot), true)
            } catch {
                log("cannot set the VM-wide counter offset: \(error)")
            }
        }
        let system: UInt64? = lock.withLock {
            if systemCounterOffset == nil {
                systemCounterOffset = own
                systemBootHostCounter = Hypervisor.hostCounter()
            }
            return systemCounterOffset
        }
        var offset = own
        if let system, system != own {
            do {
                try vcpu.setVirtualCounter(Hypervisor.hostCounter() &- system)
                offset = try vcpu.counterOffset()
            } catch {
                log("cannot align the guest counter: \(error)")
            }
            let drift = Int64(bitPattern: offset &- system)
            if drift.magnitude > frequency / 1000 {
                log("warning: guest counter differs from the system's by \(drift) ticks")
            }
        }
        let boot = lock.withLock { systemBootHostCounter } &- offset
        return ((offset, boot), false)
    }

    func imageEnded(_ image: GuestImageInstance, _ end: VCPUPool.Termination) {
        lock.withLock {
            if image.record.end == nil || image.record.end!.kind == .stopped { image.record.end = end }
            if BootProfile.shared != nil, image.record.endNs == 0 { image.record.endNs = monotonicNanoseconds() }
            changed.broadcast()
        }
    }

    func imageFinished(_ image: GuestImageInstance) {
        lock.withLock {
            finishedImages.append(image)
            changed.broadcast()
        }
    }

    func processExited(pid: Int32, status: Int32) {
        lock.withLock {
            waitStatuses[pid] = status
            if pid == rootPID, rootExitSeen == nil { rootExitSeen = monotonicMilliseconds() }
            changed.broadcast()
        }
        if config.trace { stderrLine("swiftcode-simd: \(tag(pid))process \(pid) exited (wait status \(hex(UInt64(UInt32(bitPattern: status)))))") }
    }

    func abortHost(status: Int32, message: String) {
        lock.withLock {
            if abortRequest == nil { abortRequest = (status, message) }
            changed.broadcast()
        }
    }

    func superviseRoot(timeoutMilliseconds: UInt64) -> (status: Int32, message: String, watchdog: Bool) {
        let deadline = monotonicMilliseconds() + timeoutMilliseconds
        while true {
            lock.lock()
            while finishedImages.isEmpty && abortRequest == nil && rootResultLocked(final: false) == nil
                    && monotonicMilliseconds() < deadline {
                changed.wait(lock, milliseconds: min(100, max(1, deadline &- monotonicMilliseconds())))
            }
            let batch = finishedImages
            finishedImages.removeAll()
            let abort = abortRequest
            lock.unlock()
            for image in batch { tearDown(image) }
            if let abort { return (abort.status, abort.message, false) }
            if let result = lock.withLock({ rootResultLocked(final: false) }) { return (result.status, result.message, false) }
            if monotonicMilliseconds() >= deadline {
                if let result = lock.withLock({ rootResultLocked(final: true) }) { return (result.status, result.message, false) }
                return (71, "watchdog: guest still running after \(timeoutMilliseconds) ms", true)
            }
        }
    }

    private func rootResultLocked(final: Bool) -> (status: Int32, message: String)? {
        if let record = records.last(where: { $0.pid == rootPID && $0.end?.kind == .terminated }), let end = record.end {
            return (end.status, end.message)
        }
        guard let status = waitStatuses[rootPID] else { return nil }
        let graceOver = final || (rootExitSeen.map { monotonicMilliseconds() >= $0 + 500 } ?? true)
        guard graceOver else { return nil }
        return (Self.hostStatus(waitStatus: status), "process \(rootPID) ended: \(Self.describe(waitStatus: status))")
    }

    static func hostStatus(waitStatus w: Int32) -> Int32 {
        let low = w & 0x7F
        if low == 0 { return (w >> 8) & 0xFF }
        return 128 + low
    }

    static func describe(waitStatus w: Int32) -> String {
        let low = w & 0x7F
        if low == 0 { return "exit \((w >> 8) & 0xFF)" }
        if low == 0x7F { return "stopped by signal \((w >> 8) & 0xFF)" }
        return "signal \(low)" + (w & 0x80 != 0 ? " (core)" : "")
    }

    func waitStatus(of pid: Int32) -> Int32? { lock.withLock { waitStatuses[pid] } }

    @discardableResult
    func stopAll(milliseconds: UInt64) -> Int {
        let images = lock.withLock { live }
        for image in images {
            image.kernel.lock.withLock {
                if !image.kernel.isTerminating { image.kernel.postSignal(9) }
            }
            image.pool.requestStop("stopped at host exit")
        }
        let deadline = monotonicMilliseconds() + milliseconds
        for image in images {
            let now = monotonicMilliseconds()
            if image.pool.waitUntilFinished(milliseconds: deadline > now ? deadline - now : 0) { tearDown(image) }
        }
        lock.withLock { finishedImages.removeAll { $0.record.tornDown } }
        return lock.withLock { live.count }
    }

    func superviseAll(deadline: UInt64) -> Int {
        while true {
            lock.lock()
            while finishedImages.isEmpty && !live.isEmpty && monotonicMilliseconds() < deadline {
                changed.wait(lock, milliseconds: 100)
            }
            let batch = finishedImages
            finishedImages.removeAll()
            lock.unlock()
            for image in batch { tearDown(image) }
            let remaining = liveCount
            if remaining == 0 || monotonicMilliseconds() >= deadline { return remaining }
        }
    }

    func longHandlerReport(ms: UInt64) -> [String] {
        let images = lock.withLock { live }
        var lines: [String] = []
        for image in images {
            for w in image.pool.longHandlers(atLeast: ms) {
                let ctx = w.context as? ThreadContext
                let since = monotonicMilliseconds() &- w.handlerSince.load(ordering: .relaxed)
                var text = "\(tag(image.pid))vCPU \(w.index) (host tid \(w.hostTID.load(ordering: .relaxed))) in a handler for \(since) ms: kind \(w.lastTrapKind.load(ordering: .relaxed)) "
                    + "x16 \(Int64(bitPattern: w.lastTrapX16.load(ordering: .relaxed))) ESR \(hex(w.lastTrapESR.load(ordering: .relaxed))) "
                    + "ELR \(hex(w.lastTrapELR.load(ordering: .relaxed)))"
                if let ctx {
                    text += "; thread \(ctx.threadID) arriving \(ctx.arrivingTrap.map { String(Int64(bitPattern: $0)) } ?? "-") "
                        + "in kernel \(ctx.trapInProgress.map { String(Int64(bitPattern: $0.x16)) } ?? "-") blocked \(ctx.blockedInKernel)"
                }
                lines.append(text)
            }
        }
        return lines
    }

    func longGuestRunReport(ms: UInt64) -> [String] {
        let images = lock.withLock { live }
        var lines: [String] = []
        for image in images {
            for w in image.pool.longGuestRuns(atLeast: ms) {
                let ctx = w.context as? ThreadContext
                lines.append("\(tag(image.pid))vCPU \(w.index) (thread \(ctx.map { String($0.threadID) } ?? "?")) no VM exit for "
                    + "\(monotonicMilliseconds() &- w.lastExitMs.load(ordering: .relaxed)) ms; sample #\(w.sampleCount.load(ordering: .relaxed)): "
                    + "pc \(hex(w.samplePC.load(ordering: .relaxed))) = \(image.describeAddress(w.samplePC.load(ordering: .relaxed))) "
                    + "pstate \(hex(w.samplePSTATE.load(ordering: .relaxed))) ELR_EL1 \(hex(w.sampleELR1.load(ordering: .relaxed))) "
                    + "ESR_EL1 \(hex(w.sampleESR1.load(ordering: .relaxed)))")
            }
        }
        return lines
    }

    func rootWorkerStates() -> [String] {
        let images = lock.withLock { live }
        return images.filter { $0.pid == rootPID }.flatMap { $0.pool.workerStates() }
    }

    func watchdogReport() -> String {
        let images = lock.withLock { live }
        return images.map { image in
            "  \(tag(image.pid))\(image.record.executable):\n" + image.pool.stopAll(milliseconds: 500)
        }.joined(separator: "\n")
    }

    private func tearDown(_ image: GuestImageInstance) {
        guard !image.record.tornDown else { return }
        image.pool.joinThreads()
        if BootProfile.shared != nil { image.captureProfile() }
        image.record.finalSummary = image.summary(locked: true)
        image.record.finalUnimplemented = image.unimplementedSummary()
        image.destroy()
        lock.withLock {
            image.record.tornDown = true
            image.record.image = nil
            if image.record.end == nil { image.record.end = image.pool.currentTermination }
            live.removeAll { $0 === image }
        }
        if config.trace { stderrLine("swiftcode-simd: \(tag(image.pid))image \(image.record.serial) torn down (\(image.record.endDescription))") }
    }

    var liveCount: Int { lock.withLock { live.count } }
}

final class GuestImageInstance: @unchecked Sendable {
    let launcher: VMMLauncher
    let record: ImageRecord
    let kernel: DarwinKernel
    let pid: Int32
    let vm: VirtualMachine
    let space: GuestAddressSpace
    let pool: VCPUPool
    let images: ImageMap
    let fileSystem: DarwinFileSystem
    private let options: Options
    private let trace: Bool
    private var mainState: VCPUStartState?
    private var destroyed = false

    private var milestoneReached = false
    private var preMilestoneTraps: [Int64: Int] = [:]
    private var tracker = CacheMappingTracker()
    private let trapCountAtomic = Atomic<Int>(0)
    let taskLocalTrapCount = Atomic<Int>(0)
    private let milestoneDone = Atomic<Bool>(false)
    private var trapCounts: [String: Int] = [:]
    private let endedByKernel = Atomic<Bool>(false)
    private let fatalReported = Atomic<Bool>(false)

    func say(_ text: String) { stderrLine("swiftcode-simd: " + launcher.tag(pid) + text) }

    init(launcher: VMMLauncher, serial: Int, request: ProcessImageRequest, kernel: DarwinKernel) throws {
        let config = launcher.config
        self.launcher = launcher
        self.kernel = kernel
        self.pid = kernel.pid
        self.options = config.options
        let trace = config.trace || config.options.tracePIDs.contains(kernel.pid)
            || config.options.traceNames.contains((request.executablePath as NSString).lastPathComponent)
        self.trace = trace
        self.fileSystem = kernel.fileSystem
        let execPath = request.executablePath
        if !TrapProfile.programFilter.isEmpty {
            kernel.trapProfileSelected = TrapProfile.programFilter.contains((execPath as NSString).lastPathComponent)
        }
        let verbose = trace || (serial == 1 && !config.quietRuns)
        record = ImageRecord(serial: serial, pid: kernel.pid, executable: execPath)
        if BootProfile.shared != nil {
            record.launchNs = monotonicNanoseconds()
            record.requestNs = spawnTrapStart.value
            spawnTrapStart.value = 0
        }
        let pid = kernel.pid
        func say(_ text: String) { stderrLine("swiftcode-simd: " + launcher.tag(pid) + text) }

        try Self.checkExecutable(hostPath: request.hostExecutablePath)

        var buildTimer = ImageBuildProfile.shared.map { _ in ImageBuildProfile.Timer() }
        let taken = trace ? nil : launcher.prebuilt.take()
        let builder = try taken ?? ProcessBuilder(log: trace ? { say($0) } : nil)
        buildTimer?.mark()
        let profiling = BootProfile.shared != nil
        if profiling {
            record.prebuiltVM = taken == nil ? 0 : taken!.vm.reuseCount > 0 ? 2 : 1
            record.vmReadyNs = monotonicNanoseconds()
        }
        VMCounters.shared.vmCreated()
        vm = builder.vm
        space = builder.space
        var poolForCleanup: VCPUPool?
        do {
            let vm = builder.vm, space = builder.space
            if verbose {
                say("KVM memslots available: \(vm.maxMemorySlots); RAM \(VMLayout.stage3RAMSize >> 20) MiB; anonymous pool \(VMLayout.anonymousPoolSize >> 30) GiB at \(hex(VMLayout.anonymousPoolGPA))")
            }
            try vm.write(gpa: VMLayout.shimGPA, bytes: config.shim)

            let main = try builder.loadMainExecutable(path: execPath, hostPath: request.hostExecutablePath)
            let sim = try builder.loadDyldSim(path: config.dyldSimPath, guestPath: config.dyldSimPath, base: VMLayout.dyldSimBaseVA)
            buildTimer?.mark()
            if profiling { record.loadedNs = monotonicNanoseconds() }
            guard let prepareEntry = sim.entry else { throw LoaderError.message("dyld_sim entry not found") }
            if verbose {
                say("main \(execPath) at \(hex(main.machHeader)); dyld_sim at \(hex(sim.machHeader)) slide \(hex(sim.slide)) entry \(hex(prepareEntry))")
            }

            _ = try space.mapAnonymous(at: VMLayout.userStackBase, size: VMLayout.userStackSize, protection: .readWrite, hint: nil)
            let apple = AppleStrings(executablePath: execPath)
            let arguments = KernelArgumentBlock(userStack: VMLayout.userStackTop, argv: request.argv, envp: request.envp,
                                                apple: apple.strings + request.apple, machHeader: main.machHeader)
            try builder.poke(arguments.stackPointer, arguments.bytes)

            let hostBase = VMLayout.hostPageVA
            try space.mapPermanentAnonymous(at: hostBase + VMLayout.hostPageCodeOffset, size: VMLayout.hostPageCodeSize, protection: .readExecute)
            try space.mapPermanentAnonymous(at: hostBase + VMLayout.hostPageRODataOffset, size: VMLayout.hostPageRODataSize, protection: .read)
            try space.mapPermanentAnonymous(at: hostBase + VMLayout.hostPageRWDataOffset, size: VMLayout.hostPageRWDataSize, protection: .readWrite)
            try builder.poke(hostBase, config.stubs)
            let storage = DyldImageInfoStorage(base: HostPageLayout.imageInfoStorage,
                                               images: [.init(loadAddress: main.machHeader, path: execPath)])
            guard UInt64(storage.bytes.count) <= HostPageLayout.imageInfoStorageSize else { throw LoaderError.message("image info storage overflows") }
            try builder.poke(storage.infoArrayAddress, storage.bytes)
            let infos = DyldAllImageInfos.initial(infoArray: storage.infoArrayAddress, notification: hostBase + hostPageRetStubOffset,
                                                  simMH: sim.machHeader)
            try builder.poke(HostPageLayout.allImageInfos, infos.encoded())
            let launch = LaunchBlock(prepareEntry: prepareEntry, arguments: arguments, mainMH: main.machHeader,
                                     simMH: sim.machHeader, simSlide: sim.slide)
            try builder.poke(HostPageLayout.launchBlock, launch.encoded())

            let commpage = CommpageBuilder()
            try space.mapPermanentAnonymous(at: VMLayout.readOnlyCommpageVA, size: pageSize, protection: .read)
            try space.mapPermanentAnonymous(at: VMLayout.commpageVA, size: pageSize, protection: .read)
            try builder.poke(VMLayout.readOnlyCommpageVA, commpage.roPage())
            try builder.poke(VMLayout.commpageVA, commpage.rwPage())

            if config.trace {
                for region in space.regions { say("region \(region)") }
                say("argument block at \(hex(arguments.stackPointer)) (argc \(arguments.argc)); \(vm.memorySlotCount) memslots")
            }

            let threadBlock = MainThreadBlock(address: Stage3Layout.mainThreadPage, threadID: 1, threadPort: WellKnownPort.thread,
                                              stackTop: VMLayout.userStackTop, stackSize: VMLayout.userStackSize,
                                              qos: DarwinKernel.mainThreadQoS, ptrMunge: apple.ptrMunge)
            _ = try space.mapAnonymous(at: Stage3Layout.mainThreadPage, size: Stage3Layout.mainThreadPageSize,
                                       protection: .readWrite, hint: nil)
            try builder.poke(threadBlock.address, threadBlock.bytes)
            if verbose { say("main-thread block at \(hex(threadBlock.address)); TPIDRRO_EL0 = \(hex(threadBlock.tsdBase))") }

            buildTimer?.mark()
            let doorbell = FastTraps.doorbellAddress(for: vm, log: { say($0) })
            let pool = try VCPUPool(vm: vm, bootTemplate: BootInfo(ttbr0EL1: space.pageTables.rootGPA, el0EntryPC: 0,
                                                                   doorbellAddress: doorbell),
                                    maxExitsPerVCPU: config.maxExits)
            poolForCleanup = pool
            if config.trace { pool.log = { say($0) } }
            let vcpu0 = try pool.createWorker().vcpu
            buildTimer?.mark()
            if profiling { record.vcpuReadyNs = monotonicNanoseconds() }
            let (frequency, frequencySource) = vcpu0.counterFrequency()
            let (clock, directClock) = try launcher.systemClock(for: vcpu0, vm: vm, frequency: frequency, log: { say($0) })
            buildTimer?.mark()
            if verbose {
                say("CNTFRQ_EL0 = \(frequency) Hz (\(frequencySource)); KVM_CAP_MAX_VCPUS \(vm.maxVCPUs), "
                    + "KVM_CAP_NR_VCPUS \(vm.recommendedVCPUs); vCPU pool capacity \(pool.capacity)")
            }
            if config.trace {
                let guestMMFR2 = (try? vcpu0.get(SystemRegister.idAA64MMFR2EL1)) ?? 0
                say("ID_AA64MMFR2_EL1.FWB host \((Hypervisor.hostIDAA64MMFR2() >> 40) & 0xF) guest \((guestMMFR2 >> 40) & 0xF)"
                    + " (boot info and frames are also cleaned to PoC before a vCPU's first run)")
            }
            self.pool = pool
            pool.onParked = { [weak kernel = self.kernel] in kernel?.retryPendingWorkqueue() }

            let images = ImageMap(cache: config.cacheIndex)
            images.fixed = [
                main.image,
                sim.image,
                GuestImage(name: "swiftcode host page", start: hostBase, end: hostBase + VMLayout.hostPageSize, base: hostBase),
                GuestImage(name: "swiftcode main-thread block", start: Stage3Layout.mainThreadPage,
                           end: Stage3Layout.mainThreadPage + Stage3Layout.mainThreadPageSize, base: threadBlock.address),
            ]
            images.space = space
            images.hostLibraryPaths = config.hostLibraryPaths
            self.images = images

            let offset = clock.offset
            kernel.log = { [weak launcher] line in
                if trace { stderrLine((launcher?.tag(pid) ?? "") + trapPrefix.value + line) }
            }
            kernel.tracing = trace
            let guestHz = GuestTimebase.frequency(hostFrequency: frequency)
            let clockScale = GuestTimebase.ClockScale(from: frequency, to: guestHz)
            if clockScale == .identity {
                kernel.counter = { Hypervisor.hostCounter() &- offset }
            } else {
                kernel.counter = { clockScale.apply(Hypervisor.hostCounter() &- offset) }
            }
            kernel.counterFrequency = guestHz
            kernel.timeOfDayPublisher = try FastTraps.configureCommpage(
                space: space, vm: vm, directClock: directClock, counter: kernel.counter, frequency: guestHz,
                clockScale: clockScale, wallClock: kernel.wallClock)
            kernel.bootCounter = clockScale.apply(clock.bootCounter)
            kernel.allImageInfosAddress = HostPageLayout.allImageInfos
            kernel.mainStackTop = VMLayout.userStackTop
            kernel.threadHost = PoolThreadHost(pool: pool)
            kernel.processCPUTimes = { [weak pool] in
                guard let pool else { return (0, 0) }
                var total: UInt64 = 0, userTicks: UInt64 = 0, systemTicks: UInt64 = 0
                for tid in pool.hostThreadIDs {
                    guard let s = hostTaskStats(tid) else { continue }
                    userTicks &+= s[0]
                    systemTicks &+= s[1]
                    total &+= s[5]
                }
                let ticks = userTicks &+ systemTicks
                let system = ticks == 0 ? 0 : UInt64(Double(total) * Double(systemTicks) / Double(ticks))
                return (total &- system, system)
            }
            kernel.executableUUID = uuidBytes(main.uuid)

            let firstPC = MacOSMode.enabled ? prepareEntry : VMLayout.hostPageEntryVA
            mainState = VCPUStartState(pc: firstPC, sp: arguments.stackPointer, tpidrro: threadBlock.tsdBase)
            if var timer = buildTimer {
                timer.mark()
                ImageBuildProfile.shared?.record(timer)
            }
        } catch {
            poolForCleanup?.shutdown()
            builder.vm.close()
            VMCounters.shared.vmDestroyed()
            if let error = error as? DarwinErrnoError { throw error }
            throw error
        }
        record.image = self
        if BootProfile.shared != nil { record.builtNs = monotonicNanoseconds() }

        let shimCount = config.shim.count
        let lock = kernel.lock
        let space = self.space
        pool.preBootCleanRanges = {
            lock.withLock { [(VMLayout.shimGPA, shimCount),
                             (stage4TableArenaGPA, space.pageTables.tableCount * Int(VMLayout.pageSize))] }
        }
        let kernel = self.kernel
        pool.shouldStop = { kernel.isTerminating }
        pool.trapHandler = { worker, frame in self.handleTrap(worker, &frame) }
        pool.exitHandler = { worker, exit in
            dumpVCPU(worker.vcpu)
            if self.pid != rootPID { self.say("unexpected VM exit on vCPU \(worker.index): \(exit)") }
            return .terminate(status: 71, message: "unexpected VM exit on vCPU \(worker.index): \(exit)")
        }
        pool.onEnd = { end in self.launcher.imageEnded(self, end) }
        pool.onFinished = { self.finished() }
        if BootProfile.pcHz > 0 || GaugeRecorder.active {
            let depth = GaugeRecorder.active ? 128 : 8
            pool.sampleStackReader = { [weak space] fp in
                guard let space else { return [] }
                var out: [UInt64] = []
                var frame = fp
                var buffer: [UInt8] = []
                var bufferStart: UInt64 = 0
                for _ in 0..<depth {
                    guard frame != 0, frame & 7 == 0 else { break }
                    if frame < bufferStart || frame &+ 16 > bufferStart &+ UInt64(buffer.count) {
                        let blockEnd = (frame | 0xFFF) &+ 1
                        let count = max(16, Int(min(blockEnd &- frame, 4096)))
                        guard let raw = (try? space.read(va: frame, count: count, checkingEL0Access: true))
                                ?? (try? space.read(va: frame, count: 16, checkingEL0Access: true)) else { break }
                        buffer = raw
                        bufferStart = frame
                    }
                    let o = Int(frame &- bufferStart)
                    func word(_ at: Int) -> UInt64 { (0..<8).reduce(UInt64(0)) { $0 | UInt64(buffer[at + $1]) << (8 * UInt64($1)) } }
                    out.append(word(o + 8))
                    let next = word(o)
                    guard next > frame else { break }
                    frame = next
                }
                return out
            }
        }
        SnapshotSupport.shared?.attach(self)
    }

    func startMainThread() throws {
        guard let state = mainState else { return }
        mainState = nil
        if FrameProfile.active.load(ordering: .relaxed), let fp = FrameProfile.shared {
            fp.startRequested(pid: pid, context: kernel.mainThread, mainThread: true, serial: record.serial)
        }
        guard let index = try pool.start(state, context: kernel.mainThread) else {
            throw KVMError("vCPU pool", detail: "vCPU 0 is unavailable")
        }
        kernel.mainThread.vcpuIndex = index
    }

    var snapshotMainState: VCPUStartState? {
        get { mainState }
        set { mainState = newValue }
    }

    func resumeSuspended() {
        do { try startMainThread() } catch {
            say("cannot start the main thread: \(error)")
            pool.terminate(status: 1, message: "cannot start the main thread: \(error)", vcpuIndex: nil)
        }
    }

    func abandon() {
        pool.shutdown()
        destroy()
    }

    func destroy() {
        guard !destroyed else { return }
        destroyed = true
        let backing = space.backing as? KVMPhysicalBacking
        let reusable: Bool = kernel.lock.withLock {
            if let host = kernel.threadHost as? PoolThreadHost, host.pool === pool { kernel.threadHost = nil }
            space.discardAll()
            guard PrebuiltVMs.reuseEnabled, !trace, keptVMsForDebugging == nil, let backing else { return false }
            return backing.retireForReuse()
        }
        if reusable, let backing, launcher.prebuilt.recycle(vm: vm, backing: backing) {
        } else if keptVMsForDebugging == nil {
            vm.close()
        } else {
            keptVMsLock.withLock { keptVMsForDebugging!.append(vm) }
        }
        VMCounters.shared.vmDestroyed()
    }

    private func finished() {
        let end = pool.currentTermination
        if !endedByKernel.load(ordering: .relaxed), end?.kind == .terminated, pid != rootPID {
            kernel.lock.withLock {
                if !kernel.isTerminating { kernel.postSignal(9) }
            }
        }
        launcher.imageFinished(self)
    }

    static func checkExecutable(hostPath: String) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: hostPath, isDirectory: &isDirectory) else {
            throw DarwinErrnoError(LaunchErrno.ENOENT)
        }
        if isDirectory.boolValue { throw DarwinErrnoError(LaunchErrno.EACCES) }
        guard access(hostPath, R_OK) == 0 else { throw DarwinErrnoError(LaunchErrno.EACCES) }
        if !ExecutableHeader.mapWholeFile {
            let header: ExecutableHeader
            do {
                header = try ExecutableHeader.read(path: hostPath)
            } catch .noARM64Slice {
                throw DarwinErrnoError(LaunchErrno.EBADARCH)
            } catch {
                throw DarwinErrnoError(LaunchErrno.ENOEXEC)
            }
            guard header.image.fileType == .executable else { throw DarwinErrnoError(LaunchErrno.ENOEXEC) }
            try Self.checkRunnable(header.image)
            return
        }
        guard let fat = try? MachOFile(contentsOf: URL(fileURLWithPath: hostPath)) else {
            throw DarwinErrnoError(LaunchErrno.ENOEXEC)
        }
        guard let slice = fat.slices.first(where: { $0.cpuType == MachO.cpuTypeARM64 && $0.cpuSubtype & 0x00FF_FFFF == 0 })
                ?? fat.slices.first(where: { $0.cpuType == MachO.cpuTypeARM64 }) else {
            throw DarwinErrnoError(LaunchErrno.EBADARCH)
        }
        guard let image = try? MachOImage(fat.reader, at: slice.offset), image.fileType == .executable else {
            throw DarwinErrnoError(LaunchErrno.ENOEXEC)
        }
        try Self.checkRunnable(image)
    }

    static func checkRunnable(_ image: MachOImage) throws {
        let runnable = MacOSMode.enabled
            ? image.isArm64 && MachO.isPlainARM64(cpuSubtype: image.cpuSubtype) && MacOSMode.accepts(image.buildVersion?.platform)
            : image.isRunnableInSimulator
        guard runnable else { throw DarwinErrnoError(LaunchErrno.EBADARCH) }
    }

    func describeAddress(_ address: UInt64) -> String {
        kernel.lock.withLock { images.describe(address) }
    }

    func faultReport(_ frame: TrapFrame) -> String {
        kernel.lock.withLock {
            var lines = ["  ELR \(hex(frame.elr)) = \(images.describe(frame.elr))"]
            if frame.trapKind != .svc {
                lines.append("  FAR \(hex(frame.far)) = \(images.describe(frame.far)); region: \(space.region(containing: frame.far)?.description ?? "unmapped")")
            }
            lines.append("  LR  \(hex(frame.x[30])) = \(images.describe(frame.x[30]))")
            var fp = frame.x[29], chain: [String] = []
            while chain.count < 24, fp != 0, fp & 0xF == 0,
                  let raw = try? space.read(va: fp, count: 16, checkingEL0Access: false), raw.count == 16 {
                func word(_ at: Int) -> UInt64 { (0..<8).reduce(UInt64(0)) { $0 | UInt64(raw[at + $1]) << (8 * UInt64($1)) } }
                let next = word(0), ret = word(8) & 0x0000_FFFF_FFFF_FFFF
                if ret == 0 { break }
                chain.append("    #\(chain.count + 1) \(hex(ret)) = \(images.describe(ret))")
                if next <= fp { break }
                fp = next
            }
            if !chain.isEmpty { lines.append("  frame-pointer chain:"); lines += chain }
            if frame.syndrome.exceptionClass == .brk {
                for r in [0, 1] {
                    if let text = guestCString(frame.x[r]) { lines.append("  x\(r) -> \"\(text)\"") }
                }
                lines += crashAnnotations()
            } else if frame.trapKind != .svc {
                for r in 0..<29 where frame.x[r] >= 0x1_0000 {
                    if let text = guestCString(frame.x[r]) { lines.append("  x\(r) -> \"\(text)\"") }
                }
            }
            for r in [16, 17] where images.attribute(frame.x[r]) != nil {
                lines.append("  x\(r) \(hex(frame.x[r])) = \(images.describe(frame.x[r]))")
            }
            if let code = try? space.read(va: frame.elr & ~3, count: 4, checkingEL0Access: false) {
                lines.append("  instruction word at ELR: \(code.reversed().map { String(format: "%02x", $0) }.joined())")
            }
            return lines.joined(separator: "\n")
        }
    }

    private func crashAnnotations() -> [String] {
        var lines: [String] = []
        for info in launcher.config.cacheIndex.crashInfoSections() where info.size >= 40 {
            let va = info.address &+ images.cacheDelta
            guard let raw = try? space.read(va: va, count: Int(min(info.size, 64)), checkingEL0Access: false) else { continue }
            func word(_ i: Int) -> UInt64 {
                guard (i + 1) * 8 <= raw.count else { return 0 }
                return (0..<8).reduce(UInt64(0)) { $0 | UInt64(raw[i * 8 + $1]) << (8 * UInt64($1)) }
            }
            let name = (info.image as NSString).lastPathComponent
            for (index, field) in [(1, "message"), (2, "signature"), (4, "message2")] {
                let pointer = word(index)
                guard pointer != 0 else { continue }
                lines.append("  crash annotation \(name) \(field): " + (guestCString(pointer).map { "\"\($0)\"" } ?? hex(pointer)))
            }
            if word(7) != 0 { lines.append("  crash annotation \(name) abort_cause: \(hex(word(7)))") }
        }
        return lines
    }

    private func guestCString(_ va: UInt64) -> String? {
        let limit: UInt64 = 1 << 48
        guard va >= 0x1000, va < limit else { return nil }
        var bytes: [UInt8] = []
        var address = va
        while bytes.count < 1024, address < limit {
            let pageEnd = min((address | (VMLayout.pageSize - 1)) &+ 1, limit)
            let count = min(Int(pageEnd - address), 1024 - bytes.count)
            guard let chunk = try? space.read(va: address, count: count, checkingEL0Access: true) else { break }
            if let nul = chunk.firstIndex(of: 0) {
                bytes += chunk[..<nul]
                break
            }
            bytes += chunk
            address &+= UInt64(count)
        }
        guard bytes.count >= 2, bytes.allSatisfy({ (0x20..<0x7F).contains($0) || $0 == 0x0A || $0 == 0x09 || $0 >= 0x80 }),
              let text = String(validating: bytes, as: UTF8.self) else { return nil }
        return text.replacingOccurrences(of: "\n", with: "\\n")
    }

    private func noteCacheMapping(_ pending: CacheMappingTracker.Pending?, _ frame: TrapFrame, context: ThreadContext,
                                  verbose: Bool) {
        let images = self.images
        if let p = pending, let path = p.path, !frame.carry, frame.x[0] == p.address,
           p.flags & 0x10 != 0, (path as NSString).lastPathComponent.hasPrefix("dyld_sim_shared_cache_") {
            var mappingNotes: [String] = []
            kernel.lock.withLock(context: context) {
                if tracker.expected.isEmpty { tracker.expected = images.cacheMappings() }
                let name = (path as NSString).lastPathComponent
                if let index = tracker.expected.firstIndex(where: {
                    ($0.file as NSString).lastPathComponent == name && $0.mapping.fileOffset == p.offset && $0.mapping.size == p.size
                }) {
                    let header = tracker.expected[index].mapping.address
                    tracker.seen[index] = p.address
                    if index == 0 { images.cacheDelta = p.address &- header }
                    if verbose {
                        mappingNotes.append("swiftcode-simd: " + launcher.tag(pid) + "shared-cache mapping \(index + 1)/\(tracker.expected.count) \(name) @\(hex(p.offset)) size \(hex(p.size)) mapped at \(hex(p.address)) (header address \(hex(header))\(p.address == header ? ", exact" : ""))")
                    }
                }
            }
            for line in mappingNotes { stderrLine(line) }
        }
    }

    private func handleTrap(_ worker: VCPUPool.Worker, _ frame: inout TrapFrame) -> VCPUPool.Disposition {
        if TrapFrame.peelLevel == 3, frame.kind == TrapFrame.Kind.svc.rawValue, TrapFrame.peels(at: 3, x16: frame.x[16]) {
            frame.answerPeeled()
            return .resume
        }
        let context = (worker.context as? ThreadContext) ?? kernel.mainThread
        context.hostCPUBaseNanoseconds = worker.threadCPUBaseNanoseconds
        context.arrivingTrap = frame.x[16]
        defer { context.arrivingTrap = nil }
        if FrameProfile.active.load(ordering: .relaxed), let fp = FrameProfile.shared {
            let number: Int32 = frame.trapKind == .svc ? Int32(truncatingIfNeeded: frame.x[16]) : -1000
            fp.trapEnter(pid: pid, context: context, number: number, frame: frame)
            defer { fp.trapExit(pid: pid, context: context, number: number, frame: frame) }
            return handleTrapBody(worker, &frame, context: context)
        }
        return handleTrapBody(worker, &frame, context: context)
    }

    private func trapArgKey(_ number: Int64, _ frame: TrapFrame) -> String? {
        let x = frame.x
        switch number {
        case 202:
            let n = Int(min(x[1], 8))
            guard n > 0, let raw = try? space.read(va: x[0], count: 4 * n) else { return "sysctl ?" }
            let mib = (0..<n).map { i in String(raw.withUnsafeBytes { Int32(littleEndian: $0.loadUnaligned(fromByteOffset: 4 * i, as: Int32.self)) }) }.joined(separator: ".")
            return "sysctl \(mib)\(x[4] != 0 ? " set" : "")\(x[2] == 0 ? " size" : "")"
        case 274:
            let n = Int(min(x[1], 128))
            guard n > 0, let raw = try? space.read(va: x[0], count: n) else { return "sysctlbyname ?" }
            return "sysctlbyname \(String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self))\(x[4] != 0 ? " set" : "")"
        case 336:
            let pid = Int32(truncatingIfNeeded: x[1])
            return "proc_info call \(x[0]) flavor \(Int32(truncatingIfNeeded: x[2])) pid \(pid == self.pid ? "self" : pid == 0 ? "0" : "other") size \(x[5])"
        case 75:
            return "madvise advice \(Int32(truncatingIfNeeded: x[2]))"
        case -14:
            return "mach_vm_protect set_max \(x[3]) prot \(x[4])"
        case 92, 406:
            return "fcntl cmd \(Int32(truncatingIfNeeded: x[1]))"
        default:
            return nil
        }
    }

    private func handleTrapBody(_ worker: VCPUPool.Worker, _ frame: inout TrapFrame, context: ThreadContext) -> VCPUPool.Disposition {
        let kernel = self.kernel, images = self.images, space = self.space
        let verbose = trace || (record.serial == 1 && !launcher.config.quietRuns)
        let costOn = BootProfile.trapCosts
        let costNumber: Int64 = frame.trapKind == .svc ? Int64(Int32(truncatingIfNeeded: frame.x[16])) : -1000
        let costPre = costOn && !milestoneDone.load(ordering: .relaxed)
        let costTimes = costOn ? hostThreadTimes() : (userMicros: UInt64(0), systemMicros: UInt64(0), minorFaults: UInt64(0))
        let costNs: UInt64 = costOn ? monotonicNanoseconds() : 0
        if costOn, frame.trapKind == .svc, let key = trapArgKey(costNumber, frame) {
            BootProfile.shared?.recordTrapArgs(key)
        }
        defer {
            if costOn {
                BootProfile.shared?.recordTrapCost(number: costNumber, preMilestone: costPre,
                                                   wallNs: monotonicNanoseconds() &- costNs, start: costTimes)
            }
        }

        let isSVC = frame.trapKind == .svc
        let x16 = UInt32(truncatingIfNeeded: frame.x[16])
        var pendingResult: CacheMappingTracker.Pending?
        let count = trapCountAtomic.add(1, ordering: .relaxed).newValue
        if DarwinKernel.taskLocalTrapsEnabled, !trace, isSVC, DarwinKernel.isTaskLocalTrap(Int32(bitPattern: x16)),
           milestoneDone.load(ordering: .relaxed) || images.libSystemAttribution(frame.elr) == nil {
            let entryX0 = frame.x[0], entryX1 = frame.x[1], fullX16 = frame.x[16]
            context.trapInProgress = (fullX16, frame.x)
            let outcome = kernel.handleTaskLocal(&frame, context: context, memory: space)
            context.trapInProgress = nil
            if outcome != nil {
                taskLocalTrapCount.wrappingAdd(1, ordering: .relaxed)
                context.trapCount += 1
                context.trapRing.record(fullX16, entryX0, entryX1, frame.carry ? (1 << 63) | frame.x[0] : frame.x[0])
                return .resume
            }
        }
        if !trace, isSVC, DarwinKernel.bsdFastTrapsEnabled, DarwinKernel.isBSDFastTrap(Int32(bitPattern: x16)),
           milestoneDone.load(ordering: .relaxed) || images.libSystemAttribution(frame.elr) == nil {
            let entryX0 = frame.x[0], entryX1 = frame.x[1], fullX16 = frame.x[16]
            let mmapPending: CacheMappingTracker.Pending? = x16 == 197
                ? .init(address: frame.x[0], size: frame.x[1], flags: frame.x[3], fd: Int32(truncatingIfNeeded: frame.x[4]),
                        offset: frame.x[5], path: try? fileSystem.path(for: Int32(truncatingIfNeeded: frame.x[4])))
                : nil
            context.trapInProgress = (fullX16, frame.x)
            let outcome = kernel.handleBSDFast(&frame, context: context, memory: space)
            context.trapInProgress = nil
            if outcome != nil {
                if mmapPending != nil { noteCacheMapping(mmapPending, frame, context: context, verbose: verbose) }
                context.trapCount += 1
                context.trapRing.record(fullX16, entryX0, entryX1, frame.carry ? (1 << 63) | frame.x[0] : frame.x[0])
                return .resume
            }
        }
        if !trace, isSVC, kernel.hasIPCFastPaths, DarwinKernel.isIPCFastTrap(Int32(bitPattern: x16)),
           milestoneDone.load(ordering: .relaxed) {
            let entryX0 = frame.x[0], entryX1 = frame.x[1], fullX16 = frame.x[16]
            context.trapInProgress = (fullX16, frame.x)
            let outcome = kernel.handleIPCFast(&frame, context: context, memory: space)
            context.trapInProgress = nil
            if let outcome {
                context.trapCount += 1
                context.trapRing.record(fullX16, entryX0, entryX1, frame.carry ? (1 << 63) | frame.x[0] : frame.x[0])
                return .resume
            }
        }
        let needsPrologue = trace || !milestoneDone.load(ordering: .relaxed) || (isSVC && x16 == 197)
        var notes: [String] = []
        let arrivedFrame = frame
        if isSVC, x16 == 244 || x16 == 59 || x16 == 380, !trace {
            let t0 = costOn ? hostThreadTimes() : (userMicros: UInt64(0), systemMicros: UInt64(0), minorFaults: UInt64(0))
            let n0: UInt64 = costOn ? monotonicNanoseconds() : 0
            if BootProfile.shared != nil { spawnTrapStart.value = monotonicNanoseconds() }
            launcher.prebuilt.prepare()
            if costOn {
                BootProfile.shared?.recordTrapCost(number: 100_000, preMilestone: false, wallNs: monotonicNanoseconds() &- n0, start: t0)
            }
        }
        context.trapInProgress = (frame.x[16], frame.x)
        let entryX0 = frame.x[0], entryX1 = frame.x[1]
        let outcome = kernel.handle(&frame, context: context, memory: space) { entry in
            guard needsPrologue else { return }
            if BootProfile.shared != nil, !milestoneReached {
                preMilestoneTraps[isSVC ? Int64(Int32(truncatingIfNeeded: x16)) : -1000, default: 0] += 1
            }
            let attribution = trace ? images.attribute(entry.elr) : nil
            if !milestoneReached, let (image, offset) = images.libSystemAttribution(entry.elr) {
                milestoneReached = true
                milestoneDone.store(true, ordering: .relaxed)
                if BootProfile.shared != nil { noteMilestone(worker) }
                if verbose {
                    notes.append(launcher.tag(pid) + "milestone: libSystem initializer reached (\(image.name) + \(hex(offset)); "
                        + "LR \(hex(entry.x[30])) = \(images.describeIfCheap(entry.x[30])))")
                }
            }
            if trace {
                let place = attribution.map { "\($0.image.name.split(separator: "/").last.map(String.init) ?? $0.image.name)+\(hex($0.offset))" } ?? hex(entry.elr)
                let threadTag = context.threadID == 1 ? "" : "t\(context.threadID) "
                trapPrefix.value = "[\(count)] \(threadTag)\(place): "
            }
            if trace, isSVC, x16 == 374 || x16 == 375 {
                dumpKevents(space, list: entry.x[1], count: Int(entry.x[2]), label: "change")
            }
            guard isSVC, x16 == 197 else { return }
            let fd = Int32(truncatingIfNeeded: entry.x[4])
            pendingResult = .init(address: entry.x[0], size: entry.x[1], flags: entry.x[3], fd: fd,
                                  offset: entry.x[5], path: try? fileSystem.path(for: fd))
        }
        for note in notes { stderrLine(note) }
        let pending = pendingResult
        context.trapInProgress = nil
        context.trapCount += 1
        context.trapRing.record(arrivedFrame.x[16], entryX0, entryX1, frame.carry ? (1 << 63) | frame.x[0] : frame.x[0])
        if trace, isSVC, x16 == 368, outcome == .resume, frame.x[16] == 0, frame.x[5] > 0, frame.x[5] < 64, frame.x[3] != 0 {
            kernel.lock.withLock { dumpKevents(space, list: frame.x[3], count: Int(frame.x[5]), label: "event") }
        }

        noteCacheMapping(pending, frame, context: context, verbose: verbose)

        switch outcome {
        case .resume:
            return .resume
        case .threadExit:
            if trace { say("\(context) ended; vCPU \(worker.index) parked") }
            return .park
        case let .exit(status):
            return end(.terminated, status: status, message: "guest exited with status \(status)", worker: worker)
        case .imageReplaced:
            if trace { say("image \(record.serial) replaced by exec") }
            return end(.ended, status: 0, message: "replaced by exec", worker: worker)
        case let .fatal(status, message):
            let reportFrame = kernel.lock.withLock { kernel.faultFrame } ?? arrivedFrame
            var text = ""
            if DarwinKernel.isCachePatchPlaceholderFault(reportFrame) {
                text += "\(DarwinKernel.cachePatchPlaceholderMessage): ELR \(hex(reportFrame.elr)) = "
                    + "\(describeAddress(reportFrame.elr)); LR \(hex(reportFrame.x[30])) = \(describeAddress(reportFrame.x[30]))\n"
            }
            text += "fatal guest condition in \((record.executable as NSString).lastPathComponent) on \(context), vCPU \(worker.index) (exit \(status)):\n\(message)\n\(faultReport(reportFrame))"
            if !context.recentTraps.isEmpty {
                text += "\n  last traps of this thread: " + context.recentTraps.map(DarwinKernel.ringEntry).joined(separator: " ")
            }
            if status == DarwinKernel.abortExitStatus, reportFrame.syndrome.exceptionClass != .brk {
                let notes = kernel.lock.withLock { crashAnnotations() }
                if !notes.isEmpty { text += "\n" + notes.joined(separator: "\n") }
            }
            let first = fatalReported.compareExchange(expected: false, desired: true, ordering: .relaxed).exchanged
            if first, pid != rootPID, trace || status == DarwinKernel.exceptionExitStatus || status == DarwinKernel.abortExitStatus {
                say(text)
            } else if !first, trace {
                say("\(context) ends with the process (fatal condition already reported)")
            }
            return end(.terminated, status: status, message: text, worker: worker)
        case let .unimplemented(description):
            kernel.lock.withLock { trapCounts[String(description.prefix { $0 != "(" }), default: 0] += 1 }
            if launcher.config.trace && !options.keepGoing {
                let message = "first unimplemented trap (\(context)): \(description)\n\(frame)\n\(faultReport(frame))"
                launcher.abortHost(status: DarwinKernel.unimplementedExitStatus, message: launcher.tag(pid) + message)
                return .terminate(status: DarwinKernel.unimplementedExitStatus, message: message)
            }
            return .resume
        case let .unimplementedLibraryFunction(name) where options.libfuncReturns[name] != nil:
            let value = options.libfuncReturns[name]!
            say("unimplemented libfunc \(name) (LR \(hex(frame.x[30])) = \(describeAddress(frame.x[30]))) "
                + "[--libfunc-return: x0 = \(hex(value))]")
            frame.x[0] = value
            frame.elr = frame.x[30]
            return .resume
        case let .unimplementedLibraryFunction(name):
            let seen = kernel.lock.withLock { () -> Int in
                trapCounts["libfunc " + name, default: 0] += 1
                return trapCounts["libfunc " + name] ?? 0
            }
            if seen <= 3 || seen % 100 == 0 {
                say("unimplemented libfunc \(name) (LR \(hex(frame.x[30])) = \(describeAddress(frame.x[30])))"
                    + (seen > 3 ? " [call \(seen)]" : ""))
            }
            if launcher.config.trace && !options.keepGoing {
                let message = "first unimplemented host-library function (\(context)): \(name)\n\(frame)\n\(faultReport(frame))"
                launcher.abortHost(status: DarwinKernel.unimplementedLibraryFunctionExitStatus, message: launcher.tag(pid) + message)
                return .terminate(status: DarwinKernel.unimplementedLibraryFunctionExitStatus, message: message)
            }
            return .resume
        }
    }

    private func end(_ kind: VCPUPool.Termination.Kind, status: Int32, message: String,
                     worker: VCPUPool.Worker) -> VCPUPool.Disposition {
        endedByKernel.store(true, ordering: .relaxed)
        return kind == .ended ? .end(message: message) : .terminate(status: status, message: message)
    }

    func summary(locked: Bool) -> String {
        let exits = pool.exitCount
        let traps = trapCountAtomic.load(ordering: .relaxed)
        guard locked else { return "\(traps) traps, \(exits) VM exits, \(pool.vcpuCount) vCPUs (peak \(pool.peakThreads) threads)" }
        return kernel.lock.withLock {
            let expected = tracker.expected.count
            let exact = tracker.seen.filter { tracker.expected[$0.key].mapping.address == $0.value }.count
            let locks = "; kernel lock \(kernel.lock.acquisitions) acquisitions, "
                + "\(kernel.lock.totalHeldNanoseconds / 1_000_000) ms held"
            return "\(traps) traps, \(exits) VM exits, \(pool.vcpuCount) vCPUs (peak \(pool.peakThreads) threads); "
                + "shared-cache mappings mapped: \(tracker.seen.count)/\(expected)"
                + " (\(exact) at the header address); milestone \(milestoneReached ? "reached" : "not reached")" + locks
        }
    }

    func unimplementedSummary() -> String? {
        let counts = kernel.lock.withLock { trapCounts }
        guard !counts.isEmpty else { return nil }
        return counts.sorted { $0.key < $1.key }.map { "\($0.key) x\($0.value)" }.joined(separator: ", ")
    }

    var trapTotal: Int { trapCountAtomic.load(ordering: .relaxed) }

    func attributeForProfile(_ pc: UInt64) -> (String, UInt64) {
        if let image = images.fixed.first(where: { pc >= $0.start && pc < $0.end }) {
            return ((image.name as NSString).lastPathComponent, pc &- image.base)
        }
        if pc >= VMLayout.sharedRegionBase, pc < VMLayout.sharedRegionEnd, let list = images.cache.cacheImagesIfReady() {
            let header = pc &- images.cacheDelta
            var low = 0, high = list.count
            while low < high {
                let mid = (low + high) / 2
                if list[mid].start <= header { low = mid + 1 } else { high = mid }
            }
            if low > 0, header < list[low - 1].end {
                return ((list[low - 1].name as NSString).lastPathComponent, header &- list[low - 1].base)
            }
            return ("shared cache (no image)", 0)
        }
        if pc >= 0xFFFF_0000_0000_0000 { return ("EL1 shim", 0) }
        return ("other (host library, JIT, stub)", pc & ~0xFFFF)
    }

    private func noteMilestone(_ worker: VCPUPool.Worker) {
        record.milestoneNs = monotonicNanoseconds()
        record.milestoneTraps = trapCountAtomic.load(ordering: .relaxed)
        record.milestoneLockWaitNs = kernel.profileLockWaitNanoseconds
        record.milestoneLockHeldNs = kernel.profileLockHeldNanoseconds
        record.milestoneRunNs = worker.runNanoseconds
        record.milestoneHandlerNs = worker.handlerNanoseconds
        record.milestoneTopTraps = preMilestoneTraps.sorted { $0.value > $1.value }.prefix(6)
            .map { "\($0.key)x\($0.value)" }.joined(separator: " ")
        if let s = hostTaskStats(ckvmThreadID()) {
            record.milestoneCPUNs = s[5]
            record.milestoneGuestTicks = s[2]
            record.milestoneSystemTicks = s[1]
            record.milestoneMinorFaults = s[3]
        }
        let k = worker.vcpu.kvmStatistics(["exits", "wfe_exit_stat", "wfi_exit_stat"])
        record.milestoneKVMExits = k[0]
        record.milestoneWFxExits = k[1] &+ k[2]
        record.milestoneUserExits = UInt64(worker.vcpu.exitCount)
    }

    func captureProfile() {
        record.hostStats = pool.hostStats
        record.firstRunNs = pool.firstRunNanoseconds.load(ordering: .relaxed)
        record.traps = trapTotal
        record.taskLocalTraps = taskLocalTrapCount.load(ordering: .relaxed)
        record.vcpus = pool.vcpuCount
        kernel.lock.withLock {
            record.lockHeldNs = kernel.profileLockHeldNanoseconds
            record.lockWaitNs = kernel.profileLockWaitNanoseconds
            record.lockAcquisitions = kernel.profileLockAcquisitions
        }
        record.tornDownNs = monotonicNanoseconds()
    }
}

final class PoolThreadHost: ThreadHost {
    struct Exhausted: Error, CustomStringConvertible {
        var capacity: Int
        var description: String { "the vCPU pool is exhausted (\(capacity) vCPUs)" }
    }
    weak var pool: VCPUPool?
    init(pool: VCPUPool) { self.pool = pool }

    static let restoring = Atomic<Bool>(false)

    var canStartThread: Bool { !Self.restoring.load(ordering: .acquiring) && (pool?.hasRoom ?? false) }

    func startThread(_ start: ThreadStartState, context: ThreadContext) throws -> Int {
        guard let pool, !Self.restoring.load(ordering: .acquiring) else { throw Exhausted(capacity: 0) }
        let state = VCPUStartState(pc: start.pc, sp: start.sp, registers: start.x, tpidrro: start.tpidrro, tpidr: start.tpidr)
        if FrameProfile.active.load(ordering: .relaxed), let fp = FrameProfile.shared {
            fp.startRequested(pid: context.kernel?.pid ?? -1, context: context, mainThread: false)
        }
        guard let index = try pool.start(state, context: context) else { throw Exhausted(capacity: pool.capacity) }
        context.vcpuIndex = index
        return index
    }

    func stopAllThreads() {
        pool?.requestStop("stopped by the kernel")
    }

    func kickThread(_ context: ThreadContext) {
        pool?.kickThread(context: context)
    }
}
#endif
