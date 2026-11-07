#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif
import Synchronization

public enum VnodeNote {
    public static let delete: UInt32 = 0x0000_0001
    public static let write: UInt32 = 0x0000_0002
    public static let extend: UInt32 = 0x0000_0004
    public static let attrib: UInt32 = 0x0000_0008
    public static let link: UInt32 = 0x0000_0010
    public static let rename: UInt32 = 0x0000_0020
    public static let revoke: UInt32 = 0x0000_0040
    public static let none: UInt32 = 0x0000_0080
    public static let funlock: UInt32 = 0x0000_0100
    public static let leaseDowngrade: UInt32 = 0x0000_0200
    public static let leaseRelease: UInt32 = 0x0000_0400
}

public struct HostFileKey: Hashable, Sendable, CustomStringConvertible {
    public let dev: UInt64
    public let ino: UInt64

    public init(dev: UInt64, ino: UInt64) {
        self.dev = dev
        self.ino = ino
    }

    public init?(path hostPath: String) {
        guard !hostPath.isEmpty else { return nil }
        #if canImport(Darwin)
        var st = Darwin.stat()
        #elseif canImport(Glibc)
        var st = Glibc.stat()
        #else
        var st = Musl.stat()
        #endif
        guard lstat(hostPath, &st) == 0 else { return nil }
        self.init(dev: UInt64(truncatingIfNeeded: st.st_dev), ino: UInt64(truncatingIfNeeded: st.st_ino))
    }

    public init?(fd: Int32) {
        #if canImport(Darwin)
        var st = Darwin.stat()
        #elseif canImport(Glibc)
        var st = Glibc.stat()
        #else
        var st = Musl.stat()
        #endif
        guard fstat(fd, &st) == 0 else { return nil }
        self.init(dev: UInt64(truncatingIfNeeded: st.st_dev), ino: UInt64(truncatingIfNeeded: st.st_ino))
    }

    public init?(parentOf hostPath: String) {
        guard let slash = hostPath.lastIndex(of: "/") else { return nil }
        let parent = slash == hostPath.startIndex ? "/" : String(hostPath[..<slash])
        self.init(path: parent)
    }

    public var description: String { "\(dev):\(ino)" }
}

public protocol VnodeWatcher: AnyObject, Sendable {
    func vnodeNotesPosted(_ notes: UInt32)
}

public enum VnodeNotes {
    private struct Entry {
        weak var watcher: (any VnodeWatcher)?
    }

    private static let table = Mutex<[HostFileKey: [Entry]]>([:])
    private static let watchCount = Atomic<Int>(0)

    @inline(__always) public static var isActive: Bool { watchCount.load(ordering: .acquiring) > 0 }

    public static var count: Int { watchCount.load(ordering: .acquiring) }

    public static func add(_ watcher: any VnodeWatcher, key: HostFileKey) {
        table.withLock { t in
            t[key, default: []].append(Entry(watcher: watcher))
            watchCount.wrappingAdd(1, ordering: .releasing)
        }
    }

    public static func remove(_ watcher: any VnodeWatcher, key: HostFileKey) {
        table.withLock { t in
            guard var list = t[key] else { return }
            let before = list.count
            list.removeAll { $0.watcher == nil || $0.watcher === watcher }
            watchCount.wrappingSubtract(before - list.count, ordering: .releasing)
            t[key] = list.isEmpty ? nil : list
        }
    }

    public static func isWatched(_ key: HostFileKey) -> Bool {
        guard isActive else { return false }
        return table.withLock { $0[key] != nil }
    }

    public static func post(_ key: HostFileKey?, _ notes: UInt32) {
        guard let key, notes != 0, isActive else { return }
        let watchers: [any VnodeWatcher] = table.withLock { t in
            guard let list = t[key] else { return [] }
            let live = list.compactMap(\.watcher)
            if live.count != list.count {
                watchCount.wrappingSubtract(list.count - live.count, ordering: .releasing)
                t[key] = live.isEmpty ? nil : live.map { Entry(watcher: $0) }
            }
            return live
        }
        if debugCounts, !watchers.isEmpty { posts.wrappingAdd(1, ordering: .relaxed) }
        for w in watchers { w.vnodeNotesPosted(notes) }
    }

    public static func capture(_ hostPath: String) -> Captured? {
        guard isActive, !hostPath.isEmpty else { return nil }
        if debugCounts { countCapture() }
        return Captured(object: HostFileKey(path: hostPath), directory: HostFileKey(parentOf: hostPath))
    }

    static let debugCounts = getenv("SWIFTCODE_DEBUG_VNODE").map { String(cString: $0) == "1" } ?? false
    private static let captures = Atomic<Int>(0), writeChecks = Atomic<Int>(0), posts = Atomic<Int>(0)
    private static func countCapture() {
        let n = captures.wrappingAdd(1, ordering: .relaxed).newValue
        guard n % 2000 == 0 else { return }
        let line = "swiftcode-vnode: \(n) captures, \(writeChecks.load(ordering: .relaxed)) write checks, "
            + "\(posts.load(ordering: .relaxed)) posts to watchers, \(count) watched\n"
        _ = line.withCString { hostWriteRaw(2, $0, strlen($0)) }
    }
    static func countWriteCheck() { writeChecks.wrappingAdd(1, ordering: .relaxed) }

    public struct Captured: Sendable {
        public var object: HostFileKey?
        public var directory: HostFileKey?

