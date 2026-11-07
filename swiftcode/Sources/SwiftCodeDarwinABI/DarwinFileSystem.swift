#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import Synchronization

public struct DarwinErrnoError: Error, Equatable, Hashable, Sendable, CustomStringConvertible {
    public var errno: Int32

    public init(_ errno: Int32) { self.errno = errno }

    public var description: String { "Darwin errno \(errno)\(DarwinErrnoCode.name(errno).map { " (\($0))" } ?? "")" }
}

public enum DarwinErrnoCode {
    public static let EPERM: Int32 = 1
    public static let ENOENT: Int32 = 2
    public static let EINTR: Int32 = 4
    public static let EIO: Int32 = 5
    public static let EBADF: Int32 = 9
    public static let EDEADLK: Int32 = 11
    public static let ENOMEM: Int32 = 12
    public static let EACCES: Int32 = 13
    public static let EFAULT: Int32 = 14
    public static let EEXIST: Int32 = 17
    public static let ENODEV: Int32 = 19
    public static let ENOTDIR: Int32 = 20
    public static let EISDIR: Int32 = 21
    public static let EINVAL: Int32 = 22
    public static let EMFILE: Int32 = 24
    public static let ENOTTY: Int32 = 25
    public static let EFBIG: Int32 = 27
    public static let ENOSPC: Int32 = 28
    public static let ESPIPE: Int32 = 29
    public static let EROFS: Int32 = 30
    public static let ERANGE: Int32 = 34
    public static let EAGAIN: Int32 = 35
    public static let ENOTSUP: Int32 = 45
    public static let ELOOP: Int32 = 62
    public static let ENAMETOOLONG: Int32 = 63
    public static let ENOTEMPTY: Int32 = 66
    public static let ENOSYS: Int32 = 78
    public static let EOVERFLOW: Int32 = 84
    public static let ESRCH: Int32 = 3
    public static let ENXIO: Int32 = 6
    public static let EDOM: Int32 = 33
    public static let EBUSY: Int32 = 16
    public static let EPIPE: Int32 = 32
    public static let ENOTSOCK: Int32 = 38
    public static let EDESTADDRREQ: Int32 = 39
    public static let EMSGSIZE: Int32 = 40
    public static let EPROTOTYPE: Int32 = 41
    public static let ENOPROTOOPT: Int32 = 42
    public static let EPROTONOSUPPORT: Int32 = 43
    public static let EAFNOSUPPORT: Int32 = 47
    public static let EADDRINUSE: Int32 = 48
    public static let ECONNABORTED: Int32 = 53
    public static let ECONNRESET: Int32 = 54
    public static let ENOBUFS: Int32 = 55
    public static let EISCONN: Int32 = 56
    public static let ENOTCONN: Int32 = 57
    public static let ETIMEDOUT: Int32 = 60
    public static let ECONNREFUSED: Int32 = 61
    public static let EOPNOTSUPP: Int32 = 102

    private static let names: [Int32: String] = [
        1: "EPERM", 2: "ENOENT", 3: "ESRCH", 4: "EINTR", 5: "EIO", 6: "ENXIO", 9: "EBADF", 16: "EBUSY", 11: "EDEADLK", 12: "ENOMEM",
        13: "EACCES", 14: "EFAULT", 17: "EEXIST", 19: "ENODEV", 20: "ENOTDIR", 21: "EISDIR", 22: "EINVAL",
        24: "EMFILE", 25: "ENOTTY", 27: "EFBIG", 28: "ENOSPC", 29: "ESPIPE", 30: "EROFS", 32: "EPIPE", 33: "EDOM",
        34: "ERANGE", 35: "EAGAIN", 38: "ENOTSOCK", 39: "EDESTADDRREQ", 40: "EMSGSIZE", 41: "EPROTOTYPE",
        42: "ENOPROTOOPT", 43: "EPROTONOSUPPORT", 45: "ENOTSUP", 47: "EAFNOSUPPORT", 48: "EADDRINUSE",
        53: "ECONNABORTED", 54: "ECONNRESET", 55: "ENOBUFS", 56: "EISCONN", 57: "ENOTCONN", 60: "ETIMEDOUT",
        61: "ECONNREFUSED", 62: "ELOOP", 63: "ENAMETOOLONG", 66: "ENOTEMPTY", 78: "ENOSYS", 84: "EOVERFLOW",
        102: "EOPNOTSUPP",
    ]

    public static func name(_ errno: Int32) -> String? { names[errno] }

    public static func fromHost(_ e: Int32) -> Int32 {
        #if canImport(Darwin)
        return e
        #else
        switch e {
        case Glibc.EAGAIN: return EAGAIN
        case Glibc.EDEADLK: return EDEADLK
        case Glibc.ENAMETOOLONG: return ENAMETOOLONG
        case Glibc.ELOOP: return ELOOP
        case Glibc.ENOTEMPTY: return ENOTEMPTY
        case Glibc.ENOSYS: return ENOSYS
        case Glibc.EOPNOTSUPP: return ENOTSUP
        case Glibc.EOVERFLOW: return EOVERFLOW
        case Glibc.ENOTSOCK: return ENOTSOCK
        case Glibc.EADDRINUSE: return EADDRINUSE
        case Glibc.ECONNREFUSED: return ECONNREFUSED
        case 1...34: return e
        default: return EIO
        }
        #endif
    }
}

public enum DarwinOpen {
    public static let O_RDONLY: Int32 = 0x0000
    public static let O_WRONLY: Int32 = 0x0001
    public static let O_RDWR: Int32 = 0x0002
    public static let O_ACCMODE: Int32 = 0x0003
    public static let O_NONBLOCK: Int32 = 0x0004
    public static let O_APPEND: Int32 = 0x0008
    public static let O_ASYNC: Int32 = 0x0040
    public static let O_FSYNC: Int32 = 0x0080
    public static let O_NOFOLLOW: Int32 = 0x0100
    public static let O_CREAT: Int32 = 0x0200
    public static let O_TRUNC: Int32 = 0x0400
    public static let O_EXCL: Int32 = 0x0800
    public static let O_DIRECTORY: Int32 = 0x0010_0000
    public static let O_CLOEXEC: Int32 = 0x0100_0000
    public static let O_CLOFORK: Int32 = 0x0800_0000
}

public struct DarwinTimespec: Equatable, Hashable, Sendable {
    public var sec: Int64
    public var nsec: Int64

    public init(sec: Int64 = 0, nsec: Int64 = 0) {
        self.sec = sec
        self.nsec = nsec
    }
}

public struct DarwinStat: Equatable, Hashable, Sendable {
    public var dev: UInt32
    public var mode: UInt16
    public var nlink: UInt16
    public var ino: UInt64
    public var uid: UInt32
    public var gid: UInt32
    public var rdev: UInt32
    public var atime: DarwinTimespec
    public var mtime: DarwinTimespec
    public var ctime: DarwinTimespec
    public var birthtime: DarwinTimespec
    public var size: Int64
    public var blocks: Int64
    public var blksize: Int32
    public var flags: UInt32
    public var gen: UInt32

    public init(dev: UInt32 = 0, mode: UInt16 = 0, nlink: UInt16 = 1, ino: UInt64 = 0, uid: UInt32 = 0, gid: UInt32 = 0,
                rdev: UInt32 = 0, atime: DarwinTimespec = .init(), mtime: DarwinTimespec = .init(),
                ctime: DarwinTimespec = .init(), birthtime: DarwinTimespec = .init(), size: Int64 = 0,
                blocks: Int64 = 0, blksize: Int32 = 4096, flags: UInt32 = 0, gen: UInt32 = 0) {
        self.dev = dev
        self.mode = mode
        self.nlink = nlink
        self.ino = ino
        self.uid = uid
        self.gid = gid
        self.rdev = rdev
        self.atime = atime
        self.mtime = mtime
        self.ctime = ctime
        self.birthtime = birthtime
        self.size = size
        self.blocks = blocks
        self.blksize = blksize
        self.flags = flags
        self.gen = gen
    }

    public static let encodedSize = 144

    public static let S_IFMT: UInt16 = 0o170000
    public static let S_IFIFO: UInt16 = 0o010000
    public static let S_IFCHR: UInt16 = 0o020000
    public static let S_IFDIR: UInt16 = 0o040000
    public static let S_IFBLK: UInt16 = 0o060000
    public static let S_IFREG: UInt16 = 0o100000
    public static let S_IFLNK: UInt16 = 0o120000
    public static let S_IFSOCK: UInt16 = 0o140000

    public var fileType: UInt16 { mode & Self.S_IFMT }
    public var isDirectory: Bool { fileType == Self.S_IFDIR }
    public var isRegularFile: Bool { fileType == Self.S_IFREG }
    public var isSymbolicLink: Bool { fileType == Self.S_IFLNK }

    public func encodedStat64() -> [UInt8] {
        var b = [UInt8](repeating: 0, count: Self.encodedSize)
        func put<T: FixedWidthInteger>(_ v: T, at offset: Int) {
            for i in 0..<(T.bitWidth / 8) { b[offset + i] = UInt8(truncatingIfNeeded: v >> (8 * i)) }
        }
        put(dev, at: 0)
        put(mode, at: 4)
        put(nlink, at: 6)
        put(ino, at: 8)
        put(uid, at: 16)
        put(gid, at: 20)
        put(rdev, at: 24)
        for (i, t) in [atime, mtime, ctime, birthtime].enumerated() {
            put(t.sec, at: 32 + 16 * i)
            put(t.nsec, at: 40 + 16 * i)
        }
        put(size, at: 96)
        put(blocks, at: 104)
        put(blksize, at: 112)
        put(flags, at: 116)
        put(gen, at: 120)
        return b
    }

    public init?(decodingStat64 b: [UInt8]) {
        guard b.count >= Self.encodedSize else { return nil }
        func get<T: FixedWidthInteger>(_: T.Type, at offset: Int) -> T {
            var v: T = 0
            for i in 0..<(T.bitWidth / 8) { v |= T(truncatingIfNeeded: b[offset + i]) << (8 * i) }
            return v
        }
        func ts(_ offset: Int) -> DarwinTimespec { .init(sec: get(Int64.self, at: offset), nsec: get(Int64.self, at: offset + 8)) }
        self.init(dev: get(UInt32.self, at: 0), mode: get(UInt16.self, at: 4), nlink: get(UInt16.self, at: 6),
                  ino: get(UInt64.self, at: 8), uid: get(UInt32.self, at: 16), gid: get(UInt32.self, at: 20),
                  rdev: get(UInt32.self, at: 24), atime: ts(32), mtime: ts(48), ctime: ts(64), birthtime: ts(80),
                  size: get(Int64.self, at: 96), blocks: get(Int64.self, at: 104), blksize: get(Int32.self, at: 112),
                  flags: get(UInt32.self, at: 116), gen: get(UInt32.self, at: 120))
    }
}

func hostErrno() -> Int32 { DarwinErrnoCode.fromHost(errno) }

func hostStatCall(_ path: String, follow: Bool) throws -> DarwinStat {
    #if canImport(Darwin)
    var st = Darwin.stat()
    #elseif canImport(Glibc)
    var st = Glibc.stat()
    #else
    var st = Musl.stat()
    #endif
    let r: Int32 = follow ? stat(path, &st) : lstat(path, &st)
    guard r == 0 else { throw DarwinErrnoError(hostErrno()) }
    return darwinStat(fromHost: st)
}

func hostFStat(_ fd: Int32) throws -> DarwinStat {
    #if canImport(Darwin)
    var st = Darwin.stat()
    #elseif canImport(Glibc)
    var st = Glibc.stat()
    #else
    var st = Musl.stat()
    #endif
    guard fstat(fd, &st) == 0 else { throw DarwinErrnoError(hostErrno()) }
    return darwinStat(fromHost: st)
}

public enum DarwinInodeMap {
    nonisolated(unsafe) private static var map: [HostKey: UInt64] = [:]
    nonisolated(unsafe) private static var active = false

    struct HostKey: Hashable { let dev: UInt64; let ino: UInt64 }

    public static func install(_ entries: [(dev: UInt64, hostIno: UInt64, guestIno: UInt64)]) {
        var m: [HostKey: UInt64] = [:]
        for e in entries where e.hostIno != e.guestIno { m[HostKey(dev: e.dev, ino: e.hostIno)] = e.guestIno }
        map = m
        active = !m.isEmpty
    }

    public static func guestInode(dev: UInt64, ino: UInt64) -> UInt64 {
        guard active else { return ino }
        return map[HostKey(dev: dev, ino: ino)] ?? ino
    }

    public static var count: Int { map.count }
}

