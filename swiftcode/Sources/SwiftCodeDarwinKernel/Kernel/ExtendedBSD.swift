import Foundation
import SwiftCodeDarwinABI

struct ExtendedBSDState {
    struct SignalAction: Equatable {
        var handler: UInt64 = 0
        var mask: UInt32 = 0
        var flags: Int32 = 0
    }

    struct DirectoryCursor {
        var file: GuestFile
        var entries: [(name: String, ino: UInt64, type: UInt8)]
        var next = 0
    }

    final class DirectoryCursorTable: @unchecked Sendable {
        private let lock = DescriptorTableLock(name: "directory cursors")
        nonisolated(unsafe) private var table: [Int32: DirectoryCursor] = [:]
        subscript(fd: Int32) -> DirectoryCursor? {
            get { lock.withLock { table[fd] } }
            set { lock.withLock { table[fd] = newValue } }
        }
        var all: [Int32: DirectoryCursor] { lock.withLock { table } }
        func withLock<T>(_ body: (inout [Int32: DirectoryCursor]) throws -> T) rethrows -> T {
            try lock.withLock { try body(&table) }
        }
    }

    var signalMask: UInt32 = 0
    var pendingSignals: UInt32 = 0
    var signalActions: [Int32: SignalAction] = [:]
    var alternateStack: (sp: UInt64, size: UInt64, flags: Int32) = (0, 0, DarwinKernel.SignalConstant.ssDisable)
    var rlimits: [Int32: (cur: UInt64, max: UInt64)] = [
        DarwinKernel.RLimit.stack: (8 << 20, 64 << 20),
        DarwinKernel.RLimit.nofile: (256, DarwinKernel.RLimit.infinity),
        DarwinKernel.RLimit.nproc: (6000, 9000),
        DarwinKernel.RLimit.core: (0, DarwinKernel.RLimit.infinity),
    ]
    var umask: UInt16 = 0o022
    let directoryCursors = DirectoryCursorTable()
    var selectStats = SelectStats()
    let ioPolicyStore = IOPolicyStore()
    var ioPolicies: [Int32: Int32] {
        get { ioPolicyStore.withLock { $0.process } }
        nonmutating set { ioPolicyStore.withLock { $0.process = newValue } }
    }
    var threadIOPolicies: [UInt64: [Int32: Int32]] {
        get { ioPolicyStore.withLock { $0.thread } }
        nonmutating set { ioPolicyStore.withLock { $0.thread = newValue } }
    }
    var darwinBackgroundIOPolicy: Int32 {
        get { ioPolicyStore.withLock { $0.background } }
        nonmutating set { ioPolicyStore.withLock { $0.background = newValue } }
    }

    final class IOPolicyStore: @unchecked Sendable {
        struct Policies {
            var process: [Int32: Int32] = [:]
            var thread: [UInt64: [Int32: Int32]] = [:]
            var background: Int32 = 0
        }
        private let lock = DescriptorTableLock(name: "I/O policies")
        nonisolated(unsafe) private var policies = Policies()
        func withLock<T>(_ body: (inout Policies) throws -> T) rethrows -> T { try lock.withLock { try body(&policies) } }
    }
}

extension DarwinKernel {
    public enum BSD2 {
        public static let getppid = 39, sigaction = 46, sigprocmask = 48, sigaltstack = 53, umask = 60,
                          getrusage = 117, readv = 120, writev = 121, csops = 169, csopsAudittoken = 170,
                          getrlimit = 194, setrlimit = 195, access = 33, pthreadSigmask = 329, procInfo = 336,
                          getdirentries64 = 344, kevent = 363, kevent64 = 369, threadSelfid = 372,
                          keventQos = 374, keventId = 375, openat = 463, faccessat = 466, fstatat = 469,
                          fstatat64 = 470, getentropy = 500, ulockWait = 515, ulockWake = 516,
                          terminateWithPayload = 520, osFaultWithPayload = 529, ulockWait2 = 544,
                          kill = 37, pthreadKill = 328, semwaitSignal = 334, semwaitSignalNocancel = 423,
                          statfs64 = 345, fstatfs64 = 346, workqOpen = 367, workqKernreturn = 368, sendto = 133,
                          bsdthreadCreate = 360, bsdthreadTerminate = 361, bsdthreadCtl = 478,
                          kqueueWorkloopCtl = 530, disableThreadsignal = 331,
                          sigsuspend = 111, sigsuspendNocancel = 410,
                          getxattr = 234, fgetxattr = 235, setxattr = 236, fsetxattr = 237,
                          removexattr = 238, fremovexattr = 239, listxattr = 240, flistxattr = 241,
                          gettid = 286, openDprotectedNp = 216, openatDprotectedNp = 218,
                          threadSelfusage = 482
        public static let psynchWaits: [Int: String] = [
            297: "psynch_rw_longrdlock", 298: "psynch_rw_yieldwrlock", 300: "psynch_rw_upgrade",
            301: "psynch_mutexwait", 305: "psynch_cvwait", 306: "psynch_rw_rdlock", 307: "psynch_rw_wrlock",
        ]
        public static let psynchWakes: [Int: String] = [
            299: "psynch_rw_downgrade", 302: "psynch_mutexdrop", 303: "psynch_cvbroad", 304: "psynch_cvsignal",
            308: "psynch_rw_unlock", 309: "psynch_rw_unlock2", 312: "psynch_cvclrprepost",
        ]
    }

    public enum RLimit {
        public static let cpu: Int32 = 0, fsize: Int32 = 1, data: Int32 = 2, stack: Int32 = 3, core: Int32 = 4,
                          rss: Int32 = 5, memlock: Int32 = 6, nproc: Int32 = 7, nofile: Int32 = 8
        public static let infinity: UInt64 = 0x7FFF_FFFF_FFFF_FFFF
        static let posixFlag: Int32 = 0x1000
    }

    public enum SignalConstant {
        public static let sigBlock: Int32 = 1, sigUnblock: Int32 = 2, sigSetmask: Int32 = 3
        public static let sigkill: Int32 = 9, sigstop: Int32 = 17
        public static let ssDisable: Int32 = 4
        static let unblockable: UInt32 = (1 << 8) | (1 << 16)
    }

    public enum ULock {
        public static let opMask: UInt32 = 0xFF
        public static let compareAndWait: UInt32 = 1
        public static let unfairLock: UInt32 = 2
        public static let compareAndWaitShared: UInt32 = 3
        public static let unfairLock64Shared: UInt32 = 4
        public static let compareAndWait64: UInt32 = 5
        public static let compareAndWait64Shared: UInt32 = 6
        public static let noErrno: UInt32 = 0x0100_0000
    }

