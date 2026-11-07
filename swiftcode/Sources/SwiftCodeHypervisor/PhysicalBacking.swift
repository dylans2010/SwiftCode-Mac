#if os(Linux) && arch(arm64)
import CKVM
import Glibc
import Synchronization
import SwiftCodeDarwinABI

public final class BackingCounter: @unchecked Sendable {
    public let name: String
    public let count = Atomic<UInt64>(0)
    public let nanoseconds = Atomic<UInt64>(0)
    public let bytes = Atomic<UInt64>(0)
    init(_ name: String) { self.name = name }

    @inline(__always) func add(since start: UInt64, bytes n: UInt64 = 0) {
        count.wrappingAdd(1, ordering: .relaxed)
        nanoseconds.wrappingAdd(monotonicNanoseconds() &- start, ordering: .relaxed)
        bytes.wrappingAdd(n, ordering: .relaxed)
    }

    var text: String {
        "\(name) \(count.load(ordering: .relaxed)) (\(nanoseconds.load(ordering: .relaxed) / 1_000_000) ms, "
            + "\(bytes.load(ordering: .relaxed) >> 20) MiB)"
    }
}

public enum PostTrapWork {
    private final class State {
        var vm: ObjectIdentifier?
        var work: [() -> Void] = []
    }
    nonisolated(unsafe) private static var key: pthread_key_t = {
        var k = pthread_key_t()
        pthread_key_create(&k) { p in if let p { Unmanaged<AnyObject>.fromOpaque(p).release() } }
        return k
    }()

    private static var state: State {
        if let p = pthread_getspecific(key) { return Unmanaged<State>.fromOpaque(p).takeUnretainedValue() }
        let s = State()
        pthread_setspecific(key, Unmanaged.passRetained(s).toOpaque())
        return s
    }

    public static func setCurrentVM(_ vm: VirtualMachine) { state.vm = ObjectIdentifier(vm) }

    public static func isCurrentVM(_ vm: VirtualMachine) -> Bool {
        guard let p = pthread_getspecific(key) else { return false }
        return Unmanaged<State>.fromOpaque(p).takeUnretainedValue().vm == ObjectIdentifier(vm)
    }

    static func defer_(_ body: @escaping () -> Void) { state.work.append(body) }

    public static func drain() {
        guard let p = pthread_getspecific(key) else { return }
        let s = Unmanaged<State>.fromOpaque(p).takeUnretainedValue()
        while !s.work.isEmpty {
            let list = s.work
            s.work.removeAll()
            for body in list { body() }
        }
    }
}

public enum BackingStats {
    public static let deferredDiscards = BackingCounter("discards after the trap")
    public static let fileMemslots = BackingCounter("file memslots")
    public static let fileWindowMaps = BackingCounter("file window maps")
    public static let fileCopies = BackingCounter("file copies")
    public static let sharedMemslots = BackingCounter("shared-object memslots")
    public static let discards = BackingCounter("discards")
    public static let zeroFills = BackingCounter("zero fills")

    public static var report: String {
        "host memory calls in traps: " + [fileMemslots, fileWindowMaps, fileCopies, sharedMemslots, discards, zeroFills,
                                         deferredDiscards]
            .map(\.text).joined(separator: "; ")
    }
}

public final class KVMPhysicalBacking {
    public let vm: VirtualMachine
    public let poolGPA: UInt64
    public let poolSize: UInt64
    public let fileWindowGPA: UInt64
    public let physicalLimit: UInt64
    public let readOnlyFileWindowGPA: UInt64?
    private let arena: SharedFileArena?

    public static let granule: UInt64 = 1 << 14
    public static let defaultPoolGPA: UInt64 = 0x10_0000_0000
    public static let defaultPoolSize: UInt64 = 16 << 30
    public static let defaultFileWindowGPA: UInt64 = 0x20_0000_0000
    public static let defaultReadOnlyFileWindowGPA: UInt64 = 0x80_0000_0000