        public func post(object objectNotes: UInt32 = 0, directory directoryNotes: UInt32 = 0) {
            VnodeNotes.post(object, objectNotes)
            VnodeNotes.post(directory, directoryNotes)
        }
    }

    public static func postAttrib(path: String?, fd: Int32?) {
        guard isActive else { return }
        post(fd.flatMap { HostFileKey(fd: $0) } ?? path.flatMap { HostFileKey(path: $0) }, VnodeNote.attrib)
    }

    public static func writeNotes(offset: UInt64, count: Int, sizeBefore: Int64) -> UInt32 {
        guard count > 0 else { return 0 }
        let end = offset &+ UInt64(count)
        return VnodeNote.write | (end > UInt64(max(0, sizeBefore)) ? VnodeNote.extend : 0)
    }

    public static func sizeNotes(from old: Int64, to new: Int64) -> UInt32 {
        VnodeNote.attrib | (new > old ? VnodeNote.extend : 0)
    }
}

extension GuestFile {
    public var hostKey: HostFileKey? {
        if let k = hostKeyStore.withLock({ $0 }) { return k }
        let k = HostFileKey(fd: hostFD)
        hostKeyStore.withLock { $0 = k }
        return k
    }

    public func vnodeWriteWatch() -> (key: HostFileKey, size: Int64)? {
        guard VnodeNotes.isActive else { return nil }
        if VnodeNotes.debugCounts { VnodeNotes.countWriteCheck() }
        guard let key = hostKey, VnodeNotes.isWatched(key) else { return nil }
        return (key, (try? hostFStat(hostFD).size) ?? 0)
    }
}

public enum HostDataWrites {
    public static func replace(hostPath: String, guestPath: String, data: [UInt8]) throws {
        try makeDirectories(forHostPath: hostPath, guestPath: guestPath)
        let slash = hostPath.lastIndex(of: "/")!
        let name = hostPath[hostPath.index(after: slash)...]
        let temporary = String(hostPath[..<slash]) + "/.\(name).swiftcode-\(getpid())-\(UInt32.random(in: 0...UInt32.max))"
        let guestTemporary = guestPath.lastIndex(of: "/").map { String(guestPath[..<$0]) + temporary[slash...] }
            ?? temporary
        let old = VnodeNotes.capture(hostPath)
        let fd = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o644)
        guard fd >= 0 else { throw DarwinErrnoError(hostErrno()) }
        var done = 0
        while done < data.count {
            let n = data.withUnsafeBytes { hostWriteRaw(fd, $0.baseAddress! + done, data.count - done) }
            if n < 0 {
                if errno == EINTR { continue }
                let e = hostErrno()
                _ = close(fd)
                _ = unlink(temporary)
                throw DarwinErrnoError(e)
            }
            done += n
        }
        _ = close(fd)
        guard hostRenameRaw(temporary, hostPath) == 0 else {
            let e = hostErrno()
            _ = unlink(temporary)
            throw DarwinErrnoError(e)
        }
        if VnodeNotes.isActive {
            VnodeNotes.post(old?.object, VnodeNote.delete)
            VnodeNotes.post(old?.directory, VnodeNote.write)
            VnodeNotes.post(HostFileKey(path: hostPath), VnodeNote.rename)
        }
        FileChangeFeed.note(.created, .file, guestTemporary, pid: 0)
        FileChangeFeed.note(.modified, .file, guestTemporary, pid: 0)
        FileChangeFeed.note(.renamed, .file, guestTemporary, pid: 0)
        FileChangeFeed.note(.renamed, .file, guestPath, pid: 0)
    }

    public static func remove(hostPath: String, guestPath: String) {
        let old = VnodeNotes.capture(hostPath)
        guard unlink(hostPath) == 0 else { return }
        old?.post(object: VnodeNote.delete | VnodeNote.link, directory: VnodeNote.write)
        FileChangeFeed.note(.removed, .file, guestPath, pid: 0)
    }

    public static func makeDirectories(forHostPath hostPath: String, guestPath: String) throws {
        var missing: [(host: String, guest: String)] = []
        var host = hostPath, guest = guestPath
        while let slash = host.lastIndex(of: "/"), slash != host.startIndex {
            host = String(host[..<slash])
            guest = guest.lastIndex(of: "/").map { String(guest[..<$0]) } ?? guest
            if HostFileKey(path: host) != nil { break }
            missing.append((host, guest))
        }
        for (h, g) in missing.reversed() {
            let parent = VnodeNotes.capture(h)
            if mkdir(h, 0o755) != 0 {
                if errno == EEXIST { continue }
                throw DarwinErrnoError(hostErrno())
            }
            parent?.post(directory: VnodeNote.write | VnodeNote.link)
            FileChangeFeed.note(.created, .directory, g, pid: 0)
        }
    }
}

@inline(__always) private func hostWriteRaw(_ fd: Int32, _ p: UnsafeRawPointer, _ n: Int) -> Int {
    #if canImport(Darwin)
    return Darwin.write(fd, p, n)
    #elseif canImport(Glibc)
    return Glibc.write(fd, p, n)
    #else
    return Musl.write(fd, p, n)
    #endif
}

@inline(__always) private func hostRenameRaw(_ from: String, _ to: String) -> Int32 {
    #if canImport(Darwin)
    return Darwin.rename(from, to)
    #elseif canImport(Glibc)
    return Glibc.rename(from, to)
    #else
    return Musl.rename(from, to)
    #endif
}
