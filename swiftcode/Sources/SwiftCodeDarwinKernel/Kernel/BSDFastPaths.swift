import Foundation
import Synchronization
import SwiftCodeDarwinABI

struct BSDFastDecline: Error {}

extension DarwinKernel {
    nonisolated(unsafe) public static var bsdFastTrapsEnabled = getenv("SWIFTCODE_BSD_FAST").map { String(cString: $0) != "0" } ?? true

    nonisolated(unsafe) public static var bsdFastForTests =
        (getenv("SWIFTCODE_BSD_FAST_TESTS").map { String(cString: $0) == "1" } ?? false) || DarwinSystem.splitForTests

    static let bsdFastExcluded: Set<Int32> = {
        guard let raw = getenv("SWIFTCODE_BSD_FAST_EXCLUDE") else { return [] }
        return Set(String(cString: raw).split(separator: ",").compactMap { Int32($0) })
    }()

    public static func isBSDFastTrap(_ number: Int32) -> Bool {
        if !bsdFastExcluded.isEmpty, bsdFastExcluded.contains(number) { return false }
        return switch number {
        case 5, 398, 463, 464, 6, 399, 3, 396, 153, 414, 4, 397, 154, 415, 199, 339, 92, 406, 33, 466, 469, 470, 202, 274, 327,
             220, 228, 476, 197, 515, 516, 544, 381, 41, 336: true
        case 116, 372, 500, 322, 95, 187, 136, 475, 58, 473, 345, 346: bsdFastMoreEnabled
        case 344: fastDirectoryEnabled
        case 169, 170, 545: procTableFastEnabled
        default: false
        }
    }

    nonisolated(unsafe) public static var bsdFastMoreEnabled = getenv("SWIFTCODE_BSD_FAST_MORE").map { String(cString: $0) != "0" } ?? true

    nonisolated(unsafe) public static var consoleFastEnabled = getenv("SWIFTCODE_CONSOLE_FAST").map { String(cString: $0) != "0" } ?? true

    nonisolated(unsafe) public static var fileLockFastEnabled = getenv("SWIFTCODE_FILE_LOCK_FAST").map { String(cString: $0) != "0" } ?? true

    nonisolated(unsafe) public static var fastDirectoryEnabled = getenv("SWIFTCODE_DIRECTORY_FAST").map { String(cString: $0) != "0" } ?? true

    static let fcntlDeclinedByCommand = Mutex<[Int32: UInt64]>([:])
    static let bsdDeclinedByTrap = Mutex<[Int32: UInt64]>([:])
    static func countDecline(_ table: borrowing Mutex<[Int32: UInt64]>, _ key: Int32) {
        table.withLock { $0[key, default: 0] &+= 1 }
    }

    static var bsdDeclineReport: String {
        func top(_ table: [Int32: UInt64], _ n: Int) -> String {
            table.sorted { $0.value > $1.value }.prefix(n).map { "\($0.key): \($0.value)" }.joined(separator: ", ")
        }
        return "BSD fast fallbacks by trap: " + top(bsdDeclinedByTrap.withLock { $0 }, 12)
            + "; fcntl fallbacks by command: " + top(fcntlDeclinedByCommand.withLock { $0 }, 12)
    }

    public static let bsdFastServed = Atomic<UInt64>(0)
    public static let bsdFastDeclined = Atomic<UInt64>(0)
    public static let bsdFastCloseHooks = Atomic<UInt64>(0)
    public static let bsdFastCloseHooksWatched = Atomic<UInt64>(0)

