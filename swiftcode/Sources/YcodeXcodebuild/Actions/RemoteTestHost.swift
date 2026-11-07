import Foundation
import YcodeSubprocess

public struct RemoteTestHost {
    public struct Settings: Equatable, Sendable {
        public var destination: String
        public var dataDirectory: String
        public var runtimeRoot: String
        public var simd: String
        public var device: String = "swiftcode-device"
        public var options: [String] = []
        public var environment: [String] = []
        public var ssh = HostTool.path("ssh")
        public var rsync = HostTool.path("rsync")
        public var launchTimeout: Double = 900
        public var timeout: Double = 3600

        public init(destination: String, dataDirectory: String, runtimeRoot: String, simd: String) {
            self.destination = destination
            self.dataDirectory = dataDirectory
            self.runtimeRoot = runtimeRoot
            self.simd = simd
        }

        public static func from(environment env: [String: String]) -> Settings? {
            guard let host = env["SWIFTCODE_SIM_HOST"], !host.isEmpty, let data = env["SWIFTCODE_SIM_DATA"], !data.isEmpty,
                  let rt = env["SWIFTCODE_SIM_RUNTIME"], !rt.isEmpty, let simd = env["SWIFTCODE_SIM_SIMD"], !simd.isEmpty else { return nil }
            var s = Settings(destination: host, dataDirectory: data, runtimeRoot: rt, simd: simd)
            if let d = env["SWIFTCODE_SIM_DEVICE"], !d.isEmpty { s.device = d }
            s.options = words(env["SWIFTCODE_SIM_OPTIONS"] ?? "")
            s.environment = words(env["SWIFTCODE_SIM_ENV"] ?? "")
            if let p = env["SWIFTCODE_SSH"], !p.isEmpty { s.ssh = p }
            if let p = env["SWIFTCODE_RSYNC"], !p.isEmpty { s.rsync = p }
            if let t = env["SWIFTCODE_SIM_TEST_LAUNCH_TIMEOUT"].flatMap(Double.init) { s.launchTimeout = t }
            if let t = env["SWIFTCODE_SIM_TEST_TIMEOUT"].flatMap(Double.init) { s.timeout = t }
            return s
        }

        public var devicePath: String { dataDirectory + "/devices/" + device }
        public func remoteApp(_ name: String) -> String { dataDirectory + "/test-apps/" + name }
    }

    public static func isSwiftCodeSimulator(_ spec: String) -> Bool {
        let (_, fields) = Destinations.parse(spec)
        guard (fields["platform"] ?? "").hasSuffix("Simulator") else { return false }
        return fields["id"] == "swiftcode-remote-simulator" || (fields["name"] ?? "").contains("SwiftCode")
    }

    var settings: Settings
    var context: XcodebuildContext

    init(settings: Settings, context: XcodebuildContext) {
        self.settings = settings
        self.context = context
    }

    static func quote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    static func words(_ text: String) -> [String] {
        var out: [String] = [], cur = "", inWord = false
        var quote: Character?
        var escape = false
        for c in text {
            if escape { cur.append(c); escape = false; inWord = true; continue }
            if let q = quote {
                if c == q { quote = nil } else if c == "\\" && q == "\"" { escape = true } else { cur.append(c) }
                continue
            }
            switch c {
            case "\\": escape = true
            case "'", "\"": quote = c; inWord = true
            case " ", "\t", "\n":
                if inWord { out.append(cur); cur = ""; inWord = false }
            default: cur.append(c); inWord = true
            }
        }
        if inWord { out.append(cur) }
        return out
    }

    static let appPrefix = "SWIFTCODE-APP|"
    static let agentInApp = "@executable_path/Frameworks/libSwiftCodeTestAgent.dylib"

    func command(app remoteApp: String, bundleID: String, plan: TestHostProtocol.Plan) -> String {
        let q = Self.quote
        let err = settings.devicePath + "/data/tmp/swiftcode-app.err"
        let out = settings.devicePath + "/data/tmp/swiftcode-app.out"
        let env = settings.environment.isEmpty ? "" : "env " + settings.environment.map(q).joined(separator: " ") + " "
        return "rm -f \(q(err)) \(q(out)); echo SWIFTCODE-REMOTE-PID $$; "
            + "( tail --pid=$$ -n +1 -F \(q(err)) 2>/dev/null | sed -u 's/^/\(Self.appPrefix)/' & ); "
            + "exec \(env)\(q(settings.simd)) --device \(q(settings.devicePath)) --runtime-root \(q(settings.runtimeRoot))"
            + settings.options.map { " " + q($0) }.joined()
            + " --install-app \(q(remoteApp)) --launch \(q(bundleID))"
            + " --app-env \(q("DYLD_INSERT_LIBRARIES=" + Self.agentInApp))"
            + " --app-env \(q("SWIFTCODE_TEST_PLAN=" + plan.json)) 2>&1"
    }

