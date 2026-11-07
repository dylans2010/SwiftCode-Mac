#if os(Linux) && arch(arm64)
import Foundation
import Glibc
import SwiftCodeDarwinABI
import SwiftCodeDarwinKernel
import SwiftCodeHostServices
import SwiftCodeHypervisor

final class DeviceSession: @unchecked Sendable {
    let layout: DeviceLayout
    let host: MachHostTask
    let makeFileSystem: () -> DarwinFileSystem
    private let lock = NSLock()
    private var control: LaunchSimControl?
    private var ending = false
    private var results: [Int: String] = [:]
    private var thread: Thread?
    private var appPID: Int32?
    private var appStepsBusy = false
    var launchedAppPID: Int32? { lock.withLock { appPID } }
    var appStepsRunning: Bool { lock.withLock { appStepsBusy } }
    private var requestSince: Date?
    var hostServices: [(name: String, port: UInt32)] = []
    private var queuedRegistrations: [(name: String, token: UInt32)] = []

    init(layout: DeviceLayout, host: MachHostTask, makeFileSystem: @escaping () -> DarwinFileSystem) {
        self.layout = layout
        self.host = host
        self.makeFileSystem = makeFileSystem
        hostServices += DefaultHostServices.start(host: host, log: { stderrLine("swiftcode-simd: " + $0) })
        let eventsFS = makeFileSystem()
        let configuration = FSEventsHostService.Configuration(
            statePath: layout.dev + "/swiftcode-fsevents.plist",
            volumes: [ExecConfiguration.rootDevice: "/"],
            canonicalPath: { path in Self.canonicalGuestPath(path, eventsFS) },
            identity: { path in eventsFS.identity(atCanonicalPath: path) })
        if let service = DefaultHostServices.startFileEvents(host: host, configuration: configuration,
                                                             log: { stderrLine("swiftcode-simd: " + $0) }) {
            hostServices.append(service)
        }
    }

    static func canonicalGuestPath(_ path: String, _ fs: DarwinFileSystem) -> String {
        if let real = try? fs.realpath(path) { return real }
        var head = path, tail: [String] = []
        while head.count > 1, let slash = head.lastIndex(of: "/") {
            tail.insert(String(head[head.index(after: slash)...]), at: 0)
            head = slash == head.startIndex ? "/" : String(head[..<slash])
            if let real = try? fs.realpath(head) {
                return (real == "/" ? "" : real) + "/" + tail.joined(separator: "/")
            }
        }
        return path
    }

    private func emit(_ text: String) { stderrLine("swiftcode-simd: " + text) }

    static func isLate(_ name: String) -> Bool { lateHostServices.contains(name) || name == CameraGuestService.serviceName }

    func servicePortCreated(_ channel: UInt32) {
        let c = LaunchSimControl(host: host, channel: channel, log: { [weak self] in self?.emit($0) })
        var queued: [(name: String, token: UInt32)] = []
        var deferred: [(name: String, port: UInt32)] = []
        let ordered = hostServices.filter { !Self.isLate($0.name) } + hostServices.filter { Self.isLate($0.name) }
        for (name, port) in ordered {
            do { queued.append((name, try c.queueRegistration(name, port: port))) } catch {
                deferred.append((name, port))
            }
        }
        lock.withLock {
            control = c
            queuedRegistrations = queued
            deferredRegistrations = deferred
        }
    }

    static let lateHostServices: Set<String> = [PowerManagementHostService.serviceName, AudioHostService.serviceName,
                                                FSEventsHostService.serviceName]
    private var deferredRegistrations: [(name: String, port: UInt32)] = []

    func channelArrived(_ channel: UInt32) {
        let c = lock.withLock { () -> LaunchSimControl in
            if let c = control, c.channel == channel { return c }
            let c = LaunchSimControl(host: host, channel: channel, log: { [weak self] in self?.emit($0) })
            control = c
            return c
        }
        let t = Thread { [self] in run(c) }
        t.name = "swiftcode-session"
        lock.withLock { thread = t }
        t.start()
    }

    private var isEnding: Bool { lock.withLock { ending } }

