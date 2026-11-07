import Foundation
import YcodeDarwinABI

struct SpawnAttributes: Equatable {
    var flags: UInt16 = 0
    var sigdefault: UInt32 = 0
    var sigmask: UInt32 = 0
    var pgroup: Int32 = 0
    var binprefs: [UInt32] = [0, 0, 0, 0]
    var subcpuprefs: [UInt32] = [UInt32.max, UInt32.max, UInt32.max, UInt32.max]
    var pcontrol: UInt32 = 0
    var apptype: UInt32 = 0
    var qosClamp: UInt64 = 0
    var darwinRole: UInt32 = 0

    static let blockSize = 192

    init() {}

    init(decoding b: [UInt8]) {
        flags = b.readLE(UInt16.self, at: 0)
        sigdefault = b.readLE(UInt32.self, at: 4)
        sigmask = b.readLE(UInt32.self, at: 8)
        pgroup = b.readLE(Int32.self, at: 12)
        binprefs = (0..<4).map { b.readLE(UInt32.self, at: 16 + 4 * $0) }
        pcontrol = b.readLE(UInt32.self, at: 32)
        apptype = b.readLE(UInt32.self, at: 36)
        qosClamp = b.readLE(UInt64.self, at: 80)
        darwinRole = b.readLE(UInt32.self, at: 88)
        subcpuprefs = (0..<4).map { b.readLE(UInt32.self, at: 112 + 4 * $0) }
    }
}

enum SpawnFlag {
    static let resetIDs: UInt16 = 0x0001
    static let setPGroup: UInt16 = 0x0002
    static let setSigDefault: UInt16 = 0x0004
    static let setSigMask: UInt16 = 0x0008
    static let setExec: UInt16 = 0x0040
    static let startSuspended: UInt16 = 0x0080
    static let disableASLR: UInt16 = 0x0100
    static let nanoAllocator: UInt16 = 0x0200
    static let setSID: UInt16 = 0x0400
    static let cloexecDefault: UInt16 = 0x4000
}

struct SpawnFileAction: Equatable {
    enum Kind: Int32 {
        case open = 0, close = 1, dup2 = 2, inherit = 3, fileportDup2 = 4, chdir = 5, fchdir = 6
    }

    var type: Int32
    var fd: Int32
    var oflag: Int32 = 0
    var mode: UInt16 = 0
    var newfd: Int32 = 0
    var path: String = ""

    static let recordSize = 1040

    init(type: Int32, fd: Int32, oflag: Int32 = 0, mode: UInt16 = 0, newfd: Int32 = 0, path: String = "") {
        self.type = type
        self.fd = fd
        self.oflag = oflag
        self.mode = mode
        self.newfd = newfd
        self.path = path
    }

    init(decoding b: [UInt8], at o: Int) {
        type = b.readLE(Int32.self, at: o)
        fd = b.readLE(Int32.self, at: o + 4)
        func cString(_ start: Int, _ max: Int) -> String {
            let bytes = b[(o + start)..<(o + start + max)]
            return String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
        switch Kind(rawValue: type) {
        case .open:
            oflag = b.readLE(Int32.self, at: o + 8)
            mode = b.readLE(UInt16.self, at: o + 12)
            path = cString(14, 1024)
        case .dup2, .fileportDup2:
            newfd = b.readLE(Int32.self, at: o + 8)
        case .chdir:
            path = cString(8, 1024)
        default:
            break
        }
    }
}

struct SpawnRequest {
    var path: String
    var argv: [String]
    var envp: [String]
    var attributes = SpawnAttributes()
    var fileActions: [SpawnFileAction] = []
    var portActions: [SpawnPortAction] = []
    var setExec: Bool { attributes.flags & SpawnFlag.setExec != 0 }
}

extension DarwinKernel {
    static let argumentSpaceLimit = 1 << 20
    static let E2BIG: Int32 = 7
    static let ENOEXEC: Int32 = 8
    static let EBADARCH: Int32 = 86

