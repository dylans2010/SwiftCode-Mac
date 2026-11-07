import Foundation
import SwiftCodeDebug

struct DebugServerOptions {
    var address: String
    var log = false
    var launchStopped = false
}

#if os(Linux) && arch(arm64)
import CKVM
import Glibc
import SwiftCodeDarwinABI
import SwiftCodeDarwinKernel
import SwiftCodeHypervisor

final class SimDebugServer: GDBRemoteHost, @unchecked Sendable {
    nonisolated(unsafe) static var shared: SimDebugServer?

    let options: DebugServerOptions
    var launchedPID: () -> Int32? = { nil }
    var osType = "ios"
    var osVersion = ""
    var osBuild = ""
    var launchExecutable: String?
    private var launcher: VMMLauncher?
    private var listener: GDBRemoteListener?

    final class SpawnWait {
        let name: String
        var process: SimDebugProcess?
        init(name: String) { self.name = name }
    }
    private let waitLock = NSLock()
    private var spawnWaits: [SpawnWait] = []
    private var launchWait: SpawnWait?

    init(options: DebugServerOptions) { self.options = options }

    func start(launcher: VMMLauncher) {
        self.launcher = launcher
        if options.launchStopped, let name = launchExecutable {
            let w = SpawnWait(name: name)
            waitLock.withLock { spawnWaits.append(w) }
            launchWait = w
            stderrLine("swiftcode-simd: debug: \(name) is held at its first instruction when it starts, until a debugger attaches")
        }
        do {
            if options.address.hasPrefix("unix:") {
                let dir = (String(options.address.dropFirst(5)) as NSString).deletingLastPathComponent
                if !dir.isEmpty { try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true) }
            }
            let l = try GDBRemoteListener(address: options.address)
            listener = l
            stderrLine("swiftcode-simd: debug: gdb-remote stub listening on \(l.description)")
            let t = Thread { [self] in acceptLoop(l) }
            t.name = "swiftcode debug stub"
            t.start()
        } catch {
            stderrLine("swiftcode-simd: debug: cannot listen on \(options.address): \(error)")
        }
    }

    func stop() {
        listener?.close()
        listener = nil
    }

    private func acceptLoop(_ l: GDBRemoteListener) {
        while let c = l.accept() {
            stderrLine("swiftcode-simd: debug: client connected")
            let server = GDBRemoteServer(host: self, connection: c)
            if options.log { server.log = { stderrLine("swiftcode-simd: debug: " + $0) } }
            server.serve()
            stderrLine("swiftcode-simd: debug: client disconnected")
        }
    }

    var hostInfo: [(String, String)] {
        var pairs = [("cputype", "16777228"), ("cpusubtype", "0"), ("ostype", osType), ("vendor", "apple"), ("endian", "little"),
                     ("ptrsize", "8"), ("vm-page-size", "16384")]
        if !osVersion.isEmpty { pairs.append(("os_version", osVersion)) }
        if !osBuild.isEmpty { pairs.append(("os_build", GDBRemoteHex.encode(text: osBuild))) }
        pairs += [("watchpoint_exceptions_received", "before"), ("hostname", GDBRemoteHex.encode(text: "swiftcode-simulator")),
                  ("default_packet_timeout", "20")]
        return pairs
    }

    static func runtimeVersion(root: String) -> (String, String) {
        let path = root + "/System/Library/CoreServices/SystemVersion.plist"
        guard let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return ("", "")
        }
        return (plist["ProductVersion"] as? String ?? "", plist["ProductBuildVersion"] as? String ?? "")
    }

    func imageWillStart(_ image: GuestImageInstance) {
        let wait: SpawnWait? = waitLock.withLock {
            spawnWaits.first { $0.process == nil && Self.matches(image, $0.name) }
        }
        guard let wait, let p = SimDebugProcess.hold(image, server: self) else { return }
        waitLock.withLock { wait.process = p }
        stderrLine("swiftcode-simd: debug: pid \(image.pid) (\(Self.name(image))) held at its first instruction for the debugger")
    }

    static func matches(_ i: GuestImageInstance, _ name: String) -> Bool {
        Self.name(i) == name || i.record.executable == name
    }

    private func process(of wait: SpawnWait, seconds: Double) -> SimDebugProcess? {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if let p = waitLock.withLock({ wait.process }) { return p }
            usleep(1000)
        }
        return nil
    }

    private func removeWait(_ wait: SpawnWait) {
        waitLock.withLock { spawnWaits.removeAll { $0 === wait } }
    }

    private var images: [GuestImageInstance] { launcher?.snapshotLiveImages.filter { !$0.kernel.isTerminating } ?? [] }

    static func name(_ image: GuestImageInstance) -> String { (image.record.executable as NSString).lastPathComponent }

    func processes() -> [(pid: Int, name: String)] {
        images.map { (Int($0.pid), Self.name($0)) }.sorted { $0.pid < $1.pid }
    }

    func initialProcess() -> GDBRemoteProcess? {
        if let w = launchWait, let held = waitLock.withLock({ w.process }) {
            removeWait(w)
            launchWait = nil
            if case let .success(p) = held.finishAttach() { return p }
        }
        guard let pid = launchedPID(), case let .success(p) = attach(pid: Int(pid)) else { return nil }
        return p
    }

    func attach(pid: Int) -> Result<GDBRemoteProcess, GDBRemoteError> {
        guard let image = images.first(where: { Int($0.pid) == pid }) else { return .failure(GDBRemoteError(0x01, "no process \(pid)")) }
        switch SimDebugProcess.attach(image, server: self) {
        case let .success(p): return .success(p)
        case let .failure(e): return .failure(e)
        }
    }

    func attach(name: String, wait: Bool, includeExisting: Bool) -> Result<GDBRemoteProcess, GDBRemoteError> {
        if !wait || includeExisting, let image = images.first(where: { Self.matches($0, name) }) { return attach(pid: Int(image.pid)) }
        guard wait else { return .failure(GDBRemoteError(0x01, "no process named \(name)")) }
        let w = SpawnWait(name: name)
        waitLock.withLock { spawnWaits.append(w) }
        defer { removeWait(w) }
        guard let held = process(of: w, seconds: 600) else { return .failure(GDBRemoteError(0x01, "no process named \(name) started")) }
        switch held.finishAttach() {
        case let .success(p): return .success(p)
        case let .failure(e): return .failure(e)
        }
    }
}

