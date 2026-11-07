import Foundation
import SwiftCodeBuild
import SwiftCodeIDECore

public struct PackageBuildEngine: BuildEngine {
    public var name: String { "swiftpm" }
    public var swift: [String]
    public var environment: [String: String]

    public init(swift: [String] = ["/usr/bin/env", "swift"], environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.swift = swift
        self.environment = environment
    }

    public static func arguments(for r: BuildRequest) -> [String]? {
        guard case .package(let dir) = r.container else { return nil }
        let release = r.configuration?.lowercased() == "release" ? ["-c", "release"] : []
        switch r.action {
        case .clean: return ["package", "--package-path", dir, "clean"]
        case .test, .testWithoutBuilding: return ["test", "--package-path", dir] + release
        case .buildForTesting: return ["build", "--package-path", dir, "--build-tests"] + release
        default: return ["build", "--package-path", dir] + release
        }
    }

    public static func activity(for line: String) -> String? {
        var rest = Substring(line)
        if rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
            rest = rest[rest.index(after: close)...].drop { $0 == " " }
        }
        let words = rest.split(separator: " ")
        guard let verb = words.first else { return nil }
        switch verb {
        case "Compiling", "Emitting", "Linking", "Write", "Planning", "Building":
            if verb == "Building", words.dropFirst().first == "for" { return "Planning" }
            let object = words.last.map(String.init) ?? ""
            let label = verb == "Write" ? "Writing" : String(verb)
            return words.count > 1 ? "\(label) \(object)" : label
        default:
            return nil
        }
    }

    public func start(_ request: BuildRequest) -> BuildOperation {
        guard let args = Self.arguments(for: request) else {
            return Self.failed("swiftcode: this engine builds Swift packages only; open the package folder.")
        }
        if swift == ["/usr/bin/env", "swift"], ShellToolchain.locate("swift", environment: environment) == nil { return Self.failed(issue: ShellToolchain.noSwift) }
        return SwiftPMRun.start(swift + args, currentDirectory: request.container.path)
    }

    public func executablePath(for request: BuildRequest) -> String? {
        guard case .package(let dir) = request.container else { return nil }
        let release = request.configuration?.lowercased() == "release" ? ["-c", "release"] : []
        guard let described = Self.run(swift + ["package", "--package-path", dir, "describe", "--type", "json"]),
              let products = Self.executableProducts(describeJSON: Data(described.utf8)), !products.isEmpty,
              let bin = Self.run(swift + ["build", "--package-path", dir, "--show-bin-path"] + release)?
                .trimmingCharacters(in: .whitespacesAndNewlines), !bin.isEmpty else { return nil }
        let name = products.first { $0 == request.scheme } ?? products[0]
        return (bin as NSString).appendingPathComponent(name)
    }

    public static func executableProducts(describeJSON data: Data) -> [String]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let products = root["products"] as? [[String: Any]] else { return nil }
        return products.compactMap { p in
            guard let name = p["name"] as? String, let type = p["type"] as? [String: Any], type.keys.contains("executable") else { return nil }
            return name
        }
    }

    static func run(_ args: [String]) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: args[0])
        p.arguments = Array(args.dropFirst())
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }

    static func failed(issue message: String) -> BuildOperation {
        let (stream, continuation) = AsyncStream<BuildEvent>.makeStream()
        continuation.yield(.output(message))
        let issue = Diagnostic(severity: .error, message: message, location: nil)
        continuation.yield(.finished(BuildResult(status: .failed, exitCode: -1, issues: [issue])))
        continuation.finish()
        return BuildOperation(events: stream, cancel: {})
    }

    static func failed(_ message: String) -> BuildOperation {
        let (stream, continuation) = AsyncStream<BuildEvent>.makeStream()
        continuation.yield(.output(message))
        continuation.yield(.finished(BuildResult(status: .failed, exitCode: -1, issues: [])))
        continuation.finish()
        return BuildOperation(events: stream, cancel: {})
    }
}