    func posixSpawn(_ me: DarwinProcess, _ a: [UInt64], _ call: inout CallText, _ mem: any KernelGuestMemory) throws -> BSDResult {
        let path = try readPath(a[1], mem)
        call.set("posix_spawn(pid=\(hx(a[0])), \"\(path)\", adesc=\(hx(a[2])), argv=\(hx(a[3])), envp=\(hx(a[4])))")
        var request = SpawnRequest(path: path, argv: [], envp: [])
        if a[2] != 0 {
            let d = try mem.read(va: a[2], count: 144)
            func pair(_ i: Int) -> (size: UInt64, pointer: UInt64) {
                (d.readLE(UInt64.self, at: 16 * i), d.readLE(UInt64.self, at: 16 * i + 8))
            }
            let attr = pair(0)
            if attr.size != 0 {
                request.attributes = SpawnAttributes(decoding: try mem.read(va: attr.pointer, count: SpawnAttributes.blockSize))
            }
            let setExec = request.attributes.flags & SpawnFlag.setExec != 0
            let fa = pair(1)
            if fa.size != 0 {
                let nofile = UInt64(extended.rlimits[RLimit.nofile]?.cur ?? 256)
                let minimum = UInt64(8 + SpawnFileAction.recordSize)
                guard fa.size >= minimum, fa.size <= 8 + UInt64(SpawnFileAction.recordSize) * nofile else {
                    throw Failure(errno: Errno.EINVAL)
                }
                let b = try mem.read(va: fa.pointer, count: Int(fa.size))
                let count = b.readLE(Int32.self, at: 4)
                guard count >= 0, fa.size == 8 + UInt64(SpawnFileAction.recordSize) * UInt64(count) else {
                    throw Failure(errno: Errno.EINVAL)
                }
                request.fileActions = (0..<Int(count)).map { SpawnFileAction(decoding: b, at: 8 + $0 * SpawnFileAction.recordSize) }
            }
            let pa = pair(2)
            if pa.size != 0 {
                guard pa.size >= 8 + UInt64(SpawnPortAction.recordSize), pa.size <= Self.pageSize else {
                    throw Failure(errno: Errno.EINVAL)
                }
                let b = try mem.read(va: pa.pointer, count: Int(pa.size))
                let count = b.readLE(Int32.self, at: 4)
                guard count >= 0, pa.size == 8 + UInt64(SpawnPortAction.recordSize) * UInt64(count) else {
                    throw Failure(errno: Errno.EINVAL)
                }
                request.portActions = try SpawnPortAction.parseBlock(b)
            }
            let persona = pair(5)
            if persona.size != 0 {
                guard persona.size == 88 else { throw Failure(errno: Errno.ERANGE) }
                if setExec { throw Failure(errno: Errno.ENOTSUP) }
            }
            let cred = pair(6)
            if cred.size != 0 {
                guard cred.size == 340 else { throw Failure(errno: Errno.ERANGE) }
                if setExec { throw Failure(errno: Errno.ENOTSUP) }
                guard DarwinFileSystem.guestUID == 0 else { throw Failure(errno: Errno.EPERM) }
            }
        }
        if request.attributes.apptype & 0xF00 == 0x700 { throw Failure(errno: Errno.EPERM) }
        var budget = Self.argumentSpaceLimit - (path.utf8.count + 1)
        request.argv = try readStringArray(a[3], budget: &budget, mem)
        request.envp = try readStringArray(a[4], budget: &budget, mem)
        call += " [\(request.setExec ? "SETEXEC " : "")argv \(request.argv.count) envp \(request.envp.count) "
            + "file actions \(request.fileActions.count) port actions \(request.portActions.count) "
            + "flags \(hx(request.attributes.flags))]"
        if request.setExec { return try execImage(me, request, &call) }
        let child = try spawnChild(me, request)
        call += " [pid \(child)]"
        if a[0] != 0 { try? writeU32(a[0], UInt32(bitPattern: child), mem) }
        return .value(0)
    }

