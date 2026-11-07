import Foundation
import YcodeBuild
import YcodeDebug
import YcodeSubprocess

public struct Simctl: Sendable {
    public var run: @Sendable ([String]) -> (Int32, String)
    public var launchCommand = ["/usr/bin/xcrun", "simctl"]

    public init(run: @escaping @Sendable ([String]) -> (Int32, String) = Simctl.xcrun) { self.run = run }

    public static let xcrun: @Sendable ([String]) -> (Int32, String) = { args in
        MainThreadGuard.blockingCall("simctl \(args.first ?? "")")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        p.arguments = ["simctl"] + args
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("swiftcode-simctl-\(UUID().uuidString).txt")
        FileManager.default.createFile(atPath: file.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: file) }
        guard let h = try? FileHandle(forWritingTo: file) else { return (127, "no temporary file") }
        p.standardOutput = h
        p.standardError = h
        guard (try? p.run()) != nil else { return (127, "xcrun not found") }
        p.waitUntilExit()
        try? h.close()
        return (p.terminationStatus, (try? String(contentsOf: file, encoding: .utf8)) ?? "")
    }

    public struct Failure: Error, CustomStringConvertible {
        public var description: String
    }

    @discardableResult
    func checked(_ args: [String]) throws -> String {
        let (s, out) = run(args)
        guard s == 0 else { throw Failure(description: "simctl \(args.first ?? ""): \(out.trimmingCharacters(in: .whitespacesAndNewlines))") }
        return out
    }

    public func boot(_ udid: String) throws { try checked(["bootstatus", udid, "-b"]) }
    public func install(_ udid: String, app: URL) throws { try checked(["install", udid, app.path]) }
    public func terminate(_ udid: String, bundleID: String) { _ = run(["terminate", udid, bundleID]) }
    public func shutdown(_ udid: String) { _ = run(["shutdown", udid]) }

    public static func launchArguments(udid: String, bundleID: String, waitForDebugger: Bool, arguments: [String] = []) -> [String] {
        ["launch", "--console", "--terminate-running-process"] + (waitForDebugger ? ["--wait-for-debugger"] : []) + [udid, bundleID] + arguments
    }

    public static func launchedPID(_ line: String, bundleID: String) -> Int? {
        guard line.hasPrefix(bundleID + ":") else { return nil }
        return Int(line.dropFirst(bundleID.count + 1).trimmingCharacters(in: .whitespaces))
    }
}

public struct AppBundle: Equatable, Sendable {
    public var url: URL
    public var bundleID: String
    public var executable: String
    public var executableURL: URL {
        let flat = url.appendingPathComponent(executable)
        return FileManager.default.fileExists(atPath: flat.path) ? flat : url.appendingPathComponent("Contents/MacOS/\(executable)")
    }

    public init?(url: URL) {
        let candidates = [url.appendingPathComponent("Info.plist"), url.appendingPathComponent("Contents/Info.plist")]
        guard let data = candidates.lazy.compactMap({ try? Data(contentsOf: $0) }).first,
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let id = plist["CFBundleIdentifier"] as? String else { return nil }
        self.url = url
        bundleID = id
        executable = plist["CFBundleExecutable"] as? String ?? url.deletingPathExtension().lastPathComponent
    }
}