#if canImport(Darwin)
private func darwinStat(fromHost st: Darwin.stat) -> DarwinStat {
    func ts(_ t: timespec) -> DarwinTimespec { .init(sec: Int64(t.tv_sec), nsec: Int64(t.tv_nsec)) }
    return DarwinStat(
        dev: UInt32(truncatingIfNeeded: st.st_dev), mode: UInt16(truncatingIfNeeded: st.st_mode),
        nlink: UInt16(clamping: st.st_nlink),
        ino: DarwinInodeMap.guestInode(dev: UInt64(truncatingIfNeeded: st.st_dev), ino: UInt64(truncatingIfNeeded: st.st_ino)),
        uid: guestUID(st.st_uid), gid: guestGID(st.st_gid), rdev: UInt32(truncatingIfNeeded: st.st_rdev),
        atime: ts(st.st_atimespec), mtime: ts(st.st_mtimespec), ctime: ts(st.st_ctimespec),
        birthtime: ts(st.st_birthtimespec), size: Int64(st.st_size), blocks: Int64(st.st_blocks),
        blksize: Int32(truncatingIfNeeded: st.st_blksize), flags: 0, gen: 0)
}
#else
private func darwinStat(fromHost st: stat) -> DarwinStat {
    func ts(_ t: timespec) -> DarwinTimespec { .init(sec: Int64(t.tv_sec), nsec: Int64(t.tv_nsec)) }
    let a = ts(st.st_atim), m = ts(st.st_mtim), c = ts(st.st_ctim)
    let birth = [a, m, c].min { ($0.sec, $0.nsec) < ($1.sec, $1.nsec) }!
    return DarwinStat(
        dev: UInt32(truncatingIfNeeded: st.st_dev), mode: UInt16(truncatingIfNeeded: st.st_mode),
        nlink: UInt16(clamping: st.st_nlink),
        ino: DarwinInodeMap.guestInode(dev: UInt64(truncatingIfNeeded: st.st_dev), ino: UInt64(truncatingIfNeeded: st.st_ino)),
        uid: guestUID(st.st_uid), gid: guestGID(st.st_gid), rdev: UInt32(truncatingIfNeeded: st.st_rdev),
        atime: a, mtime: m, ctime: c, birthtime: birth, size: Int64(st.st_size), blocks: Int64(st.st_blocks),
        blksize: Int32(truncatingIfNeeded: st.st_blksize), flags: 0, gen: 0)
}
#endif

private func guestUID(_ uid: uid_t) -> UInt32 { uid == geteuid() ? DarwinFileSystem.guestUID : UInt32(uid) }
private func guestGID(_ gid: gid_t) -> UInt32 { gid == getegid() ? DarwinFileSystem.guestGID : UInt32(gid) }

func hostOpen(_ path: String, _ flags: Int32, _ mode: UInt16) throws -> Int32 {
    #if os(Linux)
    do {
        let fd = open(path, flags | hostNoATime, mode_t(mode))
        if fd >= 0 { return fd }
        if errno != EPERM { throw DarwinErrnoError(hostErrno()) }
    }
    #endif
    let fd = open(path, flags, mode_t(mode))
    guard fd >= 0 else { throw DarwinErrnoError(hostErrno()) }
    return fd
}

func hostClose(_ fd: Int32) { _ = close(fd) }

#if os(Linux)
private let hostNoATime: Int32 = 0o1000000
#endif

private func hostPRead(_ fd: Int32, count: Int, offset: UInt64) throws -> [UInt8] {
    guard offset <= UInt64(Int64.max) else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
    guard count > 0 else { return [] }
    var buffer = [UInt8](repeating: 0, count: count)
    var done = 0
    while done < count {
        let n = buffer.withUnsafeMutableBytes { raw in
            pread(fd, raw.baseAddress! + done, count - done, off_t(offset) + off_t(done))
        }
        if n < 0 {
            if errno == EINTR { continue }
            throw DarwinErrnoError(hostErrno())
        }
        if n == 0 { break }
        done += n
    }
    buffer.removeSubrange(done...)
    return buffer
}

func hostPWrite(_ fd: Int32, _ bytes: [UInt8], offset: UInt64) throws -> Int {
    guard offset <= UInt64(Int64.max) else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
    var done = 0
    defer { if done > 0 { SharedFileViews.sizeMayHaveChanged(hostFD: fd) } }
    while done < bytes.count {
        let n = bytes.withUnsafeBytes { raw in
            pwrite(fd, raw.baseAddress! + done, bytes.count - done, off_t(offset) + off_t(done))
        }
        if n < 0 {
            if errno == EINTR { continue }
            throw DarwinErrnoError(hostErrno())
        }
        done += n
    }
    return done
}

func hostUnlink(_ path: String) throws {
    guard unlink(path) == 0 else { throw DarwinErrnoError(hostErrno()) }
}

func hostMkdir(_ path: String, _ mode: UInt16) throws {
    guard mkdir(path, mode_t(mode)) == 0 else { throw DarwinErrnoError(hostErrno()) }
    _ = chmod(path, mode_t(mode))
}

func hostRmdir(_ path: String) throws {
    guard rmdir(path) == 0 else { throw DarwinErrnoError(hostErrno()) }
}

func hostReadLink(_ path: String) throws -> String {
    var buffer = [CChar](repeating: 0, count: 4097)
    let n = readlink(path, &buffer, 4096)
    guard n >= 0 else { throw DarwinErrnoError(hostErrno()) }
    return String(decoding: buffer[0..<n].map { UInt8(bitPattern: $0) }, as: UTF8.self)
}

public final class GuestFile {
    public let guestPath: String
    public let hostPath: String
    public let hostFD: Int32
    let hostKeyStore = Mutex<HostFileKey?>(nil)
    public var size: UInt64 {
        (try? hostFStat(hostFD)).map { UInt64(max(0, $0.size)) } ?? UInt64(max(0, stat.size))
    }
    public let stat: DarwinStat

    public init(guestPath: String, hostPath: String, hostFD: Int32, stat: DarwinStat) {
        self.guestPath = guestPath
        self.hostPath = hostPath
        self.hostFD = hostFD
        self.stat = stat
    }

    private let memoryBackedState = Atomic<UInt8>(0)

    var isMemoryBacked: Bool {
        switch memoryBackedState.load(ordering: .relaxed) {
        case 1: return false
        case 2: return true
        default:
            #if os(Linux)
            let yes = HostFileIO.fileSystemType(hostFD).map { $0 == 0x0102_1994 || $0 == 0x8584_58F6 } ?? false
            #else
            let yes = false
            #endif
            memoryBackedState.store(yes ? 2 : 1, ordering: .relaxed)
            return yes
        }
    }

    public static func openReadOnly(hostPath: String, guestPath: String? = nil) throws -> GuestFile {
        let fd = try hostOpen(hostPath, O_RDONLY | O_CLOEXEC, 0)
        do {
            return GuestFile(guestPath: guestPath ?? hostPath, hostPath: hostPath, hostFD: fd, stat: try hostFStat(fd))
        } catch {
            hostClose(fd)
            throw error
        }
    }

    public var isDirectory: Bool { stat.isDirectory }

    public func read(count: Int, offset: UInt64) throws -> [UInt8] {
        guard count >= 0 else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
        return try hostPRead(hostFD, count: count, offset: offset)
    }

    deinit { hostClose(hostFD) }
}

public final class DarwinOpenFile {
    public enum Node {
        case console(stream: Int32)
        case file(GuestFile)
        case object(any DarwinDescriptorObject)
    }

    public let node: Node
    public var offset: UInt64 {
        get { ioLock.withLock { storedOffset } }
        set { ioLock.withLock { storedOffset = newValue } }
    }
    fileprivate var storedOffset: UInt64 = 0
    fileprivate let ioLock = OffsetLock()

    public func updateOffset<T>(wait: Bool = true, _ body: (inout UInt64) throws -> T) rethrows -> T? {
        if wait { ioLock.lock() } else if !ioLock.tryLock() { return nil }
        defer { ioLock.unlock() }
        return try body(&storedOffset)
    }
    public var statusFlags: Int32
    public var noSigPipe = false
    public var lastCloseHandlers: [String: () -> Void] = [:]
    public var confinedToProcess = false

    public init(node: Node, statusFlags: Int32) {
        self.node = node
        self.statusFlags = statusFlags
    }

    public var object: (any DarwinDescriptorObject)? {
        if case let .object(o) = node { return o }
        return nil
    }

    public var guestFile: GuestFile? {
        if case let .file(f) = node { return f }
        return nil
    }

    public var isReadable: Bool { statusFlags & DarwinOpen.O_ACCMODE != DarwinOpen.O_WRONLY }
    public var isWritable: Bool {
        let m = statusFlags & DarwinOpen.O_ACCMODE
        return m == DarwinOpen.O_WRONLY || m == DarwinOpen.O_RDWR
    }
    public var isNonBlocking: Bool { statusFlags & DarwinOpen.O_NONBLOCK != 0 }

    deinit {
        for handler in lastCloseHandlers.values { handler() }
        if case let .object(o) = node { o.lastReferenceClosed() }
    }
}

final class SocketNamespace {
    final class Node {
        weak var socket: (any DarwinDescriptorObject)?
        var stat: DarwinStat

        init(socket: any DarwinDescriptorObject, stat: DarwinStat) {
            self.socket = socket
            self.stat = stat
        }
    }

    var nodes: [String: Node] {
        get { nodesLock.withLock { storage } }
        set { nodesLock.withLock { storage = newValue } }
    }
    private var storage: [String: Node] = [:]
    private let nodesLock = NSLockLike(name: "socket names")
    var nextInode: UInt64 = 0x7963_0000_0000_0001
}

public final class DarwinFileSystem {
    public struct Prefix: Equatable, Sendable {
        public var guestPath: String
        public var hostPath: String
        public var writable: Bool
        public var device: UInt32?
        public var mountPoint: String?
        public var ownerUID: UInt32?
        public var ownerGID: UInt32?

        public init(guestPath: String, hostPath: String, writable: Bool, device: UInt32? = nil, mountPoint: String? = nil,
                    ownerUID: UInt32? = nil, ownerGID: UInt32? = nil) {
            self.guestPath = guestPath
            self.hostPath = hostPath
            self.writable = writable
            self.device = device
            self.mountPoint = mountPoint
            self.ownerUID = ownerUID
            self.ownerGID = ownerGID
        }

        public var volumeMountPoint: String { mountPoint ?? guestPath }
    }

    public var rootDevice: UInt32?

    public var cacheImageFiles: CacheImageFiles?

    public static let guestUID: UInt32 = 501
    public static let guestGID: UInt32 = 20
    public static let maxPathLength = 1024
    public static let maxNameLength = 255
    public static let maxSymlinks = 32
    public static let maxTransfer = 16 << 20
    public static let consolePath = "/dev/console"
    public static let openMax: Int32 = 10240

    struct Descriptor {
        var file: DarwinOpenFile
        var closeOnExec: Bool
        var closeOnFork = false
        var guardState: DescriptorGuard?
    }

    public var guardViolation: ((_ fd: Int32, _ flavor: UInt32, _ guard: UInt64) -> Void)?

    public let prefixes: [Prefix]
    private let console: (Int32, [UInt8]) -> Void
    private var descriptors: [Int32: Descriptor] = [:]
    public let tableLock = DescriptorTableLock()
    let sockets: SocketNamespace
    public var maxDescriptors: Int32 = 256
    public var ownerPID: Int32 = 0
    var tombstone: (directory: String, name: String, documentID: UInt32)? {
        get { tombstoneLock.withLock { tombstoneValue } }
        set { tombstoneLock.withLock { tombstoneValue = newValue } }
    }
    private var tombstoneValue: (directory: String, name: String, documentID: UInt32)?
    private let tombstoneLock = NSLockLike(name: "document tombstone")
    public var servesDevices = true
    public var guestSymlinks: [String: String] = [:] {
        didSet {
            var normalized: [String: String] = [:]
            for (k, v) in guestSymlinks { normalized[Self.normalizeAbsolute(k)] = v }
            if normalized != guestSymlinks { guestSymlinks = normalized }
        }
    }
    public static let darwinRootSymlinks = ["/var": "private/var", "/tmp": "private/tmp", "/etc": "private/etc"]

    fileprivate static func guestLinkInode(_ path: String) -> UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in path.utf8 { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
        return 0x7965_0000_0000_0000 | (h & 0xFFFF_FFFF)
    }
    public var descriptorClosed: ((Int32, DarwinOpenFile) -> Void)?

    private var cwdStorage: String {
        get { cwdLock.withLock { cwdValue } }
        set { cwdLock.withLock { cwdValue = newValue } }
    }
    private var cwdValue = "/"
    private let cwdLock = NSLockLike(name: "cwd")
    public var cwd: String {
        get { cwdStorage }
        set { cwdStorage = normalize(newValue, cwd: cwdStorage) }
    }