    func execve(_ me: DarwinProcess, _ n: Int, _ a: [UInt64], _ call: inout CallText, _ mem: any KernelGuestMemory) throws -> BSDResult {
        let path = try readPath(a[0], mem)
        call.set("\(n == ProcBSD.execve ? "execve" : "__mac_execve")(\"\(path)\", argv=\(hx(a[1])), envp=\(hx(a[2])))")
        var budget = Self.argumentSpaceLimit - (path.utf8.count + 1)
        var request = SpawnRequest(path: path, argv: try readStringArray(a[1], budget: &budget, mem),
                                   envp: try readStringArray(a[2], budget: &budget, mem))
        request.attributes.flags = SpawnFlag.setExec
        return try execImage(me, request, &call)
    }

    func readStringArray(_ va: UInt64, budget: inout Int, _ mem: any KernelGuestMemory) throws -> [String] {
        guard va != 0 else { return [] }
        var out: [String] = []
        var cursor = va
        while true {
            let p = try readU64(cursor, mem)
            budget -= 8
            if p == 0 { break }
            guard budget > 0 else { throw Failure(errno: Self.E2BIG) }
            let s = try readString(p, length: min(budget, 256 << 10) + 1, mem)
            budget -= s.utf8.count + 1
            guard budget >= 0 else { throw Failure(errno: Self.E2BIG) }
            out.append(s)
            cursor += 8
        }
        return out
    }

    func applyFileActions(_ actions: [SpawnFileAction], to fs: DarwinFileSystem) throws -> Set<Int32> {
        var marked = Set<Int32>()
        for action in actions {
            switch SpawnFileAction.Kind(rawValue: action.type) {
            case .open:
                let mode = action.mode & ~extended.umask & 0o777
                let opened = try fs.open(action.path, flags: action.oflag, mode: mode)
                if opened != action.fd {
                    do {
                        try fs.dup2(opened, action.fd)
                    } catch {
                        try? fs.close(opened)
                        throw error
                    }
                    try fs.close(opened)
                }
                marked.insert(action.fd)
            case .close:
                try fs.close(action.fd)
            case .dup2:
                try fs.dup2(action.fd, action.newfd)
                try fs.setCloseOnExec(action.newfd, false)
                marked.insert(action.newfd)
            case .inherit:
                try fs.setCloseOnExec(action.fd, false)
                marked.insert(action.fd)
            case .fileportDup2:
                guard let ipc = machIPC as? MachIPC,
                      let file = withPorts({ ipc.fileportFile(named: UInt32(bitPattern: action.fd)) }) else {
                    throw Failure(errno: Errno.EINVAL)
                }
                guard action.newfd >= 0, action.newfd < fs.maxDescriptors else { throw Failure(errno: Errno.EBADF) }
                try fs.install(file, closeOnExec: false, at: action.newfd)
                marked.insert(action.newfd)
            case .chdir:
                try fs.chdir(action.path)
            case .fchdir:
                try fs.fchdir(action.fd)
            case nil:
                throw Failure(errno: Errno.EINVAL)
            }
        }
        return marked
    }