    var sshOptions: [String] { ["-o", "BatchMode=yes"] }

    func ssh(_ command: String) -> (Int32, String) {
        let r = TestActions.run(settings.ssh, sshOptions + [settings.destination, command], environment: ProcessInfo.processInfo.environment) { _ in }
        return (r.status, r.output)
    }

    func run(_ targets: [TestTarget], quiet: Bool, outcome: inout TestActions.Outcome) {
        var groups: [(app: String, executable: String, targets: [TestTarget])] = []
        for t in targets {
            if t.isUITest {
                outcome.errors.append("\(t.blueprintName) is a UI test bundle: UI tests on the SwiftCode simulator need an automation service SwiftCode does not have yet (specs/ide/testing.md, \"SwiftCode implementation\").")
                continue
            }
            guard let (app, exe) = TestActions.hostApp(t) else {
                outcome.errors.append("\(t.blueprintName): the test host \(t.testHost ?? "") is not inside an application bundle.")
                continue
            }
            if let i = groups.firstIndex(where: { $0.app == app }) { groups[i].targets.append(t) } else { groups.append((app, exe, [t])) }
        }
        for g in groups { runGroup(app: g.app, targets: g.targets, quiet: quiet, outcome: &outcome) }
    }

    func runGroup(app: String, targets: [TestTarget], quiet: Bool, outcome: inout TestActions.Outcome) {
        let fm = FileManager.default
        let name = URL(fileURLWithPath: app).lastPathComponent
        let hostName = URL(fileURLWithPath: app).deletingPathExtension().lastPathComponent
        let sdk = targets.first?.platform ?? "iphonesimulator"
        guard fm.fileExists(atPath: app) else {
            outcome.errors.append("The test host \(app) does not exist; build it with build-for-testing first.")
            return
        }
        guard let agent = TestHostProtocol.agent(sdk: sdk, environment: context.environment, executableDirectory: context.executableDirectory) else {
            outcome.errors.append("\(hostName) needs SwiftCode's test agent for \(sdk): build it with SimGuestAgents/build-test-agent.sh into \(sdk)/ next to swiftcodebuild, or set SWIFTCODE_TEST_AGENT_\(sdk.uppercased()).")
            return
        }
        guard let bundleID = TestActions.bundleIdentifier(ofApp: app) else {
            outcome.errors.append("\(hostName) has no bundle identifier in its Info.plist.")
            return
        }
        guard fm.fileExists(atPath: app + "/Frameworks/XCTest.framework") else {
            outcome.errors.append("\(hostName) has no testing frameworks in its Frameworks folder: build it with build-for-testing for this destination first.")
            return
        }
        let stage = fm.temporaryDirectory.appendingPathComponent("swiftcodebuild-test-host-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: stage) }
        let staged = stage.appendingPathComponent(name).path
        var bundles: [TestHostProtocol.Plan.Bundle] = []
        do {
            try fm.createDirectory(at: stage, withIntermediateDirectories: true)
            try fm.copyItem(atPath: app, toPath: staged)
            try fm.createDirectory(atPath: staged + "/Frameworks", withIntermediateDirectories: true)
            try fm.copyItem(atPath: agent, toPath: staged + "/Frameworks/libSwiftCodeTestAgent.dylib")
            for t in targets {
                let rel = TestActions.agentBundlePath(t, app: app)
                if rel.hasPrefix("/") {
                    try fm.createDirectory(atPath: staged + "/PlugIns", withIntermediateDirectories: true)
                    let dest = staged + "/PlugIns/" + URL(fileURLWithPath: t.bundlePath).lastPathComponent
                    if !fm.fileExists(atPath: dest) { try fm.copyItem(atPath: t.bundlePath, toPath: dest) }
                    bundles.append(.init(path: URL(fileURLWithPath: t.bundlePath).lastPathComponent, module: t.moduleName, only: t.only, skip: t.skip))
                } else {
                    guard fm.fileExists(atPath: t.bundlePath) else {
                        outcome.errors.append("The test bundle \(t.bundlePath) does not exist; build it with build-for-testing first.")
                        return
                    }
                    bundles.append(.init(path: rel, module: t.moduleName, only: t.only, skip: t.skip))
                }
            }
        } catch {
            outcome.errors.append("Could not prepare \(hostName) for testing: \(error)")
            return
        }
        let remoteApp = settings.remoteApp(name)
        let (mk, mkOut) = ssh("mkdir -p \(Self.quote(settings.dataDirectory + "/test-apps"))")
        guard mk == 0 else {
            outcome.errors.append("Could not reach the simulator host \(settings.destination) (ssh \(mk)): \(mkOut.trimmingCharacters(in: .whitespacesAndNewlines))")
            return
        }
        let sync = TestActions.run(settings.rsync, ["-az", "--delete", "-e", ([settings.ssh] + sshOptions).joined(separator: " "),
                                                    staged + "/", "\(settings.destination):\(remoteApp)/"],
                                   environment: ProcessInfo.processInfo.environment) { _ in }
        guard sync.status == 0 else {
            outcome.errors.append("Could not copy \(name) to \(settings.destination) (rsync \(sync.status)): \(sync.output)")
            return
        }
        var plan = TestHostProtocol.Plan(bundles: bundles, repetition: targets.first?.repetition)
        plan.launchTimeout = 120
        let collector = HostRunCollector(session: plan.session, targets: targets) { line in if !quiet { context.console.out(line) } }
        let tail = SimulatorLines()
        let status = runRemote(command(app: remoteApp, bundleID: bundleID, plan: plan), collector: collector, simulator: tail)
        TestActions.collect(collector, status: status, hostName: hostName, into: &outcome)
        if !collector.isFinished {
            let last = tail.lines.suffix(12)
            if !last.isEmpty { outcome.errors.append("The SwiftCode simulator's last lines:\n\t\t" + last.joined(separator: "\n\t\t")) }
        }
    }

    final class SimulatorLines: @unchecked Sendable {
        private let lock = NSLock()
        private var kept: [String] = []
        private(set) var failure: String?
        func add(_ l: String) {
            lock.withLock {
                kept.append(l)
                if kept.count > 200 { kept.removeFirst(kept.count - 200) }
                if failure == nil, l.contains("app install: failed") || l.contains("app launch: failed") || l.contains("ylaunch: error") { failure = l }
            }
        }
        var lines: [String] { lock.withLock { kept } }
        var failed: String? { lock.withLock { failure } }
    }

    func runRemote(_ command: String, collector: HostRunCollector, simulator: SimulatorLines) -> TestActions.HostStatus {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: settings.ssh)
        p.arguments = sshOptions + [settings.destination, command]
        p.environment = ProcessInfo.processInfo.environment
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return .couldNotStart("\(error)") }
        let pid = PIDBox()
        let verdict = TestActions.Verdict()
        let started = Date()
        var stoppedAt: Date?
        let watchdog = TestActions.Watchdog("swiftcodebuild.remote-test.watchdog") { [self] in
            guard p.isRunning else { return false }
            if let at = stoppedAt {
                if Date().timeIntervalSince(at) > 150 {
                    p.terminate()
                    return false
                }
                return true
            }
            let elapsed = Date().timeIntervalSince(started)
            var stop = false
            if collector.isFinished {
                stop = true
            } else if let failure = simulator.failed {
                verdict.set(.couldNotStart(failure))
                stop = true
            } else if !collector.isAgentLoaded && elapsed > settings.launchTimeout {
                verdict.set(.noAgent)
                stop = true
            } else if elapsed > settings.timeout {
                verdict.set(.timedOut)
                stop = true
            }
            if stop {
                stoppedAt = Date()
                if let n = pid.value { _ = ssh("kill -INT \(n)") } else { p.terminate() }
            }
            return true
        }
        watchdog.start()
        TestActions.readLines(pipe.fileHandleForReading) { line in
            if line.hasPrefix(Self.appPrefix) {
                collector.feed(String(line.dropFirst(Self.appPrefix.count)))
            } else if line.hasPrefix("SWIFTCODE-REMOTE-PID "), let n = Int(line.dropFirst("SWIFTCODE-REMOTE-PID ".count)) {
                pid.set(n)
            } else {
                simulator.add(line)
            }
        }
        p.waitUntilExit()
        return verdict.value ?? .exited(p.terminationStatus)
    }

    final class PIDBox: @unchecked Sendable {
        private let lock = NSLock()
        private var v: Int?
        func set(_ n: Int) { lock.withLock { v = n } }
        var value: Int? { lock.withLock { v } }
    }
}
