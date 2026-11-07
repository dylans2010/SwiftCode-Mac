import Foundation
import Synchronization
#if canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

public enum HostSched {
    public enum Backend: String, Sendable { case none, nice, cgroup }

    nonisolated(unsafe) public private(set) static var backend: Backend = .none
    static let niceByClass: [Int32] = [19, 8, 3, 0]
    static let weightByClass = [bgWeight ?? 1, 25, 100, 400]
    static let bgWeight: Int? = {
        guard let v = getenv("SWIFTCODE_HOST_SCHED_BG_WEIGHT").map({ String(cString: $0) }) else { return 5 }
        if v == "idle" { return nil }
        return Int(v).map { max(1, min(10_000, $0)) } ?? 5
    }()
    nonisolated(unsafe) static var threadFiles: [Int32] = []
    nonisolated(unsafe) static var key = pthread_key_t()
    static let moveCount = Atomic<Int>(0)
    static let failureCount = Atomic<Int>(0)
    static let moveNanoseconds = Atomic<UInt64>(0)
    static let promotions = Atomic<Int>(0)
    static let promotionRestores = Atomic<Int>(0)
    static let promotionWaits = Atomic<Int>(0)
    static let demotionsSkipped = Atomic<Int>(0)
    nonisolated(unsafe) static var demoteDelayNanoseconds: UInt64 =
        UInt64(getenv("SWIFTCODE_HOST_SCHED_DEMOTE_MS").flatMap { Double(String(cString: $0)) } ?? 50) * 1_000_000
    nonisolated(unsafe) static var demoteKey = pthread_key_t()
    public static var report: String {
        "host scheduling \(status); \(moveCount.load(ordering: .relaxed)) moves, \(failureCount.load(ordering: .relaxed)) failures, "
            + "\(moveNanoseconds.load(ordering: .relaxed) / 1_000_000) ms moving (\(otherMoveCount.load(ordering: .relaxed)) moves of another thread, "
            + "\(otherMoveNanoseconds.load(ordering: .relaxed) / 1_000_000) ms), \(demotionsSkipped.load(ordering: .relaxed)) demotions put off; "
            + "lock holders promoted \(promotions.load(ordering: .relaxed)) "
            + "(\(promotionWaits.load(ordering: .relaxed)) waits past the delay, \(promotionRestores.load(ordering: .relaxed)) let go raised; "
            + "\(groupWrites.load(ordering: .relaxed)) class weight writes, \(groupWriteNanoseconds.load(ordering: .relaxed) / 1_000_000) ms)"
            + (bgCPUMasks == nil ? "" : "; affinity failures \(affinityFailures.load(ordering: .relaxed))")
    }
    nonisolated(unsafe) public static var promoteHolders = getenv("SWIFTCODE_LOCK_HOLDER_PROMOTION").map { String(cString: $0) != "0" } ?? true
    nonisolated(unsafe) static var promoteByGroup = getenv("SWIFTCODE_LOCK_HOLDER_PROMOTION").map { String(cString: $0) != "thread" } ?? true
    nonisolated(unsafe) static var weightFiles: [Int32] = []
    static let groupRaises = Mutex<[(count: Int, level: Int)]>([(0, 0), (0, 1), (0, 2), (0, 3)])
    @inline(__always) static func raisesGroup(_ cls: Int) -> Bool {
        promoteByGroup && moveHook == nil && backend == .cgroup && cls >= 0 && cls < weightFiles.count && weightFiles[cls] >= 0
    }
    nonisolated(unsafe) static var groupHook: ((Int, Int) -> Void)?

    static func raiseGroup(_ holder: Int, to cls: Int) {
        groupRaises.withLock { g in
            g[holder].count += 1
            if cls > g[holder].level {
                g[holder].level = cls
                writeWeight(holder, weightByClass[cls])
            }
        }
    }

    static func lowerGroup(_ holder: Int) {
        groupRaises.withLock { g in
            g[holder].count = max(0, g[holder].count - 1)
            if g[holder].count == 0, g[holder].level != holder {
                g[holder].level = holder
                writeWeight(holder, weightByClass[holder])
            }
        }
    }