    static func checkExecutable(hostPath: String, attributes: SpawnAttributes) throws {
        guard let handle = FileHandle(forReadingAtPath: hostPath) else { throw Failure(errno: Errno.ENOENT) }
        defer { try? handle.close() }
        func read(_ offset: UInt64, _ count: Int) -> [UInt8] {
            do {
                try handle.seek(toOffset: offset)
                return Array(try handle.read(upToCount: count) ?? Data())
            } catch {
                return []
            }
        }
        func be32(_ b: [UInt8], _ o: Int) -> UInt32 {
            UInt32(b[o]) << 24 | UInt32(b[o + 1]) << 16 | UInt32(b[o + 2]) << 8 | UInt32(b[o + 3])
        }
        let arm64: UInt32 = 0x0100_000C
        let head = read(0, 4096)
        guard head.count >= 8 else { throw Failure(errno: Self.ENOEXEC) }
        var sliceOffset: UInt64 = 0
        let fatMagic = be32(head, 0)
        if fatMagic == 0xCAFE_BABE || fatMagic == 0xCAFE_BABF {
            let is64 = fatMagic == 0xCAFE_BABF
            let count = Int(be32(head, 4))
            let entrySize = is64 ? 32 : 20
            guard count > 0, count < 64, head.count >= 8 + count * entrySize else { throw Failure(errno: Self.ENOEXEC) }
            var slices: [(cpu: UInt32, sub: UInt32, offset: UInt64)] = []
            for i in 0..<count {
                let o = 8 + i * entrySize
                let offset = is64 ? UInt64(be32(head, o + 8)) << 32 | UInt64(be32(head, o + 12)) : UInt64(be32(head, o + 8))
                slices.append((be32(head, o), be32(head, o + 4), offset))
            }
            var chosen: UInt64?
            if attributes.binprefs[0] != 0 {
                for (i, pref) in attributes.binprefs.enumerated() {
                    if pref == 0 { throw Failure(errno: Self.EBADARCH) }
                    if pref == UInt32.max { break }
                    if let s = slices.first(where: { $0.cpu == pref && Self.subtypeMatches(attributes.subcpuprefs[i], $0.sub) }) {
                        chosen = s.offset
                        break
                    }
                }
            }
            if chosen == nil { chosen = (slices.first { $0.cpu == arm64 && $0.sub & 0x00FF_FFFF <= 1 } ?? slices.first { $0.cpu == arm64 })?.offset }
            guard let chosen else { throw Failure(errno: Self.EBADARCH) }
            sliceOffset = chosen
        }
        let header = sliceOffset == 0 ? head : read(sliceOffset, 4096)
        guard header.count >= 32 else { throw Failure(errno: Self.ENOEXEC) }
        let magic = header.readLE(UInt32.self, at: 0)
        if magic == 0xFEED_FACE { throw Failure(errno: Self.EBADARCH) }
        guard magic == 0xFEED_FACF else { throw Failure(errno: Self.ENOEXEC) }
        let cpu = header.readLE(UInt32.self, at: 4), sub = header.readLE(UInt32.self, at: 8)
        guard cpu == arm64 else { throw Failure(errno: Self.EBADARCH) }
        guard sub & 0x00FF_FFFF <= 1 else { throw Failure(errno: Self.EBADARCH) }
        if sliceOffset == 0, attributes.binprefs[0] != 0 {
            var accepted = false
            for (i, pref) in attributes.binprefs.enumerated() {
                if pref == 0 { break }
                if pref == UInt32.max || (pref == cpu && Self.subtypeMatches(attributes.subcpuprefs[i], sub)) {
                    accepted = true
                    break
                }
            }
            guard accepted else { throw Failure(errno: Self.EBADARCH) }
        }
        guard header.readLE(UInt32.self, at: 12) == 2 else { throw Failure(errno: Self.ENOEXEC) }
        let ncmds = Int(header.readLE(UInt32.self, at: 16)), sizeofcmds = Int(header.readLE(UInt32.self, at: 20))
        let commands = 32 + sizeofcmds <= header.count ? header : read(sliceOffset, 32 + min(sizeofcmds, 1 << 20))
        var at = 32
        for _ in 0..<ncmds {
            guard at + 8 <= commands.count else { break }
            let cmd = commands.readLE(UInt32.self, at: at), size = Int(commands.readLE(UInt32.self, at: at + 4))
            if cmd == 0x32, at + 12 <= commands.count {
                let platform = commands.readLE(UInt32.self, at: at + 8)
                guard [7, 8, 9, 12].contains(platform) else { throw Failure(errno: Self.EBADARCH) }
            }
            guard size >= 8 else { break }
            at += size
        }
    }

    private static func subtypeMatches(_ pref: UInt32, _ sub: UInt32) -> Bool {
        pref == UInt32.max || pref & 0x00FF_FFFF == sub & 0x00FF_FFFF
    }