final class SimDebugProcess: GDBRemoteProcess, KernelDebugger, @unchecked Sendable {
    let image: GuestImageInstance
    let kernel: DarwinKernel
    lazy var breakpoints = GDBRemoteBreakpoints(read: { [unowned self] a, n in rawRead(a, n) },
                                                write: { [unowned self] a, b in rawWrite(a, b) })
    private let osType: String
    private let osVersion: String

    private let condition = NSCondition()
    private var pendingThread: UInt64?
    private var interruptRequested = false
    private var signalThread: UInt64?
    private var codeChanged = false
    private var stopThreads: [UInt64] = []

    private init(image: GuestImageInstance, osType: String, osVersion: String) {
        self.image = image
        kernel = image.kernel
        self.osType = osType
        self.osVersion = osVersion
    }

    static func attach(_ image: GuestImageInstance, server: SimDebugServer) -> Result<SimDebugProcess, GDBRemoteError> {
        let p = SimDebugProcess(image: image, osType: server.osType, osVersion: server.osVersion)
        guard p.kernel.debugAttach(p) else { return .failure(GDBRemoteError(0x01, "process \(image.pid) is ending or already debugged")) }
        return p.finishAttach()
    }

    static func hold(_ image: GuestImageInstance, server: SimDebugServer) -> SimDebugProcess? {
        let p = SimDebugProcess(image: image, osType: server.osType, osVersion: server.osVersion)
        guard p.kernel.debugAttach(p) else { return nil }
        p.heldAtStart = true
        return p
    }