    private let pool: RangeAllocator
    private let stale: RangeAllocator
    public static let discardLimit: UInt64 = 256 << 10
    public static let staleLimit: UInt64 = 4 << 20
    public static let zeroFillLimit: UInt64 = 64 << 10
    public static let copyLimit: UInt64 = 1 << 20
    public private(set) var copiedFileMappingCount = 0
    private var nextFileGPA: UInt64
    private let fileWindowLimit: UInt64
    private let poolHost: UnsafeMutableRawPointer
    public var anonymousBytesInUse: UInt64 { pool.bytesInUse }
    public private(set) var fileMappingCount = 0
    public private(set) var readOnlyViewCount = 0
    private let privateWindowHost: UnsafeMutableRawPointer?
    public let privateWindowGPA: UInt64
    public let privateWindowSize: UInt64
    private var privateWindowNext: UInt64 = 0
    public static let privateWindowEnabled = getenv("SWIFTCODE_PRIVATE_FILE_WINDOW").map { String(cString: $0) != "0" } ?? true
    public static let defaultPrivateWindowSize: UInt64 = 64 << 30
    public static let deferredDiscardEnabled = getenv("SWIFTCODE_DEFERRED_DISCARD").map { String(cString: $0) != "0" } ?? true
    private let readyLock = HostMutex(name: "pool runs ready")
    private var readyRuns: [(gpa: UInt64, size: UInt64)] = []
    private var hasReadyRuns = false

    public var hasOverlays = false

    @inline(__always) private func discardHost(_ host: UnsafeMutableRawPointer, _ size: Int) -> Int32 {
        hasOverlays ? ckvm_reset_anonymous(host, size) : ckvm_discard_anonymous(host, size)
    }

    private func discardAfterTrap(_ gpa: UInt64, _ size: UInt64) {
        let host = poolHost + Int(gpa - poolGPA)
        PostTrapWork.defer_ { [self] in
            let began = VCPUPool.profiling ? monotonicNanoseconds() : 0
            _ = discardHost(host, Int(size))
            if VCPUPool.profiling { BackingStats.deferredDiscards.add(since: began, bytes: size) }
            readyLock.withLock {
                readyRuns.append((gpa, size))
                hasReadyRuns = true
            }
        }
    }

    private func takeReadyRuns() {
        let runs: [(gpa: UInt64, size: UInt64)] = readyLock.withLock {
            guard hasReadyRuns else { return [] }
            hasReadyRuns = false
            let r = readyRuns
            readyRuns.removeAll()
            return r
        }
        for r in runs { pool.free(r.gpa, r.size) }
    }

    public static let sharedArenaGPA: UInt64 = 0xC0_0000_0000
    private var sharedArenaRegistered = false

    private var sharedSlots: [ObjectIdentifier: (object: SharedMemoryObject, gpa: UInt64)] = [:]