    func inheritProcessState(into k: DarwinKernel, attributes: SpawnAttributes, isExec: Bool) {
        k.sysctl = sysctl
        k.entropy = entropy
        k.sleep = sleep
        k.bootCounter = bootCounter
        k.allImageInfosAddress = allImageInfosAddress
        k.allImageInfosSize = allImageInfosSize
        k.mainStackTop = mainStackTop
        k.extended.rlimits = extended.rlimits
        k.extended.umask = extended.umask
        var actions: [Int32: ExtendedBSDState.SignalAction] = [:]
        for (sig, action) in extended.signalActions {
            if action.handler == 1 {
                actions[sig] = ExtendedBSDState.SignalAction(handler: 1)
            } else if action.handler > 1, Signal.ignoredByDefault.contains(sig), sig != Signal.sigcont {
                actions[sig] = ExtendedBSDState.SignalAction(handler: 1)
            }
        }
        if attributes.flags & SpawnFlag.setSigDefault != 0 {
            for sig in Int32(1)...31 where attributes.sigdefault & (1 << UInt32(sig - 1)) != 0 { actions[sig] = nil }
        }
        k.extended.signalActions = actions
        let ctx = current
        var mask = ctx.kind == .workqueue ? ctx.signalMask : extended.signalMask
        if attributes.flags & SpawnFlag.setSigMask != 0 { mask = attributes.sigmask }
        mask &= ~SignalConstant.unblockable
        k.extended.signalMask = mask
        k.mainThread.signalMask = mask
        if isExec { k.extended.pendingSignals = extended.pendingSignals }
    }

    private func makeRequest(_ request: SpawnRequest, guestPath: String, hostPath: String) -> ProcessImageRequest {
        var apple: [String] = []
        if request.attributes.flags & SpawnFlag.nanoAllocator != 0 { apple.append("MallocNanoZone=1") }
        let envp = system.imageEnvironment?(guestPath, request.envp) ?? request.envp
        var image = ProcessImageRequest(executablePath: guestPath, hostExecutablePath: hostPath, argv: request.argv,
                                        envp: envp, apple: apple,
                                        startSuspended: request.attributes.flags & SpawnFlag.startSuspended != 0)
        image.apple += system.kernelAppleStrings(for: image)
        return image
    }

    private func buildImage(_ request: SpawnRequest, pid newPID: Int32, isExec: Bool)
        throws -> (kernel: DarwinKernel, guestPath: String, hostPath: String) {
        let fs = fileSystem.makeChildCopy(newProcess: !isExec)
        let guestPath: String, hostPath: String
        let marked: Set<Int32>
        do {
            marked = try applyFileActions(request.fileActions, to: fs)
            (guestPath, hostPath) = try fs.hostPathForExec(request.path)
            try Self.checkExecutable(hostPath: hostPath, attributes: request.attributes)
        } catch {
            fs.closeAll()
            throw error
        }
        let k = DarwinKernel(fileSystem: fs, pid: newPID, system: system, log: log, counter: counter,
                             counterFrequency: counterFrequency, wallClock: wallClock)
        k.executableHostPath = hostPath
        inheritProcessState(into: k, attributes: request.attributes, isExec: isExec)
        if let mine = machIPC as? MachIPC, let theirs = k.machIPC as? MachIPC {
            withPorts { theirs.inheritTaskPorts(from: mine) }
            do {
                try withPorts { try theirs.applySpawnPortActions(request.portActions, from: mine) }
            } catch {
                k.discardUnlaunchedImage()
                throw error
            }
        }
        fs.closeOnExecDescriptors(keepOnly: request.attributes.flags & SpawnFlag.cloexecDefault != 0 ? marked : nil)
        return (k, guestPath, hostPath)
    }

    func discardUnlaunchedImage() {
        termination = .imageReplaced
        withPorts { (machIPC as? MachIPC)?.terminateTask() }
        fileSystem.closeAll()
    }

