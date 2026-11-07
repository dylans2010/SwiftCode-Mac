import Foundation
#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import YcodeDarwinABI

public final class TrapProfile: @unchecked Sendable {
    public struct Row: Sendable {
        public var count: UInt64 = 0
        public var handlerNanoseconds: UInt64 = 0
        public var acquisitions: UInt64 = 0
        public var holdNanoseconds: UInt64 = 0
        public var maxHoldNanoseconds: UInt64 = 0
        public var waits: UInt64 = 0
        public var contended: UInt64 = 0
        public var waitNanoseconds: UInt64 = 0
        public var maxWaitNanoseconds: UInt64 = 0
        public var faults: UInt64 = 0
        public var faultHolds: UInt64 = 0
        public var faultHoldNanoseconds: UInt64 = 0
        public var blockedHolds: UInt64 = 0
        public var blockedHoldNanoseconds: UInt64 = 0
        public var preemptedHolds: UInt64 = 0
        public var preemptedHoldNanoseconds: UInt64 = 0

        public init() {}
    }

    static let profiling = getenv("SWIFTCODE_TRAP_PROFILE").map { $0.pointee != 0 } ?? false

    public static let shared: TrapProfile? = {
        guard let raw = getenv("SWIFTCODE_TRAP_PROFILE") else { return nil }
        DebugLockNames.register = { TrapProfile.nameLock($0, $1) }
        let path = String(cString: raw)
        return path.isEmpty ? nil : TrapProfile(path: path)
    }()

    public static let eventLocks: TrapProfile? = shared.map { fineProfile($0.path + ".events") }
    public static let portLock: TrapProfile? = shared.map { fineProfile($0.path + ".ports") }

    private static func fineProfile(_ path: String) -> TrapProfile {
        let p = TrapProfile(path: path)
        p.startPeriodicDump()
        return p
    }

    public static let dumpInterval: TimeInterval = {
        guard let raw = getenv("SWIFTCODE_TRAP_PROFILE_INTERVAL"), let v = Double(String(cString: raw)), v >= 1 else { return 30 }
        return v
    }()

    public static let rowLimit: Int = {
        guard let raw = getenv("SWIFTCODE_TRAP_PROFILE_ROWS"), let v = Int(String(cString: raw)), v >= 1 else { return 25 }
        return v
    }()

    static let serviceKey = Int64.min

    public static let programFilter: Set<String> = {
        guard let raw = getenv("SWIFTCODE_TRAP_PROFILE_PROGRAM") else { return [] }
        return Set(String(cString: raw).split(separator: ",").map(String.init))
    }()
    static let otherProcessesKey = Int64.min + 1

    static func filtered(_ key: Int64, kernel: DarwinKernel?) -> Int64 {
        guard !programFilter.isEmpty, key != serviceKey else { return key }
        return kernel?.trapProfileSelected == true ? key : otherProcessesKey
    }

    public let path: String
    private let mutex = RecursiveMutex(name: "trap profile")
    private var rows: [Int64: Row] = [:]
    private let started = Date()

    public var extraReport: (() -> String)?

    nonisolated(unsafe) public static var threadUsage: (() -> ThreadUsage)?

    public struct ThreadUsage: Sendable {
        public var faults: UInt64, voluntarySwitches: UInt64, involuntarySwitches: UInt64
        public init(faults: UInt64, voluntarySwitches: UInt64, involuntarySwitches: UInt64) {
            self.faults = faults
            self.voluntarySwitches = voluntarySwitches
            self.involuntarySwitches = involuntarySwitches
        }
    }

    nonisolated(unsafe) public static var currentThreadID: (() -> Int)?

    private var holderSamples: [String: UInt64] = [:]
    private var waitingHolderSamples: [String: UInt64] = [:]
    private var holderSampleCount: UInt64 = 0
    private var idleSampleCount: UInt64 = 0
    private var staleSampleCount: UInt64 = 0
    private var futexSamples: [UInt: UInt64] = [:]
    nonisolated(unsafe) private static var lockNames: [UInt: String] = [:]
    private static let lockNamesMutex = NSLock()

    public static func nameLock(_ address: UnsafeMutableRawPointer?, _ name: String) {
        guard profiling, let address else { return }
        lockNamesMutex.lock()
        lockNames[UInt(bitPattern: address)] = name
        lockNamesMutex.unlock()
    }

    public init(path: String) { self.path = path }

    func noteHandler(_ key: Int64, _ nanoseconds: UInt64) {
        mutex.lock()
        defer { mutex.unlock() }
        rows[key, default: Row()].count &+= 1
        rows[key, default: Row()].handlerNanoseconds &+= nanoseconds
    }