    private static func writeWeight(_ group: Int, _ weight: Int) {
        if let groupHook { groupHook(group, weight); return }
        #if os(Linux)
        let start = KernelClock.now()
        let text = Array(String(weight).utf8)
        let ok = text.withUnsafeBufferPointer { pwrite(weightFiles[group], $0.baseAddress, $0.count, 0) } == text.count
        groupWrites.wrappingAdd(1, ordering: .relaxed)
        groupWriteNanoseconds.wrappingAdd(KernelClock.now() &- start, ordering: .relaxed)
        if !ok { failureCount.wrappingAdd(1, ordering: .relaxed) }
        #endif
    }
    static let groupWrites = Atomic<Int>(0)
    static let groupWriteNanoseconds = Atomic<UInt64>(0)
    @inline(__always) static var promoting: Bool { (backend != .none || moveHook != nil) && promoteHolders }
    nonisolated(unsafe) static var moveHook: ((Int32, Int) -> Void)? {
        didSet { if moveHook != nil { makeKeys() } }
    }
    private static let keysMade = Atomic<Bool>(false)
    static func makeKeys() {
        guard keysMade.compareExchange(expected: false, desired: true, ordering: .sequentiallyConsistent).exchanged else { return }
        pthread_key_create(&key, nil)
        pthread_key_create(&tidKey, nil)
        pthread_key_create(&demoteKey, nil)
    }
    nonisolated(unsafe) static var tidKey = pthread_key_t()
    nonisolated(unsafe) public static var threadID: (() -> Int)?
    nonisolated(unsafe) public private(set) static var status = "off"

    static var requested: Backend {
        Backend(rawValue: getenv("SWIFTCODE_HOST_SCHED").map { String(cString: $0) } ?? "none") ?? .none
    }

    public static func prepareProcess() {
        #if os(Linux)
        guard SchedPolicy.qosEnabled, requested == .cgroup else { return }
        guard let cg = ownCgroup(), access(cg + "/cgroup.subtree_control", W_OK) != 0 else { return }
        guard getenv("SWIFTCODE_HOST_SCHED_SCOPE") == nil else { return }
        let runtime = getenv("XDG_RUNTIME_DIR").map { String(cString: $0) } ?? "/run/user/\(getuid())"
        guard access(runtime + "/systemd/private", F_OK) == 0 else { return }
        setenv("SWIFTCODE_HOST_SCHED_SCOPE", "1", 1)
        var exe = [CChar](repeating: 0, count: 4096)
        let n = readlink("/proc/self/exe", &exe, exe.count - 1)
        guard n > 0 else { return }
        let args = ["systemd-run", "--user", "--scope", "--quiet", "-p", "Delegate=yes", "--", String(cString: exe)]
            + CommandLine.arguments.dropFirst()
        var cargs: [UnsafeMutablePointer<CChar>?] = args.map { strdup($0) } + [nil]
        execvp("systemd-run", &cargs)
        unsetenv("SWIFTCODE_HOST_SCHED_SCOPE")
        #endif
    }

    @discardableResult
    public static func configure() -> String {
        #if os(Linux)
        guard SchedPolicy.qosEnabled else { return status }
        makeKeys()
        switch requested {
        case .nice:
            var limit = rlimit()
            getrlimit(__rlimit_resource_t(13), &limit)
            if limit.rlim_cur >= 20 || geteuid() == 0 {
                backend = .nice
                status = "nice (RLIMIT_NICE \(limit.rlim_cur))"
            } else {
                status = "none: nice needs RLIMIT_NICE >= 20 to raise a thread again (it is \(limit.rlim_cur))"
            }
        case .cgroup:
            status = setUpCgroups()
        case .none:
            status = "none"
        }
        if backend != .none, let bg = bgCPUMasks {
            status += "; class bg on \(bg.background.reduce(0) { $0 + $1.nonzeroBitCount }) of \(bg.all.reduce(0) { $0 + $1.nonzeroBitCount }) CPUs"
        }
        #else
        status = "none (not Linux)"
        #endif
        return status
    }

