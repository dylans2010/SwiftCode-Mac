import Foundation
import Synchronization
import YcodeDarwinABI

public final class DarwinProcess: @unchecked Sendable, CustomStringConvertible {
    public enum State: Equatable, Sendable {
        case running
        case stopped
        case zombie
    }

    public let pid: Int32
    public let uniqueID: UInt64

    struct Fields {
        var ppid: Int32
        var pgid: Int32
        var sid: Int32
        var state: State
        var status: Int32 = 0
        var kernel: DarwinKernel?
        var executablePath: String
        var comm: String
        var name: String
        var startTime: (seconds: Int64, microseconds: Int64)
        var startAbsTime: UInt64 = 0
        var exitAbsTime: UInt64 = 0
        var parentUniqueID: UInt64 = 0
        var originalParentPIDVersion: UInt32 = 0
        var exiting = false
        var pidVersion: UInt32 = 0
        var zombieExecutableUUID: [UInt8]?
        var launchdLabel = ""
    }
    private let fieldsLock = DescriptorTableLock(name: "process record")
    nonisolated(unsafe) private var fields: Fields

    func view() -> Fields { fieldsLock.withLock { fields } }

    public internal(set) var ppid: Int32 {
        get { fieldsLock.withLock { fields.ppid } }
        set { fieldsLock.withLock { fields.ppid = newValue } }
    }
    public internal(set) var pgid: Int32 {
        get { fieldsLock.withLock { fields.pgid } }
        set { fieldsLock.withLock { fields.pgid = newValue } }
    }
    public internal(set) var sid: Int32 {
        get { fieldsLock.withLock { fields.sid } }
        set { fieldsLock.withLock { fields.sid = newValue } }
    }
    public internal(set) var state: State {
        get { fieldsLock.withLock { fields.state } }
        set { fieldsLock.withLock { fields.state = newValue } }
    }
    public internal(set) var status: Int32 {
        get { fieldsLock.withLock { fields.status } }
        set { fieldsLock.withLock { fields.status = newValue } }
    }
    var exitHighBits: Int32 = 0
    public internal(set) var kernel: DarwinKernel? {
        get { fieldsLock.withLock { fields.kernel } }
        set {
            let old = fieldsLock.withLock { () -> DarwinKernel? in
                let old = fields.kernel
                fields.kernel = newValue
                return old
            }
            withExtendedLifetime(old) {}
            newValue?.processDirtyLink.withLock { $0 = dirty }
        }
    }
    var image: (any LaunchedImage)?
    var children: [Int32] = []
    public internal(set) var executablePath: String {
        get { fieldsLock.withLock { fields.executablePath } }
        set { fieldsLock.withLock { fields.executablePath = newValue } }
    }
    public internal(set) var launchdLabel: String {
        get { fieldsLock.withLock { fields.launchdLabel } }
        set { fieldsLock.withLock { fields.launchdLabel = newValue } }
    }
    var comm: String {
        get { fieldsLock.withLock { fields.comm } }
        set { fieldsLock.withLock { fields.comm = newValue } }
    }
    var name: String {
        get { fieldsLock.withLock { fields.name } }
        set { fieldsLock.withLock { fields.name = newValue } }
    }
    var hasExeced = true
    var startTime: (seconds: Int64, microseconds: Int64) {
        get { fieldsLock.withLock { fields.startTime } }
        set { fieldsLock.withLock { fields.startTime = newValue } }
    }
    var startAbsTime: UInt64 {
        get { fieldsLock.withLock { fields.startAbsTime } }
        set { fieldsLock.withLock { fields.startAbsTime = newValue } }
    }
    var exitAbsTime: UInt64 {
        get { fieldsLock.withLock { fields.exitAbsTime } }
        set { fieldsLock.withLock { fields.exitAbsTime = newValue } }
    }
    var parentUniqueID: UInt64 {
        get { fieldsLock.withLock { fields.parentUniqueID } }
        set { fieldsLock.withLock { fields.parentUniqueID = newValue } }
    }
    var originalParentPIDVersion: UInt32 {
        get { fieldsLock.withLock { fields.originalParentPIDVersion } }
        set { fieldsLock.withLock { fields.originalParentPIDVersion = newValue } }
    }
    var exiting: Bool {
        get { fieldsLock.withLock { fields.exiting } }
        set { fieldsLock.withLock { fields.exiting = newValue } }
    }
    var watchers: [ProcessWatch] = []
    let childWaiters = WaitQueue()
    var continuedPending = false
    var continuedBy: Int32 = 0
    var dirtyState: UInt32 {
        get { dirty.bits.load(ordering: .acquiring) }
        set { dirty.bits.store(newValue, ordering: .releasing) }
    }
    let dirty = ProcessDirtyState()
    var processType: UInt32 = 0
    var processControl: UInt32 = 0
    var qosClamp = 0
    var darwinRole: UInt32 = 0
    var requestedDarwinBG = false
    var importanceBoosts = 0
    var holdStart: UInt64? {
        didSet { holdActive.store(holdStart != nil, ordering: .releasing) }
    }
    let holdActive = Atomic<Bool>(false)
    var holdLabel = ""
    var holdBoostSource: String {
        get { holdBoostLock.withLock { holdBoostSourceValue } }
        set { holdBoostLock.withLock { holdBoostSourceValue = newValue } }
    }
    private var holdBoostSourceValue = ""
    private let holdBoostLock = DescriptorTableLock(name: "hold boost source")
    var pidVersion: UInt32 {
        get { fieldsLock.withLock { fields.pidVersion } }
        set { fieldsLock.withLock { fields.pidVersion = newValue } }
    }
    var zombieExecutableUUID: [UInt8]? {
        get { fieldsLock.withLock { fields.zombieExecutableUUID } }
        set { fieldsLock.withLock { fields.zombieExecutableUUID = newValue } }
    }
    var executableUUID: [UInt8] { view().executableUUID }
    var exitReason: String?

