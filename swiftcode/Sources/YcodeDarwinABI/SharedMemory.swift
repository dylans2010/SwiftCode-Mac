#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

public final class SharedObjectArena: @unchecked Sendable {
    public static let enabled = getenv("SWIFTCODE_SHARED_WINDOW").map { String(cString: $0) != "0" } ?? true
    public static let shared: SharedObjectArena? = enabled ? SharedObjectArena(size: 128 << 30) : nil

    public let base: UnsafeMutableRawPointer
    public let size: UInt64
    private let lock = NSLockLike(name: "shared object arena")
    private let runs: RangeAllocator

    init?(size: UInt64) {
        #if canImport(Darwin)
        let flags = MAP_PRIVATE | MAP_ANON
        #else
        let flags = MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE
        #endif
        let slack = 2 << 20
        guard let raw = mmap(nil, Int(size) + slack, PROT_NONE, flags, -1, 0), raw != MAP_FAILED else { return nil }
        let aligned = (UInt(bitPattern: raw) + UInt(slack) - 1) & ~(UInt(slack) - 1)
        base = UnsafeMutableRawPointer(bitPattern: aligned)!
        self.size = size
        runs = RangeAllocator(base: 0, size: size)
    }

    func take(_ size: UInt64) -> UInt64? { lock.withLock { runs.allocate(size) } }

    public static let recycleLimit: UInt64 = (getenv("SWIFTCODE_ARENA_RECYCLE_MB").flatMap { UInt64(String(cString: $0)) } ?? 256) << 20
    public static let recycleMaxRun: UInt64 = 4 << 20
    private var pool: [UInt64: [UInt64]] = [:]
    private var pooledBytes: UInt64 = 0
    private var recycleHits: UInt64 = 0, recycleMisses: UInt64 = 0, recycleRefused: UInt64 = 0

    func takeRecycled(_ size: UInt64) -> UInt64? {
        guard Self.recycleLimit > 0, size <= Self.recycleMaxRun else { return nil }
        return lock.withLock {
            guard var list = pool[size], let at = list.popLast() else {
                recycleMisses &+= 1
                return nil
            }
            pool[size] = list.isEmpty ? nil : list
            pooledBytes -= size
            recycleHits &+= 1
            return at
        }
    }

    func recycle(_ offset: UInt64, _ size: UInt64) -> Bool {
        guard Self.recycleLimit > 0, size <= Self.recycleMaxRun else { return false }
        return lock.withLock {
            guard pooledBytes + size <= Self.recycleLimit else {
                recycleRefused &+= 1
                return false
            }
            pool[size, default: []].append(offset)
            pooledBytes += size
            return true
        }
    }

    public var recycleSummary: String {
        lock.withLock { "arena recycle: \(recycleHits) reused, \(recycleMisses) new, \(recycleRefused) refused, \(pooledBytes >> 20) MiB pooled" }
    }

    func give(_ offset: UInt64, _ size: UInt64) {
        #if canImport(Darwin)
        let flags = MAP_PRIVATE | MAP_ANON | MAP_FIXED
        #else
        let flags = MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE | MAP_FIXED
        #endif
        _ = mmap(base + Int(offset), Int(size), PROT_NONE, flags, -1, 0)
        lock.withLock { _ = runs.free(offset, size) }
    }
}

public final class SharedMemoryObject: @unchecked Sendable {
    public let size: UInt64
    public let host: UnsafeMutableRawPointer
    private static let counterLock = NSLockLike(name: "shared memory serials")
    nonisolated(unsafe) private static var counter: UInt64 = 0
    public let serial: UInt64

    public let arenaOffset: UInt64?

    public init(size: UInt64) throws {
        let rounded = (max(size, 1) + VMLayout.pageSize - 1) & ~(VMLayout.pageSize - 1)
        guard rounded <= 1 << 36 else { throw DarwinErrnoError(DarwinErrnoCode.ENOMEM) }
        #if canImport(Darwin)
        let flags = MAP_PRIVATE | MAP_ANON
        #else
        let flags = MAP_PRIVATE | MAP_ANONYMOUS | MAP_NORESERVE
        #endif
        var offset: UInt64?
        var p: UnsafeMutableRawPointer?
        if let arena = SharedObjectArena.shared, let at = arena.takeRecycled(rounded) {
            let run = arena.base + Int(at)
            memset(run, 0, Int(rounded))
            p = run
            offset = at
        } else if let arena = SharedObjectArena.shared, let at = arena.take(rounded) {
            let q = mmap(arena.base + Int(at), Int(rounded), PROT_READ | PROT_WRITE, flags | MAP_FIXED, -1, 0)
            if let q, q != MAP_FAILED {
                p = q
                offset = at
            } else {
                arena.give(at, rounded)
            }
        }
        if p == nil {
            let q = mmap(nil, Int(rounded), PROT_READ | PROT_WRITE, flags, -1, 0)
            guard let q, q != MAP_FAILED else { throw DarwinErrnoError(DarwinErrnoCode.ENOMEM) }
            p = q
        }
        arenaOffset = offset
        self.size = rounded
        self.host = p!
        isFileView = false
        serial = Self.counterLock.withLock {
            Self.counter += 1
            return Self.counter
        }
    }