    @inline(__always)
    public static func apply(_ cls: Int) {
        guard backend != .none || moveHook != nil else { return }
        let current = Int(bitPattern: pthread_getspecific(key)) - 1
        guard current != cls else {
            if pthread_getspecific(demoteKey) != nil {
                pthread_setspecific(demoteKey, nil)
                demotionsSkipped.wrappingAdd(1, ordering: .relaxed)
            }
            return
        }
        if cls < current, current >= 0, demoteDelayNanoseconds > 0 {
            let now = KernelClock.now()
            let since = UInt64(UInt(bitPattern: pthread_getspecific(demoteKey)))
            if since == 0 {
                pthread_setspecific(demoteKey, UnsafeRawPointer(bitPattern: UInt(now)))
                return
            }
            guard now &- since >= demoteDelayNanoseconds else { return }
        }
        pthread_setspecific(demoteKey, nil)
        guard let tid = currentTID() else { return }
        move(tid, to: cls, isSelf: true)
        pthread_setspecific(key, UnsafeRawPointer(bitPattern: cls + 1))
    }

    @inline(__always)
    static func setAppliedClass(_ cls: Int) {
        pthread_setspecific(key, UnsafeRawPointer(bitPattern: cls + 1))
    }

    @inline(__always)
    static func appliedClass() -> Int {
        Int(bitPattern: pthread_getspecific(key)) - 1
    }

    @inline(__always)
    static func forgetAppliedClass() {
        pthread_setspecific(key, nil)
    }

    @inline(__always)
    static func currentTID() -> Int32? {
        let cached = Int(bitPattern: pthread_getspecific(tidKey))
        if cached != 0 { return Int32(truncatingIfNeeded: cached) }
        guard let threadID else { return nil }
        let tid = threadID()
        guard tid != 0 else { return nil }
        pthread_setspecific(tidKey, UnsafeRawPointer(bitPattern: tid))
        return Int32(truncatingIfNeeded: tid)
    }

    static func move(_ tid: Int32, to cls: Int, isSelf: Bool = false) {
        if let moveHook {
            moveHook(tid, cls)
            moveCount.wrappingAdd(1, ordering: .relaxed)
            return
        }
        #if os(Linux)
        let start = KernelClock.now()
        var ok = false
        switch backend {
        case .nice:
            ok = setpriority(__priority_which_t(PRIO_PROCESS.rawValue), id_t(tid), niceByClass[cls]) == 0
        case .cgroup:
            let text = Array((isSelf && selfMoveByZero ? "0" : String(tid)).utf8)
            ok = text.withUnsafeBufferPointer { pwrite(threadFiles[cls], $0.baseAddress, $0.count, 0) } == text.count
        case .none:
            break
        }
        if ok, backend != .none, let bg = bgCPUMasks { _ = setAffinity(tid, cls == 0 ? bg.background : bg.all) }
        let took = KernelClock.now() &- start
        moveNanoseconds.wrappingAdd(took, ordering: .relaxed)
        if !isSelf {
            otherMoveCount.wrappingAdd(1, ordering: .relaxed)
            otherMoveNanoseconds.wrappingAdd(took, ordering: .relaxed)
        }
        if ok { moveCount.wrappingAdd(1, ordering: .relaxed) } else { failureCount.wrappingAdd(1, ordering: .relaxed) }
        #endif
    }
    static let bgCPUMasks: (background: [UInt64], all: [UInt64])? = {
        #if os(Linux)
        guard let v = getenv("SWIFTCODE_HOST_SCHED_BG_CPUS").flatMap({ Int(String(cString: $0)) }), v > 0 else { return nil }
        let online = Int(sysconf(Int32(_SC_NPROCESSORS_ONLN)))
        guard online > v else { return nil }
        let words = (online + 63) / 64
        var background = [UInt64](repeating: 0, count: words), all = background
        for cpu in 0..<online {
            all[cpu / 64] |= 1 << UInt64(cpu % 64)
            if cpu >= online - v { background[cpu / 64] |= 1 << UInt64(cpu % 64) }
        }
        return (background, all)
        #else
        return nil
        #endif
    }()
    static let affinityFailures = Atomic<Int>(0)
    nonisolated(unsafe) static let schedSetAffinity: (@convention(c) (Int32, Int, UnsafeRawPointer) -> Int32)? = {
        #if os(Linux)
        guard let f = dlsym(UnsafeMutableRawPointer(bitPattern: 0), "sched_setaffinity") else { return nil }
        return unsafeBitCast(f, to: (@convention(c) (Int32, Int, UnsafeRawPointer) -> Int32).self)
        #else
        return nil
        #endif
    }()