    nonisolated(unsafe) public static var unlockedImageBuild =
        getenv("SWIFTCODE_SPAWN_UNLOCKED_BUILD").map { String(cString: $0) != "0" } ?? true

    private func prepareUnlocked(_ launcher: any ProcessLauncher, _ request: ProcessImageRequest,
                                 kernel: DarwinKernel) throws -> (any PreparedImage)? {
        guard Self.unlockedImageBuild, lock.isHeldByCurrentThread else { return nil }
        let prepared = try lock.unlocked { try launcher.prepare(request, kernel: kernel) }
        if let prepared, isTerminating {
            launcher.discard(prepared)
            throw Failure(errno: 4)
        }
        return prepared
    }

    func spawnChild(_ me: DarwinProcess, _ request: SpawnRequest) throws -> Int32 {
        guard let launcher = system.launcher else {
            trace("note: posix_spawn: no process launcher; ENOSYS")
            throw Failure(errno: Errno.ENOSYS)
        }
        let childPID = try system.allocatePID()
        let (child, guestPath, hostPath) = try buildImage(request, pid: childPID, isExec: false)
        var prepared: (any PreparedImage)?
        do {
            prepared = try prepareUnlocked(launcher, makeRequest(request, guestPath: guestPath, hostPath: hostPath), kernel: child)
        } catch {
            child.discardUnlaunchedImage()
            throw error
        }
        let record = DarwinProcess(pid: childPID, ppid: pid, pgid: me.pgid, sid: me.sid, uniqueID: system.makeUniqueID(),
                                   executablePath: guestPath, startTime: DarwinSystem.now())
        record.kernel = child
        record.startAbsTime = counter()
        record.parentUniqueID = me.uniqueID
        record.originalParentPIDVersion = pidVersion
        record.processType = request.attributes.apptype
        record.processControl = request.attributes.pcontrol
        record.pidVersion = system.makePIDVersion()
        child.pidVersion = record.pidVersion
        system.processes[childPID] = record
        me.children.append(childPID)
        func undo() {
            if let p = prepared {
                launcher.discard(p)
                prepared = nil
            }
            system.reap(record)
            child.discardUnlaunchedImage()
        }
        child.applySpawnPolicy(request.attributes, record: record, isExec: false)
        var boostSenders: [Int32] = []
        var queuedAtSpawn = 0
        if let ipc = child.machIPC as? MachIPC { withPorts {
            queuedAtSpawn = ipc.pendingWatchPorts.reduce(0) { $0 + ($1.active ? $1.messages.count : 0) }
            if SchedPolicy.importanceEnabled {
                ipc.bindImportanceWatchPorts(ipc.pendingWatchPorts, to: record)
                if SchedPolicy.holdTrace, record.importanceBoosts > 0 {
                    boostSenders = ipc.pendingWatchPorts.flatMap { $0.messages.all.filter(\.importance).compactMap { $0.sender?.pid } }
                }
            }
            ipc.pendingWatchPorts = []
        } }
        let suspended = request.attributes.flags & SpawnFlag.startSuspended != 0
        let holdable = SchedPolicy.holdEnabled && !suspended && record.importanceBoosts == 0
            && (record.typeCode == ProcessTypeCode.daemonAdaptive || record.typeCode == ProcessTypeCode.daemonBackground)
        let demand = holdable && SchedPolicy.holdSkipsDemand && queuedAtSpawn > 0
        let hold = holdable && !demand
        do {
            if request.attributes.flags & SpawnFlag.setPGroup != 0 {
                try setpgid(caller: record, pid: 0, pgid: request.attributes.pgroup)
            }
            if request.attributes.flags & SpawnFlag.setSID != 0 { try setsid(record) }
            var image = makeRequest(request, guestPath: guestPath, hostPath: hostPath)
            if hold { image.startSuspended = true }
            if let p = prepared {
                prepared = nil
                record.image = try launcher.activate(p, startSuspended: image.startSuspended)
            } else {
                record.image = try launcher.launch(image, kernel: child)
            }
        } catch {
            undo()
            throw error
        }
        let viaProxy = request.argv.count > 1 && GuestPath.lastComponent(guestPath).hasPrefix("xpcproxy")
        let label = viaProxy ? request.argv[1] : GuestPath.lastComponent(guestPath)
        if viaProxy { record.launchdLabel = request.argv[1] }
        if hold {
            system.startHold(record, label: label)
        } else if demand {
            system.schedStats.demandStarts += 1
            system.holdLog?("pid \(childPID) \(label): not held (\(ProcessTypeCode.name(record.processType)), on demand: "
                + "\(queuedAtSpawn) messages queued at spawn)")
        } else if SchedPolicy.holdTrace, record.isImportanceReceiver || record.typeCode == ProcessTypeCode.daemonBackground {
            system.holdLog?("pid \(childPID) \(label): not held (\(ProcessTypeCode.name(record.processType)), "
                + "\(record.importanceBoosts) boosts at spawn from pids \(boostSenders))")
        }
        if SchedPolicy.importanceEnabled || SchedPolicy.qosEnabled {
            trace("note: sched: pid \(childPID) type \(ProcessTypeCode.name(record.processType)) clamp \(record.qosClamp) "
                + "role \(record.darwinRole) boosts \(record.importanceBoosts)\(hold ? " held" : "")")
        }
        if request.attributes.flags & SpawnFlag.startSuspended != 0 {
            record.state = .stopped
            record.kernel?.startedSuspended()
        }
        system.postProcessEvent(me, NoteProc.fork)
        trace("note: spawned pid \(childPID) \(guestPath)")
        return childPID
    }