package final class StreamingProcess: @unchecked Sendable {
    let process = Process()
    private let pipe = Pipe()
    private var buffer = Data()
    private let lock = NSLock()
    private var exitStatus: Int32?
    private var reachedEnd = false
    private var reported = false
    private var events: AsyncStream<Event>.Continuation?
    package var outputGrace: TimeInterval = 1
    package var readDelayForTesting: TimeInterval = 0

    private enum Event: Sendable {
        case lines([String])
        case exit(Int32)
    }

    package init(executable: String, arguments: [String], environment: [String: String]? = nil) {
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }
        process.standardOutput = pipe
        process.standardError = pipe
    }

    package func start(onLine: @escaping @MainActor (String) -> Void, onExit: @escaping @MainActor (Int32) -> Void) throws {
        let (stream, continuation) = AsyncStream<Event>.makeStream()
        lock.lock()
        events = continuation
        lock.unlock()
        Task { @MainActor in
            for await e in stream {
                switch e {
                case .lines(let lines): lines.forEach(onLine)
                case .exit(let status): onExit(status)
                }
            }
        }
        process.terminationHandler = { p in self.processEnded(p.terminationStatus) }
        do {
            try process.run()
        } catch {
            continuation.finish()
            throw error
        }
        let delay = readDelayForTesting
        let reader = pipe.fileHandleForReading
        let thread = Thread {
            while true {
                if delay > 0 { Thread.sleep(forTimeInterval: delay) }
                let d = reader.availableData
                if d.isEmpty { break }
                let lines = self.take(d)
                if !lines.isEmpty { self.send(.lines(lines)) }
            }
            self.outputEnded()
        }
        thread.name = "swiftcode-process-output"
        thread.start()
    }

    private func send(_ e: Event) {
        lock.lock()
        let c = events
        lock.unlock()
        c?.yield(e)
    }

    private func processEnded(_ status: Int32) {
        lock.lock()
        exitStatus = status
        let atEnd = reachedEnd
        lock.unlock()
        if atEnd { return report() }
        DispatchQueue.global().asyncAfter(deadline: .now() + outputGrace) { self.report() }
    }

    private func outputEnded() {
        lock.lock()
        reachedEnd = true
        let ended = exitStatus != nil
        let done = reported
        let c = events
        if done { events = nil }
        lock.unlock()
        if done { c?.finish() } else if ended { report() }
    }

    private func report() {
        lock.lock()
        guard !reported, let status = exitStatus else { lock.unlock(); return }
        reported = true
        let rest = String(decoding: buffer, as: UTF8.self)
        buffer = Data()
        let c = events
        let finished = reachedEnd
        if finished { events = nil }
        lock.unlock()
        if !rest.isEmpty { c?.yield(.lines([rest])) }
        c?.yield(.exit(status))
        if finished { c?.finish() }
    }

    private func take(_ d: Data) -> [String] {
        lock.lock(); defer { lock.unlock() }
        buffer.append(d)
        var out: [String] = []
        while let nl = buffer.firstIndex(of: 0x0A) {
            out.append(String(decoding: buffer[buffer.startIndex..<nl], as: UTF8.self))
            buffer.removeSubrange(buffer.startIndex...nl)
        }
        return out
    }

    var isRunning: Bool { process.isRunning }
    package func signal(_ s: Int32) { if process.isRunning { kill(process.processIdentifier, s) } }
}

@MainActor
public final class SimulatorRunState {
    public enum Target: Equatable, Sendable { case mac(udid: String), remote(destination: String) }
    public let target: Target
    public let app: AppBundle
    public internal(set) var pid: Int?
    public internal(set) var remotePID: Int?
    public internal(set) var exitStatus: Int32?
    public internal(set) var stopRequested = false
    public internal(set) var closedByIDE = false
    package var remote: RemoteSimulator?
    var process: StreamingProcess?
    var debugForward: Process?

    package init(target: Target, app: AppBundle) {
        self.target = target
        self.app = app
    }
}

