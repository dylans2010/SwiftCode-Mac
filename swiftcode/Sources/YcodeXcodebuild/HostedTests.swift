import Foundation

public enum TestHostProtocol {
    public static let prefix = "##swiftcode-test## "

    public struct Event: @unchecked Sendable {
        public var kind: String
        public var fields: [String: Any]
        public subscript(_ key: String) -> Any? { fields[key] }
        public func string(_ key: String) -> String? { fields[key] as? String }
    }

    public static func split(_ line: String) -> (text: String?, event: Event?) {
        guard let r = line.range(of: prefix) else { return (line, nil) }
        let before = String(line[..<r.lowerBound])
        let json = line[r.upperBound...]
        guard let obj = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
              let kind = obj["kind"] as? String else { return (line, nil) }
        return (before.isEmpty ? nil : before, Event(kind: kind, fields: obj))
    }

    public struct Plan: Equatable, Sendable {
        public struct Bundle: Equatable, Sendable {
            public var path: String
            public var module: String
            public var only: [String]
            public var skip: [String]
            public init(path: String, module: String, only: [String] = [], skip: [String] = []) {
                self.path = path
                self.module = module
                self.only = only
                self.skip = skip
            }
        }
        public var session: String
        public var bundles: [Bundle]
        public var repetition: TestPlanFile.Repetition?
        public var launchTimeout: Double = 30

        public init(session: String = UUID().uuidString, bundles: [Bundle], repetition: TestPlanFile.Repetition? = nil) {
            self.session = session
            self.bundles = bundles
            self.repetition = repetition
        }

        public var json: String {
            var o: [String: Any] = [
                "session": session, "launchTimeout": launchTimeout,
                "bundles": bundles.map { ["path": $0.path, "module": $0.module, "only": $0.only, "skip": $0.skip] as [String: Any] },
            ]
            if let r = repetition, r.mode != .none { o["repetition"] = ["mode": r.mode.rawValue, "count": r.count] }
            let data = (try? JSONSerialization.data(withJSONObject: o, options: [.sortedKeys])) ?? Data("{}".utf8)
            return String(decoding: data, as: UTF8.self)
        }
    }

    public static func agent(sdk: String, environment env: [String: String], executableDirectory: String?) -> String? {
        let fm = FileManager.default
        let name = "libSwiftCodeTestAgent.dylib"
        var candidates: [String] = []
        if sdk == "macosx" {
            if let p = env["SWIFTCODE_TEST_AGENT"] { candidates.append(p) }
            if let d = executableDirectory { candidates.append(d + "/" + name) }
        } else {
            if let p = env["SWIFTCODE_TEST_AGENT_" + sdk.uppercased()] { candidates.append(p) }
            if let d = executableDirectory { candidates.append(d + "/" + sdk + "/" + name) }
        }
        return candidates.first { fm.fileExists(atPath: $0) }
    }
}

final class HostRunCollector: @unchecked Sendable {
    struct Part {
        var target: TestTarget
        var parser: TestConsoleParser
        var output = ""
        var loaded = false
    }
    let session: String
    private(set) var parts: [Part]
    private var current: Int?
    private(set) var agentLoaded = false
    private(set) var finished = false
    private(set) var errors: [String] = []
    private(set) var running: String?
    private(set) var hostOutput = ""
    private let lock = NSLock()
    let echo: (String) -> Void

    init(session: String, targets: [TestTarget], echo: @escaping (String) -> Void) {
        self.session = session
        self.parts = targets.map { Part(target: $0, parser: TestConsoleParser(module: $0.moduleName, swiftTests: [])) }
        self.echo = echo
    }

    func feed(_ line: String) {
        lock.lock()
        let (text, event) = TestHostProtocol.split(line)
        if let event, event.string("session") == session || event.string("session") == nil {
            handle(event)
        } else if event != nil {
        }
        let shown = event == nil ? line : text
        lock.unlock()
        if let shown {
            echo(shown)
            lock.lock()
            if let i = current {
                parts[i].parser.feed(shown)
                parts[i].output += shown + "\n"
            } else {
                hostOutput += shown + "\n"
            }
            lock.unlock()
        }
    }