    func execImage(_ me: DarwinProcess, _ request: SpawnRequest, _ call: inout CallText) throws -> BSDResult {
        guard let launcher = system.launcher else {
            trace("note: exec: no process launcher; ENOSYS")
            throw Failure(errno: Errno.ENOSYS)
        }
        let (next, guestPath, hostPath) = try buildImage(request, pid: pid, isExec: true)
        next.pidVersion = system.makePIDVersion()
        let image: any LaunchedImage
        do {
            let imageRequest = makeRequest(request, guestPath: guestPath, hostPath: hostPath)
            if let prepared = try prepareUnlocked(launcher, imageRequest, kernel: next) {
                image = try launcher.activate(prepared, startSuspended: imageRequest.startSuspended)
            } else {
                image = try launcher.launch(imageRequest, kernel: next)
            }
        } catch {
            next.discardUnlaunchedImage()
            throw error
        }
        me.kernel = next
        me.image = image
        me.pidVersion = next.pidVersion
        me.setImagePath(guestPath)
        me.hasExeced = true
        next.applySpawnPolicy(request.attributes, record: me, isExec: true)
        if let ipc = next.machIPC as? MachIPC { withPorts {
            if SchedPolicy.importanceEnabled { ipc.bindImportanceWatchPorts(ipc.pendingWatchPorts, to: me) }
            ipc.pendingWatchPorts = []
        } }
        if request.attributes.flags & SpawnFlag.startSuspended != 0 {
            me.state = .stopped
            next.startedSuspended()
        }
        endImage(.imageReplaced)
        tearDownKEvents()
        withPorts { (machIPC as? MachIPC)?.terminateTask() }
        fileSystem.closeAll()
        do {
            if request.attributes.flags & SpawnFlag.setPGroup != 0 {
                try next.setpgid(caller: me, pid: 0, pgid: request.attributes.pgroup)
            }
            if request.attributes.flags & SpawnFlag.setSID != 0 { try next.setsid(me) }
        } catch {
            trace("note: exec: SETPGROUP/SETSID failed after the commit point; SIGKILL")
            next.terminateBySignal(Signal.sigkill)
        }
        system.postProcessEvent(me, NoteProc.exec)
        call += " [image replaced: pid \(pid) now runs \(guestPath), pid version \(next.pidVersion)]"
        return .outcome(.imageReplaced)
    }
}