    public init(vm: VirtualMachine,
                poolGPA: UInt64 = KVMPhysicalBacking.defaultPoolGPA,
                poolSize: UInt64 = KVMPhysicalBacking.defaultPoolSize,
                fileWindowGPA: UInt64 = KVMPhysicalBacking.defaultFileWindowGPA,
                physicalAddressBits: UInt64 = 40,
                sharedReadOnlyFiles: Bool = true,
                readOnlyFileWindowGPA: UInt64 = KVMPhysicalBacking.defaultReadOnlyFileWindowGPA) throws {
        precondition(poolGPA % Self.granule == 0 && poolSize % Self.granule == 0 && fileWindowGPA % Self.granule == 0)
        let hostPool: UnsafeMutableRawPointer? = switch Self.poolHuge {
        case "1": ckvm_alloc_anonymous_aligned(Int(poolSize), 2 << 20, 1)
        case "align": ckvm_alloc_anonymous_aligned(Int(poolSize), 2 << 20, 0)
        case "never": ckvm_alloc_anonymous_aligned(Int(poolSize), 2 << 20, -1)
        default: ckvm_alloc_anonymous(Int(poolSize))
        }
        guard let host = hostPool else {
            throw KVMError("mmap anonymous pool (\(poolSize >> 20) MiB, MAP_NORESERVE)", errno: Glibc.errno)
        }
        do {
            try vm.addMemorySlot(gpa: poolGPA, size: poolSize, host: host, kind: .anonymousPool, name: "anonymous pool")
        } catch {
            _ = ckvm_free_anonymous(host, Int(poolSize))
            throw error
        }
        let limit = UInt64(1) << physicalAddressBits
        var privateHost: UnsafeMutableRawPointer?
        var privateSize: UInt64 = 0
        let privateGPA = fileWindowGPA
        if Self.privateWindowEnabled, privateGPA < readOnlyFileWindowGPA,
           Self.defaultPrivateWindowSize <= readOnlyFileWindowGPA - privateGPA,
           let reservation = mmap(nil, Int(Self.defaultPrivateWindowSize), PROT_NONE,
                                  MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE, -1, 0), reservation != MAP_FAILED {
            if (try? vm.addMemorySlot(gpa: privateGPA, size: Self.defaultPrivateWindowSize, host: reservation, kind: .file,
                                      name: "private file window")) != nil {
                privateHost = reservation
                privateSize = Self.defaultPrivateWindowSize
            } else {
                munmap(reservation, Int(Self.defaultPrivateWindowSize))
            }
        }
        var window: UInt64?
        var arena: SharedFileArena?
        if sharedReadOnlyFiles, !Self.debugNoArena, vm.supportsReadOnlyMemory, let a = SharedFileArena.shared,
           readOnlyFileWindowGPA % Self.granule == 0, readOnlyFileWindowGPA > fileWindowGPA,
           readOnlyFileWindowGPA < limit, a.size <= limit - readOnlyFileWindowGPA,
           (try? vm.addMemorySlot(gpa: readOnlyFileWindowGPA, size: a.size, host: a.base, kind: .readOnlyFiles,
                                  name: "read-only file arena", readOnly: true)) != nil {
            window = readOnlyFileWindowGPA
            arena = a
        }
        self.vm = vm
        self.poolGPA = poolGPA
        self.poolSize = poolSize
        self.fileWindowGPA = fileWindowGPA
        self.physicalLimit = limit
        self.poolHost = host
        self.pool = RangeAllocator(base: poolGPA, size: poolSize)
        self.stale = RangeAllocator(base: poolGPA, size: poolSize, hardwareWatch: DebugHardwareWatch.arm != nil)
        if let objects = SharedObjectArena.shared, window != nil, let ro = SharedFileArena.shared,
           Self.sharedArenaGPA >= readOnlyFileWindowGPA + ro.size,
           objects.size <= limit - Self.sharedArenaGPA,
           (try? vm.addMemorySlot(gpa: Self.sharedArenaGPA, size: objects.size, host: objects.base, kind: .shared,
                                  name: "shared object arena")) != nil {
            sharedArenaRegistered = true
        }
        self.privateWindowHost = privateHost
        self.privateWindowGPA = privateGPA
        self.privateWindowSize = privateSize
        self.nextFileGPA = fileWindowGPA + privateSize
        self.readOnlyFileWindowGPA = window
        self.arena = arena
        self.fileWindowLimit = window ?? limit
    }

    public private(set) var retired = false

    public var reusable: Bool {
        !retired && !hasOverlays && nextFileGPA == fileWindowGPA + privateWindowSize
            && sharedSlots.values.allSatisfy { $0.gpa >= Self.sharedArenaGPA }
    }

    struct WindowKey: Equatable {
        var device: UInt64, inode: UInt64, size: Int64, mtime: Int64
        var offset: UInt64, total: UInt64, fileBytes: Int
    }
    private var windowMaps: [(key: WindowKey, at: UInt64)] = []
    private var inheritedWindowMaps: [(key: WindowKey, at: UInt64)] = []
    public static let windowInheritance = getenv("SWIFTCODE_VM_REUSE_WINDOW").map { String(cString: $0) != "0" } ?? true
    public static let inheritedWindowHits = Atomic<UInt64>(0)

    public func retireForReuse() -> Bool {
        let ok = reusable
        retired = true
        return ok
    }

    public func scrubForReuse() -> Bool {
        precondition(retired)
        _ = discardHost(poolHost, Int(poolSize))
        if let window = privateWindowHost, privateWindowNext > 0 {
            if Self.windowInheritance {
                guard ckvm_discard_anonymous(window, Int(privateWindowNext)) == 0 else { return false }
            } else {
                guard ckvm_reserve_at(window, Int(privateWindowNext)) == 0 else { return false }
                privateWindowNext = 0
                windowMaps.removeAll()
                inheritedWindowMaps.removeAll()
            }
        }
        return true
    }

