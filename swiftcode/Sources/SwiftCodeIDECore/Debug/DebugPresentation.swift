#if canImport(Darwin)
import Darwin
#endif
import Foundation
import SwiftCodeDebug
import SwiftCodeSubprocess

public enum DebugPresentation {

    public static func runningTitle(_ product: String?, on device: String? = nil) -> String {
        (product.map { "Running \($0)" } ?? "Running") + (device.map { " on \($0)" } ?? "")
    }
    public static func pausedTitle(_ product: String?) -> String { product.map { "Paused \($0)" } ?? "Paused" }
    public static func finishedTitle(_ product: String?, on device: String? = nil) -> String {
        "Finished running" + (product.map { " " + $0 } ?? "") + (device.map { " on \($0)" } ?? "")
    }

    public static func stopAnnotation(thread: Int, breakpointID: String?, hits: Int?, reason: String?) -> String {
        if let id = breakpointID { return "Thread \(thread): breakpoint \(id)" + (hits.map { " (\($0))" } ?? "") }
        return "Thread \(thread)" + (reason.map { ": \($0)" } ?? "")
    }

    public static func threadIndex(_ t: DebugThread) -> Int {
        let name = t.name.trimmingCharacters(in: .whitespaces)
        guard name.hasPrefix("Thread ") else { return t.id }
        return Int(name.dropFirst(7).prefix { $0.isNumber }) ?? t.id
    }

    public static func queueKind(_ label: String) -> String {
        let l = label.lowercased()
        if l.contains(".root.") || l.contains("global") || l.contains("concurrent") || l.hasSuffix("-qos") { return "concurrent" }
        return "serial"
    }

    public static func threadRow(_ t: DebugThread) -> String {
        let n = threadIndex(t)
        if let q = t.queue, !q.isEmpty { return "Thread \(n)  Queue: \(q) (\(queueKind(q)))" }
        if let r = t.name.range(of: " name = ") { return "Thread \(n)  \(t.name[r.upperBound...])" }
        return "Thread \(n)"
    }

    public static func truncateMiddle(_ s: String, max: Int) -> String {
        guard s.count > max, max > 1 else { return s }
        let keep = max - 1
        return String(s.prefix((keep + 1) / 2)) + "…" + String(s.suffix(keep / 2))
    }

    public static func isUserFrame(_ f: StackFrame) -> Bool {
        guard let file = f.file, file.hasPrefix("/") else { return false }
        let prefixes = ["/usr/", "/System/", "/Library/Developer/", "/Applications/Xcode", "/AppleInternal/"]
        return !prefixes.contains { file.hasPrefix($0) } && !file.contains(".xctoolchain/") && !file.contains(".platform/Developer/")
    }

    public enum FrameRow: Equatable {
        case frame(index: Int, StackFrame, user: Bool)
        case separator
    }

    public static func groupFrames(_ frames: [StackFrame], isUser: (StackFrame) -> Bool = isUserFrame) -> [FrameRow] {
        let user = frames.map(isUser)
        guard user.contains(true) else { return frames.enumerated().map { .frame(index: $0.offset, $0.element, user: false) } }
        var out: [FrameRow] = []
        var i = 0
        while i < frames.count {
            if user[i] { out.append(.frame(index: i, frames[i], user: true)); i += 1; continue }
            if i > 0 { out.append(.separator) }
            out.append(.frame(index: i, frames[i], user: false))
            while i < frames.count && !user[i] { i += 1 }
        }
        return out
    }

    public static func badge(name: String, scope: String, frameName: String?) -> String {
        if name == "self" || scope.localizedCaseInsensitiveContains("argument") { return "A" }
        return argumentNames(frameName ?? "").contains(name) ? "A" : "L"
    }

    public static func argumentNames(_ function: String) -> Set<String> {
        guard let open = function.firstIndex(of: "("), let close = function.lastIndex(of: ")"), open < close else { return [] }
        let inside = function[function.index(after: open)..<close]
        var out = Set<String>()
        for part in inside.split(separator: ",") {
            let p = part.trimmingCharacters(in: .whitespaces)
            if let colon = p.firstIndex(of: ":") {
                let words = p[..<colon].split(separator: " ")
                if let w = words.last, w != "_" { out.insert(String(w)) }
                if !p[p.index(after: colon)...].trimmingCharacters(in: .whitespaces).isEmpty, let f = words.first, f != "_" { out.insert(String(f)) }
            } else {
                let ident = p.reversed().drop { !($0.isLetter || $0.isNumber || $0 == "_") }.prefix { $0.isLetter || $0.isNumber || $0 == "_" }
                if !ident.isEmpty { out.insert(String(ident.reversed())) }
            }
        }
        return out
    }

    public static func variableRow(badge: String, _ v: Variable) -> String {
        let type = v.type.flatMap { $0.isEmpty || $0 == "<no-type>" ? nil : $0 }
        return "\(badge) \(v.name)" + (type.map { ": \($0)" } ?? "") + " = \(v.value)"
    }