    public func handleBSDFast(_ frame: inout TrapFrame, context: ThreadContext, memory: any KernelGuestMemory) -> Outcome? {
        guard Self.bsdFastTrapsEnabled, !tracing || Self.bsdFastForTests, frame.trapKind == .svc,
              frame.x.count >= TrapFrame.registerCount, context.kernel === self, !isTerminating else { return nil }
        let number = Int32(truncatingIfNeeded: frame.x[16])
        guard Self.isBSDFastTrap(number), !lock.isHeldByCurrentThread else { return nil }
        let threadLocks = KernelThreadLocks.current
        guard threadLocks.held.isEmpty, !threadLocks.isFast, !threadLocks.bsdFast else { return nil }
        threadLocks.bsdFast = true
        defer { threadLocks.bsdFast = false }
        let profile = lock.trapProfile
        let start = profile != nil ? KernelClock.now() : 0
        let generation = memory.tlbGeneration
        let a = frame.x.prefixArray(8)
        if number == 515 || number == 516 || number == 544 {
            return ulockFast(number, a, &frame, context: context, memory: memory, profileStart: start)
        }
        var call = CallText(tracing, TrapNames.describe(TrapNames.bsd(Int(number)), a))
        let result: UInt64?
        do {
            result = try fastBSDCall(Int(number), a, &call, context: context, memory)
        } catch is BSDFastDecline {
            Self.bsdFastDeclined.wrappingAdd(1, ordering: .relaxed)
            Self.countDecline(Self.bsdDeclinedByTrap, number)
            return nil
        } catch {
            let e = errno(of: error, default: Errno.EINVAL)
            frame.x[0] = UInt64(UInt32(bitPattern: e))
            frame.x[1] = 0
            frame.carry = true
            Self.bsdFastServed.wrappingAdd(1, ordering: .relaxed)
            if tracing { log("trap bsd \(number) \(call) -> error \(e) (\(Errno.name(e)))") }
            if let profile { profile.noteHandler(TrapProfile.filtered(Int64(number), kernel: self), KernelClock.now() &- start) }
            if memory.tlbGeneration != generation { frame.requestTLBInvalidation(memory.tlbRange(since: generation)) }
            return .resume
        }
        guard let value = result else {
            Self.bsdFastDeclined.wrappingAdd(1, ordering: .relaxed)
            Self.countDecline(Self.bsdDeclinedByTrap, number)
            return nil
        }
        frame.x[0] = value
        frame.x[1] = 0
        frame.carry = false
        Self.bsdFastServed.wrappingAdd(1, ordering: .relaxed)
        if tracing { log("trap bsd \(number) \(call) -> \(hx(value))") }
        if let profile { profile.noteHandler(TrapProfile.filtered(Int64(number), kernel: self), KernelClock.now() &- start) }
        if memory.tlbGeneration != generation { frame.requestTLBInvalidation(memory.tlbRange(since: generation)) }
        return .resume
    }

    private func ulockFast(_ number: Int32, _ a: [UInt64], _ frame: inout TrapFrame, context: ThreadContext,
                           memory: any KernelGuestMemory, profileStart: UInt64) -> Outcome? {
        guard eventLock != nil, !SchedPolicy.qosEnabled || SchedPolicy.classOffL0 else {
            Self.bsdFastDeclined.wrappingAdd(1, ordering: .relaxed)
            return nil
        }
        var call = CallText(tracing, TrapNames.describe(TrapNames.bsd(Int(number)), a))
        var value: UInt64 = 0
        var failure: Int32?
        lock.withFastPath(context: context) {
            context.entryFrame = frame
            defer { context.entryFrame = nil }
            do {
                value = number == 516 ? try ulockWake(a, &call) : try ulockWait(Int(number), a, &call, memory)
            } catch {
                failure = errno(of: error, default: Errno.EINVAL)
            }
        }
        if let e = failure {
            frame.x[0] = UInt64(UInt32(bitPattern: e))
            frame.carry = true
            if tracing { log("trap bsd \(number) \(call) -> error \(e) (\(Errno.name(e)))") }
        } else {
            frame.x[0] = value
            frame.carry = false
            if tracing { log("trap bsd \(number) \(call) -> \(hx(value))") }
        }
        frame.x[1] = 0
        Self.bsdFastServed.wrappingAdd(1, ordering: .relaxed)
        if let profile = lock.trapProfile {
            profile.noteHandler(TrapProfile.filtered(Int64(number), kernel: self), KernelClock.now() &- profileStart)
        }
        return .resume
    }

