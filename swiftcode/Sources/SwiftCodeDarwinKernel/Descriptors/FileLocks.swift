import Foundation
import Synchronization
import SwiftCodeDarwinABI

struct FileIdentity: Hashable {
    let dev: UInt32
    let ino: UInt64
    init(_ stat: DarwinStat) {
        dev = stat.dev
        ino = stat.ino
    }
}

final class FileLockTable: @unchecked Sendable {
    enum Owner: Hashable {
        case process(Int32)
        case description(ObjectIdentifier)
    }

    enum Kind { case posix, ofd, flock }

    struct Lock: Equatable {
        var owner: Owner
        var kind: Kind
        var exclusive: Bool
        var start: Int64
        var end: Int64

        func overlaps(_ s: Int64, _ e: Int64) -> Bool { start <= e && s <= end }
    }

    final class FileState {
        var locks: [Lock] = []
        var waiting = 0
        let waiters = WaitQueue()
    }

    let tableLock = DescriptorTableLock(name: "file locks")
    nonisolated(unsafe) private var storage: [FileIdentity: FileState] = [:]
    nonisolated(unsafe) private var blockedOnStorage: [Int32: Owner] = [:]
    nonisolated(unsafe) private var watchedStorage: Set<ObjectIdentifier> = []

    var files: [FileIdentity: FileState] { tableLock.withLock { storage } }
    var blockedOn: [Int32: Owner] {
        get { tableLock.withLock { blockedOnStorage } }
        set { tableLock.withLock { blockedOnStorage = newValue } }
    }
    var protectionClasses: [FileIdentity: Int32] {
        get { classStorage.withLock { $0 } }
        set { classStorage.withLock { $0 = newValue } }
    }
    private let classStorage = Mutex<[FileIdentity: Int32]>([:])

    func isWatched(_ key: ObjectIdentifier) -> Bool { tableLock.withLock { watchedStorage.contains(key) } }
    func watch(_ key: ObjectIdentifier) -> Bool { tableLock.withLock { watchedStorage.insert(key).inserted } }
    func unwatch(_ key: ObjectIdentifier) { tableLock.withLock { _ = watchedStorage.remove(key) } }

    func state(_ id: FileIdentity) -> FileState {
        tableLock.withLock {
            if let s = storage[id] { return s }
            let s = FileState()
            storage[id] = s
            return s
        }
    }

    func blocker(_ id: FileIdentity, owner: Owner, exclusive: Bool, start: Int64, end: Int64) -> Lock? {
        tableLock.withLock { blockerLocked(id, owner: owner, exclusive: exclusive, start: start, end: end) }
    }

    private func blockerLocked(_ id: FileIdentity, owner: Owner, exclusive: Bool, start: Int64, end: Int64) -> Lock? {
        storage[id]?.locks.first { $0.owner != owner && $0.overlaps(start, end) && (exclusive || $0.exclusive) }
    }

    func blockerCountingWaiter(_ id: FileIdentity, owner: Owner, exclusive: Bool, start: Int64, end: Int64,
                               pid: Int32?) -> (Lock, FileState)? {
        tableLock.withLock {
            guard let b = blockerLocked(id, owner: owner, exclusive: exclusive, start: start, end: end) else { return nil }
            let s = storage[id]!
            s.waiting += 1
            if let pid { blockedOnStorage[pid] = b.owner }
            return (b, s)
        }
    }

    func stoppedWaiting(_ id: FileIdentity, _ s: FileState, pid: Int32?) {
        tableLock.withLock {
            s.waiting -= 1
            if let pid { blockedOnStorage[pid] = nil }
            if s.locks.isEmpty, s.waiting == 0, storage[id] === s { storage[id] = nil }
        }
    }