    var snapshotState: (channel: UInt32, session: UInt32)? {
        guard let c = lock.withLock({ control }), let port = c.boundSessionPort else { return nil }
        return (c.channel, port)
    }

    func reattach(channel: UInt32, session: UInt32) {
        let c = LaunchSimControl(host: host, channel: channel, log: { [weak self] in self?.emit($0) })
        c.adoptSession(session)
        lock.withLock { control = c }
        Thread.detachNewThread { [self] in
            for _ in 0..<20 {
                Thread.sleep(forTimeInterval: 30)
                if isEnding { return }
                if let since = lock.withLock({ requestSince }) {
                    emit("control: spawn request waiting \(Int(Date().timeIntervalSince(since))) s; channel 0x\(String(channel, radix: 16)): "
                        + host.debugPortState(channel))
                }
            }
        }
        let probeStart = Date()
        Thread.detachNewThread { [self] in
            for attempt in 1...10 {
                if isEnding { return }
                do {
                    _ = try c.domainEnvironment(Self.livenessProbeName)
                    emit("snapshot: restore: guest live: launchd_sim answered "
                        + "\(Int(Date().timeIntervalSince(probeStart) * 1000)) ms after its session was adopted")
                    announceClockChange(c)
                    return
                } catch {
                    emit("snapshot: restore: liveness request \(attempt) not answered: \(error)")
                    Thread.sleep(forTimeInterval: 1)
                }
            }
        }
        if layout.stagedAppGuestPath != nil || layout.launchBundleID != nil {
            let t = Thread { [self] in runApps(c) }
            t.name = "swiftcode-apps"
            t.start()
        }
    }

    static let livenessProbeName = "SWIFTCODE_LIVENESS_PROBE"

    private func announceClockChange(_ c: LaunchSimControl) {
        guard let gap = SnapshotSupport.shared?.restoreCalendarGapSeconds, gap >= 1 else { return }
        let tool = layout.runtimeRoot + "/usr/bin/notifyutil"
        guard FileManager.default.isExecutableFile(atPath: tool) else { return }
        do {
            let r = try runGuestProgram(c, name: "notifyutil clock_set", path: tool,
                                        argv: ["notifyutil", "-p", Self.clockSetNotification],
                                        out: layout.data + "/tmp/swiftcode-clock-set.out", err: layout.data + "/tmp/swiftcode-clock-set.err")
            emit("snapshot: restore: \(Self.clockSetNotification) posted (the calendar moved \(gap) s since the save): "
                + describe(waitStatus: r.status))
        } catch {
            emit("snapshot: restore: \(Self.clockSetNotification) not posted: \(error)")
        }
    }

    static let clockSetNotification = "com.apple.system.clock_set"

    private func run(_ c: LaunchSimControl) {
        do {
            try c.bindSession()
        } catch {
            emit("control: bind failed: \(error) (system-domain jobs stay held)")
        }
        for (name, token) in lock.withLock({ queuedRegistrations }) {
            do {
                try c.finishRegistration(token, name: name)
                emit("control: 701 registered \(name)")
            } catch {
                emit("control: 701 register \(name) failed: \(error)")
            }
        }
        for (name, port) in lock.withLock({ deferredRegistrations }) {
            do {
                try c.registerEndpoint(name, port: port)
                emit("control: 701 registered \(name) (after the queued ones)")
            } catch {
                emit("control: 701 register \(name) failed: \(error)")
            }
        }
        if let names = ProcessInfo.processInfo.environment["SWIFTCODE_CONTROL_CHECK"], !names.isEmpty {
            checkControlOperations(c, guestNames: names == "1" ? [] : names.split(separator: ",").map(String.init))
        }
        if layout.stagedAppGuestPath != nil || layout.launchBundleID != nil {
            let t = Thread { [self] in runApps(c) }
            t.name = "swiftcode-apps"
            t.start()
        }
        guard !layout.oneshots.isEmpty else { return }
        if let delay = layout.oneshotDelay {
            let until = Date().addingTimeInterval(TimeInterval(delay))
            while Date() < until, !isEnding { Thread.sleep(forTimeInterval: 0.2) }
        }
        for index in layout.oneshots.indices where !isEnding {
            runOneshot(c, index)
        }
    }