    public init(reusing old: KVMPhysicalBacking) {
        precondition(old.retired)
        vm = old.vm
        poolGPA = old.poolGPA
        poolSize = old.poolSize
        fileWindowGPA = old.fileWindowGPA
        physicalLimit = old.physicalLimit
        poolHost = old.poolHost
        pool = RangeAllocator(base: old.poolGPA, size: old.poolSize)
        stale = RangeAllocator(base: old.poolGPA, size: old.poolSize, hardwareWatch: DebugHardwareWatch.arm != nil)
        sharedArenaRegistered = old.sharedArenaRegistered
        privateWindowHost = old.privateWindowHost
        privateWindowGPA = old.privateWindowGPA
        privateWindowSize = old.privateWindowSize
        nextFileGPA = old.fileWindowGPA + old.privateWindowSize
        privateWindowNext = old.privateWindowNext
        inheritedWindowMaps = old.windowMaps + old.inheritedWindowMaps
        readOnlyFileWindowGPA = old.readOnlyFileWindowGPA
        arena = old.arena
        fileWindowLimit = old.fileWindowLimit
    }

    static let poolHuge = getenv("SWIFTCODE_POOL_HUGE").map { String(cString: $0) } ?? "0"

    static let keepHugePages = getenv("SWIFTCODE_POOL_KEEP_THP").map { String(cString: $0) == "1" } ?? false
    static let hostHuge: UInt64 = 2 << 20
    static let keepStaleLimit: UInt64 = 64 << 20
    static let keepZeroFillLimit: UInt64 = 4 << 20
    private var staleDropAt = keepStaleLimit

    private func hugeInterior(_ gpa: UInt64, _ size: UInt64) -> (lo: UInt64, hi: UInt64) {
        let h = UInt64(UInt(bitPattern: poolHost)) + (gpa - poolGPA)
        let lo = (h + Self.hostHuge - 1) & ~(Self.hostHuge - 1)
        let hi = (h + size) & ~(Self.hostHuge - 1)
        guard hi > lo else { return (gpa, gpa) }
        return (gpa + (lo - h), gpa + (hi - h))
    }

    private func zeroPool(_ lo: UInt64, _ hi: UInt64) {
        guard hi > lo else { return }
        (poolHost + Int(lo - poolGPA)).initializeMemory(as: UInt8.self, repeating: 0, count: Int(hi - lo))
    }

    private func freeStale(_ gpa: UInt64, _ size: UInt64) {
        guard size > 0 else { return }
        pool.free(gpa, size)
        stale.mark(gpa, size)
    }

    private func releaseKeepingHugePages(_ gpa: UInt64, _ size: UInt64, deferred: Bool) {
        let (lo, hi) = hugeInterior(gpa, size)
        if hi > lo, size > Self.discardLimit {
            freeStale(gpa, lo - gpa)
            freeStale(hi, gpa + size - hi)
            if deferred {
                discardAfterTrap(lo, hi - lo)
            } else {
                pool.free(lo, hi - lo)
                let began = VCPUPool.profiling ? monotonicNanoseconds() : 0
                _ = discardHost(poolHost + Int(lo - poolGPA), Int(hi - lo))
                if VCPUPool.profiling { BackingStats.discards.add(since: began, bytes: hi - lo) }
            }
        } else {
            freeStale(gpa, size)
        }
        guard stale.bytesInUse > staleDropAt else { return }
        var merged: [Range<UInt64>] = []
        for r in stale.takeAll() {
            if let last = merged.last, last.upperBound == r.lowerBound {
                merged[merged.count - 1] = last.lowerBound..<r.upperBound
            } else {
                merged.append(r)
            }
        }
        for r in merged {
            let (a, b) = hugeInterior(r.lowerBound, r.upperBound - r.lowerBound)
            guard b > a else { stale.mark(r.lowerBound, r.upperBound - r.lowerBound); continue }
            if r.lowerBound < a { stale.mark(r.lowerBound, a - r.lowerBound) }
            if b < r.upperBound { stale.mark(b, r.upperBound - b) }
            if deferred {
                pool.mark(a, b - a)
                discardAfterTrap(a, b - a)
            } else {
                let began = VCPUPool.profiling ? monotonicNanoseconds() : 0
                _ = discardHost(poolHost + Int(a - poolGPA), Int(b - a))
                if VCPUPool.profiling { BackingStats.discards.add(since: began, bytes: b - a) }
            }
        }
        staleDropAt = max(Self.keepStaleLimit, stale.bytesInUse * 2)
    }
    static let debugNoArena = getenv("SWIFTCODE_DEBUG_NO_FILE_ARENA").map { String(cString: $0) == "1" } ?? false
    static let debugNoStale = getenv("SWIFTCODE_DEBUG_NO_STALE").map { String(cString: $0) == "1" } ?? false
    static let debugNoFileCopy = getenv("SWIFTCODE_DEBUG_NO_FILE_COPY").map { String(cString: $0) == "1" } ?? false