extension WorkspaceSession {
    public func runOnSimulator(app appURL: URL, udid: String, debug: Bool, simctl: Simctl = Simctl(), adapter: DAPTransport? = nil) async {
        guard let app = AppBundle(url: appURL) else { appendConsole("SwiftCode: \(appURL.lastPathComponent) is not an application bundle.\n"); return }
        let state = SimulatorRunState(target: .mac(udid: udid), app: app)
        simulatorRun = state
        let device = destination.flatMap { $0.identifier == udid ? $0.name : nil } ?? "Simulator"
        runningProduct = app.executable
        runningDeviceName = device
        setActivity(.running(RunActivityText.launching(app.executable)))
        do {
            try await Task.detached { try simctl.boot(udid) }.value
            appendConsole("SwiftCode: simulator \(udid) is booted.\n")
            try await Task.detached { try simctl.install(udid, app: appURL) }.value
            appendConsole("SwiftCode: installed \(app.bundleID).\n")
        } catch {
            appendConsole("SwiftCode: \(error)\n")
            simulatorRun = nil
            setActivity(.finished("Run failed"))
            return
        }
        let o = launchOptions
        var env: [String: String]?
        if !o.environment.isEmpty {
            env = ProcessInfo.processInfo.environment
            for (k, v) in o.environment { env?["SIMCTL_CHILD_" + k] = v }
        }
        let proc = StreamingProcess(executable: simctl.launchCommand[0],
                                    arguments: Array(simctl.launchCommand.dropFirst()) + Simctl.launchArguments(udid: udid, bundleID: app.bundleID, waitForDebugger: debug, arguments: o.arguments),
                                    environment: env)
        state.process = proc
        do {
            try proc.start(onLine: { [weak self, weak state] line in
                guard let self, let state else { return }
                if let pid = Simctl.launchedPID(line, bundleID: app.bundleID) { if state.pid == nil { state.pid = pid }; return }
                self.appendConsole(line + "\n", kind: .target)
            }, onExit: { [weak self, weak state] status in
                state?.exitStatus = status
                guard let self else { return }
                self.appendConsole("Program ended with exit code: \(status)\n")
                if self.simulatorRun === state { self.simulatorRun = nil }
                if self.debugClient == nil { self.setActivity(.finished(RunActivityText.finished(app.executable, on: device))) }
            })
        } catch {
            appendConsole("SwiftCode: \(error)\n")
            simulatorRun = nil
            return
        }
        let marker = "/\(appURL.lastPathComponent)/\(app.executable)"
        for _ in 0..<1200 where state.pid == nil && simulatorRun === state && state.exitStatus == nil {
            if let pid = await Task.detached(operation: { Self.newestProcess(matching: marker) }).value { state.pid = pid; break }
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard simulatorRun === state, state.exitStatus == nil else { return }
        if debug, let pid = state.pid {
            setActivity(.running(RunActivityText.configuringDebugger))
            await attachToSimulatorApp(pid: pid, executable: app.executableURL.path, adapter: adapter)
        }
        guard simulatorRun === state, state.exitStatus == nil else { return }
        if case .paused = activity { return }
        setActivity(.running(RunActivityText.running(app.executable, on: device)))
    }

    nonisolated static func newestProcess(matching marker: String) -> Int? {
        MainThreadGuard.blockingCall("pgrep -f")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        p.arguments = ["-n", "-f", marker]
        let out = Pipe()
        p.standardOutput = out
        guard (try? p.run()) != nil else { return nil }
        let d = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return Int(String(decoding: d, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func attachToSimulatorApp(pid: Int, executable: String, adapter: DAPTransport?) async {
        let transport: DAPTransport
        if let adapter { transport = adapter } else {
            guard let path = await Task.detached(operation: { LLDBDAP.locate() }).value else { appendConsole("SwiftCode: lldb-dap was not found.\n"); return }
            transport = ProcessTransport(executable: path)
        }
        do {
            let client = try DAPClient(transport: transport)
            debugClient = client
            Task { [weak self] in
                for await e in client.events { await self?.handle(e) }
                self?.sessionEnded()
            }
            try await client.initialize()
            attachingSimulatorApp = true
            defer { attachingSimulatorApp = false }
            try await client.attach(pid: pid, program: executable, waitFor: false, threadFormat: DebugThread.format)
            for _ in 0..<100 where stoppedThread == nil { try? await Task.sleep(for: .milliseconds(100)) }
            attachingSimulatorApp = false
            if stoppedThread != nil { await continueOrPause() }
        } catch {
            appendConsole("SwiftCode: attach failed: \(error)\n")
        }
    }

    public func stopSimulatorRun(simctl: Simctl = Simctl(), remote: RemoteSimulator? = nil) {
        guard let run = simulatorRun else { return }
        switch run.target {
        case .mac(let udid):
            let client = debugClient, bundleID = run.app.bundleID, process = run.process
            Task.detached {
                if let client { try? await client.disconnect(terminate: true); client.close() }
                simctl.terminate(udid, bundleID: bundleID)
                process?.signal(SIGTERM)
            }
            return
        case .remote:
            stopRemoteRun(run, remote: run.remote ?? remote)
        }
        if let c = debugClient { Task { try? await c.disconnect(terminate: false); c.close() } }
    }

    func stopRemoteRun(_ run: SimulatorRunState, remote: RemoteSimulator?) {
        if run.stopRequested {
            run.process?.signal(SIGINT)
            return
        }
        run.stopRequested = true
        guard run.process != nil else { return }
        guard let remote else { run.process?.signal(SIGINT); return }
        setActivity(.running(RemoteSimulator.stoppingStatus(app: run.app.executable, saves: remote.settings.warmBoot)))
        if let pid = run.remotePID { sendRemoteStop(run, pid: pid, remote: remote) }
    }

    func sendRemoteStop(_ run: SimulatorRunState, pid: Int, remote: RemoteSimulator) {
        let process = run.process
        Task { [weak self] in
            let status = await Task.detached { remote.signalRemote(pid, signal: "INT") }.value
            if status != 0 {
                self?.appendConsole("SwiftCode: the stop signal did not reach \(remote.settings.destination) (ssh status \(status)); closing the connection.\n", kind: .debugger)
                process?.signal(SIGINT)
                return
            }
            try? await Task.sleep(for: .seconds(remote.stopGrace))
            if process?.isRunning == true {
                self?.appendConsole("SwiftCode: SwiftCode Simulator did not end \(Int(remote.stopGrace)) s after Stop; closing the connection.\n", kind: .debugger)
                process?.signal(SIGINT)
            }
        }
    }
}