    init(pid: Int32, ppid: Int32, pgid: Int32, sid: Int32, uniqueID: UInt64, executablePath: String,
         startTime: (Int64, Int64)) {
        self.pid = pid
        self.uniqueID = uniqueID
        let last = GuestPath.lastComponent(executablePath)
        fields = Fields(ppid: ppid, pgid: pgid, sid: sid, state: .running, executablePath: executablePath,
                        comm: String(decoding: Array(last.utf8.prefix(15)), as: UTF8.self),
                        name: String(decoding: Array(last.utf8.prefix(31)), as: UTF8.self),
                        startTime: startTime)
    }

    public var isZombie: Bool { state == .zombie }

    public var description: String {
        "pid \(pid) ppid \(ppid) pgid \(pgid) sid \(sid) \(state)\(state == .zombie ? " status \(hx(UInt32(bitPattern: status)))" : "") \(executablePath)"
    }

    func setImagePath(_ path: String) {
        let last = GuestPath.lastComponent(path)
        let comm = String(decoding: Array(last.utf8.prefix(15)), as: UTF8.self)
        let name = String(decoding: Array(last.utf8.prefix(31)), as: UTF8.self)
        fieldsLock.withLock {
            fields.executablePath = path
            fields.comm = comm
            fields.name = name
        }
    }
}

final class ProcessWatch {
    weak var knote: Knote?
    weak var kernel: DarwinKernel?

    init(knote: Knote, kernel: DarwinKernel) {
        self.knote = knote
        self.kernel = kernel
    }
}

public final class DarwinSystem: @unchecked Sendable {
    public let lock: KernelLock
    public let mach: MachIPCSystem
    public weak var launcher: (any ProcessLauncher)?

    let isImplicit: Bool

    var processes: [Int32: DarwinProcess] {
        get { processTableLock.withLock { processTable } }
        set {
            let old = processTableLock.withLock { () -> [Int32: DarwinProcess] in
                let old = processTable
                processTable = newValue
                return old
            }
            withExtendedLifetime(old) {}
        }
    }
    private let processTableLock = DescriptorTableLock(name: "process table")
    nonisolated(unsafe) private var processTable: [Int32: DarwinProcess] = [:]

    func processRecord(_ pid: Int32) -> DarwinProcess? { processTableLock.withLock { processTable[pid] } }
    var posixShmSegments: [String: PosixShmSegment] = [:]
    var posixSemaphoreStorage: [String: PosixSemaphore] = [:]
    var fileLockStorage: FileLockTable?
    let fileLockCreation = Mutex<Void>(())
    let posixLockUsers = Mutex<Set<Int32>>([])
    let objectPaths = ObjectPathIndex()
    var heldProcesses: [DarwinProcess] = []
    var holdThreadRunning = false
    let holdWake = WaitQueue()
    public internal(set) var schedStats = SchedStats()
    public var holdLog: ((String) -> Void)?
    public var shellReadyHoldLabels: Set<String> = []
    var shellReady = false
    var lastPID: Int32 = VMLayout.guestPID
    var nextPIDVersion: UInt32 = 0x100
    var nextUniqueID: UInt64 = 1
    public var bootSalt = UInt32.random(in: 0...UInt32.max)
    public var bootSessionUUID: String = UUID().uuidString
    public static let initPID: Int32 = 1
    public static let maxPID: Int32 = 99_999
    public static let firstWrappedPID: Int32 = 100