    func noteHold(_ key: Int64, _ nanoseconds: UInt64, usage: ThreadUsage? = nil) {
        mutex.lock()
        defer { mutex.unlock() }
        var r = rows[key, default: Row()]
        r.acquisitions &+= 1
        r.holdNanoseconds &+= nanoseconds
        r.maxHoldNanoseconds = max(r.maxHoldNanoseconds, nanoseconds)
        if let usage {
            r.faults &+= usage.faults
            if usage.faults > 0 {
                r.faultHolds &+= 1
                r.faultHoldNanoseconds &+= nanoseconds
            }
            if usage.voluntarySwitches > 0 {
                r.blockedHolds &+= 1
                r.blockedHoldNanoseconds &+= nanoseconds
            }
            if usage.involuntarySwitches > 0 {
                r.preemptedHolds &+= 1
                r.preemptedHoldNanoseconds &+= nanoseconds
            }
        }
        rows[key] = r
    }

    func noteWait(_ key: Int64, _ nanoseconds: UInt64, contended: Bool) {
        mutex.lock()
        defer { mutex.unlock() }
        var r = rows[key, default: Row()]
        r.waits &+= 1
        if contended { r.contended &+= 1 }
        r.waitNanoseconds &+= nanoseconds
        r.maxWaitNanoseconds = max(r.maxWaitNanoseconds, nanoseconds)
        rows[key] = r
    }

    static func key(for context: ThreadContext?) -> Int64 {
        guard let context else { return serviceKey }
        if let trap = context.trapInProgress { return filtered(Int64(Int32(truncatingIfNeeded: trap.x16)), kernel: context.kernel) }
        if let arriving = context.arrivingTrap { return filtered(Int64(Int32(truncatingIfNeeded: arriving)), kernel: context.kernel) }
        return serviceKey
    }

    public static func name(_ key: Int64) -> String {
        if key == serviceKey { return "(service: no trap)" }
        if key == otherProcessesKey { return "(other processes)" }
        if key == Int64(Int32.min) { return "platform" }
        if key < 0 { return "mach \(TrapNames.mach(Int(key)).name) (\(key))" }
        if key < 0x10000 { return "bsd \(key) \(TrapNames.bsd(Int(key)).name)" }
        let low = UInt32(truncatingIfNeeded: key)
        if (DarwinKernel.Private.rangeStart...DarwinKernel.Private.rangeEnd).contains(low) {
            return String(format: "private 0x%x", low)
        }
        return String(format: "0x%llx", key)
    }

    public var snapshot: [Int64: Row] {
        mutex.lock()
        defer { mutex.unlock() }
        return rows
    }

    public func snapshotRows() -> [Int64: Row] {
        mutex.lock()
        defer { mutex.unlock() }
        return rows
    }