    @discardableResult
    func apply(_ id: FileIdentity, owner: Owner, kind: Kind, exclusive: Bool?, start: Int64, end: Int64) -> [FileState] {
        tableLock.withLock {
            let s: FileState
            if let existing = storage[id] { s = existing } else { s = FileState(); storage[id] = s }
            var kept: [Lock] = []
            var mine: [Lock] = []
            for l in s.locks {
                guard l.owner == owner else { kept.append(l); continue }
                guard l.overlaps(start, end) else { mine.append(l); continue }
                if l.start < start { var left = l; left.end = start - 1; mine.append(left) }
                if l.end > end { var right = l; right.start = end + 1; mine.append(right) }
            }
            if let exclusive { mine.append(Lock(owner: owner, kind: kind, exclusive: exclusive, start: start, end: end)) }
            mine.sort { $0.start < $1.start }
            var merged: [Lock] = []
            for l in mine {
                if var last = merged.last, last.exclusive == l.exclusive, last.kind == l.kind,
                   last.end == Int64.max || last.end + 1 >= l.start {
                    last.end = max(last.end, l.end)
                    merged[merged.count - 1] = last
                } else {
                    merged.append(l)
                }
            }
            s.locks = kept + merged
            return changedLocked(id)
        }
    }

    @discardableResult
    func release(owner: Owner, on id: FileIdentity? = nil) -> [FileState] {
        tableLock.withLock {
            var wake: [FileState] = []
            for (key, s) in storage where id == nil || key == id {
                let before = s.locks.count
                s.locks.removeAll { $0.owner == owner }
                if s.locks.count != before { wake += changedLocked(key) }
            }
            return wake
        }
    }

    private func changedLocked(_ id: FileIdentity) -> [FileState] {
        guard let s = storage[id] else { return [] }
        if s.locks.isEmpty && s.waiting == 0 { storage[id] = nil }
        return s.waiting > 0 ? [s] : []
    }

    func hasLocks(of owner: Owner, on id: FileIdentity) -> Bool {
        tableLock.withLock { storage[id]?.locks.contains { $0.owner == owner } ?? false }
    }

    func wouldDeadlock(_ pid: Int32, waitingFor owner: Owner) -> Bool {
        tableLock.withLock {
            var current = owner
            for _ in 0..<64 {
                guard case let .process(p) = current else { return false }
                if p == pid { return true }
                guard let next = blockedOnStorage[p] else { return false }
                current = next
            }
            return false
        }
    }
}

extension KernelLock {
    func wakeFileLockWaiters(_ states: [FileLockTable.FileState]) {
        guard !states.isEmpty else { return }
        withLock { for s in states { _ = s.waiters.wakeAll() } }
    }
}

extension DarwinSystem {
    var fileLocks: FileLockTable {
        fileLockCreation.withLock { _ in
            if let t = fileLockStorage { return t }
            let t = FileLockTable()
            fileLockStorage = t
            return t
        }
    }
}

enum FileLockControl {
    static let getlk: Int32 = 7, setlk: Int32 = 8, setlkw: Int32 = 9, setlkwTimeout: Int32 = 10
    static let ofdSetlk: Int32 = 90, ofdSetlkw: Int32 = 91, ofdGetlk: Int32 = 92, ofdSetlkwTimeout: Int32 = 93
    static let rdlck: Int16 = 1, unlck: Int16 = 2, wrlck: Int16 = 3
    static let lockSH: Int32 = 1, lockEX: Int32 = 2, lockNB: Int32 = 4, lockUN: Int32 = 8
    static let commands: Set<Int32> = [getlk, setlk, setlkw, setlkwTimeout, ofdSetlk, ofdSetlkw, ofdGetlk, ofdSetlkwTimeout]
    static let names: [Int32: String] = [7: "F_GETLK", 8: "F_SETLK", 9: "F_SETLKW", 10: "F_SETLKWTIMEOUT",
                                         90: "F_OFD_SETLK", 91: "F_OFD_SETLKW", 92: "F_OFD_GETLK",
                                         93: "F_OFD_SETLKWTIMEOUT"]
    static let protectionLevel: UInt64 = 5
    static let defaultFileClass: Int32 = 3
}