enum SwiftPMRun {
    static func start(_ args: [String], currentDirectory: String) -> BuildOperation {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: args[0])
        process.arguments = Array(args.dropFirst())
        process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
        var env = ProcessInfo.processInfo.environment
        env["NO_COLOR"] = "1"
        env["TERM"] = "dumb"
        process.environment = env
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        let cancelled = CancelFlag()
        let (stream, continuation) = AsyncStream<BuildEvent>.makeStream()
        let thread = Thread {
            var lines = LineBuffer()
            var parser = DiagnosticParser()
            var counter = LogTaskCounter()
            var summaries: [Diagnostic] = []
            var log: [String] = []
            var issues: [Diagnostic] = []
            func report(_ ds: [Diagnostic]) {
                for d in ds {
                    if isSummary(d) { summaries.append(d); continue }
                    issues.append(d)
                    continuation.yield(.issue(d))
                }
            }
            func handle(_ raw: String) {
                let line = stripANSI(raw)
                log.append(line)
                continuation.yield(.output(line))
                if let p = counter.feed(line) { continuation.yield(.progress(done: p.done, total: p.total)) }
                if let a = PackageBuildEngine.activity(for: line) { continuation.yield(.activity(a)) }
                report(parser.feed(line))
            }
            do {
                try process.run()
            } catch {
                continuation.yield(.output("swiftcode: cannot run \(args[0]): \(error)"))
                continuation.yield(.finished(BuildResult(status: .failed, exitCode: -1, issues: [])))
                continuation.finish()
                return
            }
            let reader = pipe.fileHandleForReading
            while true {
                let data = reader.availableData
                if data.isEmpty { break }
                lines.append(data).forEach(handle)
            }
            if let last = lines.flush() { handle(last) }
            report(parser.finish())
            process.waitUntilExit()
            if !issues.contains(where: { $0.severity == .error }) {
                for d in summaries {
                    issues.append(d)
                    continuation.yield(.issue(d))
                }
            }
            let code = process.terminationStatus
            if let d = toolMissing(status: code, log: log, issues: issues) {
                issues.append(d)
                continuation.yield(.issue(d))
            }
            let status: BuildStatus = cancelled.isSet ? .cancelled : (code == 0 ? .succeeded : .failed)
            continuation.yield(.finished(BuildResult(status: status, exitCode: code, issues: issues)))
            continuation.finish()
        }
        thread.start()
        return BuildOperation(events: stream) {
            cancelled.set()
            if process.isRunning { process.interrupt() }
        }
    }

    static func toolMissing(status: Int32, log: [String], issues: [Diagnostic]) -> Diagnostic? {
        guard status == 127, !issues.contains(where: { $0.severity == .error }) else { return nil }
        let text = log.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        return Diagnostic(severity: .error, message: text.isEmpty ? ShellToolchain.noSwift : text, location: nil)
    }

    static func isSummary(_ d: Diagnostic) -> Bool {
        guard d.severity == .error, d.location == nil else { return false }
        return d.message == "Build failed" || d.message.lowercased() == "fatalerror" || d.message.hasSuffix("failed with a nonzero exit code")
            || d.message.contains("failed with a nonzero exit code. Command line:")
    }

    static func stripANSI(_ s: String) -> String {
        guard s.contains("\u{1B}") else { return s }
        var out = ""
        var it = s.unicodeScalars.makeIterator()
        while let c = it.next() {
            guard c == "\u{1B}" else { out.unicodeScalars.append(c); continue }
            guard let next = it.next() else { break }
            guard next == "[" else { continue }
            while let b = it.next(), !(0x40...0x7E).contains(b.value) {}
        }
        return out
    }

    final class CancelFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.withLock { value = true } }
        var isSet: Bool { lock.withLock { value } }
    }
}

public enum ShellToolchain {
    public static let noSwift = "SwiftCode could not find a Swift toolchain. Install Swift 6 or later (swift.org/install), make sure `swift` is on your PATH, then build again."
    public static let noBuildTool = "SwiftCode could not find its build tool, swiftcodebuild. It ships with SwiftCode; if you built SwiftCode from source, build the swiftcodebuild product too."

    public static let noAppleSDK = "This project is for Apple platforms, and My Computer cannot build it here: that takes the platform's SDK, which SwiftCode does not include. "
        + "Swift packages build and run on this computer. Building for a SwiftCode simulator host is experimental and needs your own SDK; see the README."

    public static func locate(_ tool: String, environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        for dir in (environment["PATH"] ?? "").split(separator: ":") where FileManager.default.isExecutableFile(atPath: "\(dir)/\(tool)") {
            return "\(dir)/\(tool)"
        }
        return nil
    }
}

struct LinuxProjectEngine: BuildEngine {
    var inner: BuildEngine
    var name: String { inner.name }
    func start(_ request: BuildRequest) -> BuildOperation {
        guard request.destination == ShellBuildSetup.hostDestination.specifier, request.action != .clean else { return inner.start(request) }
        return PackageBuildEngine.failed(issue: ShellToolchain.noAppleSDK)
    }
    func executablePath(for request: BuildRequest) -> String? {
        request.destination == ShellBuildSetup.hostDestination.specifier ? nil : inner.executablePath(for: request)
    }
}

struct MissingToolEngine: BuildEngine {
    var name: String { "missing" }
    var message: String
    func start(_ request: BuildRequest) -> BuildOperation { PackageBuildEngine.failed(issue: message) }
    func executablePath(for request: BuildRequest) -> String? { nil }
}

public enum ShellBuildSetup {
    public static var hostDestination: Destination {
        #if os(Linux)
        Destination(name: "My Computer", specifier: "platform=Linux", platform: "Linux", kind: .mac)
        #else
        .myMac
        #endif
    }

    public static func destinationGroups(for model: WorkspaceModel) -> [DestinationGroup] {
        #if os(Linux)
        [DestinationGroup(title: "My Computer", destinations: [hostDestination])]
        #else
        model.destinationGroups
        #endif
    }

    public static func engine(environment: [String: String] = ProcessInfo.processInfo.environment) -> BuildEngine {
        #if os(Linux)
        let swiftcodebuild: BuildEngine = TestRunnerSelection.locateSwiftCodebuild(environment: environment).map { LinuxProjectEngine(inner: XcodebuildEngine(command: [$0])) }
            ?? MissingToolEngine(message: ShellToolchain.noBuildTool)
        if environment["SWIFTCODE_IDE_ENGINE"] == "swiftcodebuild" { return swiftcodebuild }
        return FallbackEngine(primary: PackageBuildEngine(), fallback: swiftcodebuild) { r in
            if case .package = r.container { return true }
            return false
        }
        #else
        _ = environment
        return BuildSystemPreference.current().makeEngine()
        #endif
    }
}