    public static let atFDCWD: Int32 = -2
    static let atSymlinkNofollow: Int32 = 0x20
    static let ETIMEDOUT: Int32 = 60
    static let ENOATTR: Int32 = 93
    static let ENOTSOCK: Int32 = 38
    static let EDEADLK: Int32 = 11

    public static func hostEntropy(_ count: Int) -> [UInt8] {
        if let h = FileHandle(forReadingAtPath: "/dev/urandom") {
            defer { try? h.close() }
            if let d = try? h.read(upToCount: count), d.count == count { return Array(d) }
        }
        var rng = SystemRandomNumberGenerator()
        return (0..<count).map { _ in UInt8.random(in: UInt8.min...UInt8.max, using: &rng) }
    }

    private func extendedAttributeCall(_ n: Int, _ a: [UInt64], _ call: inout CallText,
                                       _ mem: any KernelGuestMemory) throws -> UInt64 {
        func int(_ i: Int) -> Int32 { Int32(truncatingIfNeeded: a[i]) }
        let byDescriptor = [BSD2.fgetxattr, BSD2.fsetxattr, BSD2.fremovexattr, BSD2.flistxattr].contains(n)
        let options: Int32
        switch n {
        case BSD2.getxattr, BSD2.fgetxattr, BSD2.setxattr, BSD2.fsetxattr: options = int(5)
        case BSD2.removexattr, BSD2.fremovexattr: options = int(2)
        default: options = int(3)
        }
        let target: DarwinFileSystem.XattrTarget
        let subject: String
        if byDescriptor {
            target = .descriptor(int(0))
            subject = "fd \(int(0))"
        } else {
            let path = try readPath(a[0], mem)
            target = .path(path, followSymlinks: options & 0x1 == 0)
            subject = "\"\(path)\""
        }
        let fs = fileSystem
        switch n {
        case BSD2.listxattr, BSD2.flistxattr:
            call.set("\(byDescriptor ? "flistxattr" : "listxattr")(\(subject), buf=\(hx(a[1])), size=\(a[2]))")
            let names = try fs.listExtendedAttributes(target)
            let bytes: [UInt8] = names.flatMap { name -> [UInt8] in Array(name.utf8) + [0] }
            if a[1] == 0 { return UInt64(bytes.count) }
            guard UInt64(bytes.count) <= a[2] else { throw Failure(errno: Errno.ERANGE) }
            if !bytes.isEmpty { try mem.write(va: a[1], bytes: bytes) }
            return UInt64(bytes.count)
        default:
            let name = try readString(a[1], length: 256, mem)
            switch n {
            case BSD2.getxattr, BSD2.fgetxattr:
                call.set("\(byDescriptor ? "fgetxattr" : "getxattr")(\(subject), \"\(name)\", size=\(a[3]))")
                guard a[4] == 0 else { throw Failure(errno: Errno.EINVAL) }
                let value = try fs.getExtendedAttribute(target, name: name)
                if a[2] == 0 { return UInt64(value.count) }
                guard UInt64(value.count) <= a[3] else { throw Failure(errno: Errno.ERANGE) }
                if !value.isEmpty { try mem.write(va: a[2], bytes: value) }
                return UInt64(value.count)
            case BSD2.setxattr, BSD2.fsetxattr:
                call.set("\(byDescriptor ? "fsetxattr" : "setxattr")(\(subject), \"\(name)\", size=\(a[3]), options=\(hx(UInt32(bitPattern: options))))")
                guard a[4] == 0, a[3] <= 1 << 26 else { throw Failure(errno: Errno.EINVAL) }
                let value: [UInt8] = a[3] == 0 ? [] : try mem.read(va: a[2], count: Int(a[3]))
                try fs.setExtendedAttribute(target, name: name, value: value, create: options & 0x2 != 0,
                                            replace: options & 0x4 != 0)
                return 0
            default:
                call.set("\(byDescriptor ? "fremovexattr" : "removexattr")(\(subject), \"\(name)\")")
                try fs.removeExtendedAttribute(target, name: name)
                return 0
            }
        }
    }