extension DarwinKernel {
    func lockableFile(_ fd: Int32, notFile: Int32 = DarwinErrnoCode.EBADF) throws -> (DarwinOpenFile, GuestFile) {
        let open = try fileSystem.openFile(for: fd)
        guard let f = open.guestFile else { throw fail(notFile) }
        return (open, f)
    }

    private func watchDescription(_ open: DarwinOpenFile) {
        let key = ObjectIdentifier(open)
        guard !open.lastCloseHandlers.keys.contains("locks") else { return }
        let system = self.system
        open.lastCloseHandlers["locks"] = { [weak system] in
            guard let system else { return }
            let table = system.fileLocks
            table.unwatch(key)
            system.lock.wakeFileLockWaiters(table.release(owner: .description(key)))
        }
        _ = system.fileLocks.watch(key)
    }

    func fileLockFcntl(_ fd: Int32, _ cmd: Int32, _ arg: UInt64, _ call: inout CallText,
                       _ mem: any KernelGuestMemory, fast: Bool = false) throws -> UInt64 {
        call.set("fcntl(fd=\(fd), \(FileLockControl.names[cmd] ?? "cmd \(cmd)"), arg=\(hx(arg)))")
        if cmd < FileLockControl.ofdSetlk, cmd != FileLockControl.getlk {
            let pid = self.pid
            system.posixLockUsers.withLock { _ = $0.insert(pid) }
        }
        let (open, file) = try lockableFile(fd)
        let raw = try mem.read(va: arg, count: 24)
        let lStart = raw.readLE(Int64.self, at: 0), lLen = raw.readLE(Int64.self, at: 8)
        let lType = raw.readLE(Int16.self, at: 20), lWhence = raw.readLE(Int16.self, at: 22)
        var start: Int64
        switch lWhence {
        case 0: start = lStart
        case 1: start = Int64(clamping: open.offset).addingReportingOverflow(lStart).partialValue
        case 2: start = (try fileSystem.fstat(fd).size).addingReportingOverflow(lStart).partialValue
        default: throw fail(Code.EINVAL)
        }
        guard start >= 0 else { throw fail(Code.EINVAL) }
        let end: Int64
        if lLen < 0 {
            guard start != 0 else { throw fail(Code.EINVAL) }
            end = start - 1
            start += lLen
            guard start >= 0 else { throw fail(Code.EINVAL) }
        } else if lLen == 0 {
            end = Int64.max
        } else {
            guard lLen - 1 <= Int64.max - start else { throw fail(Code.EOVERFLOW) }
            end = start + (lLen - 1)
        }
        let ofd = cmd >= FileLockControl.ofdSetlk
        let owner: FileLockTable.Owner = ofd ? .description(ObjectIdentifier(open)) : .process(pid)
        let table = system.fileLocks
        let id = FileIdentity(file.stat)
        call += " [\(lType == FileLockControl.rdlck ? "rd" : lType == FileLockControl.wrlck ? "wr" : lType == FileLockControl.unlck ? "un" : "type \(lType)") "
            + "\(start)…\(end == Int64.max ? "eof" : String(end))]"

        if cmd == FileLockControl.getlk || cmd == FileLockControl.ofdGetlk {
            guard [FileLockControl.rdlck, FileLockControl.wrlck, FileLockControl.unlck].contains(lType) else {
                throw fail(Code.EINVAL)
            }
            var out = raw
            if let b = table.blocker(id, owner: owner, exclusive: lType == FileLockControl.wrlck, start: start, end: end) {
                out.putLE(b.start, at: 0)
                out.putLE(b.end == Int64.max ? Int64(0) : b.end - b.start + 1, at: 8)
                if case let .process(p) = b.owner { out.putLE(p, at: 16) } else { out.putLE(Int32(-1), at: 16) }
                out.putLE(b.exclusive ? FileLockControl.wrlck : FileLockControl.rdlck, at: 20)
                out.putLE(Int16(0), at: 22)
                call += " [held by \(b.owner)]"
            } else {
                out.putLE(FileLockControl.unlck, at: 20)
            }
            try mem.write(va: arg, bytes: out)
            return 0
        }

        let exclusive: Bool?
        switch lType {
        case FileLockControl.rdlck:
            guard open.isReadable else { throw fail(Code.EBADF) }
            exclusive = false
        case FileLockControl.wrlck:
            guard open.isWritable else { throw fail(Code.EBADF) }
            exclusive = true
        case FileLockControl.unlck:
            exclusive = nil
        default:
            throw fail(Code.EINVAL)
        }
        if ofd {
            if fast, !table.isWatched(ObjectIdentifier(open)) { throw BSDFastDecline() }
            if !fast { watchDescription(open) }
        }
        let wait = cmd == FileLockControl.setlkw || cmd == FileLockControl.ofdSetlkw
            || cmd == FileLockControl.setlkwTimeout || cmd == FileLockControl.ofdSetlkwTimeout
        var deadline: UInt64?
        if cmd == FileLockControl.setlkwTimeout || cmd == FileLockControl.ofdSetlkwTimeout {
            let ts = try mem.read(va: arg + 24, count: 16)
            let sec = ts.readLE(Int64.self, at: 0), nsec = ts.readLE(Int64.self, at: 8)
            guard sec >= 0, nsec >= 0, nsec < 1_000_000_000 else { throw fail(Code.EINVAL) }
            let ns = UInt64(sec).multipliedReportingOverflow(by: 1_000_000_000)
            deadline = ns.overflow ? UInt64.max : KernelClock.deadline(afterNanoseconds: ns.partialValue &+ UInt64(nsec))
        }
        try acquire(table, id, owner: owner, kind: ofd ? .ofd : .posix, exclusive: exclusive, start: start, end: end,
                    wait: wait, deadline: deadline, call: &call)
        return 0
    }