    private func fastBSDCall(_ n: Int, _ a: [UInt64], _ call: inout CallText, context: ThreadContext,
                             _ mem: any KernelGuestMemory) throws -> UInt64? {
        let fs = fileSystem
        func int(_ i: Int) -> Int32 { Int32(truncatingIfNeeded: a[i]) }
        switch n {
        case 5, 398:
            let path = try readPath(a[0], mem)
            call.set("open(\"\(path)\", flags=\(openFlagsText(int(1))), mode=0o\(String(a[2] & 0o7777, radix: 8)))")
            let newFD = try openUnlocked(path, flags: int(1), mode: UInt16(truncatingIfNeeded: a[2]))
            return UInt64(UInt32(bitPattern: newFD))

        case 463, 464:
            let path = try resolveAtPath(int(0), a[1], mem)
            call.set("openat(\(int(0)), \"\(path)\", flags=\(openFlagsText(int(2))), mode=0o\(String(a[3] & 0o7777, radix: 8)))")
            let newFD = try openUnlocked(path, flags: int(2), mode: UInt16(truncatingIfNeeded: a[3]))
            return UInt64(UInt32(bitPattern: newFD))

        case 336:
            return try procInfoFast(a, &call, mem)

        case 545:
            guard !system.isImplicit else { return nil }
            let callnum = Int32(truncatingIfNeeded: a[0])
            guard callnum == ProcInfoCall.listPIDs || callnum == ProcInfoCall.pidInfo || callnum == ProcInfoCall.pidRUsage
            else { return nil }
            return try procInfoExtendedID(a, &call, mem)

        case 169, 170:
            guard !system.isImplicit else { return nil }
            call.set("\(n == 170 ? "csops_audittoken" : "csops")(pid=\(int(0)), ops=\(int(1)), addr=\(hx(a[2])), size=\(a[3]))")
            return try csopsCall(n == 170, a, &call, mem)

        case 6, 399:
            call.set("close(\(int(0)))")
            return try fastClose(int(0), context: context) ? 0 : nil

        case 3, 396, 153, 414:
            let isPread = n == 153 || n == 414
            call.set(isPread ? "pread(fd=\(int(0)), buf=\(hx(a[1])), len=\(hx(a[2])), off=\(hx(a[3])))"
                : "read(fd=\(int(0)), buf=\(hx(a[1])), len=\(hx(a[2])))")
            guard let io = try? hostFileIO(int(0), writing: false) else { return nil }
            let count = Int(min(a[2], UInt64(Int32.max)))
            let bytes = try readUnlocked(io, count: count, offset: isPread ? a[3] : nil)
            if !bytes.isEmpty { try mem.write(va: a[1], bytes: bytes) }
            return UInt64(bytes.count)

        case 4, 397, 154, 415:
            let isPwrite = n == 154 || n == 415
            call.set(isPwrite ? "pwrite(fd=\(int(0)), buf=\(hx(a[1])), len=\(hx(a[2])), off=\(hx(a[3])))"
                : "write(fd=\(int(0)), buf=\(hx(a[1])), len=\(hx(a[2])))")
            guard a[2] <= UInt64(Int32.max), !isPwrite || Int64(bitPattern: a[3]) >= 0 else { return nil }
            if let flags = fs.guardFlags(int(0)), flags & DarwinGuard.write != 0 { return nil }
            guard let io = try? hostFileIO(int(0), writing: true, guardChecked: true) else {
                guard Self.bsdFastMoreEnabled, Self.consoleFastEnabled, !isPwrite, let file = try? fs.openFile(for: int(0)),
                      case .console = file.node else { return nil }
                let bytes = a[2] == 0 ? [] : try mem.read(va: a[1], count: Int(a[2]))
                return UInt64(try fs.write(int(0), bytes, guardChecked: true))
            }
            let bytes = a[2] == 0 ? [] : try mem.read(va: a[1], count: Int(a[2]))
            return UInt64(try isPwrite ? io.pwrite(bytes, offset: a[3]) : io.write(bytes))

        case 199:
            call.set("lseek(fd=\(int(0)), offset=\(Int64(bitPattern: a[1])), whence=\(int(2)))")
            let target = try fs.lseekTarget(int(0))
            return try target.seek(offset: Int64(bitPattern: a[1]), whence: int(2))!

        case 339:
            call.set("fstat64(fd=\(int(0)), buf=\(hx(a[1])))")
            let file = try fs.openFile(for: int(0))
            if let object = file.object, !(object is DarwinDevice) { return nil }
            try mem.write(va: a[1], bytes: fs.fstat(of: file).encodedStat64())
            return 0

        case 92, 406:
            return try fastFcntl(a, &call, mem)

        case 33, 466:
            let isAt = n == 466
            let path = try resolveAtPath(isAt ? int(0) : Self.atFDCWD, isAt ? a[1] : a[0], mem)
            let mode = isAt ? int(2) : int(1)
            call.set(isAt ? "faccessat(\(int(0)), \"\(path)\", mode=\(mode), flag=\(hx(a[3])))" : "access(\"\(path)\", mode=\(mode))")
            let follow = !isAt || int(3) & Self.atSymlinkNofollow == 0
            let st = try statUnlocked(path, followSymlinks: follow)
            if let denied = accessDenied(st, path: path, read: mode & 4 != 0, write: mode & 2 != 0, execute: mode & 1 != 0) {
                throw Failure(errno: denied)
            }
            return 0

        case 469, 470:
            let path = try resolveAtPath(int(0), a[1], mem)
            call.set("fstatat64(\(int(0)), \"\(path)\", buf=\(hx(a[2])), flag=\(hx(a[3])))")
            let st = try statUnlocked(path, followSymlinks: int(3) & Self.atSymlinkNofollow == 0)
            try mem.write(va: a[2], bytes: st.encodedStat64())
            return 0

        case 202:
            let count = Int(UInt32(truncatingIfNeeded: a[1]))
            if count >= 2, count <= 12 {
                let raw = try mem.read(va: a[0], count: count >= 3 ? 12 : 8)
                if raw.readLE(Int32.self, at: 0) == 1, raw.readLE(Int32.self, at: 4) == 14,
                   !(Self.procTableFastEnabled && !system.isImplicit && count == 4 && raw.readLE(Int32.self, at: 8) == 1) {
                    return nil
                }
            }
            return try sysctlMIB(a, &call, mem)

        case 274:
            let name = try readString(a[0], length: Int(min(a[1], 1024)), mem)
            call.set("sysctlbyname(\"\(name)\", old=\(hx(a[2])), oldlenp=\(hx(a[3])), new=\(hx(a[4])), newlen=\(hx(a[5])))")
            return try sysctlRead(sysctl.lookup(name: name), name: name,
                                  old: a[2], oldlenp: a[3], new: a[4], newlen: a[5], mem)

        case 327:
            call.set("issetugid()")
            return 0

        case 116:
            call.set("gettimeofday(tp=\(hx(a[0])), tzp=\(hx(a[1])), mach_time=\(hx(a[2])))")
            return try gettimeofdayCall(a, mem)

        case 372:
            call.set("thread_selfid()")
            return context.threadID

        case 95, 187:
            return try syncCall(n, int(0), &call)

        case 136, 475:
            return try mkdirCall(n, a, &call, mem)

        case 58, 473:
            return try readlinkCall(n, a, &call, mem)

        case 345, 346:
            return try statfsCall(n, a, &call, mem)

        case 322:
            return try ioPolicyCall(a, thread: context.threadID, &call, mem)

        case 344:
            return try getdirentries64(a, &call, mem)

        case 500:
            call.set("getentropy(buf=\(hx(a[0])), size=\(a[1]))")
            guard a[1] <= 256 else { throw Failure(errno: Errno.EINVAL) }
            if a[1] > 0 {
                var bytes = entropy(Int(a[1]))
                if bytes.count < Int(a[1]) { bytes += [UInt8](repeating: 0, count: Int(a[1]) - bytes.count) }
                try mem.write(va: a[0], bytes: Array(bytes.prefix(Int(a[1]))))
            }
            return 0

        case 41:
            call.set("dup(\(int(0)))")
            if (try? fs.guardState(of: int(0))) != nil { return nil }
            return UInt64(UInt32(bitPattern: try fs.dup(int(0))))

        case 381:
            let policy = (try? readString(a[0], length: 64, mem)) ?? "?"
            call.set("__mac_syscall(\"\(policy)\", \(int(1)), \(hx(a[2])))")
            if policy == "Sandbox" {
                if int(1) == 2 || int(1) == 12 { return 0 }
                guard Self.bsdFastMoreEnabled else { return nil }
                if let value = try sandboxExtensionCall(int(1), arg: a[2], mem) { return value }
            }
            throw Failure(errno: MetadataBSD.enoPolicy)

        case 220, 228, 476:
            return try attributeListCall(n, a, &call, mem)

        case 197:
            var fallback = Errno.EINVAL
            do {
                return try mmap(a, &call, &fallback, mem, fast: true)
            } catch is BSDFastDecline {
                throw BSDFastDecline()
            } catch {
                throw Failure(errno: errno(of: error, default: fallback))
            }

        default:
            return nil
        }
    }