    public static func sessionEndedLine(code: Int, reason: String) -> String { "Debug session ended with code \(code): \(reason)" }
    public static let killedLine = sessionEndedLine(code: 9, reason: "killed")
}

public struct ProcessGauges: Equatable, Sendable {
    public var cpuPercent: Double = 0
    public var memoryBytes: UInt64 = 0
    public var diskBytesPerSecond: Double = 0
    public var networkBytesPerSecond: Double = 0
    public init() {}

    public var energyImpact: String {
        switch cpuPercent {
        case ..<0.5: "Zero"
        case ..<20: "Low"
        case ..<60: "High"
        default: "Very High"
        }
    }

    public var energyLevel: Double {
        switch energyImpact {
        case "Low": 0.25
        case "High": 0.6
        case "Very High": 1
        default: 0
        }
    }

    public static func bytes(_ b: Double) -> String {
        if b < 1024 { return "Zero KB" }
        let units = ["KB", "MB", "GB", "TB"]
        var v = b / 1024
        var i = 0
        while v >= 1024 && i < units.count - 1 { v /= 1024; i += 1 }
        return (v < 10 && i > 0 ? String(format: "%.1f", v) : String(Int(v.rounded()))) + " " + units[i]
    }

    public var rows: [(String, String)] {
        [("CPU", "\(Int(cpuPercent.rounded()))%"), ("Memory", Self.bytes(Double(memoryBytes))), ("Energy Impact", energyImpact),
         ("Disk", Self.bytes(diskBytesPerSecond) + "/s"), ("Network", Self.bytes(networkBytesPerSecond) + "/s")]
    }
}

#if canImport(Darwin)
public final class ProcessGaugeSampler {
    public let pid: Int32
    private var last: (time: UInt64, cpu: UInt64, disk: UInt64, wall: Date)?
    private let timebase: (numer: UInt32, denom: UInt32) = {
        var t = mach_timebase_info_data_t()
        mach_timebase_info(&t)
        return (t.numer, max(1, t.denom))
    }()

    public init(pid: Int32) { self.pid = pid }

    public func sample() -> ProcessGauges? {
        var info = rusage_info_v2()
        let r = withUnsafeMutablePointer(to: &info) { p in
            p.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V2, $0) }
        }
        guard r == 0 else { return nil }
        let cpuNanos = (info.ri_user_time + info.ri_system_time) &* UInt64(timebase.numer) / UInt64(timebase.denom)
        let disk = info.ri_diskio_bytesread + info.ri_diskio_byteswritten
        let now = Date()
        var g = ProcessGauges()
        g.memoryBytes = info.ri_phys_footprint
        if let last {
            let wall = max(0.001, now.timeIntervalSince(last.wall))
            g.cpuPercent = max(0, Double(cpuNanos &- last.cpu) / 1e9 / wall * 100)
            g.diskBytesPerSecond = max(0, Double(disk &- last.disk) / wall)
        }
        last = (0, cpuNanos, disk, now)
        return g
    }
}
#else
public final class ProcessGaugeSampler {
    public let pid: Int32
    private var last: (cpu: Double, disk: UInt64, wall: Date)?
    private let ticksPerSecond = Double(max(1, sysconf(Int32(_SC_CLK_TCK))))

    public init(pid: Int32) { self.pid = pid }

    public func sample() -> ProcessGauges? {
        func read(_ name: String) -> String? { try? String(contentsOfFile: "/proc/\(pid)/\(name)", encoding: .utf8) }
        guard let stat = read("stat"), let close = stat.lastIndex(of: ")") else { return nil }
        let fields = stat[stat.index(after: close)...].split(separator: " ")
        guard fields.count > 12, let user = Double(fields[11]), let system = Double(fields[12]) else { return nil }
        let cpu = (user + system) / ticksPerSecond
        var g = ProcessGauges()
        if let status = read("status"), let line = status.split(separator: "\n").first(where: { $0.hasPrefix("VmRSS:") }),
           let kb = line.split(separator: " ").dropFirst().first.flatMap({ UInt64($0) }) {
            g.memoryBytes = kb * 1024
        }
        var disk: UInt64 = 0
        for line in (read("io") ?? "").split(separator: "\n") where line.hasPrefix("read_bytes:") || line.hasPrefix("write_bytes:") {
            disk += line.split(separator: " ").last.flatMap { UInt64($0) } ?? 0
        }
        let now = Date()
        if let last {
            let wall = max(0.001, now.timeIntervalSince(last.wall))
            g.cpuPercent = max(0, (cpu - last.cpu) / wall * 100)
            g.diskBytesPerSecond = max(0, Double(disk &- last.disk) / wall)
        }
        last = (cpu, disk, now)
        return g
    }
}
#endif

public enum GitBranchLookup {
    public static func current(at path: String) -> String? {
        MainThreadGuard.blockingCall("git rev-parse --abbrev-ref HEAD")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: HostTool.path("git"))
        p.arguments = ["-C", path, "rev-parse", "--abbrev-ref", "HEAD"]
        p.environment = GitRepository.environment
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let s = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty || s == "HEAD" ? nil : s
    }
}