    public convenience init(prefixes: [Prefix], console: @escaping (Int32, [UInt8]) -> Void) {
        var normalized: [Prefix] = []
        for var p in prefixes {
            p.guestPath = Self.normalizeAbsolute(p.guestPath)
            while p.hostPath.count > 1 && p.hostPath.hasSuffix("/") { p.hostPath.removeLast() }
            normalized.append(p)
        }
        self.init(normalizedPrefixes: normalized, console: console, sockets: SocketNamespace(),
                  directoryPrefixes: DirectoryPrefixCache())
        for fd: Int32 in 0...2 {
            let flags = fd == 0 ? DarwinOpen.O_RDONLY : DarwinOpen.O_WRONLY
            descriptors[fd] = Descriptor(file: DarwinOpenFile(node: .console(stream: fd), statusFlags: flags),
                                         closeOnExec: false)
        }
    }

    private init(normalizedPrefixes: [Prefix], console: @escaping (Int32, [UInt8]) -> Void, sockets: SocketNamespace,
                 directoryPrefixes: DirectoryPrefixCache) {
        self.prefixes = normalizedPrefixes
        self.console = console
        self.sockets = sockets
        self.directoryPrefixes = directoryPrefixes
    }

    public func normalize(_ guestPath: String, cwd: String) -> String {
        if guestPath.hasPrefix("/") { return Self.normalizeAbsolute(guestPath) }
        return Self.normalizeAbsolute(cwd + "/" + guestPath)
    }