    private func fastClose(_ fd: Int32, context: ThreadContext) throws -> Bool {
        guard let file = try? fileSystem.removeIf(fd, { file, guarded in
            guard !guarded else { return false }
            switch file.node {
            case .console: return true
            case let .file(f): return !f.isDirectory || Self.fastDirectoryEnabled
            case let .object(o): return o is DarwinDevice
            }
        }) else { return false }
        if case let .file(f) = file.node, f.isDirectory { extended.directoryCursors[fd] = nil }
        let watched = isDescriptorWatched(fd)
        let pid = self.pid
        let posixLocks = system.posixLockUsers.withLock { $0.contains(pid) }
        if watched || posixLocks {
            Self.bsdFastCloseHooks.wrappingAdd(1, ordering: .relaxed)
            if watched { Self.bsdFastCloseHooksWatched.wrappingAdd(1, ordering: .relaxed) }
            lock.withLock(context: context) {
                descriptorWasClosed(fd)
                releasePOSIXLocksOnClose(file)
            }
        }
        return true
    }

    private func fastFcntl(_ a: [UInt64], _ call: inout CallText, _ mem: any KernelGuestMemory) throws -> UInt64? {
        let fs = fileSystem
        let fd = Int32(truncatingIfNeeded: a[0])
        let cmd = Int32(truncatingIfNeeded: a[1])
        let arg = a[2]
        call.set("fcntl(fd=\(fd), \(Self.fcntlNames[cmd] ?? "cmd \(cmd)"), arg=\(hx(arg)))")
        switch cmd {
        case Fcntl.getfd:
            return (try fs.closeOnExec(fd) ? 1 : 0) | (try fs.closeOnFork(fd) ? 2 : 0)
        case Fcntl.setfd:
            try fs.setCloseOnExec(fd, arg & 1 != 0)
            try fs.setCloseOnFork(fd, arg & 2 != 0)
            return 0
        case Fcntl.getfl:
            return UInt64(UInt32(bitPattern: try fs.statusFlags(fd)))
        case Fcntl.getpath, Fcntl.getpathNoFirmlink:
            let path = try fs.path(for: fd)
            let bytes = cString(path)
            call += " [\(path)]"
            guard bytes.count <= DarwinFileSystem.maxPathLength else { throw Failure(errno: Errno.ENAMETOOLONG) }
            try mem.write(va: arg, bytes: bytes)
            return 0
        case Fcntl.checkLV:
            return 0
        case Fcntl.addFileSigsReturn:
            let size = try fs.file(for: fd).size
            var b: [UInt8] = []
            b.appendLE(size)
            try mem.write(va: arg, bytes: b)
            return 0
        case 0, 67:
            call.set("fcntl(fd=\(fd), \(cmd == 67 ? "F_DUPFD_CLOEXEC" : "F_DUPFD"), arg=\(Int32(truncatingIfNeeded: arg)))")
            if (try? fs.guardState(of: fd)) != nil { return nil }
            _ = try fs.openFile(for: fd)
            return UInt64(try fs.dup(fd, minimum: Int32(truncatingIfNeeded: arg), closeOnExec: cmd == 67))
        case Fcntl.getConfined:
            return try fs.openFile(for: fd).confinedToProcess ? 1 : 0
        case let c where Fcntl.hints.contains(c):
            _ = try fs.openFile(for: fd)
            return 0
        case DescriptorControl.setfl where Self.bsdFastMoreEnabled:
            call.set("fcntl(fd=\(fd), F_SETFL, arg=\(hx(UInt32(truncatingIfNeeded: arg))))")
            guard try fs.openFile(for: fd).object == nil else { return nil }
            try fs.setStatusFlags(fd, Int32(truncatingIfNeeded: arg))
            return 0
        case DescriptorControl.setNoSigPipe where Self.bsdFastMoreEnabled:
            call.set("fcntl(fd=\(fd), F_SETNOSIGPIPE, arg=\(Int32(truncatingIfNeeded: arg)))")
            try fs.openFile(for: fd).noSigPipe = Int32(truncatingIfNeeded: arg) != 0
            return 0
        case DescriptorControl.getNoSigPipe where Self.bsdFastMoreEnabled:
            call.set("fcntl(fd=\(fd), F_GETNOSIGPIPE)")
            return try fs.openFile(for: fd).noSigPipe ? 1 : 0
        case FileLockControl.getlk, FileLockControl.setlk, FileLockControl.ofdGetlk, FileLockControl.ofdSetlk
            where Self.fileLockFastEnabled:
            return try fileLockFcntl(fd, cmd, arg, &call, mem, fast: true)
        case Fcntl.getProtectionClass, Fcntl.getProtectionLevel:
            guard Self.bsdFastMoreEnabled else { return nil }
            return try protectionFcntl(fd, cmd, arg, &call)
        default:
            Self.countDecline(Self.fcntlDeclinedByCommand, cmd)
            return nil
        }
    }
}