    static func roundUp(_ value: UInt64, _ alignment: UInt64) -> UInt64 { (value + alignment - 1) & ~(alignment - 1) }

    public func allocateAnonymous(size: UInt64) throws -> UInt64 {
        let size = Self.roundUp(max(size, 1), Self.granule)
        guard !vm.isClosed, !retired else { throw KVMError("anonymous pool", errno: EBADF, detail: "the VM is closed") }
        if Self.deferredDiscardEnabled { takeReadyRuns() }
        guard let start = pool.allocate(size) else {
            throw KVMError("anonymous pool", errno: ENOMEM,
                           detail: "no free run of \(size) bytes (\(anonymousBytesInUse >> 20) MiB of \(poolSize >> 20) MiB in use)")
        }
        if stale.bytesInUse > 0 {
            let old = stale.free(start, size)
            let oldBytes = old.reduce(0) { $0 + ($1.upperBound - $1.lowerBound) }
            let began = VCPUPool.profiling ? monotonicNanoseconds() : 0
            if Self.keepHugePages {
                for r in old {
                    let (a, b) = oldBytes > Self.keepZeroFillLimit
                        ? hugeInterior(r.lowerBound, r.upperBound - r.lowerBound) : (r.upperBound, r.upperBound)
                    if b > a {
                        zeroPool(r.lowerBound, a)
                        _ = discardHost(poolHost + Int(a - poolGPA), Int(b - a))
                        zeroPool(b, r.upperBound)
                    } else {
                        zeroPool(r.lowerBound, r.upperBound)
                    }
                }
                if VCPUPool.profiling { BackingStats.zeroFills.add(since: began, bytes: oldBytes) }
            } else if oldBytes > Self.zeroFillLimit {
                _ = discardHost(poolHost + Int(start - poolGPA), Int(size))
                if VCPUPool.profiling {
                    BackingStats.discards.add(since: began, bytes: size)
                }
            } else {
                for r in old {
                    (poolHost + Int(r.lowerBound - poolGPA)).initializeMemory(as: UInt8.self, repeating: 0,
                                                                              count: Int(r.upperBound - r.lowerBound))
                }
                if VCPUPool.profiling { BackingStats.zeroFills.add(since: began) }
            }
        }
        return start
    }

    public func release(gpa: UInt64, size: UInt64) {
        let size = Self.roundUp(size, Self.granule)
        guard size > 0, gpa >= poolGPA, gpa + size <= poolGPA + poolSize, gpa % Self.granule == 0 else { return }
        guard !vm.isClosed, !retired else { return }
        guard pool.isAllocated(gpa, size) else { return }
        let deferred = Self.deferredDiscardEnabled && PostTrapWork.isCurrentVM(vm)
        if Self.keepHugePages {
            releaseKeepingHugePages(gpa, size, deferred: deferred)
            return
        }
        if deferred, size > Self.discardLimit || Self.debugNoStale {
            discardAfterTrap(gpa, size)
            return
        }
        pool.free(gpa, size)
        let began = VCPUPool.profiling ? monotonicNanoseconds() : 0
        if size <= Self.discardLimit && !Self.debugNoStale {
            stale.mark(gpa, size)
            if stale.bytesInUse > Self.staleLimit {
                if deferred {
                    for r in stale.takeAll() {
                        pool.mark(r.lowerBound, r.upperBound - r.lowerBound)
                        discardAfterTrap(r.lowerBound, r.upperBound - r.lowerBound)
                    }
                    return
                }
                var bytes: UInt64 = 0
                for r in stale.takeAll() {
                    _ = discardHost(poolHost + Int(r.lowerBound - poolGPA), Int(r.upperBound - r.lowerBound))
                    bytes += r.upperBound - r.lowerBound
                }
                if VCPUPool.profiling {
                    BackingStats.discards.add(since: began, bytes: bytes)
                }
            }
        } else {
            _ = discardHost(poolHost + Int(gpa - poolGPA), Int(size))
            if VCPUPool.profiling {
                BackingStats.discards.add(since: began, bytes: size)
            }
        }
    }