    private static func normalizeAbsolute(_ path: String) -> String {
        let bytes = Array(path.utf8)
        var parts: [ArraySlice<UInt8>] = []
        var start = 0
        func component(_ c: ArraySlice<UInt8>) {
            if c.isEmpty || (c.count == 1 && c.first == 0x2E) { return }
            if c.count == 2 && c.first == 0x2E && c.last == 0x2E {
                if !parts.isEmpty { parts.removeLast() }
                return
            }
            parts.append(c)
        }
        for (i, b) in bytes.enumerated() where b == 0x2F {
            component(bytes[start..<i])
            start = i + 1
        }
        component(bytes[start...])
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count + 1)
        if parts.isEmpty { out.append(0x2F) }
        for p in parts { out.append(0x2F); out += p }
        return String(decoding: out, as: UTF8.self)
    }

    func lookupPrefix(_ path: String) -> (prefix: Prefix, host: String)? {
        var best: (prefix: Prefix, host: String)?
        for p in prefixes {
            let rest: Substring
            if p.guestPath == "/" {
                rest = path.dropFirst()
            } else if path == p.guestPath {
                rest = ""
            } else if path.hasPrefix(p.guestPath + "/") {
                rest = path.dropFirst(p.guestPath.count + 1)
            } else {
                continue
            }
            if let b = best, b.prefix.guestPath.count >= p.guestPath.count { continue }
            let host = rest.isEmpty ? p.hostPath : (p.hostPath == "/" ? "/" : p.hostPath + "/") + rest
            best = (p, host)
        }
        return best
    }

    struct Resolved {
        var guestPath: String
        var hostPath: String
        var prefix: Prefix
        var stat: DarwinStat?
        var device: DarwinDevice.Kind?
        var guestLink: String?
    }

    private static let devicePrefix = Prefix(guestPath: "/dev", hostPath: "/dev", writable: false)

    private func firstGuestLink(in path: String) -> (link: String, target: String, rest: String)? {
        guard !guestSymlinks.isEmpty else { return nil }
        let bytes = Array(path.utf8)
        var end = 1
        while end <= bytes.count {
            if end == bytes.count || bytes[end] == 0x2F {
                let link = String(decoding: bytes[..<end], as: UTF8.self)
                if link != "/", let target = guestSymlinks[link] {
                    let rest = end + 1 < bytes.count ? String(decoding: bytes[(end + 1)...], as: UTF8.self) : ""
                    return (link, target, rest)
                }
            }
            end += 1
        }
        return nil
    }

    private func resolveDevice(_ path: String) throws -> Resolved {
        if path == "/dev" {
            var st = try hostStatCall("/dev", follow: true)
            st.mode = DarwinStat.S_IFDIR | 0o555
            st.uid = 0
            st.gid = 0
            return Resolved(guestPath: "/dev", hostPath: "/dev", prefix: Self.devicePrefix, stat: st)
        }
        let parts = path.dropFirst(5).split(separator: "/")
        let name = parts.first.map(String.init) ?? ""
        let kind = DarwinDevice.Kind(rawValue: name)
        if parts.count > 1 { throw DarwinErrnoError(kind == nil ? DarwinErrnoCode.ENOENT : DarwinErrnoCode.ENOTDIR) }
        guard name.utf8.count <= Self.maxNameLength else { throw DarwinErrnoError(DarwinErrnoCode.ENAMETOOLONG) }
        return Resolved(guestPath: "/dev/" + name, hostPath: "", prefix: Self.devicePrefix,
                        stat: kind.map { DarwinDevice.stat(of: $0) }, device: kind)
    }

    func resolve(_ path: String, followFinal: Bool, noFollowAny: Bool = false) throws -> Resolved {
        guard !path.isEmpty else { throw DarwinErrnoError(DarwinErrnoCode.ENOENT) }
        guard path.utf8.count < Self.maxPathLength else { throw DarwinErrnoError(DarwinErrnoCode.ENAMETOOLONG) }
        var current = normalize(path, cwd: cwdStorage)
        var linksFollowed = 0

        restart: while true {
            if let (link, target, rest) = firstGuestLink(in: current) {
                if rest.isEmpty && !followFinal {
                    let st = DarwinStat(mode: DarwinStat.S_IFLNK | 0o755, nlink: 1, ino: Self.guestLinkInode(link),
                                        uid: 0, gid: 0, size: Int64(target.utf8.count), blksize: 4096)
                    return Resolved(guestPath: link, hostPath: "", prefix: Self.devicePrefix, stat: st, guestLink: target)
                }
                if noFollowAny { throw DarwinErrnoError(DarwinErrnoCode.ELOOP) }
                linksFollowed += 1
                guard linksFollowed <= Self.maxSymlinks else { throw DarwinErrnoError(DarwinErrnoCode.ELOOP) }
                let parent = String(link[..<link.lastIndex(of: "/")!])
                var next = target.hasPrefix("/") ? target : (parent.isEmpty ? "/" : parent) + "/" + target
                if !rest.isEmpty { next += "/" + rest }
                current = Self.normalizeAbsolute(next)
                continue restart
            }
            if servesDevices && (current == "/dev" || current.hasPrefix("/dev/")) {
                return try resolveDevice(current)
            }
            guard let (prefix, _) = lookupPrefix(current) else {
                if isSyntheticAncestor(current) {
                    let dev = rootDevice
                        ?? prefixes.lazy.compactMap { try? hostStatCall($0.hostPath, follow: true).dev }.first ?? 1
                    let st = DarwinStat(dev: dev, mode: DarwinStat.S_IFDIR | 0o755, nlink: 2, ino: Self.guestLinkInode(current),
                                        uid: 0, gid: 0, size: 64, blksize: 4096)
                    return Resolved(guestPath: current, hostPath: "", prefix: Self.devicePrefix, stat: st)
                }
                throw DarwinErrnoError(DarwinErrnoCode.ENOENT)
            }
            let components = current == prefix.guestPath ? []
                : (prefix.guestPath == "/" ? current.dropFirst() : current.dropFirst(prefix.guestPath.count + 1))
                    .split(separator: "/").map(String.init)
            if components.contains(where: { $0.utf8.count > Self.maxNameLength }) {
                throw DarwinErrnoError(DarwinErrnoCode.ENAMETOOLONG)
            }
            var guest = prefix.guestPath
            var host = prefix.hostPath
            var st: DarwinStat? = try hostStatCall(host, follow: true)
            for (i, name) in components.enumerated() {
                let isLast = i == components.count - 1
                guard let parent = st else { throw DarwinErrnoError(DarwinErrnoCode.ENOENT) }
                guard parent.isDirectory else { throw DarwinErrnoError(DarwinErrnoCode.ENOTDIR) }
                guest = guest == "/" ? "/" + name : guest + "/" + name
                host = host == "/" ? "/" + name : host + "/" + name
                do {
                    st = try hostStatCall(host, follow: false)
                } catch let e as DarwinErrnoError where e.errno == DarwinErrnoCode.ENOENT {
                    st = sockets.nodes[guest]?.stat
                    continue
                }
                if let s = st, s.isSymbolicLink, !isLast || followFinal {
                    if noFollowAny { throw DarwinErrnoError(DarwinErrnoCode.ELOOP) }
                    linksFollowed += 1
                    guard linksFollowed <= Self.maxSymlinks else { throw DarwinErrnoError(DarwinErrnoCode.ELOOP) }
                    let target = try hostReadLink(host)
                    let parentGuest = String(guest[..<guest.lastIndex(of: "/")!])
                    let rest = components[(i + 1)...].joined(separator: "/")
                    var next = target.hasPrefix("/") ? target : (parentGuest.isEmpty ? "/" : parentGuest) + "/" + target
                    if !rest.isEmpty { next += "/" + rest }
                    current = Self.normalizeAbsolute(next)
                    continue restart
                }
            }
            if let device = prefix.device, st != nil { st!.dev = device }
            if st != nil {
                if let uid = prefix.ownerUID { st!.uid = uid }
                if let gid = prefix.ownerGID { st!.gid = gid }
            }
            return Resolved(guestPath: guest, hostPath: host, prefix: prefix, stat: st)
        }
    }

    private func isSyntheticAncestor(_ path: String) -> Bool {
        if path == "/" { return true }
        let below = path + "/"
        let directories = directoryPrefixes.paths {
            prefixes.filter { (try? hostStatCall($0.hostPath, follow: true))?.isDirectory ?? false }.map(\.guestPath)
        }
        return directories.contains { $0.hasPrefix(below) } || guestSymlinks.keys.contains { $0.hasPrefix(below) }
    }

    private final class DirectoryPrefixCache: @unchecked Sendable {
        private let lock = NSLockLike(name: "directory prefix cache")
        private var value: [String]?
        func paths(_ compute: () -> [String]) -> [String] {
            lock.withLock {
                if let value { return value }
                let computed = compute()
                value = computed
                return computed
            }
        }
    }
    private let directoryPrefixes: DirectoryPrefixCache

    public func realpath(_ path: String) throws -> String {
        let r = try resolve(path, followFinal: true)
        guard r.stat != nil else { throw DarwinErrnoError(DarwinErrnoCode.ENOENT) }
        return r.guestPath
    }

    func entry(_ fd: Int32) throws -> Descriptor {
        guard let d = tableLock.withLock({ descriptors[fd] }) else { throw DarwinErrnoError(DarwinErrnoCode.EBADF) }
        return d
    }

    private func lowestFreeDescriptor(from minimum: Int32 = 0) throws -> Int32 {
        var fd = max(0, minimum)
        while descriptors[fd] != nil { fd += 1 }
        guard fd < maxDescriptors else { throw DarwinErrnoError(DarwinErrnoCode.EMFILE) }
        return fd
    }

    public var freeDescriptorCount: Int {
        tableLock.withLock { max(0, Int(maxDescriptors) - descriptors.keys.filter { $0 < maxDescriptors }.count) }
    }

    private typealias Closed = [(fd: Int32, descriptor: Descriptor)]

    private func changingTable<T>(_ body: (inout Closed) throws -> T) rethrows -> T {
        var closed: Closed = []
        defer {
            for c in closed { descriptorClosed?(c.fd, c.descriptor.file) }
            closed.removeAll()
        }
        return try tableLock.withLock { try body(&closed) }
    }

    @discardableResult
    private func remove(_ fd: Int32, into closed: inout Closed) -> Bool {
        guard let old = descriptors.removeValue(forKey: fd) else { return false }
        closed.append((fd, old))
        return true
    }

    public func open(_ path: String, flags: Int32, mode: UInt16) throws -> Int32 {
        let (file, closeOnExec) = try makeOpenFile(path, flags: flags, mode: mode)
        return try tableLock.withLock {
            let fd = try lowestFreeDescriptor()
            descriptors[fd] = Descriptor(file: file, closeOnExec: closeOnExec,
                                         closeOnFork: flags & DarwinOpen.O_CLOFORK != 0)
            return fd
        }
    }

    public struct PreparedOpen {
        let file: DarwinOpenFile
        let closeOnExec: Bool
        let closeOnFork: Bool
    }

    public func prepareOpen(_ path: String, flags: Int32, mode: UInt16) throws -> PreparedOpen {
        let (file, closeOnExec) = try makeOpenFile(path, flags: flags, mode: mode)
        return PreparedOpen(file: file, closeOnExec: closeOnExec, closeOnFork: flags & DarwinOpen.O_CLOFORK != 0)
    }

    public func install(_ prepared: PreparedOpen) throws -> Int32 {
        try tableLock.withLock {
            let fd = try lowestFreeDescriptor()
            descriptors[fd] = Descriptor(file: prepared.file, closeOnExec: prepared.closeOnExec,
                                         closeOnFork: prepared.closeOnFork)
            return fd
        }
    }

    @discardableResult
    public func open(_ path: String, flags: Int32, mode: UInt16, at fd: Int32) throws -> Int32 {
        guard fd >= 0, fd < maxDescriptors else { throw DarwinErrnoError(DarwinErrnoCode.EBADF) }
        let (file, closeOnExec) = try makeOpenFile(path, flags: flags, mode: mode)
        return try install(file, closeOnExec: closeOnExec, at: fd)
    }

    public func installDeviceModeStandardDescriptors() throws {
        try open("/dev/null", flags: DarwinOpen.O_RDONLY, mode: 0, at: 0)
        try open("/dev/null", flags: DarwinOpen.O_WRONLY, mode: 0, at: 1)
        try open("/dev/console", flags: DarwinOpen.O_WRONLY, mode: 0, at: 3)
    }

    private func makeOpenFile(_ path: String, flags: Int32, mode: UInt16) throws -> (DarwinOpenFile, Bool) {
        let accessMode = flags & DarwinOpen.O_ACCMODE
        guard accessMode != DarwinOpen.O_ACCMODE else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
        let wantsWrite = accessMode != DarwinOpen.O_RDONLY
        let create = flags & DarwinOpen.O_CREAT != 0
        let exclusive = create && flags & DarwinOpen.O_EXCL != 0
        let truncate = flags & DarwinOpen.O_TRUNC != 0
        let directory = flags & DarwinOpen.O_DIRECTORY != 0
        let follow = flags & DarwinOpen.O_NOFOLLOW == 0 && !exclusive

        let r = try resolve(path, followFinal: follow)
        let status = flags & (DarwinOpen.O_ACCMODE | DarwinOpen.O_APPEND | DarwinOpen.O_NONBLOCK)
        let closeOnExec = flags & DarwinOpen.O_CLOEXEC != 0
        if let kind = r.device {
            if exclusive { throw DarwinErrnoError(DarwinErrnoCode.EEXIST) }
            if directory { throw DarwinErrnoError(DarwinErrnoCode.ENOTDIR) }
            switch kind {
            case .tty: throw DarwinErrnoError(DarwinErrnoCode.ENXIO)
            case .console: return (DarwinOpenFile(node: .console(stream: 1), statusFlags: status), closeOnExec)
            default: return (DarwinOpenFile(node: .object(DarwinDevice(kind)), statusFlags: status), closeOnExec)
            }
        }
        if let st = r.stat {
            if exclusive { throw DarwinErrnoError(DarwinErrnoCode.EEXIST) }
            if st.isSymbolicLink { throw DarwinErrnoError(DarwinErrnoCode.ELOOP) }
            if directory && !st.isDirectory { throw DarwinErrnoError(DarwinErrnoCode.ENOTDIR) }
            if st.fileType == DarwinStat.S_IFSOCK { throw DarwinErrnoError(DarwinErrnoCode.EOPNOTSUPP) }
            if st.isDirectory && (wantsWrite || truncate) { throw DarwinErrnoError(DarwinErrnoCode.EISDIR) }
            if !r.prefix.writable && (wantsWrite || truncate) { throw DarwinErrnoError(DarwinErrnoCode.EROFS) }
        } else {
            guard create else { throw DarwinErrnoError(DarwinErrnoCode.ENOENT) }
            guard r.prefix.writable else { throw DarwinErrnoError(DarwinErrnoCode.EROFS) }
            guard !directory else { throw DarwinErrnoError(DarwinErrnoCode.ENOENT) }
        }
        var hostFlags: Int32 = O_CLOEXEC
        switch accessMode {
        case DarwinOpen.O_WRONLY: hostFlags |= O_WRONLY
        case DarwinOpen.O_RDWR: hostFlags |= O_RDWR
        default: hostFlags |= O_RDONLY
        }
        if r.stat == nil { hostFlags |= O_CREAT | O_EXCL }
        if truncate { hostFlags |= O_TRUNC }
        if directory { hostFlags |= O_DIRECTORY }
        hostFlags |= O_NOFOLLOW
        if r.hostPath.isEmpty { throw DarwinErrnoError(DarwinErrnoCode.EACCES) }
        let watched = r.stat == nil || (truncate && (r.stat?.size ?? 0) != 0) ? VnodeNotes.capture(r.hostPath) : nil
        let hostFD = try hostOpen(r.hostPath, hostFlags, mode & 0o7777)
        if truncate && r.stat != nil { SharedFileViews.sizeMayHaveChanged(hostFD: hostFD) }
        let file: GuestFile
        do {
            var st = try hostFStat(hostFD)
            if let device = r.prefix.device { st.dev = device }
            file = GuestFile(guestPath: r.guestPath, hostPath: r.hostPath, hostFD: hostFD, stat: st)
        } catch {
            hostClose(hostFD)
            throw error
        }
        if r.stat == nil {
            inheritTombstone(guestPath: r.guestPath, hostFD: hostFD)
            FileChangeFeed.note(.created, .file, r.guestPath, pid: ownerPID)
            watched?.post(directory: VnodeNote.write)
        } else if truncate {
            WriteGenerations.noteWrite(dev: file.stat.dev, ino: file.stat.ino)
            FileChangeFeed.note(.modified, .file, r.guestPath, pid: ownerPID)
            watched?.post(object: VnodeNotes.sizeNotes(from: r.stat?.size ?? 0, to: 0))
        }
        return (DarwinOpenFile(node: .file(file), statusFlags: status), closeOnExec)
    }

    public func close(_ fd: Int32) throws {
        try changingTable { closed in
            try checkGuard(fd, DarwinGuard.close, flavor: DarwinGuard.exceptionClose)
            guard remove(fd, into: &closed) else { throw DarwinErrnoError(DarwinErrnoCode.EBADF) }
        }
    }

    public func removeIf(_ fd: Int32, _ accept: (DarwinOpenFile, _ guarded: Bool) -> Bool) throws -> DarwinOpenFile? {
        try tableLock.withLock {
            guard let d = descriptors[fd] else { throw DarwinErrnoError(DarwinErrnoCode.EBADF) }
            guard accept(d.file, d.guardState != nil) else { return nil }
            descriptors[fd] = nil
            return d.file
        }
    }

    public func read(_ fd: Int32, count: Int) throws -> [UInt8] {
        let d = try entry(fd)
        guard d.file.isReadable else { throw DarwinErrnoError(DarwinErrnoCode.EBADF) }
        guard count >= 0 else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
        switch d.file.node {
        case .console:
            return []
        case let .file(f):
            if f.isDirectory { throw DarwinErrnoError(DarwinErrnoCode.EISDIR) }
            return try HostFileIO(description: d.file, file: f).read(count: count)
        case let .object(o):
            guard let device = o as? DarwinDevice else { throw DarwinErrnoError(DarwinErrnoCode.EOPNOTSUPP) }
            return device.read(count: min(count, Self.maxTransfer))
        }
    }

    public func pread(_ fd: Int32, count: Int, offset: UInt64) throws -> [UInt8] {
        let d = try entry(fd)
        guard d.file.isReadable else { throw DarwinErrnoError(DarwinErrnoCode.EBADF) }
        guard count >= 0 else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
        switch d.file.node {
        case let .object(o as DarwinDevice):
            return o.read(count: min(count, Self.maxTransfer))
        case .console, .object:
            throw DarwinErrnoError(DarwinErrnoCode.ESPIPE)
        case let .file(f):
            if f.isDirectory { throw DarwinErrnoError(DarwinErrnoCode.EISDIR) }
            return try hostPRead(f.hostFD, count: min(count, Self.maxTransfer), offset: offset)
        }
    }

    public func write(_ fd: Int32, _ bytes: [UInt8]) throws -> Int {
        try write(fd, bytes, guardChecked: false)
    }

    public func write(_ fd: Int32, _ bytes: [UInt8], guardChecked: Bool) throws -> Int {
        if !guardChecked { try checkGuard(fd, DarwinGuard.write, flavor: DarwinGuard.exceptionWrite) }
        let d = try entry(fd)
        switch d.file.node {
        case let .console(stream):
            console(stream, bytes)
            return bytes.count
        case let .file(f):
            guard d.file.isWritable else { throw DarwinErrnoError(DarwinErrnoCode.EBADF) }
            return try HostFileIO(description: d.file, file: f, pid: ownerPID).write(bytes)
        case let .object(o):
            guard let device = o as? DarwinDevice else { throw DarwinErrnoError(DarwinErrnoCode.EOPNOTSUPP) }
            guard d.file.isWritable else { throw DarwinErrnoError(DarwinErrnoCode.EBADF) }
            return device.write(bytes)
        }
    }

    public func pwrite(_ fd: Int32, _ bytes: [UInt8], offset: UInt64) throws -> Int {
        try pwrite(fd, bytes, offset: offset, guardChecked: false)
    }

    public func pwrite(_ fd: Int32, _ bytes: [UInt8], offset: UInt64, guardChecked: Bool) throws -> Int {
        if !guardChecked { try checkGuard(fd, DarwinGuard.write, flavor: DarwinGuard.exceptionWrite) }
        let d = try entry(fd)
        guard d.file.isWritable else { throw DarwinErrnoError(DarwinErrnoCode.EBADF) }
        switch d.file.node {
        case let .object(o as DarwinDevice):
            return o.write(bytes)
        case .console, .object:
            throw DarwinErrnoError(DarwinErrnoCode.ESPIPE)
        case let .file(f):
            let watch = f.vnodeWriteWatch()
            let n = try hostPWrite(f.hostFD, bytes, offset: offset)
            f.noteWritten(pid: ownerPID)
            if let watch { VnodeNotes.post(watch.key, VnodeNotes.writeNotes(offset: offset, count: n, sizeBefore: watch.size)) }
            return n
        }
    }

    public func lseek(_ fd: Int32, offset: Int64, whence: Int32) throws -> UInt64 {
        try lseekTarget(fd).seek(offset: offset, whence: whence)!
    }

    public func lseekTarget(_ fd: Int32) throws -> LSeek {
        let d = try entry(fd)
        switch d.file.node {
        case let .file(file): return LSeek(description: d.file, file: file)
        case .object(is DarwinDevice): return LSeek(description: d.file, file: nil)
        default: throw DarwinErrnoError(DarwinErrnoCode.ESPIPE)
        }
    }

    public struct LSeek: @unchecked Sendable {
        let description: DarwinOpenFile
        let file: GuestFile?

        public func seek(offset: Int64, whence: Int32, wait: Bool = true) throws -> UInt64? {
            guard (0...2).contains(whence) else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
            let end: Int64 = whence == 2 ? (try file.map { try hostFStat($0.hostFD).size } ?? 0) : 0
            return try description.updateOffset(wait: wait) { current -> UInt64 in
                let base = whence == 0 ? 0 : whence == 1 ? Int64(clamping: current) : end
                let (target, overflow) = base.addingReportingOverflow(offset)
                guard !overflow else { throw DarwinErrnoError(DarwinErrnoCode.EOVERFLOW) }
                guard target >= 0 else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
                current = UInt64(target)
                return current
            }
        }
    }

    public func stat(_ path: String, followSymlinks: Bool, cacheImages: Bool = true) throws -> DarwinStat {
        let r = try resolve(path, followFinal: followSymlinks)
        guard var st = r.stat else {
            if cacheImages, let images = cacheImageFiles, let st = cacheImageStat(images, path: path, resolved: r) { return st }
            throw DarwinErrnoError(DarwinErrnoCode.ENOENT)
        }
        if r.prefix.writable, !r.hostPath.isEmpty { st.flags = VolumeMetadata.read(hostPath: r.hostPath).flags }
        return st
    }

    public func statEntry(inDirectory directory: String, name: String) throws -> DarwinStat {
        let entry = directory == "/" ? "/" + name : directory + "/" + name
        guard !name.isEmpty, !name.contains("/"), name != ".", name != "..",
              !(servesDevices && (entry == "/dev" || entry.hasPrefix("/dev/"))),
              firstGuestLink(in: entry) == nil,
              let (prefix, host) = lookupPrefix(entry), entry != prefix.guestPath,
              lookupPrefix(directory)?.prefix.guestPath == prefix.guestPath,
              var st = try? hostStatCall(host, follow: false) else {
            return try stat(entry, followSymlinks: false)
        }
        if let device = prefix.device { st.dev = device }
        if let uid = prefix.ownerUID { st.uid = uid }
        if let gid = prefix.ownerGID { st.gid = gid }
        if prefix.writable { st.flags = VolumeMetadata.read(hostPath: host).flags }
        return st
    }

    private func cacheImageStat(_ images: CacheImageFiles, path: String, resolved r: Resolved) -> DarwinStat? {
        guard r.device == nil, r.guestLink == nil else { return nil }
        let dev = r.prefix.device ?? ((try? hostStatCall(r.prefix.hostPath, follow: true))?.dev ?? 0)
        return images.stat(forGuestPath: r.guestPath, dev: dev)
            ?? images.stat(forGuestPath: normalize(path, cwd: cwdStorage), dev: dev)
    }

    public func fstat(_ fd: Int32) throws -> DarwinStat {
        try fstat(of: try entry(fd).file)
    }

    public func fstat(of description: DarwinOpenFile) throws -> DarwinStat {
        switch description.node {
        case .console:
            return DarwinStat(mode: DarwinStat.S_IFCHR | 0o620, nlink: 1, uid: Self.guestUID, gid: 4,
                              blksize: 131_072)
        case let .file(f):
            var st = try hostFStat(f.hostFD)
            st.dev = f.stat.dev
            if let prefix = lookupPrefix(f.guestPath)?.prefix {
                if let uid = prefix.ownerUID { st.uid = uid }
                if let gid = prefix.ownerGID { st.gid = gid }
                if prefix.writable { st.flags = VolumeMetadata.read(fd: f.hostFD).flags }
            }
            return st
        case let .object(o):
            return o.descriptorStat()
        }
    }

    public func file(for fd: Int32) throws -> GuestFile {
        switch try entry(fd).file.node {
        case .console, .object: throw DarwinErrnoError(DarwinErrnoCode.ENODEV)
        case let .file(f): return f
        }
    }

    public func path(for fd: Int32) throws -> String {
        switch try entry(fd).file.node {
        case .console: return Self.consolePath
        case let .file(f): return f.guestPath
        case let .object(o as DarwinDevice): return o.path
        case .object: throw DarwinErrnoError(DarwinErrnoCode.EBADF)
        }
    }

    public func setCloseOnExec(_ fd: Int32, _ on: Bool) throws {
        try tableLock.withLock {
            var d = try entry(fd)
            if let g = d.guardState, !on {
                guardViolation?(fd, DarwinGuard.exceptionNoCloexec, g.value)
                throw DarwinErrnoError(DarwinErrnoCode.EPERM)
            }
            d.closeOnExec = on
            descriptors[fd] = d
        }
    }

    public func closeOnExec(_ fd: Int32) throws -> Bool { try entry(fd).closeOnExec }

    public func closeOnFork(_ fd: Int32) throws -> Bool { try entry(fd).closeOnFork }

    public func setCloseOnFork(_ fd: Int32, _ on: Bool) throws {
        try tableLock.withLock {
            _ = try entry(fd)
            descriptors[fd]?.closeOnFork = on
        }
    }

    public func setConfined(_ fd: Int32, _ on: Bool) throws {
        try tableLock.withLock {
            let d = try entry(fd)
            guard on else { throw DarwinErrnoError(DarwinErrnoCode.EPERM) }
            if d.file.confinedToProcess { return }
            guard descriptors.values.filter({ $0.file === d.file }).count == 1 else {
                throw DarwinErrnoError(DarwinErrnoCode.EAGAIN)
            }
            guard d.closeOnFork else { throw DarwinErrnoError(DarwinErrnoCode.EBADF) }
            d.file.confinedToProcess = true
        }
    }

    public func statusFlags(_ fd: Int32) throws -> Int32 { try entry(fd).file.statusFlags }

    public static let settableStatusFlags = DarwinOpen.O_APPEND | DarwinOpen.O_NONBLOCK | DarwinOpen.O_ASYNC
        | DarwinOpen.O_FSYNC

    public func setStatusFlags(_ fd: Int32, _ flags: Int32) throws {
        let file = try entry(fd).file
        file.statusFlags = (file.statusFlags & ~Self.settableStatusFlags) | (flags & Self.settableStatusFlags)
    }

    public var openDescriptors: [Int32] { tableLock.withLock { descriptors.keys.sorted() } }
}