    private func checkControlOperations(_ c: LaunchSimControl, guestNames: [String]) {
        func outcome(_ body: () throws -> String) -> String {
            do { return try body() } catch { return "failed: \(error)" }
        }
        let hostName = hostServices.first?.name ?? "com.apple.IOSurface.Remote"
        for name in [hostName] + guestNames {
            emit("control check: 702 find \(name): " + outcome {
                let port = try c.findEndpoint(name)
                try? host.deallocate(port)
                return "send right"
            })
        }
        emit("control check: 703 getenv \(Self.livenessProbeName): " + outcome { try c.domainEnvironment(Self.livenessProbeName) ?? "not set" })
        let test = "dev.swiftcode.control-check"
        guard let port = try? host.makePort(sendRight: true) else { emit("control check: no port"); return }
        defer { try? host.destroyPort(port) }
        emit("control check: 701 register \(test): " + outcome { try c.registerEndpoint(test, port: port); return "ok" })
        emit("control check: 702 find \(test): " + outcome {
            let found = try c.findEndpoint(test)
            try? host.deallocate(found)
            return "send right"
        })
        emit("control check: 709 unregister \(test): " + outcome { try c.unregisterEndpoint(test); return "ok" })
        emit("control check: 702 find \(test) after 709: " + outcome { _ = try c.findEndpoint(test); return "still found" })
        emit("control check: 709 unregister \(test) again: " + outcome { try c.unregisterEndpoint(test); return "ok" })
    }

    private func outputFileport(_ fs: DarwinFileSystem, _ path: String) throws -> UInt32 {
        let fd = try fs.open(path, flags: DarwinOpen.O_WRONLY | DarwinOpen.O_CREAT | DarwinOpen.O_TRUNC, mode: 0o644)
        defer { try? fs.close(fd) }
        return try host.makeFileport(try fs.openFile(for: fd))
    }

    private func runGuestProgram(_ c: LaunchSimControl, name: String, path: String, argv: [String], environment: [String] = [],
                                 out: String, err: String, started: ((Int32) -> Void)? = nil) throws -> (pid: Int32, status: Int32) {
        let fs = makeFileSystem()
        var ports: [UInt32] = []
        do {
            for file in [out, err] { ports.append(try outputFileport(fs, layout.guestPath(file))) }
        } catch {
            ports.forEach { try? host.deallocate($0) }
            throw error
        }
        let attributes = LaunchSimSpawnAttributes(path: layout.guestPath(path), argv: argv, environment: environment, workingDirectory: "/")
        let pid: Int32
        lock.withLock { requestSince = Date() }
        do {
            pid = try c.spawn(attributes, stdin: 0, stdout: ports[0], stderr: ports[1])
            lock.withLock { requestSince = nil }
        } catch {
            lock.withLock { requestSince = nil }
            ports.forEach { try? host.deallocate($0) }
            throw error
        }
        emit("control: one-shot \(name) spawned (704): pid \(pid)")
        started?(pid)
        let status = try c.waitpid(pid, timeout: nil)
        emit("control: one-shot \(name) (pid \(pid)) ended (705): " + describe(waitStatus: status))
        return (pid, status)
    }

    private func runOneshot(_ c: LaunchSimControl, _ index: Int) {
        let name = layout.oneshotLabel(index)
        do {
            let r = try runGuestProgram(c, name: name, path: layout.oneshotProgram(index), argv: layout.oneshots[index],
                                        out: layout.oneshotOutputHostPath(index, err: false),
                                        err: layout.oneshotOutputHostPath(index, err: true),
                                        started: { [self] pid in record(index, "\(name): pid \(pid), still running") })
            record(index, "\(name): pid \(r.pid), " + describe(waitStatus: r.status))
        } catch {
            if !isEnding { record(index, "\(name): failed: \(error)") }
        }
    }