    public let isFileView: Bool

    public struct FileSource: Sendable {
        public var guestPath: String
        public var hostPath: String
        public var offset: UInt64
        public var requestedSize: UInt64
        public init(guestPath: String, hostPath: String, offset: UInt64, requestedSize: UInt64) {
            self.guestPath = guestPath
            self.hostPath = hostPath
            self.offset = offset
            self.requestedSize = requestedSize
        }
    }
    public var snapshotFileSource: FileSource?

    public init?(hostFile fd: Int32, offset: UInt64, size: UInt64, fileSize: UInt64, reopenReadOnly: Bool = false) {
        let page = VMLayout.pageSize
        let rounded = (max(size, 1) + page - 1) & ~(page - 1)
        guard offset & (page - 1) == 0, rounded <= 1 << 36, offset <= UInt64(Int64.max) else { return nil }
        let viewFD: Int32
        if fcntl(fd, F_GETFL) & O_ACCMODE == O_RDWR {
            viewFD = fcntl(fd, F_DUPFD_CLOEXEC, 0)
        } else if reopenReadOnly {
            #if os(Linux)
            viewFD = open("/proc/self/fd/\(fd)", O_RDWR | O_CLOEXEC)
            #else
            viewFD = -1
            #endif
        } else {
            viewFD = -1
        }
        guard viewFD >= 0 else { return nil }
        var arenaAt: UInt64?
        var reservationOrNil: UnsafeMutableRawPointer?
        if let arena = SharedObjectArena.shared, let at = arena.take(rounded) {
            let q = mmap(arena.base + Int(at), Int(rounded), PROT_READ | PROT_WRITE, MAP_PRIVATE | Self.anonymous | MAP_FIXED, -1, 0)
            if let q, q != MAP_FAILED {
                reservationOrNil = q
                arenaAt = at
            } else {
                arena.give(at, rounded)
            }
        }
        if reservationOrNil == nil {
            let q = mmap(nil, Int(rounded), PROT_READ | PROT_WRITE, MAP_PRIVATE | Self.anonymous, -1, 0)
            if let q, q != MAP_FAILED { reservationOrNil = q }
        }
        guard let reservation = reservationOrNil else {
            close(viewFD)
            return nil
        }
        let backed = SharedFileViews.backedBytes(fileSize: fileSize, offset: offset, size: rounded)
        if backed > 0 {
            guard let p = mmap(reservation, Int(backed), PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, viewFD,
                               Self.hostOffset(offset)), p == reservation else {
                if let arenaAt, let arena = SharedObjectArena.shared { arena.give(arenaAt, rounded) } else { munmap(reservation, Int(rounded)) }
                close(viewFD)
                return nil
            }
        }
        arenaOffset = arenaAt
        self.size = rounded
        self.host = reservation
        isFileView = true
        serial = Self.counterLock.withLock {
            Self.counter += 1
            return Self.counter
        }
        let key = SharedFileViews.key(viewFD)
        fileView = FileViewState(fd: viewFD, offset: offset, backed: backed, key: key)
        if let key { SharedFileViews.register(self, key: key) }
    }

    #if canImport(Darwin)
    static func hostOffset(_ offset: UInt64) -> off_t { off_t(offset) }
    #else
    static func hostOffset(_ offset: UInt64) -> __off_t { __off_t(offset) }
    #endif

    struct FileViewState {
        var fd: Int32
        var offset: UInt64
        var backed: UInt64
        var key: SharedFileViews.Key?
    }
    var fileView: FileViewState?

    public var fileBackedBytes: UInt64 { SharedFileViews.lock.withLock { fileView?.backed ?? 0 } }