    private func acquire(_ table: FileLockTable, _ id: FileIdentity, owner: FileLockTable.Owner, kind: FileLockTable.Kind,
                         exclusive: Bool?, start: Int64, end: Int64, wait: Bool, deadline: UInt64?,
                         call: inout CallText) throws {
        if let exclusive {
            while let b = table.blocker(id, owner: owner, exclusive: exclusive, start: start, end: end) {
                guard wait else { throw fail(Code.EAGAIN) }
                precondition(lock.isHeldByCurrentThread, "a file-lock wait needs the kernel lock")
                if case let .process(me) = owner, kind == .posix, table.wouldDeadlock(me, waitingFor: b.owner) {
                    throw fail(Code.EDEADLK)
                }
                call += " [waits for \(b.owner)]"
                var waiterPID: Int32?
                if case let .process(me) = owner { waiterPID = me }
                guard let (_, state) = table.blockerCountingWaiter(id, owner: owner, exclusive: exclusive, start: start,
                                                                     end: end, pid: waiterPID) else { continue }
                let result = state.waiters.wait(on: lock, deadline: deadline)
                table.stoppedWaiting(id, state, pid: waiterPID)
                switch result {
                case .woken: continue
                case .timedOut: throw fail(Code.ETIMEDOUT)
                case .interrupted: throw fail(Code.EINTR)
                }
            }
        }
        lock.wakeFileLockWaiters(table.apply(id, owner: owner, kind: kind, exclusive: exclusive, start: start, end: end))
    }

    func flockCall(_ fd: Int32, _ operation: Int32, _ call: inout CallText) throws -> UInt64 {
        call.set("flock(\(fd), \(hx(UInt32(bitPattern: operation))))")
        let (open, file) = try lockableFile(fd, notFile: Code.ENOTSUP)
        let owner = FileLockTable.Owner.description(ObjectIdentifier(open))
        let table = system.fileLocks
        let id = FileIdentity(file.stat)
        let op = operation & ~FileLockControl.lockNB
        if op & FileLockControl.lockUN != 0 {
            let held = VnodeNotes.isActive && table.hasLocks(of: owner, on: id)
            lock.wakeFileLockWaiters(table.apply(id, owner: owner, kind: .flock, exclusive: nil, start: 0, end: Int64.max))
            if held { VnodeNotes.post(file.hostKey, VnodeNote.funlock) }
            return 0
        }
        let exclusive: Bool
        if op & FileLockControl.lockEX != 0 {
            exclusive = true
        } else if op & FileLockControl.lockSH != 0 {
            exclusive = false
        } else {
            throw fail(Code.EBADF)
        }
        watchDescription(open)
        try acquire(table, id, owner: owner, kind: .flock, exclusive: exclusive, start: 0, end: Int64.max,
                    wait: operation & FileLockControl.lockNB == 0, deadline: nil, call: &call)
        return 0
    }