    public func mapFile(hostFD: Int32, fileSize: UInt64, offset: UInt64, size: UInt64, name: String) throws -> UInt64 {
        guard !retired else { throw KVMError("file mapping", errno: EBADF, detail: "the image ended") }
        let hostPage = UInt64(ckvm_host_page_size())
        guard offset % hostPage == 0 else {
            throw KVMError("file memslot", errno: EINVAL, detail: "offset 0x\(String(offset, radix: 16)) of \(name) is not host-page aligned")
        }
        let total = Self.roundUp(max(size, 1), Self.granule)
        let gpa = Self.roundUp(nextFileGPA, Self.granule)
        guard gpa <= fileWindowLimit, total <= fileWindowLimit - gpa else {
            throw KVMError("file memslot", errno: ENOMEM, detail: "guest physical space exhausted mapping \(name)")
        }
        let available = offset < fileSize ? fileSize - offset : 0
        let fileBytes = Int(min(min(size, available), total))
        let began = VCPUPool.profiling ? monotonicNanoseconds() : 0
        if total <= Self.copyLimit && !Self.debugNoFileCopy {
            defer {
                if VCPUPool.profiling {
                    BackingStats.fileCopies.add(since: began, bytes: total)
                }
            }
            let gpa = try allocateAnonymous(size: total)
            let destination = poolHost + Int(gpa - poolGPA)
            var done = 0
            while done < fileBytes {
                let n = pread(hostFD, destination + done, fileBytes - done, off_t(offset) + off_t(done))
                if n < 0 && Glibc.errno == EINTR { continue }
                if n < 0 {
                    let saved = Glibc.errno
                    (destination).initializeMemory(as: UInt8.self, repeating: 0, count: done)
                    release(gpa: gpa, size: total)
                    throw KVMError("read \(name) at offset 0x\(String(offset, radix: 16))", errno: saved)
                }
                if n == 0 { break }
                done += n
            }
            copiedFileMappingCount += 1
            return gpa
        }
        var key: WindowKey?
        if privateWindowHost != nil, Self.windowInheritance {
            var st = stat()
            if fstat(hostFD, &st) == 0 {
                key = WindowKey(device: UInt64(st.st_dev), inode: UInt64(st.st_ino), size: Int64(st.st_size),
                                mtime: Int64(st.st_mtim.tv_sec) &* 1_000_000_000 &+ Int64(st.st_mtim.tv_nsec),
                                offset: offset, total: total, fileBytes: fileBytes)
                if let i = inheritedWindowMaps.firstIndex(where: { $0.key == key! }) {
                    let entry = inheritedWindowMaps.remove(at: i)
                    windowMaps.append(entry)
                    fileMappingCount += 1
                    Self.inheritedWindowHits.wrappingAdd(1, ordering: .relaxed)
                    return privateWindowGPA + entry.at
                }
            }
        }
        if let windowHost = privateWindowHost, total <= privateWindowSize - privateWindowNext {
            let at = windowHost + Int(privateWindowNext)
            guard ckvm_map_file_private_at(at, hostFD, offset, fileBytes, Int(total)) != nil else {
                let saved = Glibc.errno
                var target = [CChar](repeating: 0, count: 512)
                let n = readlink("/proc/self/fd/\(hostFD)", &target, 511)
                let what = n > 0 ? String(cString: target) : "?"
                throw KVMError("mmap \(name) at offset 0x\(String(offset, radix: 16)) (private file window; fd \(hostFD) -> \(what); "
                               + "fileBytes \(fileBytes) total \(total); arena files \(SharedFileArena.shared?.fileCount ?? -1) "
                               + "bytes \((SharedFileArena.shared?.bytesUsed ?? 0) >> 20) MiB)", errno: saved)
            }
            let gpa = privateWindowGPA + privateWindowNext
            if let key { windowMaps.append((key, privateWindowNext)) }
            privateWindowNext += total
            fileMappingCount += 1
            if VCPUPool.profiling {
                BackingStats.fileWindowMaps.add(since: began, bytes: total)
            }
            return gpa
        }
        guard let host = ckvm_map_file_private(hostFD, offset, fileBytes, Int(total)) else {
            throw KVMError("mmap \(name) at offset 0x\(String(offset, radix: 16))", errno: Glibc.errno)
        }
        do {
            try vm.addMemorySlot(gpa: gpa, size: total, host: host, kind: .file,
                                 name: "\(name)@0x\(String(offset, radix: 16))")
        } catch {
            _ = ckvm_free_anonymous(host, Int(total))
            throw error
        }
        nextFileGPA = gpa + total
        fileMappingCount += 1
        if VCPUPool.profiling {
            BackingStats.fileMemslots.add(since: began, bytes: total)
        }
        return gpa
    }