    private func ylaunch(_ c: LaunchSimControl, step: String, _ arguments: [String]) throws -> (status: Int32, output: String) {
        guard let tool = layout.ylaunchPath else { throw LaunchSimControlError(operation: "ylaunch: not staged", code: 2) }
        let out = layout.data + "/tmp/swiftcode-ylaunch-\(step).out", err = layout.data + "/tmp/swiftcode-ylaunch-\(step).err"
        let r = try runGuestProgram(c, name: "ylaunch \(step)", path: tool, argv: ["ylaunch"] + arguments,
                                    environment: ["YLAUNCH_RETRY_SECONDS=600", "YLAUNCH_INSTALL_SECONDS=1200"], out: out, err: err)
        let text = (FileManager.default.contents(atPath: out)).map { String(decoding: $0, as: UTF8.self) } ?? ""
        for line in text.split(separator: "\n") { emit("app: " + line) }
        if let e = FileManager.default.contents(atPath: err), !e.isEmpty {
            emit("app: ylaunch \(step) stderr: " + String(decoding: e.prefix(2000), as: UTF8.self))
        }
        return (r.status, text)
    }

    private func runApps(_ c: LaunchSimControl) {
        lock.withLock { appStepsBusy = true }
        defer { lock.withLock { appStepsBusy = false } }
        SnapshotSupport.shared?.holdAppsUntilSnapshot { [self] in isEnding }
        let bundleID = layout.launchBundleID
        if let app = layout.stagedAppGuestPath {
            do {
                let r = try ylaunch(c, step: "install", ["install", layout.guestPath(app)])
                let installed = r.output.split(separator: "\n").compactMap { line -> String? in
                    line.hasPrefix("ylaunch: installed ") ? String(line.dropFirst("ylaunch: installed ".count)) : nil
                }.first
                guard r.status == 0, let installed else {
                    record(1000, "app install: failed (" + describe(waitStatus: r.status) + ")")
                    return
                }
                record(1000, "app install: \(installed) installed")
            } catch {
                record(1000, "app install: failed: \(error)")
                return
            }
        }
        guard let bundleID, !isEnding else { return }
        var arguments = ["open", bundleID, "--stdout", DeviceLayout.appStdoutGuestPath, "--stderr", DeviceLayout.appStderrGuestPath]
        for a in layout.appArguments { arguments += ["--arg", a] }
        if let url = layout.appURL { arguments += ["--url", url] }
        for e in layout.appEnvironment { arguments += ["--env", e] }
        do {
            let began = monotonicNanoseconds()
            let r = try ylaunch(c, step: "open", arguments)
            stderrLine("swiftcode-simd: app launch: open request took \((monotonicNanoseconds() &- began) / 1_000_000) ms")
            let launched = r.output.split(separator: "\n").first { $0.hasPrefix("ylaunch: launched ") }
            if let launched, let range = launched.range(of: " pid ", options: .backwards),
               let pid = Int32(launched[range.upperBound...].trimmingCharacters(in: .whitespaces)) {
                lock.withLock { appPID = pid }
            }
            record(1001, launched.map { "app launch: " + $0.dropFirst("ylaunch: ".count) }
                   ?? "app launch: failed (" + describe(waitStatus: r.status) + ")")
        } catch {
            record(1001, "app launch: failed: \(error)")
        }
    }

    func killApp(_ bundleID: String) -> String {
        guard let c = lock.withLock({ control }), c.isBound else { return "the device session is not bound" }
        guard layout.ylaunchPath != nil else { return "no ylaunch staged (--guest-tools)" }
        do {
            let r = try ylaunch(c, step: "kill", ["kill", bundleID])
            return r.output.split(separator: "\n").last.map(String.init) ?? describe(waitStatus: r.status)
        } catch {
            return "ylaunch kill failed: \(error)"
        }
    }

    private func describe(waitStatus s: Int32) -> String {
        s & 0x7F == 0 ? "exit \((s >> 8) & 0xFF)" : "signal \(s & 0x7F)"
    }

    private func record(_ index: Int, _ line: String) { lock.withLock { results[index] = line } }

    var resultLines: [String] { lock.withLock { results.keys.sorted().map { results[$0]! } } }

    func end() {
        let c = lock.withLock { () -> LaunchSimControl? in ending = true; return control }
        c?.endSession()
    }

    var isBound: Bool { lock.withLock { control }?.isBound ?? false }

    var boundControl: LaunchSimControl? {
        lock.withLock { () -> LaunchSimControl? in
            guard !ending, let c = control, c.isBound else { return nil }
            return c
        }
    }
}
#endif
