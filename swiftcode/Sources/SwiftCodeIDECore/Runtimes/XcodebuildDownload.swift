import Foundation

public struct XcodebuildDownload: Sendable, Equatable {
    public var platform: SimPlatform
    public var exportPath: String?
    public var buildVersion: String?

    public init(platform: SimPlatform, exportPath: String? = nil, buildVersion: String? = nil) {
        self.platform = platform
        self.exportPath = exportPath
        self.buildVersion = buildVersion
    }

    public static func tool(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let t = environment["SWIFTCODE_XCODEBUILD"], !t.isEmpty { return t }
        return "/usr/bin/xcodebuild"
    }

    public func arguments(tool: String = "xcodebuild") -> [String] {
        var a = [tool, "-downloadPlatform", platform.downloadName]
        if let b = buildVersion, !b.isEmpty { a += ["-buildVersion", b] }
        if let e = exportPath, !e.isEmpty { a += ["-exportPath", e] }
        return a
    }

    public var shownCommand: String { RuntimeCommands.line(arguments()) }
}

public struct XcodebuildProgress: Sendable, Equatable {
    public var fraction: Double?
    public var done: Int64?
    public var total: Int64?
    public var line: String
    public var stage: String?

    nonisolated(unsafe) static let sizes = try? NSRegularExpression(
        pattern: #"([0-9]+(?:\.[0-9]+)?)\s*([KMGT]?B|bytes)\s*(?:of|/)\s*([0-9]+(?:\.[0-9]+)?)\s*([KMGT]?B|bytes)"#, options: [.caseInsensitive])
    static let units: [String: Double] = ["B": 1, "BYTES": 1, "KB": 1024, "MB": 1_048_576, "GB": 1_073_741_824, "TB": 1_099_511_627_776]

    public static func parse(_ chunk: String) -> XcodebuildProgress? {
        var best: XcodebuildProgress?
        for raw in chunk.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            var p = XcodebuildProgress(line: line)
            if let m = line.range(of: #"([0-9]+(?:\.[0-9]+)?)\s*%"#, options: .regularExpression) {
                let n = line[m].filter { "0123456789.".contains($0) }
                p.fraction = Double(n).map { min(1, $0 / 100) }
            }
            let ns = line as NSString
            if let m = sizes?.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) {
                func bytes(_ v: Int, _ u: Int) -> Int64? {
                    guard let x = Double(ns.substring(with: m.range(at: v))), let scale = units[ns.substring(with: m.range(at: u)).uppercased()] else { return nil }
                    return Int64(x * scale)
                }
                if let d = bytes(1, 2), let t = bytes(3, 4) {
                    p.done = d
                    p.total = t
                    if p.fraction == nil, t > 0 { p.fraction = min(1, Double(d) / Double(t)) }
                }
            }
            let lower = line.lowercased()
            for s in ["downloading", "installing", "verifying", "exporting", "mounting"] where lower.hasPrefix(s) || lower.contains(" \(s) ") {
                p.stage = s.prefix(1).uppercased() + s.dropFirst()
                break
            }
            if p.fraction != nil || p.stage != nil { best = p }
        }
        return best
    }
}

public final class XcodebuildDownloadRun: @unchecked Sendable {
    public let download: XcodebuildDownload
    public let tool: String
    private let lock = NSLock()
    private var process: Process?
    private var interrupted = false

    public init(_ d: XcodebuildDownload, tool: String = XcodebuildDownload.tool()) {
        download = d
        self.tool = tool
    }

    public enum Outcome: Sendable, Equatable {
        case finished
        case cancelled
        case failed(Int32, String)
    }

    public func cancel() {
        let p: Process? = lock.withLock { interrupted = true; return process }
        guard let p, p.isRunning else { return }
        p.interrupt()
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) { if p.isRunning { p.terminate() } }
    }

    public func run(output: @escaping @Sendable (String) -> Void, progress: @escaping @Sendable (XcodebuildProgress) -> Void) async -> Outcome {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = Array(download.arguments(tool: tool).dropFirst())
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        lock.withLock { process = p }
        do { try p.run() } catch {
            return .failed(127, "\(tool): \(error.localizedDescription)")
        }
        return await withCheckedContinuation { (k: CheckedContinuation<Outcome, Never>) in
            Thread.detachNewThread { [self] in
                let h = pipe.fileHandleForReading
                var text = Data(), line = Data()
                func parse(_ bytes: Data) {
                    if let pr = XcodebuildProgress.parse(String(decoding: bytes, as: UTF8.self)) { progress(pr) }
                }
                while true {
                    let d = h.availableData
                    if d.isEmpty { break }
                    text.append(d)
                    output(String(decoding: d, as: UTF8.self))
                    for b in d {
                        if b == UInt8(ascii: "\n") || b == UInt8(ascii: "\r") {
                            if !line.isEmpty { parse(line) }
                            line.removeAll(keepingCapacity: true)
                        } else {
                            line.append(b)
                        }
                    }
                }
                if !line.isEmpty { parse(line) }
                p.waitUntilExit()
                let wasInterrupted = lock.withLock { interrupted }
                if p.terminationStatus == 0 { k.resume(returning: .finished) }
                else if wasInterrupted { k.resume(returning: .cancelled) }
                else {
                    let tail = String(decoding: text, as: UTF8.self).split(whereSeparator: \.isNewline).suffix(4).joined(separator: "\n")
                    k.resume(returning: .failed(p.terminationStatus, tail))
                }
            }
        }
    }
}