    private func handle(_ e: TestHostProtocol.Event) {
        switch e.kind {
        case "agentLoaded": agentLoaded = true
        case "bundleStarted":
            let path = e.string("path") ?? ""
            current = parts.firstIndex { p in
                !p.loaded && (p.target.bundlePath == path || path.hasSuffix("/" + URL(fileURLWithPath: p.target.bundlePath).lastPathComponent)
                              || path == URL(fileURLWithPath: p.target.bundlePath).lastPathComponent)
            } ?? parts.firstIndex { !$0.loaded }
        case "bundleLoaded":
            if let i = current { parts[i].loaded = true }
        case "bundleFinished":
            if let i = current { parts[i].loaded = true }
            current = nil
        case "swiftTest":
            guard let i = current, let id = e.string("id") else { return }
            parts[i].parser.addSwiftTest(SwiftTestingBridge.TestRecord(id: id, name: e.string("name") ?? "", isSuite: e["isSuite"] as? Bool ?? false,
                                                                     file: e.string("file"), line: e["line"] as? Int))
        case "testStarted":
            let suite = e.string("suite") ?? ""
            running = (suite.isEmpty ? "" : suite + "/") + (e.string("name") ?? "")
        case "testFinished": running = nil
        case "error": errors.append(e.string("message") ?? "The test agent reported an error.")
        case "runFinished": finished = true
        default: break
        }
    }

    var isAgentLoaded: Bool { lock.withLock { agentLoaded } }
    var isFinished: Bool { lock.withLock { finished } }
}

extension TestActions {
    static func testFrameworkCopying(action: BuildAction, sdk: String?) -> [(String, String)] {
        guard [.buildForTesting, .test].contains(action),
              let sdk, (sdk as NSString).lastPathComponent.lowercased().contains("simulator") else { return [] }
        return [("SKIP_COPYING_TEST_FRAMEWORKS", "NO")]
    }

    static func hostedSelection(_ t: TestTarget) -> (only: [String], skip: [String]) {
        (t.only, t.skip)
    }

    static func hostApp(_ t: TestTarget) -> (app: String, executable: String)? {
        guard let exe = t.testHost else { return nil }
        var url = URL(fileURLWithPath: exe)
        while url.path != "/" && url.pathExtension != "app" { url.deleteLastPathComponent() }
        guard url.pathExtension == "app" else { return nil }
        return (url.path, exe)
    }

    static func bundleIdentifier(ofApp app: String) -> String? {
        for rel in ["Info.plist", "Contents/Info.plist"] {
            if let data = FileManager.default.contents(atPath: app + "/" + rel),
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let id = plist["CFBundleIdentifier"] as? String { return id }
        }
        return nil
    }

    static func agentBundlePath(_ t: TestTarget, app: String) -> String {
        let plugins = [app + "/PlugIns/", app + "/Contents/PlugIns/"]
        for p in plugins where t.bundlePath.hasPrefix(p) { return String(t.bundlePath.dropFirst(p.count)) }
        return t.bundlePath
    }

    static func runHostedLocally(_ t: TestTarget, quiet: Bool, context ctx: XcodebuildContext, outcome: inout Outcome) {
        let console = ctx.console
        guard let (app, exe) = hostApp(t) else {
            outcome.errors.append("\(t.blueprintName): the test host \(t.testHost ?? "") is not inside an application bundle.")
            return
        }
        guard FileManager.default.isExecutableFile(atPath: exe) else {
            outcome.errors.append("The test host \(exe) does not exist; build it with build-for-testing first.")
            return
        }
        guard FileManager.default.fileExists(atPath: t.bundlePath) else {
            outcome.errors.append("The test bundle \(t.bundlePath) does not exist; build it with build-for-testing first.")
            return
        }
        guard let agent = TestHostProtocol.agent(sdk: "macosx", environment: ctx.environment, executableDirectory: ctx.executableDirectory) else {
            outcome.errors.append("\(t.blueprintName) runs inside \(URL(fileURLWithPath: app).lastPathComponent), which needs SwiftCode's test agent: build it (swift build --product SwiftCodeTestAgent) next to swiftcodebuild, or set SWIFTCODE_TEST_AGENT to its path.")
            return
        }
        let sel = hostedSelection(t)
        var plan = TestHostProtocol.Plan(bundles: [.init(path: agentBundlePath(t, app: app), module: t.moduleName, only: sel.only, skip: sel.skip)],
                                         repetition: t.repetition)
        plan.launchTimeout = 30
        var env = testEnvironment(t, ctx)
        let inserted = [env["DYLD_INSERT_LIBRARIES"], agent].compactMap { $0 }.filter { !$0.isEmpty }
        env["DYLD_INSERT_LIBRARIES"] = inserted.joined(separator: ":")
        env["SWIFTCODE_TEST_PLAN"] = plan.json
        let collector = HostRunCollector(session: plan.session, targets: [t]) { line in if !quiet { console.out(line) } }
        let args = t.arguments + ["-ApplePersistenceIgnoreState", "YES"]
        let status = runHost(exe, args, environment: env, collector: collector,
                             agentTimeout: Double(ctx.environment["SWIFTCODE_TEST_AGENT_TIMEOUT"] ?? "") ?? 60,
                             timeout: Double(ctx.environment["SWIFTCODE_TEST_HOST_TIMEOUT"] ?? "") ?? 3600)
        collect(collector, status: status, hostName: URL(fileURLWithPath: app).deletingPathExtension().lastPathComponent, into: &outcome)
    }