    private var heldAtStart = false

    func finishAttach() -> Result<SimDebugProcess, GDBRemoteError> {
        var stopped = waitUntilStopped(seconds: 10)
        if stopped, heldAtStart {
            let deadline = Date().addingTimeInterval(10)
            while !kernel.debugIsParked(kernel.mainThread) && !kernel.isTerminating {
                if Date() > deadline { stopped = false; break }
                usleep(250)
            }
        }
        guard stopped else {
            kernel.debugDetach()
            return .failure(GDBRemoteError(0x01, "process \(image.pid) did not stop"))
        }
        signalThread = kernel.debugThreads.first?.threadID
        stopThreads = kernel.debugThreads.map(\.threadID)
        let pc = signalThread.flatMap { registers($0)?.pc }.map { " at pc 0x" + String($0, radix: 16) } ?? ""
        stderrLine("swiftcode-simd: debug: attached to pid \(image.pid) (\(SimDebugServer.name(image))), \(kernel.debugThreads.count) threads\(pc)")
        return .success(self)
    }

    private func waitUntilStopped(seconds: Double) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        var rounds = 0
        while !kernel.debugAllStopped() {
            if Date() > deadline { return false }
            if rounds % 4 == 3 { kernel.debugKickRunning() }
            rounds += 1
            usleep(250)
        }
        return true
    }

    private func thread(_ tid: UInt64) -> ThreadContext? { kernel.debugThreads.first { $0.threadID == tid } }

    func kernelDebugException(_ kernel: DarwinKernel, thread: ThreadContext, stop: KernelDebugStop) -> KernelDebugDecision {
        if case .breakpoint = stop.kind, !breakpoints.contains(stop.pc) {
            let now = rawRead(stop.pc, 4)
            if now.count == 4, GDBRemoteHex.littleEndianValue(now) & 0xFFE0_001F != 0xD420_0000 { return .retry }
        }
        condition.lock()
        if pendingThread == nil { pendingThread = thread.threadID }
        condition.broadcast()
        condition.unlock()
        return .stop
    }

    var pid: Int { Int(image.pid) }

    var processInfo: [(String, String)] {
        [("parent-pid", String(kernel.debugParentPID, radix: 16)), ("real-uid", "1f5"), ("real-gid", "14"),
         ("effective-uid", "1f5"), ("effective-gid", "14"), ("cputype", "100000c"), ("cpusubtype", "0"),
         ("ostype", osType), ("vendor", "apple"), ("endian", "little"), ("ptrsize", "8")]
            + (osVersion.isEmpty ? [] : [("os_version", osVersion)])
    }

    func loadedImages() -> [(address: UInt64, path: String)]? {
        let infos = kernel.allImageInfosAddress
        let head = rawRead(infos, 40)
        guard head.count == 40 else { return nil }
        let count = Int(min(GDBRemoteMachO.u32(head, DyldAllImageInfos.Offset.infoArrayCount), 1 << 14))
        let array = GDBRemoteMachO.u64(head, DyldAllImageInfos.Offset.infoArray)
        let dyld = GDBRemoteMachO.u64(head, DyldAllImageInfos.Offset.dyldImageLoadAddress)
        var out: [(address: UInt64, path: String)] = []
        if array != 0, count > 0 {
            let bytes = rawRead(array, 24 * count)
            for o in stride(from: 0, to: bytes.count / 24 * 24, by: 24) {
                let a = GDBRemoteMachO.u64(bytes, o)
                guard a != 0 else { continue }
                out.append((a, GDBRemoteServer.cString(at: GDBRemoteMachO.u64(bytes, o + 8)) { [self] in rawRead($0, $1) }))
            }
        }
        if dyld != 0, !out.contains(where: { $0.address == dyld }) {
            out.append((dyld, memoryRegion(at: dyld)?.name ?? "/usr/lib/dyld_sim"))
        }
        return out
    }

    var dyldState: GDBRemoteDyldState? {
        if kernel.debugDyldMainCalled { return .programRunning }
        let infos = kernel.allImageInfosAddress
        let head = rawRead(infos, 32)
        guard head.count == 32 else { return nil }
        if head[DyldAllImageInfos.Offset.libSystemInitialized] != 0 { return .libSystemInitialized }
        return GDBRemoteMachO.u32(head, DyldAllImageInfos.Offset.infoArrayCount) > 1 ? .dyldInitialized : .notStarted
    }

    struct Watch: Equatable {
        var address: UInt64
        var size: Int
        var kind: GDBRemoteWatchKind
        var registers: VCPUPool.HardwareWatchpoint
    }
    private var watches: [Watch] = []
    private var steppedThreads: Set<UInt64> = []
    private var stepStarts: [UInt64: UInt64] = [:]

    var watchpointSlots: Int { min(image.pool.hardwareWatchpointCount, 16) }

    static func registers(address: UInt64, size: Int, kind: GDBRemoteWatchKind) -> VCPUPool.HardwareWatchpoint? {
        let lsc: UInt64 = kind == .read ? 1 : kind == .write ? 2 : 3
        let common: UInt64 = 1 | (0b10 << 1) | (lsc << 3)
        let base = address & ~UInt64(7)
        if size <= 8, address + UInt64(size) <= base + 8 {
            let bas = ((UInt64(1) << UInt64(size)) - 1) << (address - base)
            return .init(value: base, control: common | (bas << 5))
        }
        let n = UInt64(size)
        guard n >= 8, n <= 1 << 31, n & (n - 1) == 0, address & (n - 1) == 0 else { return nil }
        return .init(value: address, control: common | (0xFF << 5) | (UInt64(n.trailingZeroBitCount) << 24))
    }

    func insertWatchpoint(address: UInt64, size: Int, kind: GDBRemoteWatchKind) -> Result<Void, GDBRemoteError> {
        if watches.contains(where: { $0.address == address && $0.size == size && $0.kind == kind }) { return .success(()) }
        guard let r = Self.registers(address: address, size: size, kind: kind) else {
            return .failure(GDBRemoteError(0x16, "a watchpoint of \(size) bytes at 0x\(String(address, radix: 16)) cannot be set"))
        }
        guard watches.count < watchpointSlots else { return .failure(GDBRemoteError(0x1C, "no free hardware watchpoint")) }
        watches.append(Watch(address: address, size: size, kind: kind, registers: r))
        image.pool.setHardwareWatchpoints(watches.map(\.registers))
        return .success(())
    }

    func removeWatchpoint(address: UInt64, size: Int, kind: GDBRemoteWatchKind) -> Result<Void, GDBRemoteError> {
        let before = watches.count
        watches.removeAll { $0.address == address && $0.size == size && $0.kind == kind }
        if watches.count != before { image.pool.setHardwareWatchpoints(watches.map(\.registers)) }
        return .success(())
    }

    func watchStop(hit: UInt64) -> GDBRemoteStopReason {
        if let i = watches.firstIndex(where: { hit >= $0.address && hit < $0.address + UInt64($0.size) }) {
            return .watchpoint(address: hit, index: i, hit: hit)
        }
        let candidates = watches.enumerated().filter { _, w in (hit & ~UInt64(7)) < w.address + UInt64(w.size) && hit + 16 > w.address }
        if let (i, w) = candidates.min(by: { abs(Int64(bitPattern: $0.1.address &- hit)) < abs(Int64(bitPattern: $1.1.address &- hit)) }) {
            return .watchpoint(address: w.address, index: i, hit: hit)
        }
        return .watchpoint(address: watches.first?.address ?? hit, index: 0, hit: hit)
    }

    var sharedLibraryInfoAddress: UInt64? { kernel.allImageInfosAddress }

    var sharedCacheInfo: (base: UInt64, uuid: [UInt8])? {
        let infos = kernel.allImageInfosAddress
        let uuid = rawRead(infos &+ UInt64(DyldAllImageInfos.Offset.sharedCacheUUID), 16)
        let base = GDBRemoteHex.littleEndianValue(rawRead(infos &+ UInt64(DyldAllImageInfos.Offset.sharedCacheBaseAddress), 8))
        guard uuid.count == 16, uuid.contains(where: { $0 != 0 }), base != 0 else { return nil }
        return (base, uuid)
    }
    var hasFloatingPointRegisters: Bool { true }

    func threadIDs() -> [UInt64] {
        let alive = Set(kernel.debugThreads.map(\.threadID))
        return stopThreads.filter { alive.contains($0) }
    }

    func threadName(_ tid: UInt64) -> String? { nil }

    func dispatchQueueAddress(_ tid: UInt64) -> UInt64? {
        guard let t = thread(tid), t.pthreadAddress != 0 else { return nil }
        return t.pthreadAddress + 224 + 20 * 8
    }

    func stopInfo(_ tid: UInt64) -> GDBRemoteThreadStop {
        guard let t = thread(tid) else { return .quiet }
        guard let stop = kernel.debugStopOf(t) else {
            return tid == signalThread ? GDBRemoteThreadStop(signal: 17, reason: .signal) : .quiet
        }
        switch stop.kind {
        case let .breakpoint(immediate):
            if steppedThreads.contains(tid), breakpoints.contains(stop.pc) {
                if let from = stepStarts[tid], stop.pc != from &+ 4 {
                    stderrLine("swiftcode-simd: debug: thread \(tid) stepped from 0x\(String(from, radix: 16)) to the breakpoint at 0x\(String(stop.pc, radix: 16))")
                    stepStarts[tid] = nil
                }
                return GDBRemoteThreadStop(signal: 5, reason: .trace)
            }
            if breakpoints.contains(stop.pc) { return GDBRemoteThreadStop(signal: 5, reason: .breakpoint) }
            return GDBRemoteThreadStop(signal: 5, reason: .exception("EXC_BREAKPOINT (brk #\(String(immediate, radix: 16)))"))
        case .step:
            return GDBRemoteThreadStop(signal: 5, reason: .trace)
        case let .fault(signal, description):
            return GDBRemoteThreadStop(signal: Int(signal), reason: .exception(description))
        case let .watchpoint(address, _):
            return GDBRemoteThreadStop(signal: 5, reason: watchStop(hit: address))
        }
    }

    private func vcpu(of t: ThreadContext) -> VCPU? {
        image.pool.activeWorkers().first { $0.context === t }?.vcpu
    }

    func registers(_ tid: UInt64) -> GDBRemoteThreadRegisters? {
        guard let t = thread(tid), let f = kernel.debugRegisters(t) else { return nil }
        var r = GDBRemoteThreadRegisters(x: Array(f.x.prefix(31)), sp: f.spEL0, pc: f.elr,
                                         cpsr: UInt32(truncatingIfNeeded: f.spsr) & 0xF000_0000)
        if let v = vcpu(of: t) {
            var fp = [UInt8](repeating: 0, count: 520)
            if fp.withUnsafeMutableBufferPointer({ ckvm_get_fp_state(v.fd, $0.baseAddress) }) >= 0 {
                r.vector = Array(fp[0..<512])
                r.fpsr = UInt32(GDBRemoteHex.littleEndianValue(fp[512..<516]))
                r.fpcr = UInt32(GDBRemoteHex.littleEndianValue(fp[516..<520]))
            }
        }
        return r
    }

    func setRegisters(_ tid: UInt64, _ r: GDBRemoteThreadRegisters) -> Bool {
        guard let t = thread(tid), var f = kernel.debugRegisters(t) else { return false }
        let old = registers(tid)
        for i in 0..<31 { f.x[i] = r.x[i] }
        f.spEL0 = r.sp
        f.elr = r.pc
        f.spsr = (f.spsr & ~UInt64(0xF000_0000)) | UInt64(r.cpsr & 0xF000_0000)
        guard kernel.debugSetRegisters(t, f) else { return false }
        if let vec = r.vector, vec.count == 512, vec != old?.vector || r.fpsr != old?.fpsr || r.fpcr != old?.fpcr {
            guard let v = vcpu(of: t) else { return false }
            var fp = vec
            for word in [r.fpsr ?? 0, r.fpcr ?? 0] { for i in 0..<4 { fp.append(UInt8(truncatingIfNeeded: word >> (8 * UInt32(i)))) } }
            guard fp.withUnsafeBufferPointer({ ckvm_set_fp_state(v.fd, $0.baseAddress) }) >= 0 else { return false }
        }
        return true
    }

    func rawRead(_ address: UInt64, _ count: Int) -> [UInt8] {
        var out: [UInt8] = []
        var cursor = address
        var remaining = count
        while remaining > 0 {
            let inPage = Int(VMLayout.pageSize - (cursor & (VMLayout.pageSize - 1)))
            let n = min(inPage, remaining)
            guard let bytes = try? image.space.read(va: cursor, count: n, checkingEL0Access: false) else { break }
            out += bytes
            cursor &+= UInt64(n)
            remaining -= n
        }
        return out
    }

    func rawWrite(_ address: UInt64, _ bytes: [UInt8]) -> Bool {
        do {
            try image.space.write(va: address, bytes: bytes, checkingEL0Access: false)
            codeChanged = true
            return true
        } catch {
            return false
        }
    }

    func readMemory(_ address: UInt64, count: Int) -> [UInt8] {
        var bytes = rawRead(address, count)
        let field = kernel.allImageInfosAddress &+ UInt64(DyldAllImageInfos.Offset.dyldAllImageInfosAddress)
        let end = address &+ UInt64(bytes.count)
        if field < end, field &+ 8 > address, rawRead(field, 8) == [UInt8](repeating: 0, count: 8) {
            let own = kernel.allImageInfosAddress
            for i in 0..<8 {
                let a = field &+ UInt64(i)
                if a >= address, a < end { bytes[Int(a - address)] = UInt8(truncatingIfNeeded: own >> (8 * UInt64(i))) }
            }
        }
        return bytes
    }
    func writeMemory(_ address: UInt64, bytes: [UInt8]) -> Bool { rawWrite(address, bytes) }

    private var allocations: [UInt64: UInt64] = [:]

    func allocateMemory(size: UInt64, permissions: String) -> UInt64? {
        var protection: VMProtection = []
        if permissions.contains("r") { protection.insert(.read) }
        if permissions.contains("w") { protection.insert(.write) }
        if permissions.contains("x") { protection.insert(.execute) }
        let rounded = (size + VMLayout.pageSize - 1) & ~(VMLayout.pageSize - 1)
        guard let a = try? kernel.debugLocked({ try image.space.mapAnonymous(at: nil, size: rounded, protection: protection, hint: nil) }) else {
            return nil
        }
        allocations[a] = rounded
        return a
    }

    func deallocateMemory(_ address: UInt64) -> Bool {
        guard let size = allocations.removeValue(forKey: address) else { return false }
        _ = try? kernel.debugLocked { try image.space.unmap(va: address, size: size) }
        codeChanged = true
        return true
    }

    func memoryRegion(at address: UInt64) -> GDBRemoteMemoryRegion? {
        let a = address & VMLayout.addressWithoutTag
        let regions = image.space.regions
        if let r = regions.first(where: { $0.va <= a && a < $0.end }) {
            var perms = ""
            if r.protection.contains(.read) { perms += "r" }
            if r.protection.contains(.write) { perms += "w" }
            if r.protection.contains(.execute) { perms += "x" }
            var name: String?
            if case let .file(path, _, _) = r.backing { name = path }
            return GDBRemoteMemoryRegion(start: r.va, size: r.size, permissions: perms, name: name)
        }
        let next = regions.first(where: { $0.va > a })?.va ?? (UInt64(1) << 47)
        let start = regions.last(where: { $0.end <= a })?.end ?? 0
        return GDBRemoteMemoryRegion(start: start, size: next > start ? next - start : 0, permissions: nil)
    }

    func resume(_ actions: [UInt64: GDBRemoteResume], others: GDBRemoteResume) -> Result<Void, GDBRemoteError> {
        func map(_ r: GDBRemoteResume, _ tid: UInt64?) -> DarwinKernel.DebugResume {
            switch r {
            case .stop: return .stay
            case let .continue(signal):
                guard let signal, let tid, case .exception = stopInfo(tid).reason, stopInfo(tid).signal == signal else { return .run(deliverSignal: false) }
                return .run(deliverSignal: true)
            case .step: return .step
            }
        }
        var mapped: [UInt64: DarwinKernel.DebugResume] = [:]
        for (tid, a) in actions { mapped[tid] = map(a, tid) }
        steppedThreads = Set(mapped.filter { $0.value == .step }.keys)
        stepStarts = [:]
        for tid in steppedThreads { stepStarts[tid] = registers(tid)?.pc }
        let rest = map(others, nil)
        condition.lock()
        pendingThread = nil
        interruptRequested = false
        signalThread = nil
        condition.unlock()
        if codeChanged {
            codeChanged = false
            kernel.debugRequestFlush()
        }
        kernel.debugResume(mapped, others: rest)
        return .success(())
    }

    func interrupt() {
        kernel.debugStopAll()
        condition.lock()
        interruptRequested = true
        condition.broadcast()
        condition.unlock()
    }

    func waitForEvent() -> GDBRemoteEvent {
        while true {
            if let status = kernel.debugTerminationStatus ?? (kernel.isTerminating ? Int32(DarwinKernel.Signal.sigkill) : nil) {
                breakpoints.forgetAll()
                return status & 0x7F == 0 ? .exited(status: Int((status >> 8) & 0xFF)) : .terminated(signal: Int(status & 0x7F))
            }
            condition.lock()
            if pendingThread == nil && !interruptRequested { _ = condition.wait(until: Date().addingTimeInterval(0.05)) }
            let hit = pendingThread
            let interrupted = interruptRequested
            condition.unlock()
            guard hit != nil || interrupted else { continue }
            if !waitUntilStopped(seconds: 5) {
                if kernel.isTerminating { continue }
                stderrLine("swiftcode-simd: debug: some threads of pid \(pid) did not stop within 5 s; reporting the stop anyway")
            }
            stopThreads = kernel.debugThreads.map(\.threadID)
            if let hit { return .stopped(thread: hit) }
            let main = kernel.debugThreads.first?.threadID ?? 0
            condition.lock()
            signalThread = main
            condition.unlock()
            return .stopped(thread: main)
        }
    }

    func detach() {
        if !watches.isEmpty {
            watches = []
            image.pool.setHardwareWatchpoints([])
        }
        if codeChanged {
            codeChanged = false
            kernel.debugRequestFlush()
        }
        kernel.debugDetach()
        stderrLine("swiftcode-simd: debug: detached from pid \(pid)")
    }

    func kill() {
        if !watches.isEmpty {
            watches = []
            image.pool.setHardwareWatchpoints([])
        }
        kernel.debugDetach()
        kernel.debugKill()
        stderrLine("swiftcode-simd: debug: killed pid \(pid)")
    }
}
#endif