    public func report(limit: Int = TrapProfile.rowLimit) -> String {
        let (snapshot, elapsed): ([Int64: Row], TimeInterval) = {
            mutex.lock()
            defer { mutex.unlock() }
            return (rows, Date().timeIntervalSince(started))
        }()
        func sum(_ field: (Row) -> UInt64) -> UInt64 { snapshot.values.reduce(UInt64(0)) { $0 &+ field($1) } }
        let totalHold = sum(\.holdNanoseconds), totalWait = sum(\.waitNanoseconds)
        let totalCount = sum(\.count), totalHandler = sum(\.handlerNanoseconds)
        let totalAcquisitions = sum(\.acquisitions), totalWaits = sum(\.waits), totalContended = sum(\.contended)
        var out = "swiftcode trap lock profile: \(fixed(elapsed, 1)) s elapsed, \(totalCount) traps, "
            + "handler \(fixed(Double(totalHandler) / 1e9, 1)) s, lock held \(fixed(Double(totalHold) / 1e9, 1)) s "
            + "(\(fixed(elapsed > 0 ? 100 * Double(totalHold) / 1e9 / elapsed : 0, 1)) % busy), "
            + "lock wait \(fixed(Double(totalWait) / 1e9, 1)) s\n"
        out += "Acquisitions \(totalAcquisitions) (\(fixed(totalCount == 0 ? 0 : Double(totalAcquisitions) / Double(totalCount), 2)) per trap); "
            + "lock calls \(totalWaits), contended \(totalContended) "
            + "(\(fixed(totalWaits == 0 ? 0 : 100 * Double(totalContended) / Double(totalWaits), 1)) %)\n"
        if Self.threadUsage != nil {
            let pct = { (ns: UInt64) in self.fixed(totalHold == 0 ? 0 : 100 * Double(ns) / Double(totalHold), 1) }
            out += "Hold time in holds that faulted \(pct(sum(\.faultHoldNanoseconds))) % (\(sum(\.faults)) faults in "
                + "\(sum(\.faultHolds)) holds), blocked in the host kernel \(pct(sum(\.blockedHoldNanoseconds))) % "
                + "(\(sum(\.blockedHolds)) holds), preempted \(pct(sum(\.preemptedHoldNanoseconds))) % "
                + "(\(sum(\.preemptedHolds)) holds)\n"
        }
        if let extra = extraReport?() { out += extra + "\n" }
        let (samples, idle, stale, states, waiting): (UInt64, UInt64, UInt64, [String: UInt64], [String: UInt64]) = {
            mutex.lock()
            defer { mutex.unlock() }
            return (holderSampleCount, idleSampleCount, staleSampleCount, holderSamples, waitingHolderSamples)
        }()
        if samples > 0 {
            let held = samples &- idle
            out += "Kernel-lock holder samples \(samples) (lock free in \(idle); \(stale) more dropped: the hold ended during the read); holder state and wchan: "
                + states.sorted { $0.value > $1.value }.prefix(15).map {
                    "\($0.key) \(fixed(held == 0 ? 0 : 100 * Double($0.value) / Double(held), 1)) %"
                }.joined(separator: ", ") + "\n"
            out += "Holders not running, by trap: " + waiting.sorted { $0.value > $1.value }.prefix(20).map {
                "\($0.key) \(fixed(held == 0 ? 0 : 100 * Double($0.value) / Double(held), 1)) %"
            }.joined(separator: "; ") + "\n"
            let futexes: [UInt: UInt64] = { mutex.lock(); defer { mutex.unlock() }; return futexSamples }()
            if !futexes.isEmpty {
                let names: [UInt: String] = { Self.lockNamesMutex.lock(); defer { Self.lockNamesMutex.unlock() }; return Self.lockNames }()
                let regions = Self.mappings()
                out += "Holders in a futex wait, by futex word: " + futexes.sorted { $0.value > $1.value }.prefix(12).map { item in
                    let place = names[item.key] ?? Self.region(item.key, regions)
                    return String(format: "0x%lx", item.key) + " (\(place)) \(fixed(held == 0 ? 0 : 100 * Double(item.value) / Double(held), 1)) %"
                }.joined(separator: "; ") + "\n"
            }
        }
        out += "Times in ms unless noted (hold and wait are kernel-lock time; means in us; acq = acquisitions).\n"
        let columns: [(String, Int)] = [("#", 3), ("trap", 40), ("count", 10), ("acq", 10), ("acq/trap", 8),
                                        ("handler", 10), ("hold", 10), ("hold max", 9), ("hold us", 9),
                                        ("wait", 9), ("wait max", 9), ("wait us", 9), ("cont %", 6), ("hold %", 6),
                                        ("flt/acq", 7), ("flt h%", 6), ("blk h%", 6), ("pre h%", 6)]
        func line(_ cells: [String]) -> String {
            var s = ""
            for (i, cell) in cells.enumerated() {
                let width = columns[i].1
                s += (i == 1 ? pad(cell, width, left: true) : pad(cell, width, left: false)) + (i + 1 < cells.count ? " " : "")
            }
            return s + "\n"
        }
        func table(_ title: String, _ sorted: [(key: Int64, value: Row)]) {
            out += "\n== top \(limit) by \(title) ==\n"
            out += line(columns.map(\.0))
            for (rank, item) in sorted.prefix(limit).enumerated() {
                let r = item.value
                let holdMean = r.acquisitions == 0 ? 0 : Double(r.holdNanoseconds) / Double(r.acquisitions) / 1e3
                let waitMean = r.waits == 0 ? 0 : Double(r.waitNanoseconds) / Double(r.waits) / 1e3
                let share = totalHold == 0 ? 0 : 100 * Double(r.holdNanoseconds) / Double(totalHold)
                let perTrap = r.count == 0 ? 0 : Double(r.acquisitions) / Double(r.count)
                let contendedShare = r.waits == 0 ? 0 : 100 * Double(r.contended) / Double(r.waits)
                out += line([
                    "\(rank + 1)", Self.name(item.key), "\(r.count)", "\(r.acquisitions)", fixed(perTrap, 2),
                    fixed(Double(r.handlerNanoseconds) / 1e6, 1), fixed(Double(r.holdNanoseconds) / 1e6, 1),
                    fixed(Double(r.maxHoldNanoseconds) / 1e6, 2), fixed(holdMean, 1),
                    fixed(Double(r.waitNanoseconds) / 1e6, 1), fixed(Double(r.maxWaitNanoseconds) / 1e6, 2),
                    fixed(waitMean, 1), fixed(contendedShare, 1), fixed(share, 1),
                    fixed(r.acquisitions == 0 ? 0 : Double(r.faults) / Double(r.acquisitions), 2),
                    fixed(within(r.faultHoldNanoseconds, r.holdNanoseconds), 1),
                    fixed(within(r.blockedHoldNanoseconds, r.holdNanoseconds), 1),
                    fixed(within(r.preemptedHoldNanoseconds, r.holdNanoseconds), 1),
                ])
            }
        }
        let entries = Array(snapshot)
        table("lock hold time", entries.sorted { $0.value.holdNanoseconds > $1.value.holdNanoseconds })
        table("count", entries.sorted { $0.value.count > $1.value.count })
        table("lock wait time", entries.sorted { $0.value.waitNanoseconds > $1.value.waitNanoseconds })
        table("acquisitions", entries.sorted { $0.value.acquisitions > $1.value.acquisitions })
        return out
    }