    enum HostStatus: Equatable { case exited(Int32), noAgent, timedOut, couldNotStart(String) }

    static func runHost(_ exe: String, _ args: [String], environment: [String: String], collector: HostRunCollector,
                        agentTimeout: Double, timeout: Double) -> HostStatus {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        p.environment = environment
        p.currentDirectoryURL = URL(fileURLWithPath: exe).deletingLastPathComponent()
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return .couldNotStart("\(error)") }
        let verdict = Verdict()
        let started = Date()
        var finishedAt: Date?
        let watchdog = Watchdog("swiftcodebuild.test-host.watchdog") {
            guard p.isRunning else { return false }
            let elapsed = Date().timeIntervalSince(started)
            if !collector.isAgentLoaded && elapsed > agentTimeout {
                verdict.set(.noAgent)
                p.terminate()
                return false
            }
            if elapsed > timeout {
                verdict.set(.timedOut)
                p.terminate()
                return false
            }
            if collector.isFinished {
                if let f = finishedAt, Date().timeIntervalSince(f) > 10 {
                    p.terminate()
                    return false
                }
                if finishedAt == nil { finishedAt = Date() }
            }
            return true
        }
        watchdog.start()
        readLines(pipe.fileHandleForReading, into: collector.feed)
        p.waitUntilExit()
        return verdict.value ?? .exited(p.terminationStatus)
    }

    final class Watchdog: @unchecked Sendable {
        private let queue: DispatchQueue
        private let tick: () -> Bool
        init(_ label: String, tick: @escaping () -> Bool) {
            queue = DispatchQueue(label: label)
            self.tick = tick
        }
        func start() { schedule() }
        private func schedule() {
            queue.asyncAfter(deadline: .now() + 1) { [self] in
                if tick() { schedule() }
            }
        }
    }

    final class Verdict: @unchecked Sendable {
        private let lock = NSLock()
        private var v: HostStatus?
        func set(_ s: HostStatus) { lock.withLock { if v == nil { v = s } } }
        var value: HostStatus? { lock.withLock { v } }
    }

    static func readLines(_ h: FileHandle, into feed: (String) -> Void) {
        var buffer = Data()
        while true {
            let d = h.availableData
            if d.isEmpty { break }
            buffer.append(d)
            while let nl = buffer.firstIndex(of: 0x0A) {
                feed(String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self))
                buffer = Data(buffer[(nl + 1)...])
            }
        }
        if !buffer.isEmpty { feed(String(decoding: buffer, as: UTF8.self)) }
    }

    static func collect(_ c: HostRunCollector, status: HostStatus, hostName: String, into outcome: inout Outcome) {
        for part in c.parts {
            let results = collapseRepetitions(part.parser.results, mode: part.target.repetition?.mode)
            outcome.results += results
            outcome.targets.append(.init(target: part.target, results: results, selected: !part.target.only.isEmpty,
                                         starts: Dictionary(part.parser.results.map { ($0.name, part.parser.startIndex(of: $0.name)) },
                                                            uniquingKeysWith: { a, _ in a }),
                                         output: c.hostOutput + part.output))
        }
        outcome.errors += c.errors
        guard !c.finished else { return }
        let culprit = c.running.map { " (while running \($0))" } ?? ""
        switch status {
        case .noAgent:
            outcome.errors.append("\(hostName) did not load SwiftCode's test agent. A host built with the hardened runtime needs the \"Allow DYLD Environment Variables\" and \"Disable Library Validation\" exceptions for its test builds (ENABLE_HARDENED_RUNTIME, specs/ide/testing.md).")
        case .timedOut:
            outcome.errors.append("\(hostName) did not finish its tests in time\(culprit).")
        case .couldNotStart(let why):
            outcome.errors.append("\(hostName) could not be started: \(why)")
        case .exited(let code):
            outcome.errors.append("\(hostName) exited with status \(code) before its tests finished\(culprit).")
        }
    }
}