extension DarwinFileSystem {
    public func installObject(_ object: DarwinDescriptorObject, statusFlags: Int32, closeOnExec: Bool) throws -> Int32 {
        try install(DarwinOpenFile(node: .object(object), statusFlags: statusFlags), closeOnExec: closeOnExec)
    }

    public func object(for fd: Int32) throws -> DarwinDescriptorObject? {
        try entry(fd).file.object
    }

    public func openFile(for fd: Int32) throws -> DarwinOpenFile {
        try entry(fd).file
    }

    @discardableResult
    public func install(_ file: DarwinOpenFile, closeOnExec: Bool, at fd: Int32? = nil) throws -> Int32 {
        try changingTable { closed in try install(file, closeOnExec: closeOnExec, at: fd, closed: &closed) }
    }

    private func install(_ file: DarwinOpenFile, closeOnExec: Bool, at fd: Int32?, closed: inout Closed) throws -> Int32 {
        if let fd {
            guard fd >= 0, fd < maxDescriptors else { throw DarwinErrnoError(DarwinErrnoCode.EBADF) }
            if descriptors[fd] != nil { try checkGuard(fd, DarwinGuard.close, flavor: DarwinGuard.exceptionClose) }
            let old = descriptors[fd]
            descriptors[fd] = Descriptor(file: file, closeOnExec: closeOnExec)
            if let old { closed.append((fd, old)) }
            return fd
        }
        let n = try lowestFreeDescriptor()
        descriptors[n] = Descriptor(file: file, closeOnExec: closeOnExec)
        return n
    }

    public func dup(_ fd: Int32, minimum: Int32 = 0) throws -> Int32 {
        try dup(fd, minimum: minimum, closeOnExec: false)
    }

    public func dup(_ fd: Int32, minimum: Int32, closeOnExec: Bool) throws -> Int32 {
        try tableLock.withLock {
            let d = try entry(fd)
            try checkGuard(fd, DarwinGuard.dup, flavor: DarwinGuard.exceptionDup)
            guard minimum >= 0, minimum < maxDescriptors else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
            let n = try lowestFreeDescriptor(from: minimum)
            descriptors[n] = Descriptor(file: d.file, closeOnExec: closeOnExec)
            return n
        }
    }

    public func dup2(_ from: Int32, _ to: Int32) throws {
        try changingTable { closed in
            let d = try entry(from)
            try checkGuard(from, DarwinGuard.dup, flavor: DarwinGuard.exceptionDup)
            guard to >= 0, to < maxDescriptors else { throw DarwinErrnoError(DarwinErrnoCode.EBADF) }
            if from == to { return }
            _ = try install(d.file, closeOnExec: false, at: to, closed: &closed)
        }
    }

    public func makeChildCopy(newProcess: Bool = true) -> DarwinFileSystem {
        let child = DarwinFileSystem(normalizedPrefixes: prefixes, console: console, sockets: sockets,
                                     directoryPrefixes: directoryPrefixes)
        child.cwdStorage = cwdStorage
        child.maxDescriptors = maxDescriptors
        child.servesDevices = servesDevices
        child.guestSymlinks = guestSymlinks
        child.rootDevice = rootDevice
        child.cacheImageFiles = cacheImageFiles
        let inherited = tableLock.withLock { descriptors }
        for (fd, d) in inherited where !(d.file.object?.isConfined ?? false)
            && !(newProcess && d.file.confinedToProcess) {
            child.descriptors[fd] = d
        }
        return child
    }

    public func closeOnExecDescriptors(keepOnly: Set<Int32>? = nil) {
        changingTable { closed in
            let doomed = descriptors.filter { fd, d in d.closeOnExec || !(keepOnly?.contains(fd) ?? true) }.keys.sorted()
            for fd in doomed { remove(fd, into: &closed) }
        }
    }

    public func closeAll() {
        changingTable { closed in
            for fd in descriptors.keys.sorted() { remove(fd, into: &closed) }
        }
    }

    public func chdir(_ path: String) throws {
        let r = try resolve(path, followFinal: true)
        guard let st = r.stat else { throw DarwinErrnoError(DarwinErrnoCode.ENOENT) }
        guard st.isDirectory else { throw DarwinErrnoError(DarwinErrnoCode.ENOTDIR) }
        cwdStorage = r.guestPath
    }

    public func fchdir(_ fd: Int32) throws {
        guard case let .file(f) = try entry(fd).file.node, f.isDirectory else {
            throw DarwinErrnoError(DarwinErrnoCode.ENOTDIR)
        }
        cwdStorage = f.guestPath
    }

    public func directoryEntryCount(_ path: String) -> Int? {
        guard let r = try? resolve(path, followFinal: true), r.stat?.isDirectory == true, !r.hostPath.isEmpty else { return nil }
        return GuestPath.hostDirectoryNames(r.hostPath)?.count
    }

    public func hostPathForExec(_ path: String) throws -> (guestPath: String, hostPath: String) {
        let r = try resolve(path, followFinal: true)
        guard let st = r.stat else { throw DarwinErrnoError(DarwinErrnoCode.ENOENT) }
        guard st.isRegularFile, sockets.nodes[r.guestPath] == nil else {
            throw DarwinErrnoError(DarwinErrnoCode.EACCES)
        }
        return (r.guestPath, r.hostPath)
    }

    public func unlink(_ path: String) throws {
        _ = try unlink(path, socketsToo: true)
    }

    public func unlinkHostFile(_ path: String) throws -> Bool {
        try unlink(path, socketsToo: false)
    }

    private func unlink(_ path: String, socketsToo: Bool) throws -> Bool {
        let r = try resolve(path, followFinal: false)
        if sockets.nodes[r.guestPath] != nil {
            guard socketsToo else { return false }
            sockets.nodes[r.guestPath] = nil
            return true
        }
        guard let st = r.stat else { throw DarwinErrnoError(DarwinErrnoCode.ENOENT) }
        if st.isDirectory { throw DarwinErrnoError(DarwinErrnoCode.EPERM) }
        guard r.prefix.writable else { throw DarwinErrnoError(DarwinErrnoCode.EROFS) }
        let record = VolumeMetadata.read(hostPath: r.hostPath)
        let watched = VnodeNotes.capture(r.hostPath)
        try hostUnlink(r.hostPath)
        leaveTombstone(guestPath: r.guestPath, record)
        FileChangeFeed.note(.removed, FileChange.item(st), r.guestPath, pid: ownerPID)
        watched?.post(object: VnodeNote.delete | VnodeNote.link, directory: VnodeNote.write)
        return true
    }

    public func mkdir(_ path: String, mode: UInt16, umask: UInt16) throws {
        let r = try resolve(path, followFinal: false)
        guard r.stat == nil else { throw DarwinErrnoError(DarwinErrnoCode.EEXIST) }
        guard r.prefix.writable, !r.hostPath.isEmpty else { throw DarwinErrnoError(DarwinErrnoCode.EROFS) }
        let watched = VnodeNotes.capture(r.hostPath)
        try hostMkdir(r.hostPath, mode & ~umask & 0o7777)
        FileChangeFeed.note(.created, .directory, r.guestPath, pid: ownerPID)
        watched?.post(directory: VnodeNote.write | VnodeNote.link)
    }

    public func rmdir(_ path: String) throws {
        let r = try resolve(path, followFinal: false)
        guard let st = r.stat else { throw DarwinErrnoError(DarwinErrnoCode.ENOENT) }
        guard st.isDirectory else { throw DarwinErrnoError(DarwinErrnoCode.ENOTDIR) }
        if r.guestPath == r.prefix.guestPath || prefixes.contains(where: { $0.guestPath == r.guestPath }) {
            throw DarwinErrnoError(DarwinErrnoCode.EBUSY)
        }
        guard r.prefix.writable else { throw DarwinErrnoError(DarwinErrnoCode.EROFS) }
        if !socketNames(inDirectory: r.guestPath).isEmpty { throw DarwinErrnoError(DarwinErrnoCode.ENOTEMPTY) }
        let watched = VnodeNotes.capture(r.hostPath)
        try hostRmdir(r.hostPath)
        FileChangeFeed.note(.removed, .directory, r.guestPath, pid: ownerPID)
        watched?.post(object: VnodeNote.delete | VnodeNote.link, directory: VnodeNote.write | VnodeNote.link)
    }

    public func readlink(_ path: String) throws -> String {
        let r = try resolve(path, followFinal: false)
        if let target = r.guestLink { return target }
        guard let st = r.stat else { throw DarwinErrnoError(DarwinErrnoCode.ENOENT) }
        guard st.isSymbolicLink else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
        return try hostReadLink(r.hostPath)
    }