    public convenience init() {
        self.init(implicit: false)
    }

    public convenience init(ipcLocks: Bool) {
        self.init(implicit: false, ipcLocks: ipcLocks)
    }

    nonisolated(unsafe) public static var ipcLocksDefault = getenv("SWIFTCODE_IPC_LOCKS").map { String(cString: $0) != "0" } ?? true

    nonisolated(unsafe) public static var splitForTests = getenv("SWIFTCODE_IPC_LOCKS_TESTS").map { String(cString: $0) == "1" } ?? false

    init(implicit: Bool, ipcLocks: Bool = DarwinSystem.ipcLocksDefault || DarwinSystem.splitForTests) {
        let split = ipcLocks && (!implicit || Self.splitForTests)
        lock = KernelLock(ipcLocks: split)
        mach = MachIPCSystem()
        if split { mach.portLock = KernelLock(fineLockOf: lock, level: 2, name: "port lock (G)") }
        isImplicit = implicit
        lock.blockingObserver = { context, blocking in
            context.kernel?.threadBlockingChanged(context, blocking: blocking)
        }
        let initRecord = DarwinProcess(pid: Self.initPID, ppid: 0, pgid: Self.initPID, sid: Self.initPID, uniqueID: 0,
                                       executablePath: "/sbin/launchd", startTime: Self.now())
        processes[Self.initPID] = initRecord
    }

    public var processExited: ((_ pid: Int32, _ status: Int32) -> Void)?

    public var imageEnvironment: (@Sendable (_ executable: String, _ envp: [String]) -> [String])?

    public func kernel(forPID pid: Int32) -> DarwinKernel? {
        lock.withLock {
            guard let p = processes[pid], p.state != .zombie else { return nil }
            return p.kernel
        }
    }

    public func process(pid: Int32) -> DarwinProcess? {
        lock.withLock { processes[pid] }
    }

    public var allProcesses: [DarwinProcess] {
        lock.withLock { processes.values.filter { $0.pid != Self.initPID }.sorted { $0.pid < $1.pid } }
    }

    func record(of kernel: DarwinKernel) -> DarwinProcess? {
        guard let p = processes[kernel.pid], p.kernel === kernel else { return nil }
        return p
    }

    static func now() -> (Int64, Int64) {
        let t = Date().timeIntervalSince1970
        let s = t.rounded(.down)
        return (Int64(s), Int64((t - s) * 1e6))
    }

    func numberInUse(_ n: Int32) -> Bool {
        if processes[n] != nil { return true }
        return processes.values.contains { $0.pgid == n || $0.sid == n }
    }

    func allocatePID() throws -> Int32 {
        var candidate = lastPID
        for _ in 0..<Int(Self.maxPID) {
            candidate = candidate >= Self.maxPID ? Self.firstWrappedPID : candidate + 1
            if !numberInUse(candidate) {
                lastPID = candidate
                return candidate
            }
        }
        throw DarwinErrnoError(DarwinErrnoCode.EAGAIN)
    }

    func makePIDVersion() -> UInt32 {
        nextPIDVersion &+= 1
        if nextPIDVersion == 0 { nextPIDVersion = 1 }
        return nextPIDVersion
    }

    func makeUniqueID() -> UInt64 {
        defer { nextUniqueID += 1 }
        return nextUniqueID
    }

    func groupExists(_ pgid: Int32) -> Bool {
        processes.values.contains { $0.pgid == pgid && $0.pid != Self.initPID }
    }

    public func spawnInitialProcess(_ request: ProcessImageRequest, fileSystem: DarwinFileSystem,
                                    exitedChildEnvironmentKey: String? = nil) throws -> DarwinKernel {
        var request = request
        request.apple += kernelAppleStrings(for: request)
        return try lock.withLock {
            guard let launcher else { throw DarwinErrnoError(DarwinErrnoCode.ENOSYS) }
            let pid = numberInUse(VMLayout.guestPID) ? try allocatePID() : VMLayout.guestPID
            let kernel = DarwinKernel(fileSystem: fileSystem, pid: pid, system: self)
            let record = DarwinProcess(pid: pid, ppid: Self.initPID, pgid: pid, sid: pid, uniqueID: makeUniqueID(),
                                       executablePath: request.executablePath, startTime: Self.now())
            record.kernel = kernel
            record.pidVersion = makePIDVersion()
            kernel.pidVersion = record.pidVersion
            kernel.executableHostPath = request.hostExecutablePath
            processes[pid] = record
            processes[Self.initPID]?.children.append(pid)
            var zombie: DarwinProcess?
            if let key = exitedChildEnvironmentKey {
                let childPID = try allocatePID()
                let child = DarwinProcess(pid: childPID, ppid: pid, pgid: pid, sid: pid, uniqueID: makeUniqueID(),
                                          executablePath: request.executablePath, startTime: Self.now())
                child.state = .zombie
                child.status = 0
                child.parentUniqueID = record.uniqueID
                child.pidVersion = makePIDVersion()
                processes[childPID] = child
                record.children.append(childPID)
                request.envp.append("\(key)=\(childPID)")
                zombie = child
            }
            do {
                record.image = try launcher.launch(request, kernel: kernel)
            } catch {
                if let zombie { processes[zombie.pid] = nil }
                processes[pid] = nil
                processes[Self.initPID]?.children.removeAll { $0 == pid }
                kernel.withPorts { (kernel.machIPC as? MachIPC)?.terminateTask() }
                throw error
            }
            if request.startSuspended {
                record.state = .stopped
                kernel.startedSuspended()
            }
            return kernel
        }
    }