    func followFileSize(_ fileSize: UInt64) {
        guard var v = fileView else { return }
        let want = SharedFileViews.backedBytes(fileSize: fileSize, offset: v.offset, size: size)
        if want > v.backed {
            let p = mmap(host + Int(v.backed), Int(want - v.backed), PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, v.fd,
                         Self.hostOffset(v.offset + v.backed))
            guard p == host + Int(v.backed) else { return }
        } else if want < v.backed {
            let p = mmap(host + Int(want), Int(v.backed - want), PROT_READ | PROT_WRITE,
                         MAP_PRIVATE | Self.anonymous | MAP_FIXED, -1, 0)
            guard p == host + Int(want) else { return }
        } else {
            return
        }
        v.backed = want
        fileView = v
    }

    deinit {
        if let v = SharedFileViews.lock.withLock({ fileView }) {
            if let key = v.key { SharedFileViews.unregister(self, key: key) }
            close(v.fd)
        }
        if let arenaOffset, let arena = SharedObjectArena.shared {
            if !isFileView, arena.recycle(arenaOffset, size) { return }
            arena.give(arenaOffset, size)
        } else if Self.quarantine {
            _ = mmap(host, Int(size), PROT_NONE, MAP_PRIVATE | Self.anonymous | MAP_FIXED, -1, 0)
        } else {
            munmap(host, Int(size))
        }
    }
    private static let quarantine = getenv("SWIFTCODE_DEBUG_QUARANTINE").map { String(cString: $0) == "1" } ?? false
    #if canImport(Darwin)
    private static let anonymous = MAP_ANON
    #else
    private static let anonymous = MAP_ANONYMOUS | MAP_NORESERVE
    #endif

    public func read(offset: UInt64, count: Int) -> [UInt8] {
        precondition(offset <= size && UInt64(count) <= size - offset)
        return [UInt8](UnsafeRawBufferPointer(start: host + Int(offset), count: count))
    }

    public func write(offset: UInt64, bytes: [UInt8]) {
        precondition(offset <= size && UInt64(bytes.count) <= size - offset)
        bytes.withUnsafeBytes { if !$0.isEmpty { (host + Int(offset)).copyMemory(from: $0.baseAddress!, byteCount: $0.count) } }
    }
}

public enum SharedFileViews {
    struct Key: Hashable {
        var device: UInt64
        var inode: UInt64
    }
    final class Weak {
        weak var object: SharedMemoryObject?
        init(_ object: SharedMemoryObject) { self.object = object }
    }

    static let lock = NSLockLike(name: "shared file views")
    nonisolated(unsafe) private static var views: [Key: [ObjectIdentifier: Weak]] = [:]

    public static var count: Int { lock.withLock { views.values.reduce(0) { $0 + $1.count } } }

    static func key(_ fd: Int32) -> Key? {
        var st = stat()
        guard fstat(fd, &st) == 0 else { return nil }
        return Key(device: UInt64(st.st_dev), inode: UInt64(st.st_ino))
    }

    static let hostPage = UInt64(max(sysconf(Int32(_SC_PAGESIZE)), 4096))

    static func backedBytes(fileSize: UInt64, offset: UInt64, size: UInt64) -> UInt64 {
        guard fileSize > offset else { return 0 }
        let bytes = fileSize - offset
        return min((bytes + hostPage - 1) & ~(hostPage - 1), size)
    }

    static func register(_ object: SharedMemoryObject, key: Key) {
        lock.withLock { views[key, default: [:]][ObjectIdentifier(object)] = Weak(object) }
    }

    static func unregister(_ object: SharedMemoryObject, key: Key) {
        lock.withLock {
            views[key]?[ObjectIdentifier(object)] = nil
            if views[key]?.isEmpty == true { views[key] = nil }
        }
    }

    public static func sizeMayHaveChanged(hostFD fd: Int32) {
        guard lock.withLock({ !views.isEmpty }) else { return }
        var st = stat()
        guard fstat(fd, &st) == 0 else { return }
        let key = Key(device: UInt64(st.st_dev), inode: UInt64(st.st_ino))
        let size = UInt64(max(0, Int64(st.st_size)))
        var held: [SharedMemoryObject] = []
        lock.withLock {
            guard let entries = views[key] else { return }
            for entry in entries.values {
                guard let object = entry.object else { continue }
                held.append(object)
                object.followFileSize(size)
            }
        }
        held.removeAll()
    }
}

final class NSLockLike: @unchecked Sendable {
    private let mutex: UnsafeMutablePointer<pthread_mutex_t>
    init(name: String? = nil) {
        mutex = .allocate(capacity: 1)
        mutex.initialize(to: pthread_mutex_t())
        pthread_mutex_init(mutex, nil)
        if let name { DebugLockNames.register?(UnsafeMutableRawPointer(mutex), name) }
    }
    deinit {
        pthread_mutex_destroy(mutex)
        mutex.deallocate()
    }
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return try body()
    }
}