    public func bindSocket(_ socket: DarwinDescriptorObject, path: String, umask: UInt16) throws -> String {
        let r = try resolve(path, followFinal: false)
        guard r.stat == nil else { throw DarwinErrnoError(DarwinErrnoCode.EADDRINUSE) }
        guard r.prefix.writable else { throw DarwinErrnoError(DarwinErrnoCode.EROFS) }
        let parentHost = r.hostPath.lastIndex(of: "/").map { String(r.hostPath[..<$0]) } ?? "/"
        let parent = try? hostStatCall(parentHost.isEmpty ? "/" : parentHost, follow: true)
        let now = Self.now()
        let st = DarwinStat(dev: parent?.dev ?? 0, mode: DarwinStat.S_IFSOCK | (0o777 & ~umask), nlink: 1,
                            ino: sockets.nextInode, uid: Self.guestUID, gid: Self.guestGID, atime: now, mtime: now,
                            ctime: now, birthtime: now, size: 0, blocks: 0, blksize: 4096)
        sockets.nextInode += 1
        sockets.nodes[r.guestPath] = SocketNamespace.Node(socket: socket, stat: st)
        return r.guestPath
    }

    public enum SocketPathTarget {
        case socket(DarwinDescriptorObject)
        case noSocket
    }

    public func socketTarget(_ path: String) throws -> SocketPathTarget {
        let r = try resolve(path, followFinal: true)
        if let node = sockets.nodes[r.guestPath] {
            if let s = node.socket { return .socket(s) }
            return .noSocket
        }
        guard let st = r.stat else { throw DarwinErrnoError(DarwinErrnoCode.ENOENT) }
        guard st.fileType == DarwinStat.S_IFSOCK else { throw DarwinErrnoError(DarwinErrnoCode.ENOTSOCK) }
        return .noSocket
    }

    public func socketNames(inDirectory guestPath: String) -> [(name: String, stat: DarwinStat)] {
        let dir = normalize(guestPath, cwd: cwdStorage)
        let start = dir == "/" ? "/" : dir + "/"
        return sockets.nodes.compactMap { path, node in
            guard path.hasPrefix(start) else { return nil }
            let name = String(path.dropFirst(start.count))
            return name.contains("/") ? nil : (name, node.stat)
        }.sorted { $0.name < $1.name }
    }

    private static func now() -> DarwinTimespec {
        var ts = timespec()
        clock_gettime(CLOCK_REALTIME, &ts)
        return DarwinTimespec(sec: Int64(ts.tv_sec), nsec: Int64(ts.tv_nsec))
    }
}

public final class DarwinDevice: DarwinDescriptorObject {
    public enum Kind: String, CaseIterable, Sendable {
        case null, zero, random, urandom, console, tty
    }

    public let kind: Kind

    public init(_ kind: Kind) { self.kind = kind }

    public var path: String { "/dev/" + kind.rawValue }

    public var fileType: UInt16 { DarwinStat.S_IFCHR }

    public func lastReferenceClosed() {}

    public func descriptorStat() -> DarwinStat { Self.stat(of: kind) }

    nonisolated(unsafe) public static var entropy: (Int) -> [UInt8] = { count in
        var rng = SystemRandomNumberGenerator()
        var out = [UInt8]()
        out.reserveCapacity(count)
        while out.count < count {
            var v = rng.next()
            for _ in 0..<8 where out.count < count {
                out.append(UInt8(truncatingIfNeeded: v))
                v >>= 8
            }
        }
        return out
    }

    public func read(count: Int) -> [UInt8] {
        guard count > 0 else { return [] }
        switch kind {
        case .zero: return [UInt8](repeating: 0, count: count)
        case .random, .urandom: return Self.entropy(count)
        default: return []
        }
    }

    public func write(_ bytes: [UInt8]) -> Int { bytes.count }

    public static let deviceFileSystemID: UInt32 = 0x0300_0000 | 0x7963
    private static let created: DarwinTimespec = {
        var ts = timespec()
        clock_gettime(CLOCK_REALTIME, &ts)
        return DarwinTimespec(sec: Int64(ts.tv_sec), nsec: 0)
    }()

    public static func stat(of kind: Kind) -> DarwinStat {
        let index = UInt64(Kind.allCases.firstIndex(of: kind)!)
        let rdev: UInt32
        switch kind {
        case .null: rdev = 0x0300_0002
        case .zero: rdev = 0x0300_0003
        case .random: rdev = 0x0E00_0000
        case .urandom: rdev = 0x0E00_0001
        case .console: rdev = 0
        case .tty: rdev = 0x0200_0000
        }
        let console = kind == .console
        return DarwinStat(dev: deviceFileSystemID, mode: DarwinStat.S_IFCHR | (console ? 0o600 : 0o666), nlink: 1,
                          ino: 300 + index, uid: console ? DarwinFileSystem.guestUID : 0, gid: 0, rdev: rdev,
                          atime: created, mtime: created, ctime: created, birthtime: created, size: 0, blocks: 0,
                          blksize: 131_072)
    }
}

public struct DescriptorGuard: Equatable, Sendable {
    public var value: UInt64
    public var flags: UInt32

    public init(value: UInt64, flags: UInt32) {
        self.value = value
        self.flags = flags
    }
}

public enum DarwinGuard {
    public static let close: UInt32 = 1 << 0
    public static let dup: UInt32 = 1 << 1
    public static let socketIPC: UInt32 = 1 << 2
    public static let fileport: UInt32 = 1 << 3
    public static let write: UInt32 = 1 << 4
    public static let required: UInt32 = dup
    public static let all: UInt32 = close | dup | socketIPC | fileport | write
    public static let exceptionClose: UInt32 = 1, exceptionDup: UInt32 = 2, exceptionNoCloexec: UInt32 = 4,
                      exceptionSocketIPC: UInt32 = 8, exceptionFileport: UInt32 = 16, exceptionMismatch: UInt32 = 32,
                      exceptionWrite: UInt32 = 64

    public static func isValid(_ flags: UInt32) -> Bool { flags & required == required && flags & ~all == 0 }
}

extension DarwinFileSystem {
    public func guardState(of fd: Int32) throws -> DescriptorGuard? { try entry(fd).guardState }

    public func guardFlags(_ fd: Int32) -> UInt32? {
        tableLock.withLock { descriptors[fd]?.guardState?.flags }
    }

    public func checkGuard(_ fd: Int32, _ flags: UInt32, flavor: UInt32) throws {
        guard let g = tableLock.withLock({ descriptors[fd]?.guardState }), g.flags & flags == flags else { return }
        guardViolation?(fd, flavor, g.value)
        throw DarwinErrnoError(DarwinErrnoCode.EPERM)
    }

    public func openGuarded(_ path: String, flags: Int32, mode: UInt16, guard value: UInt64,
                            guardFlags: UInt32) throws -> Int32 {
        guard flags & DarwinOpen.O_CLOEXEC != 0, DarwinGuard.isValid(guardFlags), value != 0 else {
            throw DarwinErrnoError(DarwinErrnoCode.EINVAL)
        }
        let (file, closeOnExec) = try makeOpenFile(path, flags: flags, mode: mode)
        return try tableLock.withLock {
            let fd = try lowestFreeDescriptor()
            descriptors[fd] = Descriptor(file: file, closeOnExec: closeOnExec,
                                         closeOnFork: flags & DarwinOpen.O_CLOFORK != 0)
            descriptors[fd]?.guardState = DescriptorGuard(value: value, flags: guardFlags)
            descriptors[fd]?.closeOnExec = true
            return fd
        }
    }

    public func setGuard(_ fd: Int32, _ g: DescriptorGuard) throws {
        guard DarwinGuard.isValid(g.flags), g.value != 0 else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
        try tableLock.withLock {
            _ = try entry(fd)
            descriptors[fd]?.guardState = g
            descriptors[fd]?.closeOnExec = true
        }
    }

    public func guardedClose(_ fd: Int32, guard value: UInt64) throws {
        try changingTable { closed in
            guard let g = try entry(fd).guardState else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
            guard g.value == value else { throw DarwinErrnoError(DarwinErrnoCode.EPERM) }
            remove(fd, into: &closed)
        }
    }

    public func checkGuardValue(_ fd: Int32, _ value: UInt64) throws {
        guard let g = try entry(fd).guardState else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
        guard g.value == value else { throw DarwinErrnoError(DarwinErrnoCode.EPERM) }
    }

    public func changeGuard(_ fd: Int32, old: UInt64?, oldFlags: UInt32, new: UInt64?, newFlags: UInt32,
                            fdFlags: Int32) throws {
        try tableLock.withLock { try changeGuardLocked(fd, old: old, oldFlags: oldFlags, new: new, newFlags: newFlags, fdFlags: fdFlags) }
    }

    private func changeGuardLocked(_ fd: Int32, old: UInt64?, oldFlags: UInt32, new: UInt64?, newFlags: UInt32,
                                   fdFlags: Int32) throws {
        let d = try entry(fd)
        if let g = d.guardState {
            guard old != nil, oldFlags != 0 else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
            guard old != 0 else { throw DarwinErrnoError(DarwinErrnoCode.EPERM) }
            if let new {
                guard new != 0, DarwinGuard.isValid(newFlags) else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
                guard old == g.value, oldFlags == g.flags else { throw DarwinErrnoError(DarwinErrnoCode.EPERM) }
                descriptors[fd]?.guardState = DescriptorGuard(value: new, flags: newFlags)
            } else {
                guard newFlags == 0 else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
                guard old == g.value, oldFlags == g.flags else { throw DarwinErrnoError(DarwinErrnoCode.EPERM) }
                descriptors[fd]?.guardState = nil
                descriptors[fd]?.closeOnExec = fdFlags & 1 != 0
            }
        } else {
            guard old == nil, oldFlags == 0 else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
            guard let new else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
            guard new != 0, DarwinGuard.isValid(newFlags) else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
            descriptors[fd]?.guardState = DescriptorGuard(value: new, flags: newFlags)
            descriptors[fd]?.closeOnExec = true
        }
    }
}

extension DarwinFileSystem {
    public static let renameSeclude: UInt32 = 0x1, renameSwap: UInt32 = 0x2, renameExclusive: UInt32 = 0x4,
                      renameNoFollowAny: UInt32 = 0x10

    public func rename(_ from: String, to: String, flags: UInt32 = 0) throws {
        _ = try rename(from, to: to, flags: flags, socketsToo: true)
    }

    private func rename(_ from: String, to: String, flags: UInt32, socketsToo: Bool) throws -> Bool {
        let known = Self.renameSeclude | Self.renameSwap | Self.renameExclusive | Self.renameNoFollowAny
        guard flags & ~known == 0, flags & (Self.renameSwap | Self.renameExclusive) != Self.renameSwap | Self.renameExclusive
        else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
        let noFollowAny = flags & Self.renameNoFollowAny != 0
        let a = try resolve(from, followFinal: false, noFollowAny: noFollowAny)
        let b = try resolve(to, followFinal: false, noFollowAny: noFollowAny)
        if a.device != nil || b.device != nil { throw DarwinErrnoError(18) }
        if let node = sockets.nodes[a.guestPath] {
            guard socketsToo else { return false }
            if flags & Self.renameExclusive != 0, b.stat != nil || sockets.nodes[b.guestPath] != nil {
                throw DarwinErrnoError(DarwinErrnoCode.EEXIST)
            }
            sockets.nodes[a.guestPath] = nil
            sockets.nodes[b.guestPath] = node
            return true
        }
        guard a.stat != nil else { throw DarwinErrnoError(DarwinErrnoCode.ENOENT) }
        guard a.prefix.writable, b.prefix.writable, !a.hostPath.isEmpty, !b.hostPath.isEmpty else {
            throw DarwinErrnoError(DarwinErrnoCode.EROFS)
        }
        if flags & Self.renameExclusive != 0, b.stat != nil { throw DarwinErrnoError(DarwinErrnoCode.EEXIST) }
        let item = FileChange.item(a.stat)
        let watchedA = VnodeNotes.capture(a.hostPath), watchedB = VnodeNotes.capture(b.hostPath)
        if flags & Self.renameSwap != 0 {
            guard b.stat != nil else { throw DarwinErrnoError(DarwinErrnoCode.ENOENT) }
            if try !hostRenameAtomically(a.hostPath, b.hostPath, swap: true) {
                let temporary = a.hostPath + ".swiftcode-swap-\(UInt32.random(in: 0...UInt32.max))"
                try hostRename(a.hostPath, temporary)
                do { try hostRename(b.hostPath, a.hostPath) } catch { try? hostRename(temporary, a.hostPath); throw error }
                try hostRename(temporary, b.hostPath)
            }
            FileChangeFeed.note(.renamed, item, a.guestPath, pid: ownerPID)
            FileChangeFeed.note(.renamed, FileChange.item(b.stat), b.guestPath, pid: ownerPID)
            postRenameNotes(watchedA, watchedB, sourceIsDirectory: a.stat?.isDirectory ?? false, replaced: false,
                            swapped: b.stat?.isDirectory ?? false)
            return true
        }
        let source = VolumeMetadata.read(hostPath: a.hostPath)
        if flags & Self.renameExclusive != 0 {
            if try !hostRenameAtomically(a.hostPath, b.hostPath, swap: false) {
                try hostRename(a.hostPath, b.hostPath)
            }
        } else {
            let target = b.stat != nil ? VolumeMetadata.read(hostPath: b.hostPath) : VolumeMetadata.Record()
            if target.documentID != 0, source.documentID == 0, a.hostPath != b.hostPath {
                var inherited = source
                inherited.flags |= VolumeMetadata.ufTracked
                inherited.documentID = target.documentID
                try? VolumeMetadata.write(inherited, hostPath: a.hostPath)
            }
            try hostRename(a.hostPath, b.hostPath)
        }
        if b.stat == nil {
            if source.documentID != 0 {
                leaveTombstone(guestPath: a.guestPath, source)
            } else {
                inheritTombstone(guestPath: b.guestPath, hostPath: b.hostPath)
            }
        }
        FileChangeFeed.note(.renamed, item, a.guestPath, pid: ownerPID)
        FileChangeFeed.note(.renamed, item, b.guestPath, pid: ownerPID)
        if a.hostPath != b.hostPath {
            postRenameNotes(watchedA, watchedB, sourceIsDirectory: a.stat?.isDirectory ?? false, replaced: b.stat != nil,
                            swapped: nil)
        }
        return true
    }