    private func within(_ part: UInt64, _ whole: UInt64) -> Double {
        whole == 0 ? 0 : 100 * Double(part) / Double(whole)
    }

    private func fixed(_ value: Double, _ digits: Int) -> String {
        String(format: "%.\(digits)f", value)
    }

    private func pad(_ text: String, _ width: Int, left: Bool) -> String {
        let fill = String(repeating: " ", count: max(0, width - text.count))
        return left ? text + fill : fill + text
    }

    public func dump() {
        let text = report()
        try? text.write(toFile: path, atomically: true, encoding: .utf8)
    }

    public func startHolderSampler(lock: KernelLock, every microseconds: UInt32) {
        let thread = Thread { [self] in
            while true {
                usleep(microseconds)
                let sequence = lock.holdSequence
                let tid = lock.holderThreadID
                let trap = lock.holderTrapKey
                guard tid != 0 else {
                    mutex.lock(); holderSampleCount &+= 1; idleSampleCount &+= 1; mutex.unlock()
                    continue
                }
                let state = Self.procField("/proc/self/task/\(tid)/stat")
                let wchan = Self.procField("/proc/self/task/\(tid)/wchan")
                var code = "?"
                if let state, let close = state.lastIndex(of: ")") {
                    let rest = state[state.index(after: close)...].drop { $0 == " " }
                    if let c = rest.first { code = String(c) }
                }
                let key = code == "R" ? "R" : "\(code) \(wchan.flatMap { $0.isEmpty || $0 == "0" ? nil : $0 } ?? "-")"
                var futex: UInt?
                if code == "S", wchan?.contains("futex") == true,
                   let call = Self.procField("/proc/self/task/\(tid)/syscall")?.split(separator: " "),
                   call.count > 1, call[0] == "98", call[1].hasPrefix("0x") {
                    futex = UInt(call[1].dropFirst(2), radix: 16)
                }
                guard lock.holdSequence == sequence else {
                    mutex.lock(); staleSampleCount &+= 1; mutex.unlock()
                    continue
                }
                mutex.lock()
                if let futex { futexSamples[futex, default: 0] &+= 1 }
                holderSampleCount &+= 1
                holderSamples[key, default: 0] &+= 1
                if code != "R" { waitingHolderSamples[Self.name(trap) + ": " + key, default: 0] &+= 1 }
                mutex.unlock()
            }
        }
        thread.name = "swiftcode lock holder sampler"
        thread.start()
    }

    private static func mappings() -> [(start: UInt, end: UInt, offset: UInt, path: String)] {
        guard let text = try? String(contentsOfFile: "/proc/self/maps", encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            let f = line.split(separator: " ", omittingEmptySubsequences: true)
            guard f.count >= 5 else { return nil }
            let range = f[0].split(separator: "-")
            guard range.count == 2, let a = UInt(range[0], radix: 16), let b = UInt(range[1], radix: 16) else { return nil }
            return (a, b, UInt(f[2], radix: 16) ?? 0, f.count > 5 ? f[5...].joined(separator: " ") : "anon")
        }
    }

    private static func region(_ address: UInt, _ maps: [(start: UInt, end: UInt, offset: UInt, path: String)]) -> String {
        guard let m = maps.first(where: { $0.start <= address && address < $0.end }) else { return "unmapped" }
        let name = m.path.split(separator: "/").last.map(String.init) ?? m.path
        return m.path.hasPrefix("/") ? name + String(format: "+0x%lx", address - m.start + m.offset) : name
    }

    private static func procField(_ path: String) -> String? {
        let fd = open(path, O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var buffer = [UInt8](repeating: 0, count: 512)
        let n = read(fd, &buffer, buffer.count)
        guard n > 0 else { return nil }
        return String(decoding: buffer[0..<n], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func startPeriodicDump(every seconds: TimeInterval = TrapProfile.dumpInterval) {
        let thread = Thread { [self] in
            while true {
                Thread.sleep(forTimeInterval: seconds)
                dump()
            }
        }
        thread.name = "swiftcode trap profile"
        thread.start()
    }
}