    func kernelAppleStrings(for request: ProcessImageRequest) -> [String] {
        guard !request.apple.contains(where: { $0.hasPrefix("executable_boothash=") }) else { return [] }
        return CodeSignature.appleStrings(hostPath: request.hostExecutablePath, bootSalt: bootSalt,
                                          bootSessionUUID: bootSessionUUID)
    }

    func reap(_ p: DarwinProcess) {
        processes[p.pid] = nil
        processes[p.ppid]?.children.removeAll { $0 == p.pid }
    }

    func reapsChildrenAtOnce(_ parent: DarwinProcess?) -> Bool {
        guard let parent, parent.pid != Self.initPID, let k = parent.kernel else { return true }
        let action = k.extended.signalActions[DarwinKernel.Signal.sigchld]
        return action?.handler == 1 || (action?.flags ?? 0) & DarwinKernel.Signal.saNoCldWait != 0
    }

    func exitProcess(_ p: DarwinProcess, waitStatus: Int32, highBits: Int32 = 0, outcome: DarwinKernel.Outcome) {
        guard !p.exiting, p.state != .zombie, p.pid != Self.initPID else { return }
        p.exiting = true
        if let k = p.kernel {
            p.exitAbsTime = k.counter()
            k.endImage(outcome)
            k.tearDownKEvents()
            k.withPorts { (k.machIPC as? MachIPC)?.terminateTask() }
            k.fileSystem.closeAll()
            lock.wakeFileLockWaiters(fileLocks.release(owner: .process(p.pid)))
            k.log("note: process \(p.pid) exited, wait status \(hx(UInt32(bitPattern: waitStatus)))")
        }
        p.zombieExecutableUUID = p.kernel?.executableUUID
        p.image = nil
        p.kernel = nil
        p.status = waitStatus
        p.exitHighBits = highBits
        p.state = .zombie
        let initRecord = processes[Self.initPID]
        for c in p.children {
            guard let child = processes[c] else { continue }
            if child.state == .zombie {
                processes[c] = nil
            } else {
                child.ppid = Self.initPID
                initRecord?.children.append(c)
            }
        }
        p.children = []
        let parent = processes[p.ppid]
        let reapNow = reapsChildrenAtOnce(parent)
        if reapNow { reap(p) }
        postProcessEvent(p, NoteProc.exit, data: Int64(waitStatus & 0xF_FFFF))
        p.watchers.removeAll()
        if let parent {
            if !reapNow { parent.kernel?.postSignal(DarwinKernel.Signal.sigchld) }
            parent.childWaiters.wakeAll()
        }
        processExited?(p.pid, waitStatus)
    }

    public func terminateAllProcesses() {
        lock.withLock {
            for p in processes.values.sorted(by: { $0.pid > $1.pid }) where p.pid != Self.initPID && p.state != .zombie {
                exitProcess(p, waitStatus: DarwinKernel.Signal.sigkill,
                            outcome: .fatal(status: 128 + DarwinKernel.Signal.sigkill, message: "terminated by the VMM"))
            }
        }
    }

    func postProcessEvent(_ p: DarwinProcess, _ event: UInt32, data: Int64 = 0) {
        p.watchers.removeAll { $0.knote == nil || $0.kernel == nil || $0.knote!.dropped }
        for w in p.watchers {
            guard let kn = w.knote, let k = w.kernel, !k.isTerminating else { continue }
            k.processEventFired(kn, event: event, data: data)
        }
    }
}

extension DarwinProcess.Fields {
    var isZombie: Bool { state == .zombie }
    var executableUUID: [UInt8] {
        let u = kernel?.executableUUID ?? zombieExecutableUUID ?? []
        return u.count == 16 ? u : [UInt8](repeating: 0, count: 16)
    }
}