    @discardableResult
    static func setAffinity(_ tid: Int32, _ mask: [UInt64]) -> Bool {
        #if os(Linux)
        guard let call = schedSetAffinity else { return false }
        let ok = mask.withUnsafeBytes { call(tid, $0.count, $0.baseAddress!) } == 0
        if !ok { affinityFailures.wrappingAdd(1, ordering: .relaxed) }
        return ok
        #else
        return false
        #endif
    }

    nonisolated(unsafe) static var selfMoveByZero = getenv("SWIFTCODE_HOST_SCHED_SELF_ZERO").map { String(cString: $0) != "0" } ?? true
    static let otherMoveCount = Atomic<Int>(0)
    static let otherMoveNanoseconds = Atomic<UInt64>(0)

    #if os(Linux)
    static func ownCgroup() -> String? {
        guard let text = try? String(contentsOfFile: "/proc/self/cgroup", encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n") where line.hasPrefix("0::") {
            return "/sys/fs/cgroup" + line.dropFirst(3)
        }
        return nil
    }

    static func write(_ path: String, _ value: String) -> Bool {
        let fd = open(path, O_WRONLY)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        let bytes = Array(value.utf8)
        return bytes.withUnsafeBufferPointer { Glibc.write(fd, $0.baseAddress, $0.count) } == bytes.count
    }

    static func setUpCgroups() -> String {
        guard let cg = ownCgroup() else { return "none: no cgroup v2 path" }
        guard access(cg + "/cgroup.subtree_control", W_OK) == 0 else { return "none: \(cg) is not delegated" }
        var files: [Int32] = []
        var weights: [Int32] = []
        for c in 0..<SchedClass.count {
            let dir = cg + "/swiftcode-class\(c)"
            if mkdir(dir, 0o755) != 0 && errno != EEXIST { return "none: mkdir \(dir) failed (errno \(errno))" }
            guard write(dir + "/cgroup.type", "threaded") else { return "none: \(dir) cannot be threaded" }
        }
        guard write(cg + "/cgroup.subtree_control", "+cpu") else { return "none: cannot enable cpu in \(cg)" }
        for c in 0..<SchedClass.count {
            let dir = cg + "/swiftcode-class\(c)"
            if c == 0, bgWeight == nil, write(dir + "/cpu.idle", "1") {
            } else {
                if c == 0 { _ = write(dir + "/cpu.idle", "0") }
                _ = write(dir + "/cpu.weight", String(weightByClass[c]))
            }
            let fd = open(dir + "/cgroup.threads", O_WRONLY)
            guard fd >= 0 else { return "none: cannot open \(dir)/cgroup.threads" }
            files.append(fd)
            weights.append(c == 0 && bgWeight == nil ? -1 : open(dir + "/cpu.weight", O_WRONLY))
        }
        threadFiles = files
        weightFiles = weights
        backend = .cgroup
        let bg = bgWeight.map { "class 0 weight \($0)" } ?? "class 0 idle"
        return "cgroup \(cg) (weights \(weightByClass.dropFirst().map(String.init).joined(separator: "/")), \(bg); "
            + "holder promotion \(promoteHolders ? (promoteByGroup ? "by class weight" : "by thread move") : "off"))"
    }
    #endif
}