    public func mapFileReadOnly(hostFD: Int32, offset: UInt64, size: UInt64) -> UInt64? {
        guard !retired, let arena, let window = readOnlyFileWindowGPA,
              let at = arena.view(hostFD: hostFD, offset: offset, size: Self.roundUp(max(size, 1), Self.granule)) else {
            return nil
        }
        readOnlyViewCount += 1
        return window + at
    }

    public func mapShared(_ object: SharedMemoryObject) throws -> UInt64 {
        guard !retired else { throw KVMError("shared mapping", errno: EBADF, detail: "the image ended") }
        if let slot = sharedSlots[ObjectIdentifier(object)] { return slot.gpa }
        if sharedArenaRegistered, let offset = object.arenaOffset {
            let gpa = Self.sharedArenaGPA + offset
            sharedSlots[ObjectIdentifier(object)] = (object, gpa)
            return gpa
        }
        let began = VCPUPool.profiling ? monotonicNanoseconds() : 0
        defer { if VCPUPool.profiling { BackingStats.sharedMemslots.add(since: began) } }
        let gpa = Self.roundUp(nextFileGPA, Self.granule)
        guard gpa <= fileWindowLimit, object.size <= fileWindowLimit - gpa else {
            throw KVMError("shared memslot", errno: ENOMEM, detail: "guest physical space exhausted")
        }
        try vm.addMemorySlot(gpa: gpa, size: object.size, host: object.host, kind: .shared,
                             name: "shared object #\(object.serial)")
        nextFileGPA = gpa + object.size
        sharedSlots[ObjectIdentifier(object)] = (object, gpa)
        return gpa
    }

    public func readPhysical(gpa: UInt64, count: Int) throws -> [UInt8] {
        guard !retired else { throw KVMError("guest physical read", errno: EFAULT, detail: "the image ended") }
        if let slot = vm.memorySlot(containing: gpa), slot.contains(gpa: gpa, count: count) {
            return [UInt8](UnsafeRawBufferPointer(start: UnsafeRawPointer(bitPattern: slot.hostAddress)! + Int(gpa - slot.gpa),
                                                  count: count))
        }
        var result: [UInt8] = []
        result.reserveCapacity(count)
        var address = gpa, remaining = count
        while remaining > 0 {
            guard let slot = vm.memorySlot(containing: address) else {
                throw KVMError("guest physical read", errno: EFAULT, detail: "GPA 0x\(String(address, radix: 16)) is outside every memslot")
            }
            let chunk = Int(min(UInt64(remaining), slot.end - address))
            result.append(contentsOf: try vm.read(gpa: address, count: chunk))
            address += UInt64(chunk)
            remaining -= chunk
        }
        return result
    }

    public func writePhysical(gpa: UInt64, bytes: [UInt8]) throws {
        try bytes.withUnsafeBytes { try writePhysical(gpa: gpa, from: $0) }
    }

    public func writePhysical(gpa: UInt64, from bytes: UnsafeRawBufferPointer) throws {
        guard !retired else { throw KVMError("guest physical write", errno: EFAULT, detail: "the image ended") }
        var address = gpa, offset = 0
        while offset < bytes.count {
            guard let slot = vm.memorySlot(containing: address) else {
                throw KVMError("guest physical write", errno: EFAULT, detail: "GPA 0x\(String(address, radix: 16)) is outside every memslot")
            }
            let chunk = Int(min(UInt64(bytes.count - offset), slot.end - address))
            let destination = try vm.writableHostPointer(gpa: address, count: chunk)
            destination.copyMemory(from: bytes.baseAddress! + offset, byteCount: chunk)
            address += UInt64(chunk)
            offset += chunk
        }
    }
}

extension KVMPhysicalBacking: PhysicalBacking {
    public func mapFile(_ file: GuestFile, offset: UInt64, size: UInt64) throws -> UInt64 {
        try mapFile(hostFD: file.hostFD, fileSize: file.size, offset: offset, size: size, name: file.guestPath)
    }

    public func mapFileReadOnly(_ file: GuestFile, offset: UInt64, size: UInt64) throws -> UInt64? {
        mapFileReadOnly(hostFD: file.hostFD, offset: offset, size: size)
    }
}
#endif