    private func postRenameNotes(_ a: VnodeNotes.Captured?, _ b: VnodeNotes.Captured?, sourceIsDirectory: Bool,
                                 replaced: Bool, swapped: Bool?) {
        guard let a, let b else { return }
        let sameDirectory = a.directory == b.directory
        var events = VnodeNote.write
        if let targetIsDirectory = swapped {
            if !sameDirectory, sourceIsDirectory != targetIsDirectory { events |= VnodeNote.link }
        } else if sourceIsDirectory, (!sameDirectory && !replaced) || (sameDirectory && replaced) {
            events |= VnodeNote.link
        }
        VnodeNotes.post(a.directory, events)
        if !sameDirectory { VnodeNotes.post(b.directory, events) }
        if swapped != nil {
            VnodeNotes.post(a.object, VnodeNote.rename)
            VnodeNotes.post(b.object, VnodeNote.rename)
            return
        }
        if replaced, b.object != a.object { VnodeNotes.post(b.object, VnodeNote.delete) }
        VnodeNotes.post(a.object, VnodeNote.rename)
    }

    public func chmod(_ path: String, mode: UInt16, followSymlinks: Bool) throws {
        let r = try resolve(path, followFinal: followSymlinks)
        guard let st = r.stat else { throw DarwinErrnoError(DarwinErrnoCode.ENOENT) }
        guard r.prefix.writable, !r.hostPath.isEmpty else { throw DarwinErrnoError(DarwinErrnoCode.EROFS) }
        if st.isSymbolicLink { return }
        guard hostChmod(r.hostPath, mode & 0o7777) == 0 else { throw DarwinErrnoError(hostErrno()) }
        FileChangeFeed.note(.owner, FileChange.item(st), r.guestPath, pid: ownerPID)
        VnodeNotes.capture(r.hostPath)?.post(object: VnodeNote.attrib)
    }

    public func fchmod(_ fd: Int32, mode: UInt16) throws {
        guard case let .file(f) = try entry(fd).file.node else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
        guard writable(guestPath: f.guestPath) else { throw DarwinErrnoError(DarwinErrnoCode.EROFS) }
        guard hostFchmod(f.hostFD, mode & 0o7777) == 0 else { throw DarwinErrnoError(hostErrno()) }
        FileChangeFeed.note(.owner, FileChange.item(f.stat), f.guestPath, pid: ownerPID)
        if VnodeNotes.isActive { VnodeNotes.post(f.hostKey, VnodeNote.attrib) }
    }

    public func chown(_ path: String, uid: UInt32, gid: UInt32, followSymlinks: Bool) throws {
        let r = try resolve(path, followFinal: followSymlinks)
        guard let st = r.stat else { throw DarwinErrnoError(DarwinErrnoCode.ENOENT) }
        try checkOwnerChange(st, uid: uid, gid: gid)
        guard r.prefix.writable else { throw DarwinErrnoError(DarwinErrnoCode.EROFS) }
        FileChangeFeed.note(.owner, FileChange.item(st), r.guestPath, pid: ownerPID)
        VnodeNotes.capture(r.hostPath)?.post(object: VnodeNote.attrib)
    }

    public func fchown(_ fd: Int32, uid: UInt32, gid: UInt32) throws {
        let st = try fstat(fd)
        try checkOwnerChange(st, uid: uid, gid: gid)
    }

    private func checkOwnerChange(_ st: DarwinStat, uid: UInt32, gid: UInt32) throws {
        let keep = UInt32.max
        guard uid == keep || uid == st.uid else { throw DarwinErrnoError(DarwinErrnoCode.EPERM) }
        guard gid == keep || gid == st.gid || gid == Self.guestGID else { throw DarwinErrnoError(DarwinErrnoCode.EPERM) }
    }

    public func setTimes(_ path: String, access: DarwinTimespec?, modification: DarwinTimespec?, followSymlinks: Bool) throws {
        let r = try resolve(path, followFinal: followSymlinks)
        guard r.stat != nil else { throw DarwinErrnoError(DarwinErrnoCode.ENOENT) }
        guard r.prefix.writable, !r.hostPath.isEmpty else { throw DarwinErrnoError(DarwinErrnoCode.EROFS) }
        guard hostSetTimes(path: r.hostPath, fd: nil, access, modification, follow: followSymlinks) == 0 else {
            throw DarwinErrnoError(hostErrno())
        }
        FileChangeFeed.note(.inodeMetadata, FileChange.item(r.stat), r.guestPath, pid: ownerPID)
        VnodeNotes.capture(r.hostPath)?.post(object: VnodeNote.attrib)
    }

    public func setTimes(_ fd: Int32, access: DarwinTimespec?, modification: DarwinTimespec?) throws {
        guard case let .file(f) = try entry(fd).file.node else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
        guard writable(guestPath: f.guestPath) else { throw DarwinErrnoError(DarwinErrnoCode.EROFS) }
        guard hostSetTimes(path: nil, fd: f.hostFD, access, modification, follow: true) == 0 else {
            throw DarwinErrnoError(hostErrno())
        }
        FileChangeFeed.note(.inodeMetadata, FileChange.item(f.stat), f.guestPath, pid: ownerPID)
        if VnodeNotes.isActive { VnodeNotes.post(f.hostKey, VnodeNote.attrib) }
    }

    public func truncate(_ path: String, length: Int64) throws {
        guard length >= 0 else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
        let r = try resolve(path, followFinal: true)
        guard let st = r.stat else { throw DarwinErrnoError(DarwinErrnoCode.ENOENT) }
        if st.isDirectory { throw DarwinErrnoError(DarwinErrnoCode.EISDIR) }
        guard r.prefix.writable, !r.hostPath.isEmpty else { throw DarwinErrnoError(DarwinErrnoCode.EROFS) }
        let watched = VnodeNotes.capture(r.hostPath)
        guard hostTruncate(r.hostPath, length) == 0 else { throw DarwinErrnoError(hostErrno()) }
        WriteGenerations.noteWrite(dev: st.dev, ino: st.ino)
        FileChangeFeed.note(.modified, .file, r.guestPath, pid: ownerPID)
        watched?.post(object: VnodeNotes.sizeNotes(from: st.size, to: length))
        if SharedFileViews.count > 0, let fd = try? hostOpen(r.hostPath, O_RDONLY | O_CLOEXEC | O_NOFOLLOW, 0) {
            SharedFileViews.sizeMayHaveChanged(hostFD: fd)
            hostClose(fd)
        }
    }

    public func writable(guestPath: String) -> Bool { lookupPrefix(guestPath)?.prefix.writable ?? false }
}

func hostRename(_ from: String, _ to: String) throws {
    guard rename(from, to) == 0 else { throw DarwinErrnoError(hostErrno()) }
}

private func hostChmod(_ path: String, _ mode: UInt16) -> Int32 { chmod(path, mode_t(mode)) }
private func hostFchmod(_ fd: Int32, _ mode: UInt16) -> Int32 { fchmod(fd, mode_t(mode)) }
private func hostTruncate(_ path: String, _ length: Int64) -> Int32 { truncate(path, off_t(length)) }

func hostSetTimes(path: String?, fd: Int32?, _ access: DarwinTimespec?, _ modification: DarwinTimespec?,
                  follow: Bool) -> Int32 {
    func spec(_ t: DarwinTimespec?) -> timespec {
        #if canImport(Darwin)
        let now = -1
        #else
        let now = (1 << 30) - 1
        #endif
        guard let t else { return timespec(tv_sec: 0, tv_nsec: now) }
        return timespec(tv_sec: Int(t.sec), tv_nsec: Int(t.nsec))
    }
    var times = [spec(access), spec(modification)]
    if let fd { return futimens(fd, &times) }
    #if canImport(Darwin)
    let cwd: Int32 = -2, noFollow: Int32 = 0x20
    #else
    let cwd: Int32 = -100, noFollow: Int32 = 0x100
    #endif
    return utimensat(cwd, path!, &times, follow ? 0 : noFollow)
}

#if !canImport(Darwin)
enum LinuxXattr {
    typealias Get = @convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>, UnsafeMutableRawPointer?, Int) -> Int
    typealias FGet = @convention(c) (Int32, UnsafePointer<CChar>, UnsafeMutableRawPointer?, Int) -> Int
    typealias Set = @convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>, UnsafeRawPointer?, Int, Int32) -> Int32
    typealias FSet = @convention(c) (Int32, UnsafePointer<CChar>, UnsafeRawPointer?, Int, Int32) -> Int32
    typealias Remove = @convention(c) (UnsafePointer<CChar>, UnsafePointer<CChar>) -> Int32
    typealias FRemove = @convention(c) (Int32, UnsafePointer<CChar>) -> Int32
    typealias List = @convention(c) (UnsafePointer<CChar>, UnsafeMutablePointer<CChar>?, Int) -> Int
    typealias FList = @convention(c) (Int32, UnsafeMutablePointer<CChar>?, Int) -> Int

    static func symbol<T>(_ name: String, _: T.Type) -> T {
        guard let p = dlsym(UnsafeMutableRawPointer(bitPattern: 0), name) else { fatalError("libc lacks \(name)") }
        return unsafeBitCast(p, to: T.self)
    }
    static let lget = symbol("lgetxattr", Get.self), fget = symbol("fgetxattr", FGet.self)
    static let lset = symbol("lsetxattr", Set.self), fset = symbol("fsetxattr", FSet.self)
    static let lremove = symbol("lremovexattr", Remove.self), fremove = symbol("fremovexattr", FRemove.self)
    static let llist = symbol("llistxattr", List.self), flist = symbol("flistxattr", FList.self)
}
#endif

extension DarwinFileSystem {
    public enum XattrTarget {
        case path(String, followSymlinks: Bool)
        case descriptor(Int32)
    }

    static let xattrPrefix = "user.swiftcode."
    static let ENOATTR: Int32 = 93

    func xattrHost(_ t: XattrTarget) throws -> (path: String?, fd: Int32?, writable: Bool, guestPath: String, item: FileChange.Item) {
        switch t {
        case let .path(path, follow):
            let r = try resolve(path, followFinal: follow)
            guard r.stat != nil else { throw DarwinErrnoError(DarwinErrnoCode.ENOENT) }
            return (r.hostPath.isEmpty ? nil : r.hostPath, nil, r.prefix.writable && !r.hostPath.isEmpty, r.guestPath,
                    FileChange.item(r.stat))
        case let .descriptor(fd):
            let d = try entry(fd)
            guard case let .file(f) = d.file.node else { return (nil, nil, false, "", .other) }
            return (nil, f.hostFD, writable(guestPath: f.guestPath), f.guestPath, FileChange.item(f.stat))
        }
    }

    private static func checkName(_ name: String) throws {
        guard !name.isEmpty else { throw DarwinErrnoError(DarwinErrnoCode.EINVAL) }
        guard name.utf8.count <= 127 else { throw DarwinErrnoError(DarwinErrnoCode.ENAMETOOLONG) }
    }

    private static func xattrErrno() -> Int32 {
        #if canImport(Darwin)
        return errno == 93 ? ENOATTR : DarwinErrnoCode.fromHost(errno)
        #else
        return errno == 61 ? ENOATTR : (errno == 95 ? DarwinErrnoCode.ENOTSUP : DarwinErrnoCode.fromHost(errno))
        #endif
    }