    func releasePOSIXLocksOnClose(_ file: DarwinOpenFile) {
        guard termination != .imageReplaced, let f = file.guestFile else { return }
        let table = system.fileLocks
        let id = FileIdentity(f.stat)
        guard table.hasLocks(of: .process(pid), on: id) else { return }
        lock.wakeFileLockWaiters(table.release(owner: .process(pid), on: id))
    }

    func protectionClass(of file: GuestFile) -> Int32 {
        protectionClass(stat: file.stat, path: file.guestPath)
    }

    func protectionClass(stat: DarwinStat, path: String) -> Int32 {
        let table = system.fileLocks
        if let c = table.protectionClasses[FileIdentity(stat)] { return c }
        if !fileSystem.writable(guestPath: path) { return FileLockControl.defaultFileClass }
        var parent = GuestPath.deletingLastComponent(path)
        while !parent.isEmpty {
            if let st = try? fileSystem.stat(parent, followSymlinks: true),
               let c = table.protectionClasses[FileIdentity(st)] {
                return stat.isDirectory || c != 0 ? c : FileLockControl.defaultFileClass
            }
            if parent == "/" { break }
            parent = GuestPath.deletingLastComponent(parent)
        }
        return stat.isDirectory ? 0 : FileLockControl.defaultFileClass
    }

    func setProtectionClass(_ file: GuestFile, _ requested: Int32) throws {
        let table = system.fileLocks
        let id = FileIdentity(file.stat)
        switch requested {
        case 1, 2, 3: table.protectionClasses[id] = requested
        case 4: table.protectionClasses[id] = 3
        case 0 where file.isDirectory: table.protectionClasses[id] = 0
        case 7 where file.isDirectory: break
        case 6, 7: throw fail(Code.EPERM)
        default: throw fail(Code.EINVAL)
        }
    }

    func protectionFcntl(_ fd: Int32, _ cmd: Int32, _ arg: UInt64, _ call: inout CallText) throws -> UInt64 {
        let (_, file) = try lockableFile(fd)
        switch cmd {
        case 63:
            let c = protectionClass(of: file)
            call += " [class \(c)]"
            return UInt64(UInt32(bitPattern: c))
        case 64:
            try setProtectionClass(file, Int32(truncatingIfNeeded: arg))
            return 0
        default:
            return FileLockControl.protectionLevel
        }
    }

    func noteCreatedWithClass(_ fd: Int32, _ requested: Int32) {
        guard let (_, file) = try? lockableFile(fd), (1...4).contains(requested) else { return }
        try? setProtectionClass(file, requested)
    }
}

extension DarwinKernel {
    func checkDataProtectionOpen(flags: Int32, dpflags: Int32) throws {
        if dpflags & 0x2 != 0 { throw fail(Code.EPERM) }
        if dpflags & 0x4 != 0 { throw fail(Code.EINVAL) }
        if dpflags & 0x1 != 0 && flags & DarwinOpen.O_ACCMODE != DarwinOpen.O_RDONLY { throw fail(Code.EINVAL) }
    }
}

extension DarwinKernel {
    func syncCall(_ n: Int, _ fd: Int32, _ call: inout CallText) throws -> UInt64 {
        call.set("\(n == 95 ? "fsync" : "fdatasync")(\(fd))")
        _ = try lockableFile(fd, notFile: Code.ENOTSUP)
        return 0
    }
}