    func extendedBSDCall(_ n: Int, _ a: [UInt64], _ call: inout CallText, _ fallback: inout Int32,
                         _ mem: any KernelGuestMemory) throws -> BSDResult? {
        func int(_ i: Int) -> Int32 { Int32(truncatingIfNeeded: a[i]) }
        switch n {
        case BSD2.readv, BSD2.writev:
            return .value(try vectoredIO(write: n == BSD2.writev, a, &call, mem))

        case SelectBSD.select, SelectBSD.pselect:
            return try selectCall(n, a, &call, mem)

        case SelectBSD.poll:
            return try pollCall(a, &call, mem)

        case 284:
            let size = Int(min(a[1], 1 << 20))
            call.set("access_extended(entries=\(hx(a[0])), size=\(size), results=\(hx(a[2])), uid=\(int(3)))")
            guard size <= 16 * 1024 else { throw Failure(errno: Errno.ENOMEM) }
            guard size >= 16 + 2 else { throw Failure(errno: Errno.EINVAL) }
            var buffer = try mem.read(va: a[0], count: size)
            buffer.append(0)
            let first = Int(buffer.readLE(UInt32.self, at: 0))
            let count = first / 16
            guard count >= 1, count <= 100, first <= size else { throw Failure(errno: Errno.EINVAL) }
            var results: [UInt8] = []
            var name: String?
            for i in 0..<count {
                let offset = Int(buffer.readLE(UInt32.self, at: i * 16))
                guard offset < size else { throw Failure(errno: Errno.EINVAL) }
                if offset != 0 || name == nil {
                    guard offset >= first else { throw Failure(errno: Errno.EINVAL) }
                    let bytes = buffer[offset...].prefix { $0 != 0 }
                    name = String(decoding: bytes, as: UTF8.self)
                }
                var result: Int32 = 0
                do {
                    guard let path = name, !path.isEmpty else { throw Failure(errno: Errno.ENOENT) }
                    let st = try statUnlocked(path, followSymlinks: true)
                    let flags = Int32(bitPattern: buffer.readLE(UInt32.self, at: i * 16 + 4))
                    if let denied = accessDenied(st, path: path, read: flags & (4 | 1 << 9) != 0,
                                                 write: flags & (2 | 1 << 10) != 0, execute: flags & (1 | 1 << 11) != 0) {
                        throw Failure(errno: denied)
                    }
                } catch {
                    result = errno(of: error, default: Errno.ENOENT)
                }
                results.appendLE(result)
            }
            try mem.write(va: a[2], bytes: results)
            call += " [\(count) entries]"
            return .value(0)

        case 65, 405:
            let flags = int(2)
            call.set("msync(addr=\(hx(a[0])), len=\(hx(a[1])), flags=\(hx(UInt64(UInt32(bitPattern: flags)))))")
            guard a[0] & (VMLayout.pageSize - 1) == 0, flags & ~0x1F == 0, flags & 0x11 != 0x11 else {
                throw Failure(errno: Errno.EINVAL)
            }
            let end = a[0].addingReportingOverflow(a[1])
            guard !end.overflow else { throw Failure(errno: Errno.ENOMEM) }
            var va = a[0]
            while va < end.partialValue {
                guard let region = mem.region(containing: va) else { throw Failure(errno: Errno.ENOMEM) }
                va = region.end
            }
            return .value(0)

        case 203, 204:
            call.set("\(n == 203 ? "mlock" : "munlock")(addr=\(hx(a[0])), len=\(hx(a[1])))")
            let start = a[0] & ~(VMLayout.pageSize - 1)
            let end = a[0].addingReportingOverflow(a[1])
            guard !end.overflow else { throw Failure(errno: Errno.EINVAL) }
            var va = start
            while va < end.partialValue {
                guard let region = mem.region(containing: va) else { throw Failure(errno: Errno.ENOMEM) }
                va = region.end
            }
            return .value(0)

        case 322:
            return .value(try ioPolicyCall(a, thread: current.threadID, &call, mem))

        case 89:
            call.set("getdtablesize()")
            return .value(UInt64(fileSystem.maxDescriptors))

        case 191, 192:
            let name = int(1)
            if n == 191 {
                let path = try readPath(a[0], mem)
                call.set("pathconf(\"\(path)\", name=\(name))")
                _ = try statUnlocked(path, followSymlinks: true)
            } else {
                call.set("fpathconf(fd=\(int(0)), name=\(name))")
                _ = try fileSystem.fstat(int(0))
            }
            let values: [Int32: Int64] = [
                1: 32767,
                2: 1024,
                3: 1024,
                4: 255,
                5: 1024,
                6: 512,
                7: 200112,
                8: 200112,
                9: 0xFF,
                10: 255,
                11: 1,
                12: 1,
                13: 0,
                14: 0,
                15: 1,
                16: 4096,
                18: 64,
                24: 1024,
                26: 64,
                27: 0,
            ]
            guard let value = values[name] else { throw Failure(errno: Errno.EINVAL) }
            call += " [\(value)]"
            return .value(UInt64(bitPattern: value))

        case 186:
            call.set("thread_selfcounts(kind=\(int(0)), buf=\(hx(a[1])), size=\(a[2]))")
            throw Failure(errno: 45)

        case 96:
            call.set("setpriority(which=\(int(0)), who=\(a[1]), prio=\(int(2)))")
            guard (0...6).contains(int(0)) else { throw Failure(errno: Errno.EINVAL) }
            if SchedPolicy.qosEnabled {
                let bg = int(2) == DarwinPriority.prioDarwinBG
                if int(0) == DarwinPriority.prioDarwinThread, a[1] == 0, current.threadDarwinBG != bg {
                    current.threadDarwinBG = bg
                    refreshSchedClass(current)
                    call += " [thread darwin-bg \(bg)]"
                } else if int(0) == DarwinPriority.prioDarwinProcess {
                    let target = int(1) == 0 ? pid : Int32(truncatingIfNeeded: int(1))
                    if let p = system.processes[target], p.state != .zombie, p.requestedDarwinBG != bg {
                        p.requestedDarwinBG = bg
                        p.kernel?.refreshSchedClasses()
                        call += " [process \(target) darwin-bg \(bg)]"
                    }
                }
            }
            return .value(0)

        case BSD2.ulockWait, BSD2.ulockWait2:
            return .value(try ulockWait(n, a, &call, mem))
        case BSD2.ulockWake:
            return .value(try ulockWake(a, &call))

        case BSD2.getentropy:
            call.set("getentropy(buf=\(hx(a[0])), size=\(a[1]))")
            guard a[1] <= 256 else { throw Failure(errno: Errno.EINVAL) }
            if a[1] > 0 {
                var bytes = entropy(Int(a[1]))
                if bytes.count < Int(a[1]) { bytes += [UInt8](repeating: 0, count: Int(a[1]) - bytes.count) }
                try mem.write(va: a[0], bytes: Array(bytes.prefix(Int(a[1]))))
            }
            return .value(0)

        case BSD2.sigprocmask, BSD2.pthreadSigmask:
            call.set("\(n == BSD2.sigprocmask ? "sigprocmask" : "__pthread_sigmask")(how=\(int(0)), set=\(hx(a[1])), oset=\(hx(a[2])))")
            let old = extended.signalMask
            if a[1] != 0 {
                let set = try mem.read(va: a[1], count: 4).readLE(UInt32.self, at: 0)
                switch int(0) {
                case SignalConstant.sigBlock: extended.signalMask |= set
                case SignalConstant.sigUnblock: extended.signalMask &= ~set
                case SignalConstant.sigSetmask: extended.signalMask = set
                default: throw Failure(errno: Errno.EINVAL)
                }
                extended.signalMask &= ~SignalConstant.unblockable
                call += " [mask \(hx(extended.signalMask))]"
            }
            if a[2] != 0 { try writeU32(a[2], old, mem) }
            return .value(0)

        case BSD2.sigaction:
            return .value(try sigaction(a, &call, mem))

        case BSD2.sigaltstack:
            call.set("sigaltstack(nss=\(hx(a[0])), oss=\(hx(a[1])))")
            let old = extended.alternateStack
            if a[0] != 0 {
                let b = try mem.read(va: a[0], count: 24)
                extended.alternateStack = (b.readLE(UInt64.self, at: 0), b.readLE(UInt64.self, at: 8),
                                           b.readLE(Int32.self, at: 16))
            }
            if a[1] != 0 {
                var b: [UInt8] = []
                b.appendLE(old.sp)
                b.appendLE(old.size)
                b.appendLE(old.flags)
                b.appendLE(Int32(0))
                try mem.write(va: a[1], bytes: b)
            }
            return .value(0)

        case BSD2.getrlimit, BSD2.setrlimit:
            let which = int(0) & ~RLimit.posixFlag
            let isGet = n == BSD2.getrlimit
            call.set("\(isGet ? "getrlimit" : "setrlimit")(which=\(which), rlp=\(hx(a[1])))")
            guard (0...8).contains(which) else { throw Failure(errno: Errno.EINVAL) }
            if isGet {
                let l = extended.rlimits[which] ?? (RLimit.infinity, RLimit.infinity)
                var b: [UInt8] = []
                b.appendLE(l.cur)
                b.appendLE(l.max)
                try mem.write(va: a[1], bytes: b)
                call += " [cur \(hx(l.cur)) max \(hx(l.max))]"
            } else {
                let b = try mem.read(va: a[1], count: 16)
                let cur = b.readLE(UInt64.self, at: 0), max = b.readLE(UInt64.self, at: 8)
                guard cur <= max else { throw Failure(errno: Errno.EINVAL) }
                let old = extended.rlimits[which] ?? (RLimit.infinity, RLimit.infinity)
                guard max <= old.max else { throw Failure(errno: Errno.EPERM) }
                extended.rlimits[which] = (cur, max)
                if which == RLimit.nofile { fileSystem.maxDescriptors = Int32(min(cur, 10240)) }
                call += " [cur \(hx(cur)) max \(hx(max))]"
            }
            return .value(0)

        case BSD2.csops, BSD2.csopsAudittoken:
            call.set("\(n == BSD2.csops ? "csops" : "csops_audittoken")(pid=\(int(0)), ops=\(int(1)), addr=\(hx(a[2])), size=\(a[3]))")
            return .value(try csopsCall(n == BSD2.csopsAudittoken, a, &call, mem))

        case BSD2.procInfo:
            call.set("proc_info(callnum=\(int(0)), pid=\(int(1)), flavor=\(int(2)), arg=\(hx(a[3])), buffer=\(hx(a[4])), "
                + "buffersize=\(int(5)))")
            trace("note: proc_info call \(int(0)) flavor \(int(2)) is not supported")
            throw Failure(errno: Errno.ENOTSUP)

        case BSD2.getdirentries64:
            return .value(try getdirentries64(a, &call, mem))

        case BSD2.kevent, BSD2.kevent64, BSD2.keventQos, BSD2.keventId:
            return .value(try withEvents { try keventCall(n, a, &call, mem) })

        case BSD2.kqueueWorkloopCtl:
            return .value(try withEvents { try kqueueWorkloopCtl(a, &call, mem) })

        case WorkIntervalABI.syscall:
            return .value(try workIntervalCtl(a, &call, mem))

        case BSD2.bsdthreadCreate:
            return try bsdthreadCreate(a, &call, mem)
        case BSD2.bsdthreadTerminate:
            return try bsdthreadTerminate(a, &call, mem)
        case BSD2.bsdthreadCtl:
            return .value(try bsdthreadCtl(a, &call, mem))

        case BSD2.kill, BSD2.pthreadKill:
            let isKill = n == BSD2.kill
            let sig = int(1)
            let target = UInt32(truncatingIfNeeded: a[0])
            call.set(isKill ? "kill(pid=\(int(0)), sig=\(sig), posix=\(int(2)))" : "__pthread_kill(thread=\(hx(target)), sig=\(sig))")
            if isKill {
                guard int(0) == pid || int(0) == 0 || int(0) == -1 || int(0) == -pid else { throw Failure(errno: Errno.ESRCH) }
            } else {
                guard let thread = threadsByPort[target] else { throw Failure(errno: Errno.ESRCH) }
                guard (0...31).contains(sig) else { throw Failure(errno: Errno.EINVAL) }
                if sig == 0 { return .value(0) }
                if thread !== current {
                    trace("note: __pthread_kill(\(sig)) to \(thread): no cross-thread signal delivery in stage 4a; dropped")
                    call += " [dropped]"
                    return .value(0)
                }
            }
            guard (0...31).contains(sig) else { throw Failure(errno: Errno.EINVAL) }
            if sig == 0 { return .value(0) }
            return signalSelf(sig, &call)

        case BSD2.sigsuspend, BSD2.sigsuspendNocancel:
            let mask = UInt32(truncatingIfNeeded: a[0])
            call.set("\(n == BSD2.sigsuspend ? "sigsuspend" : "__sigsuspend_nocancel")(mask=\(hx(mask)))")
            let old = extended.signalMask
            extended.signalMask = mask & ~SignalConstant.unblockable
            var result = WaitResult.woken
            current.snapshotSigsuspendSavedMask = old
            defer { current.snapshotSigsuspendSavedMask = nil }
            while extended.pendingSignals & ~extended.signalMask == 0 {
                result = signalWaiters.wait(on: lock, deadline: nil)
                if result == .interrupted { break }
            }
            extended.pendingSignals &= extended.signalMask
            extended.signalMask = old
            call += " [\(result == .interrupted ? "interrupted" : "woken")]"
            throw Failure(errno: Self.EINTR)

        case BSD2.disableThreadsignal:
            call.set("__disable_threadsignal(\(int(0)))")
            return .value(0)

        case BSD2.semwaitSignal, BSD2.semwaitSignalNocancel:
            call.set("__semwait_signal(cond=\(hx(UInt32(truncatingIfNeeded: a[0]))), mutex=\(hx(UInt32(truncatingIfNeeded: a[1]))), "
                + "timeout=\(int(2)), relative=\(int(3)), sec=\(Int64(bitPattern: a[4])), nsec=\(int(5)))")
            return .value(try semwaitSignal(a, &call))

        case let n where BSD2.psynchWaits[n] != nil:
            let name = BSD2.psynchWaits[n]!
            call.set("\(name)(\(hx(a[0])), \(hx(a[1])), \(hx(a[2])), \(hx(a[3])), \(hx(a[4])))")
            trace("DEADLOCK?: \(name) on \(hx(a[0])) would block the only thread; returning ENOTSUP")
            throw Failure(errno: Errno.ENOTSUP)

        case let n where BSD2.psynchWakes[n] != nil:
            call.set("\(BSD2.psynchWakes[n]!)(\(hx(a[0])), \(hx(a[1])), \(hx(a[2])), \(hx(a[3])), \(hx(a[4])))")
            call += " [no waiters on one thread]"
            return .value(0)

        case BSD2.workqOpen:
            call.set("workq_open()")
            guard threadRegistration != nil else { throw Failure(errno: Errno.EINVAL) }
            withEvents { workqueue.isOpen = true }
            return .value(0)
        case BSD2.workqKernreturn:
            return try withEvents { try workqKernreturn(a, &call, mem) }

        case BSD2.statfs64, BSD2.fstatfs64:
            return .value(try statfsCall(n, a, &call, mem))

        case BSD2.threadSelfid:
            call.set("thread_selfid()")
            return .value(current.threadID)

        case BSD2.getppid:
            call.set("getppid()")
            return .value(1)

        case BSD2.umask:
            call.set("umask(0o\(String(a[0] & 0o777, radix: 8)))")
            let old = extended.umask
            extended.umask = UInt16(a[0] & 0o777)
            return .value(UInt64(old))

        case BSD2.getrusage:
            call.set("getrusage(who=\(int(0)), rusage=\(hx(a[1])))")
            guard int(0) == 0 || int(0) == -1 else { throw Failure(errno: Errno.EINVAL) }
            var b = [UInt8](repeating: 0, count: 144)
            if int(0) == 0, let times = processCPUTimes?() {
                b.putLE(Int64(times.user / 1_000_000_000), at: 0)
                b.putLE(Int32(times.user / 1000 % 1_000_000), at: 8)
                b.putLE(Int64(times.system / 1_000_000_000), at: 16)
                b.putLE(Int32(times.system / 1000 % 1_000_000), at: 24)
            }
            try mem.write(va: a[1], bytes: b)
            return .value(0)

        case BSD2.threadSelfusage:
            call.set("thread_selfusage()")
            return .value(Self.threadSelfUsage(context: current, counterFrequency: counterFrequency))

        case BSD2.access, BSD2.faccessat:
            let isAt = n == BSD2.faccessat
            let path = try resolveAtPath(isAt ? int(0) : Self.atFDCWD, isAt ? a[1] : a[0], mem)
            let mode = isAt ? int(2) : int(1)
            call.set(isAt ? "faccessat(\(int(0)), \"\(path)\", mode=\(mode), flag=\(hx(a[3])))" : "access(\"\(path)\", mode=\(mode))")
            let follow = !isAt || int(3) & Self.atSymlinkNofollow == 0
            let st = try statUnlocked(path, followSymlinks: follow)
            if let denied = accessDenied(st, path: path, read: mode & 4 != 0, write: mode & 2 != 0, execute: mode & 1 != 0) {
                throw Failure(errno: denied)
            }
            return .value(0)

        case BSD2.getxattr, BSD2.fgetxattr, BSD2.setxattr, BSD2.fsetxattr,
             BSD2.removexattr, BSD2.fremovexattr, BSD2.listxattr, BSD2.flistxattr:
            return .value(try extendedAttributeCall(n, a, &call, mem))

        case BSD2.gettid:
            call.set("gettid(uidp=\(hx(a[0])), gidp=\(hx(a[1])))")
            throw Failure(errno: Errno.ESRCH)

        case BSD2.fstatat, BSD2.fstatat64:
            let path = try resolveAtPath(int(0), a[1], mem)
            call.set("fstatat64(\(int(0)), \"\(path)\", buf=\(hx(a[2])), flag=\(hx(a[3])))")
            let st = try statUnlocked(path, followSymlinks: int(3) & Self.atSymlinkNofollow == 0)
            try mem.write(va: a[2], bytes: st.encodedStat64())
            return .value(0)

        case BSD2.openat:
            let path = try resolveAtPath(int(0), a[1], mem)
            call.set("openat(\(int(0)), \"\(path)\", flags=\(openFlagsText(int(2))), mode=0o\(String(a[3] & 0o7777, radix: 8)))")
            let newFD = try openUnlocked(path, flags: int(2), mode: UInt16(truncatingIfNeeded: a[3]))
            extended.directoryCursors[newFD] = nil
            return .value(UInt64(UInt32(bitPattern: newFD)))

        case BSD2.openDprotectedNp, BSD2.openatDprotectedNp:
            let at = n == BSD2.openatDprotectedNp
            let path = try resolveAtPath(at ? int(0) : Self.atFDCWD, at ? a[1] : a[0], mem)
            let base = at ? 2 : 1
            let flags = int(base), dpclass = int(base + 1), dpflags = int(base + 2)
            call.set("\(at ? "openat_dprotected_np(\(int(0)), " : "open_dprotected_np(")\"\(path)\", "
                + "flags=\(openFlagsText(flags)), class=\(dpclass), dpflags=\(hx(UInt64(UInt32(bitPattern: dpflags)))), "
                + "mode=0o\(String(a[base + 3] & 0o7777, radix: 8)))")
            try checkDataProtectionOpen(flags: flags, dpflags: dpflags)
            let created = (try? fileSystem.stat(path, followSymlinks: true)) == nil
            let newFD = try fileSystem.open(path, flags: flags, mode: UInt16(truncatingIfNeeded: a[base + 3]))
            if created { noteCreatedWithClass(newFD, dpclass) }
            extended.directoryCursors[newFD] = nil
            return .value(UInt64(UInt32(bitPattern: newFD)))

        case BSD2.terminateWithPayload:
            let reason = a[5] == 0 ? "" : ((try? readString(a[5], length: 4096, mem)) ?? "<unreadable>")
            call.set("terminate_with_payload(pid=\(int(0)), namespace=\(int(1)), code=\(hx(a[2])))")
            return .fatal(Self.abortExitStatus, "terminate_with_payload: namespace \(int(1)) code \(hx(a[2])): \(reason)")

        case BSD2.osFaultWithPayload:
            let reason = a[4] == 0 ? "" : ((try? readString(a[4], length: 4096, mem)) ?? "<unreadable>")
            call.set("os_fault_with_payload(namespace=\(int(0)), code=\(hx(a[1]))) [\(reason)]")
            return .value(0)

        default:
            return nil
        }
    }

    private func semwaitSignal(_ a: [UInt64], _ call: inout CallText) throws -> UInt64 {
        let cond = UInt32(truncatingIfNeeded: a[0]), mutex = UInt32(truncatingIfNeeded: a[1])
        var deadline: UInt64?
        if Int32(truncatingIfNeeded: a[2]) != 0 {
            let sec = Int64(bitPattern: a[4]), nsec = Int64(Int32(truncatingIfNeeded: a[5]))
            guard sec >= 0, (0..<1_000_000_000).contains(nsec) else { throw Failure(errno: Errno.EINVAL) }
            var ns = sec.multipliedReportingOverflow(by: 1_000_000_000).overflow ? Int64.max : sec * 1_000_000_000 + nsec
            if Int32(truncatingIfNeeded: a[3]) == 0 {
                let w = wallClock()
                ns -= w.seconds * 1_000_000_000 + w.nanoseconds
            }
            deadline = KernelClock.deadline(afterNanoseconds: UInt64(max(0, ns)))
        }
        if mutex != 0 {
            guard let m = semaphore(named: mutex) else { throw Failure(errno: Errno.EINVAL) }
            m.signal()
        }
        let result: WaitResult
        if cond != 0 {
            guard let c = semaphore(named: cond) else { throw Failure(errno: Errno.EINVAL) }
            switch c.wait(lock: lock, deadline: deadline) {
            case KernReturn.success: return 0
            case KernReturn.operationTimedOut: result = .timedOut
            default: result = .interrupted
            }
        } else {
            result = WaitQueue().wait(on: lock, deadline: deadline)
        }
        switch result {
        case .timedOut: throw Failure(errno: Self.ETIMEDOUT)
        case .interrupted: throw Failure(errno: Self.EINTR)
        case .woken: return 0
        }
    }

    struct VolumeSpace: Equatable {
        var blocks: UInt64
        var available: UInt64
        var files: UInt64
        var freeFiles: UInt64
        static let fallback = VolumeSpace(blocks: 1 << 24, available: 1 << 23, files: 1 << 20, freeFiles: 1 << 19)
    }

    static func volumeSpaceHostPath(mountPoint: String, prefixes: [DarwinFileSystem.Prefix]) -> String? {
        let onVolume = prefixes.filter { $0.volumeMountPoint == mountPoint }
        return (onVolume.first(where: \.writable) ?? onVolume.first(where: { $0.guestPath == mountPoint }) ?? onVolume.first)?.hostPath
    }

    func volumeSpace(mountPoint: String) -> VolumeSpace {
        let host = Self.volumeSpaceHostPath(mountPoint: mountPoint, prefixes: fileSystem.prefixes) ?? "/"
        var vfs = statvfs()
        guard statvfs(host, &vfs) == 0, vfs.f_frsize > 0 else { return .fallback }
        let unit = UInt64(vfs.f_frsize)
        return VolumeSpace(blocks: UInt64(vfs.f_blocks).multipliedReportingOverflow(by: unit).partialValue / 4096,
                           available: UInt64(vfs.f_bavail).multipliedReportingOverflow(by: unit).partialValue / 4096,
                           files: UInt64(vfs.f_files), freeFiles: UInt64(vfs.f_ffree))
    }

    func statfs64Bytes(guestPath: String, dev: UInt32) -> [UInt8] {
        let prefix = fileSystem.prefixes
            .filter { guestPath == $0.guestPath || guestPath.hasPrefix($0.guestPath == "/" ? "/" : $0.guestPath + "/") }
            .max { $0.guestPath.count < $1.guestPath.count }
        let mountPoint = prefix?.volumeMountPoint ?? "/"
        let readOnly = !(prefix?.writable ?? false)
        let space = volumeSpace(mountPoint: mountPoint)
        let (blocks, free, files, ffree) = (space.blocks, space.available, space.files, space.freeFiles)
        var b = [UInt8](repeating: 0, count: 2168)
        b.putLE(UInt32(4096), at: 0)
        b.putLE(Int32(1 << 20), at: 4)
        b.putLE(blocks, at: 8)
        b.putLE(free, at: 16)
        b.putLE(free, at: 24)
        b.putLE(files, at: 32)
        b.putLE(ffree, at: 40)
        let fsDev = dev != 0 ? dev : (try? fileSystem.stat(prefix?.guestPath ?? "/System", followSymlinks: true).dev) ?? 1
        b.putLE(fsDev, at: 48)
        b.putLE(UInt32(0x1A), at: 52)
        b.putLE(UInt32(0), at: 56)
        b.putLE(UInt32(0x1A), at: 60)
        b.putLE(UInt32((readOnly ? 0x1 : 0) | 0x1000 | (mountPoint == "/" ? 0x4000 : 0) | 0x8000 | 0x80_0000), at: 64)
        b.putLE(UInt32(1), at: 68)
        b.put(Array("apfs".utf8), at: 72)
        b.put(Array(mountPoint.utf8.prefix(1023)), at: 88)
        b.put(Array("swiftcode-vfs".utf8), at: 1112)
        return b
    }

    func fileSystemStatList(buffer: UInt64, size: UInt64, _ call: inout CallText,
                            _ mem: any KernelGuestMemory) throws -> UInt64 {
        var mounts: [(path: String, dev: UInt32)] = []
        if let root = try? fileSystem.stat("/", followSymlinks: true) { mounts.append(("/", root.dev)) }
        for prefix in fileSystem.prefixes where prefix.guestPath != "/" && prefix.mountPoint == nil {
            guard let st = try? fileSystem.stat(prefix.guestPath, followSymlinks: true), st.isDirectory,
                  !mounts.contains(where: { $0.path == prefix.guestPath }) else { continue }
            mounts.append((prefix.guestPath, st.dev))
        }
        let entrySize = 2168
        guard buffer != 0 else {
            call += " [\(mounts.count) volumes]"
            return UInt64(mounts.count)
        }
        let count = min(mounts.count, Int(min(size, 1 << 24)) / entrySize)
        var out: [UInt8] = []
        out.reserveCapacity(count * entrySize)
        for m in mounts.prefix(count) { out += statfs64Bytes(guestPath: m.path, dev: m.dev) }
        if !out.isEmpty { try mem.write(va: buffer, bytes: out) }
        call += " [\(mounts.prefix(count).map(\.path).joined(separator: ", "))]"
        return UInt64(count)
    }

    private func signalSelf(_ sig: Int32, _ call: inout CallText) -> BSDResult {
        let names: [Int32: String] = [1: "SIGHUP", 2: "SIGINT", 3: "SIGQUIT", 4: "SIGILL", 5: "SIGTRAP", 6: "SIGABRT",
                                      8: "SIGFPE", 9: "SIGKILL", 10: "SIGBUS", 11: "SIGSEGV", 13: "SIGPIPE", 14: "SIGALRM",
                                      15: "SIGTERM"]
        let name = names[sig] ?? "signal \(sig)"
        let handler = extended.signalActions[sig]?.handler ?? 0
        let ignoredByDefault: Set<Int32> = [16, 18, 20, 23, 28, 29]
        if handler == 1 || (handler == 0 && ignoredByDefault.contains(sig)) {
            call += " [\(name) ignored]"
            return .value(0)
        }
        if handler == 0 || sig == SignalConstant.sigkill || sig == SignalConstant.sigstop {
            call += " [\(name): default action, the guest terminates]"
            return .fatal(128 + sig, "guest terminated by \(name) (no signal delivery yet; default action)")
        }
        trace("note: \(name) has a handler at \(hx(handler)); signal delivery is not implemented, dropped")
        call += " [\(name) caught by \(hx(handler)); dropped]"
        return .value(0)
    }

    private func vectoredIO(write: Bool, _ a: [UInt64], _ call: inout CallText, _ mem: any KernelGuestMemory) throws -> UInt64 {
        let fd = Int32(truncatingIfNeeded: a[0])
        let count = Int32(truncatingIfNeeded: a[2])
        call.set("\(write ? "writev" : "readv")(fd=\(fd), iov=\(hx(a[1])), iovcnt=\(count))")
        guard count > 0, count <= 1024 else { throw Failure(errno: Errno.EINVAL) }
        let raw = try mem.read(va: a[1], count: 16 * Int(count))
        var iov: [(base: UInt64, length: UInt64)] = []
        var total: UInt64 = 0
        for i in 0..<Int(count) {
            let base = raw.readLE(UInt64.self, at: 16 * i), length = raw.readLE(UInt64.self, at: 16 * i + 8)
            total += length
            guard total <= UInt64(Int32.max) else { throw Failure(errno: Errno.EINVAL) }
            iov.append((base, length))
        }
        if write {
            var bytes: [UInt8] = []
            for v in iov where v.length > 0 { bytes += try mem.read(va: v.base, count: Int(v.length)) }
            return UInt64(try fileSystem.write(fd, bytes))
        }
        let data = try fileSystem.read(fd, count: Int(total))
        var offset = 0
        for v in iov where offset < data.count && v.length > 0 {
            let n = min(Int(v.length), data.count - offset)
            try mem.write(va: v.base, bytes: Array(data[offset..<(offset + n)]))
            offset += n
        }
        return UInt64(data.count)
    }

    private func sigaction(_ a: [UInt64], _ call: inout CallText, _ mem: any KernelGuestMemory) throws -> UInt64 {
        let signum = Int32(truncatingIfNeeded: a[0])
        call.set("sigaction(\(signum), nsa=\(hx(a[1])), osa=\(hx(a[2])))")
        guard (1...31).contains(signum) else { throw Failure(errno: Errno.EINVAL) }
        let old = extended.signalActions[signum] ?? ExtendedBSDState.SignalAction()
        if a[1] != 0 {
            guard signum != SignalConstant.sigkill, signum != SignalConstant.sigstop else {
                throw Failure(errno: Errno.EINVAL)
            }
            let b = try mem.read(va: a[1], count: 24)
            let action = ExtendedBSDState.SignalAction(handler: b.readLE(UInt64.self, at: 0),
                                                       mask: b.readLE(UInt32.self, at: 16),
                                                       flags: b.readLE(Int32.self, at: 20))
            extended.signalActions[signum] = action
            if action.handler == 1 || (action.handler == 0 && Signal.ignoredByDefault.contains(signum)) {
                extended.pendingSignals &= ~(1 << UInt32(signum - 1))
            }
            call += " [handler \(hx(action.handler)) flags \(hx(UInt32(bitPattern: action.flags)))]"
        }
        if a[2] != 0 {
            var b: [UInt8] = []
            b.appendLE(old.handler)
            b.appendLE(old.mask)
            b.appendLE(old.flags)
            try mem.write(va: a[2], bytes: b)
        }
        return 0
    }

    func resolveAtPath(_ dirfd: Int32, _ pointer: UInt64, _ mem: any KernelGuestMemory) throws -> String {
        let path = try readPath(pointer, mem)
        if path.hasPrefix("/") || dirfd == Self.atFDCWD { return path }
        guard !path.isEmpty else { throw Failure(errno: Errno.ENOENT) }
        let base = try fileSystem.path(for: dirfd)
        guard try fileSystem.fstat(dirfd).isDirectory else { throw Failure(errno: Errno.ENOTDIR) }
        return base == "/" ? "/" + path : base + "/" + path
    }

    func ioPolicyCall(_ a: [UInt64], thread: UInt64, _ call: inout CallText, _ mem: any KernelGuestMemory) throws -> UInt64 {
        let cmd = Int32(truncatingIfNeeded: a[0])
        let raw = try mem.read(va: a[1], count: 12)
        let scope = raw.readLE(Int32.self, at: 0), iotype = raw.readLE(Int32.self, at: 4)
        let policy = raw.readLE(Int32.self, at: 8)
        call.set("iopolicysys(cmd=\(cmd), scope=\(scope), iotype=\(iotype), policy=\(policy))")
        guard (0...1).contains(cmd), (0...2).contains(scope), (0...15).contains(iotype) else {
            throw Failure(errno: Errno.EINVAL)
        }
        if cmd == 0 {
            extended.ioPolicyStore.withLock { p in
                switch scope {
                case 0: p.process[iotype] = policy
                case 1: p.thread[thread, default: [:]][iotype] = policy
                default: p.background = policy
                }
            }
            return 0
        }
        let value: Int32 = extended.ioPolicyStore.withLock { p in
            switch scope {
            case 0: p.process[iotype] ?? 0
            case 1: p.thread[thread]?[iotype] ?? 0
            default: p.background
            }
        }
        try mem.write(va: a[1] + 8, bytes: le32(UInt32(bitPattern: value)))
        call += " [\(value)]"
        return 0
    }

    func statfsCall(_ n: Int, _ a: [UInt64], _ call: inout CallText, _ mem: any KernelGuestMemory) throws -> UInt64 {
        let path: String
        if n == BSD2.statfs64 {
            path = try fileSystem.realpath(try readPath(a[0], mem))
            call.set("statfs64(\"\(path)\", buf=\(hx(a[1])))")
        } else {
            path = try fileSystem.path(for: Int32(truncatingIfNeeded: a[0]))
            call.set("fstatfs64(fd=\(Int32(truncatingIfNeeded: a[0])), buf=\(hx(a[1]))) [\(path)]")
        }
        let st = n == BSD2.statfs64 ? try fileSystem.stat(path, followSymlinks: true) : try fileSystem.fstat(Int32(truncatingIfNeeded: a[0]))
        try mem.write(va: a[1], bytes: statfs64Bytes(guestPath: path, dev: st.dev))
        return 0
    }

    func getdirentries64(_ a: [UInt64], _ call: inout CallText, _ mem: any KernelGuestMemory) throws -> UInt64 {
        let fd = Int32(truncatingIfNeeded: a[0])
        let bufferSize = Int(min(a[2], 1 << 20))
        call.set("getdirentries64(fd=\(fd), buf=\(hx(a[1])), bufsize=\(a[2]), position=\(hx(a[3])))")
        let file = try fileSystem.file(for: fd)
        guard file.isDirectory else { throw Failure(errno: Errno.ENOTDIR) }
        let extendedBuffer = bufferSize >= 1024
        let capacity = extendedBuffer ? bufferSize - 4 : bufferSize
        var taken: (out: [UInt8], start: Int, next: Int, eof: Bool)?
        for _ in 0..<4 {
            try ensureDirectoryCursor(fd, file)
            taken = extended.directoryCursors.withLock { table -> (out: [UInt8], start: Int, next: Int, eof: Bool)? in
                guard var cursor = table[fd], cursor.file === file else { return nil }
                let start = cursor.next
                var out: [UInt8] = []
                while cursor.next < cursor.entries.count {
                    let e = cursor.entries[cursor.next]
                    let name = Array(e.name.utf8)
                    let length = (21 + name.count + 1 + 7) & ~7
                    if out.count + length > capacity { break }
                    var r: [UInt8] = []
                    r.appendLE(e.ino)
                    r.appendLE(UInt64(cursor.next + 1))
                    r.appendLE(UInt16(length))
                    r.appendLE(UInt16(name.count))
                    r.append(e.type)
                    r += name
                    r += [UInt8](repeating: 0, count: length - r.count)
                    out += r
                    cursor.next += 1
                }
                if out.isEmpty && cursor.next < cursor.entries.count { return (out, start, -1, false) }
                table[fd] = cursor
                return (out, start, cursor.next, cursor.next >= cursor.entries.count)
            }
            if taken != nil { break }
        }
        guard let (out, start, next, eof) = taken else { throw Failure(errno: Errno.EBADF) }
        if next < 0 { throw Failure(errno: Errno.EINVAL) }
        if !out.isEmpty { try mem.write(va: a[1], bytes: out) }
        if extendedBuffer {
            try writeU32(a[1] + UInt64(bufferSize - 4), eof ? 1 : 0, mem)
        }
        if a[3] != 0 { try writeU64(a[3], UInt64(start), mem) }
        call += " [\(next - start) entries]"
        return UInt64(out.count)
    }

    func ensureDirectoryCursor(_ fd: Int32, _ file: GuestFile) throws {
        if let c = extended.directoryCursors[fd], c.file === file { return }
        let entries = try listDirectory(fd: fd, file: file)
        extended.directoryCursors.withLock { table in
            if table[fd].map({ $0.file !== file }) ?? true { table[fd] = .init(file: file, entries: entries) }
        }
    }

    func listDirectory(fd: Int32, file: GuestFile) throws -> [(name: String, ino: UInt64, type: UInt8)] {
        let selfStat = try fileSystem.fstat(fd)
        let fileSystem = self.fileSystem
        return try lock.unlocked { try Self.listDirectory(file: file, selfStat: selfStat, fileSystem: fileSystem) }
    }

    private static func listDirectory(file: GuestFile, selfStat: DarwinStat,
                                      fileSystem: DarwinFileSystem) throws -> [(name: String, ino: UInt64, type: UInt8)] {
        let dir = file.guestPath
        guard let names = GuestPath.hostDirectoryNames(file.hostPath) else {
            throw Failure(errno: Errno.EIO)
        }
        var entries: [(name: String, ino: UInt64, type: UInt8)] = []
        entries.append((".", selfStat.ino, 4))
        let parent = GuestPath.deletingLastComponent(dir)
        let parentIno = (try? fileSystem.stat(parent.isEmpty ? "/" : parent, followSymlinks: true).ino) ?? selfStat.ino
        entries.append(("..", parentIno, 4))
        for name in names.sorted() {
            guard let st = try? fileSystem.statEntry(inDirectory: dir, name: name) else { continue }
            let type: UInt8 = switch st.fileType {
            case DarwinStat.S_IFDIR: 4
            case DarwinStat.S_IFREG: 8
            case DarwinStat.S_IFLNK: 10
            case DarwinStat.S_IFCHR: 2
            case DarwinStat.S_IFBLK: 6
            case DarwinStat.S_IFIFO: 1
            case DarwinStat.S_IFSOCK: 12
            default: 0
            }
            entries.append((name, st.ino, type))
        }
        return entries
    }
}

extension DarwinKernel {
    func accessDenied(_ st: DarwinStat, path: String, read: Bool, write: Bool, execute: Bool) -> Int32? {
        if write && !fileSystem.writable(guestPath: path) && st.fileType != DarwinStat.S_IFCHR { return 30 }
        let bits: UInt16
        if st.uid == DarwinFileSystem.guestUID { bits = (st.mode >> 6) & 7 }
        else if [DarwinFileSystem.guestGID, 12, 80].contains(st.gid) { bits = (st.mode >> 3) & 7 }
        else { bits = st.mode & 7 }
        if (read && bits & 4 == 0) || (write && bits & 2 == 0) || (execute && bits & 1 == 0) { return 13 }
        return nil
    }
}

extension DarwinKernel {
    public static func hostThreadCPUNanoseconds() -> UInt64 {
        var t = timespec()
        guard clock_gettime(CLOCK_THREAD_CPUTIME_ID, &t) == 0 else { return 0 }
        return UInt64(t.tv_sec) * 1_000_000_000 + UInt64(t.tv_nsec)
    }

    static func threadSelfUsage(context: ThreadContext, counterFrequency: UInt64) -> UInt64 {
        let now = hostThreadCPUNanoseconds()
        let ns = now >= context.hostCPUBaseNanoseconds ? now - context.hostCPUBaseNanoseconds : now
        let f = counterFrequency == 0 ? 1_000_000_000 : counterFrequency
        return UInt64((Double(ns) * Double(f) / 1e9).rounded(.down))
    }
}