    public func getExtendedAttribute(_ t: XattrTarget, name: String) throws -> [UInt8] {
        try Self.checkName(name)
        let host = try xattrHost(t)
        guard host.path != nil || host.fd != nil else { throw DarwinErrnoError(Self.ENOATTR) }
        let key = Self.xattrPrefix + name
        func call(_ buffer: UnsafeMutableRawPointer?, _ size: Int) -> Int {
            #if canImport(Darwin)
            if let fd = host.fd { return fgetxattr(fd, key, buffer, size, 0, 0) }
            return getxattr(host.path!, key, buffer, size, 0, XATTR_NOFOLLOW)
            #else
            if let fd = host.fd { return LinuxXattr.fget(fd, key, buffer, size) }
            return LinuxXattr.lget(host.path!, key, buffer, size)
            #endif
        }
        for _ in 0..<4 {
            let size = call(nil, 0)
            guard size >= 0 else { throw DarwinErrnoError(Self.xattrErrno()) }
            var bytes = [UInt8](repeating: 0, count: size)
            let n = bytes.withUnsafeMutableBytes { call($0.baseAddress, size) }
            if n >= 0 { return Array(bytes.prefix(n)) }
            guard errno == ERANGE else { throw DarwinErrnoError(Self.xattrErrno()) }
        }
        throw DarwinErrnoError(DarwinErrnoCode.EIO)
    }

    public func setExtendedAttribute(_ t: XattrTarget, name: String, value: [UInt8], create: Bool, replace: Bool) throws {
        try Self.checkName(name)
        let host = try xattrHost(t)
        guard host.writable, host.path != nil || host.fd != nil else { throw DarwinErrnoError(DarwinErrnoCode.EROFS) }
        let key = Self.xattrPrefix + name
        let r: Int32 = value.withUnsafeBytes { v in
            #if canImport(Darwin)
            let flags: Int32 = (create ? XATTR_CREATE : 0) | (replace ? XATTR_REPLACE : 0)
            if let fd = host.fd { return fsetxattr(fd, key, v.baseAddress, v.count, 0, flags) }
            return setxattr(host.path!, key, v.baseAddress, v.count, 0, flags | XATTR_NOFOLLOW)
            #else
            let flags: Int32 = (create ? 1 : 0) | (replace ? 2 : 0)
            if let fd = host.fd { return LinuxXattr.fset(fd, key, v.baseAddress, v.count, flags) }
            return LinuxXattr.lset(host.path!, key, v.baseAddress, v.count, flags)
            #endif
        }
        guard r == 0 else { throw DarwinErrnoError(Self.xattrErrno()) }
        FileChangeFeed.note(.extendedAttribute, host.item, host.guestPath, pid: ownerPID)
        VnodeNotes.postAttrib(path: host.path, fd: host.fd)
    }

    public func removeExtendedAttribute(_ t: XattrTarget, name: String) throws {
        try Self.checkName(name)
        let host = try xattrHost(t)
        guard host.path != nil || host.fd != nil else { throw DarwinErrnoError(Self.ENOATTR) }
        guard host.writable else { throw DarwinErrnoError(DarwinErrnoCode.EROFS) }
        let key = Self.xattrPrefix + name
        #if canImport(Darwin)
        let r = host.fd.map { fremovexattr($0, key, 0) } ?? removexattr(host.path!, key, XATTR_NOFOLLOW)
        #else
        let r = host.fd.map { LinuxXattr.fremove($0, key) } ?? LinuxXattr.lremove(host.path!, key)
        #endif
        guard r == 0 else { throw DarwinErrnoError(Self.xattrErrno()) }
        FileChangeFeed.note(.extendedAttribute, host.item, host.guestPath, pid: ownerPID)
        VnodeNotes.postAttrib(path: host.path, fd: host.fd)
    }

    public func listExtendedAttributes(_ t: XattrTarget) throws -> [String] {
        let host = try xattrHost(t)
        guard host.path != nil || host.fd != nil else { return [] }
        func call(_ buffer: UnsafeMutablePointer<CChar>?, _ size: Int) -> Int {
            #if canImport(Darwin)
            if let fd = host.fd { return flistxattr(fd, buffer, size, 0) }
            return listxattr(host.path!, buffer, size, XATTR_NOFOLLOW)
            #else
            if let fd = host.fd { return LinuxXattr.flist(fd, buffer, size) }
            return LinuxXattr.llist(host.path!, buffer, size)
            #endif
        }
        for _ in 0..<4 {
            let size = call(nil, 0)
            guard size >= 0 else {
                if errno == ENOTSUP || errno == EPERM { return [] }
                throw DarwinErrnoError(Self.xattrErrno())
            }
            if size == 0 { return [] }
            var buffer = [CChar](repeating: 0, count: size)
            let n = buffer.withUnsafeMutableBufferPointer { call($0.baseAddress, size) }
            if n < 0 {
                guard errno == ERANGE else { throw DarwinErrnoError(Self.xattrErrno()) }
                continue
            }
            let bytes = buffer.prefix(n).map { UInt8(bitPattern: $0) }
            return bytes.split(separator: 0).map { String(decoding: $0, as: UTF8.self) }
                .filter { $0.hasPrefix(Self.xattrPrefix) }.map { String($0.dropFirst(Self.xattrPrefix.count)) }
        }
        throw DarwinErrnoError(DarwinErrnoCode.EIO)
    }
}

public enum GuestPath {
    public static func lastComponent(_ path: String) -> String {
        var s = Substring(path)
        while s.count > 1, s.hasSuffix("/") { s.removeLast() }
        if s == "/" { return "/" }
        if let slash = s.lastIndex(of: "/") { return String(s[s.index(after: slash)...]) }
        return String(s)
    }

    public static func deletingLastComponent(_ path: String) -> String {
        var s = Substring(path)
        while s.count > 1, s.hasSuffix("/") { s.removeLast() }
        guard let slash = s.lastIndex(of: "/") else { return "" }
        if slash == s.startIndex { return "/" }
        var parent = s[..<slash]
        while parent.count > 1, parent.hasSuffix("/") { parent.removeLast() }
        return String(parent)
    }

    public static func hostDirectoryNames(_ hostPath: String) -> [String]? {
        guard let dir = opendir(hostPath) else { return nil }
        defer { closedir(dir) }
        var names: [String] = []
        while let entry = readdir(dir) {
            let name = withUnsafeBytes(of: entry.pointee.d_name) { raw -> String in
                let bytes = raw.bindMemory(to: UInt8.self)
                let n = bytes.firstIndex(of: 0) ?? bytes.count
                return String(decoding: bytes[..<n], as: UTF8.self)
            }
            if name != "." && name != ".." { names.append(name) }
        }
        return names
    }
}

final class OffsetLock: @unchecked Sendable {
    private let mutex: UnsafeMutablePointer<pthread_mutex_t>

    init() {
        mutex = .allocate(capacity: 1)
        mutex.initialize(to: pthread_mutex_t())
        pthread_mutex_init(mutex, nil)
    }

    deinit {
        pthread_mutex_destroy(mutex)
        mutex.deallocate()
    }

    func lock() { pthread_mutex_lock(mutex) }
    func tryLock() -> Bool { pthread_mutex_trylock(mutex) == 0 }
    func unlock() { pthread_mutex_unlock(mutex) }

    @inline(__always)
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return try body()
    }
}

public struct HostFileIO: @unchecked Sendable {
    public let description: DarwinOpenFile
    let file: GuestFile
    let append: Bool
    let pid: Int32

    init(description: DarwinOpenFile, file: GuestFile, pid: Int32 = 0) {
        self.description = description
        self.file = file
        self.pid = pid
        append = description.statusFlags & DarwinOpen.O_APPEND != 0
    }

    public func read(count: Int) throws -> [UInt8] {
        try description.ioLock.withLock {
            let bytes = try hostPRead(file.hostFD, count: min(count, DarwinFileSystem.maxTransfer),
                                      offset: description.storedOffset)
            description.storedOffset += UInt64(bytes.count)
            return bytes
        }
    }

    public func pread(count: Int, offset: UInt64) throws -> [UInt8] {
        try hostPRead(file.hostFD, count: min(count, DarwinFileSystem.maxTransfer), offset: offset)
    }

    public func readIfCached(count: Int) -> [UInt8]? {
        guard description.ioLock.tryLock() else { return nil }
        defer { description.ioLock.unlock() }
        guard let bytes = cachedRead(count: count, offset: description.storedOffset) else { return nil }
        description.storedOffset += UInt64(bytes.count)
        return bytes
    }

    public func preadIfCached(count: Int, offset: UInt64) -> [UInt8]? {
        cachedRead(count: count, offset: offset)
    }

    public func write(_ bytes: [UInt8]) throws -> Int {
        let watch = file.vnodeWriteWatch()
        let (n, offset) = try description.ioLock.withLock { () throws -> (Int, UInt64) in
            if append { description.storedOffset = UInt64(max(0, try hostFStat(file.hostFD).size)) }
            let at = description.storedOffset
            let n = try hostPWrite(file.hostFD, bytes, offset: at)
            description.storedOffset += UInt64(n)
            file.noteWritten(pid: pid)
            return (n, at)
        }
        if let watch { VnodeNotes.post(watch.key, VnodeNotes.writeNotes(offset: offset, count: n, sizeBefore: watch.size)) }
        return n
    }

    public func pwrite(_ bytes: [UInt8], offset: UInt64) throws -> Int {
        let watch = file.vnodeWriteWatch()
        let n = try hostPWrite(file.hostFD, bytes, offset: offset)
        file.noteWritten(pid: pid)
        if let watch { VnodeNotes.post(watch.key, VnodeNotes.writeNotes(offset: offset, count: n, sizeBefore: watch.size)) }
        return n
    }

    private func cachedRead(count: Int, offset: UInt64) -> [UInt8]? {
        #if os(Linux)
        guard let preadv2 = HostFileIO.preadv2, offset <= UInt64(Int64.max) else { return nil }
        let want = min(max(count, 0), DarwinFileSystem.maxTransfer)
        if want == 0 { return [] }
        var buffer = [UInt8](repeating: 0, count: want)
        var failure: Int32 = 0
        let n = buffer.withUnsafeMutableBytes { raw -> Int in
            var iov = iovec(iov_base: raw.baseAddress, iov_len: raw.count)
            let r = preadv2(file.hostFD, &iov, 1, off_t(offset), HostFileIO.rwfNoWait)
            if r < 0 { failure = errno }
            return r
        }
        guard n >= 0 else {
            guard failure == EOPNOTSUPP, file.isMemoryBacked else { return nil }
            return try? hostPRead(file.hostFD, count: want, offset: offset)
        }
        if n < want {
            guard let size = try? hostFStat(file.hostFD).size, UInt64(max(0, size)) <= offset + UInt64(n) else { return nil }
        }
        buffer.removeSubrange(n...)
        return buffer
        #else
        return nil
        #endif
    }

    #if os(Linux)
    static let rwfNoWait: Int32 = 0x8
    typealias PReadV2 = @convention(c) (Int32, UnsafePointer<iovec>?, Int32, off_t, Int32) -> Int
    typealias FStatFS = @convention(c) (Int32, UnsafeMutableRawPointer?) -> Int32
    static let fstatfs: FStatFS? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: 0), "fstatfs") else { return nil }
        return unsafeBitCast(symbol, to: FStatFS.self)
    }()

    static func fileSystemType(_ fd: Int32) -> Int? {
        guard let fstatfs else { return nil }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: 256, alignment: 8)
        defer { buffer.deallocate() }
        guard fstatfs(fd, buffer) == 0 else { return nil }
        return buffer.load(as: Int.self)
    }

    static let preadv2: PReadV2? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: 0), "preadv2") else { return nil }
        return unsafeBitCast(symbol, to: PReadV2.self)
    }()
    #endif
}

extension DarwinFileSystem {
    public func hostFileIO(_ fd: Int32, writing: Bool, guardChecked: Bool = false) throws -> HostFileIO? {
        if writing, !guardChecked { try checkGuard(fd, DarwinGuard.write, flavor: DarwinGuard.exceptionWrite) }
        let d = try entry(fd)
        guard case let .file(f) = d.file.node else { return nil }
        if writing {
            guard d.file.isWritable else { throw DarwinErrnoError(DarwinErrnoCode.EBADF) }
        } else {
            guard d.file.isReadable else { throw DarwinErrnoError(DarwinErrnoCode.EBADF) }
            if f.isDirectory { throw DarwinErrnoError(DarwinErrnoCode.EISDIR) }
        }
        return HostFileIO(description: d.file, file: f, pid: ownerPID)
    }

    public func renameHostFiles(_ from: String, to: String, flags: UInt32 = 0) throws -> Bool {
        try rename(from, to: to, flags: flags, socketsToo: false)
    }
}
