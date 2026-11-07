import Foundation
import YcodeBuild

public struct RemoteWatchRunPlan: Equatable, Sendable {
    public var iOSApp: URL?
    public var watchApp: URL
    public var launchWatchApp: Bool

    public init(iOSApp: URL?, watchApp: URL, launchWatchApp: Bool) {
        self.iOSApp = iOSApp
        self.watchApp = watchApp
        self.launchWatchApp = launchWatchApp
    }
}

public enum RemoteWatchRunError {
    public static let noPairedWatch = "The install is directed to a paired Apple Watch, but there isn't one."
    public static let selectPairedPhone = "Select an iPhone Run Destination with a paired Apple Watch."
}

extension RemoteSimulator {
    public static func embeddedWatchApp(in app: URL) -> URL? {
        let dir = app.appendingPathComponent("Watch")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return names.sorted().first { $0.hasSuffix(".app") }.map { dir.appendingPathComponent($0) }
    }

    public var isWatch: Bool { target?.isWatch ?? false }

    public var stagedAppsDirectory: String { "\(remoteDevicePath)/data/tmp/swiftcode-apps" }

    public var stageDirectoryCommand: String { "mkdir -p \(Self.quote(stagedAppsDirectory))" }

    public func stageArguments(_ app: URL) -> [String] {
        ["-az", "--delete", "-e", ([settings.ssh] + sshOptions).joined(separator: " "),
         app.path + "/", "\(settings.destination):\(stagedAppsDirectory)/\(app.lastPathComponent)/"]
    }

    public func agentCommand(_ op: String, _ args: [(String, String)] = [], devicePathRelative: (key: String, path: String)? = nil) -> String {
        let q = Self.quote
        var prefix = ""
        var words = args.map { q("\($0.0)=\($0.1)") }
        if let rel = devicePathRelative {
            prefix = "g=$(cat \(q(remoteDevicePath + "/swiftcode-device-path")) 2>/dev/null); [ -n \"$g\" ] || g=\(q(remoteDevicePath)); "
            words.append("\"\(rel.key)=$g\"\(q(rel.path))")
        }
        return prefix + "exec \(q(settings.simdPath)) --device \(q(remoteDevicePath)) --control pairing agent \(q(op))"
            + words.map { " " + $0 }.joined()
    }

    public func installAppCommand(_ app: URL) -> String {
        agentCommand("installApp", devicePathRelative: ("path", "/data/tmp/swiftcode-apps/\(app.lastPathComponent)"))
    }

    public func openAppCommand(bundleID: String) -> String { agentCommand("openApp", [("bundleID", bundleID)]) }

    public var pairingStateCommand: String { controlCommand(["pairing", "state"]) }

    public static func agentIsUp(stateReply: String) -> Bool { stateReply.contains("agent up") }

    public func runRemote(_ command: String) -> (Int32, String) { runLocal(settings.ssh, sshArguments(command)) }

    public func stageApp(_ app: URL) throws {
        let (m, mo) = runRemote(stageDirectoryCommand)
        guard m == 0 else { throw Simctl.Failure(description: "ssh mkdir failed (\(m)): \(mo)") }
        let (r, ro) = runLocal(settings.rsync, stageArguments(app))
        guard r == 0 else { throw Simctl.Failure(description: "rsync failed (\(r)): \(ro)") }
    }
}

extension WorkspaceSession {
    public func build(scheme name: String, destination: Destination) async -> (BuildResult, BuildRequest) {
        let request = model.buildRequest(scheme: name, destination: destination, action: .build)
        let engine = self.engine
        let result = await performBuild(request, presentation: .init(action: .build, subject: name), start: engine.start)
        return (result, request)
    }

    public func failRemoteRun(_ text: String) {
        appendConsole("SwiftCode: \(text)\n")
        setActivity(.finished("Run failed"))
    }

    nonisolated public static var watchAgentWait: TimeInterval { Double(ProcessInfo.processInfo.environment["SWIFTCODE_WATCH_AGENT_WAIT_S"] ?? "") ?? 1800 }
    nonisolated public static var pairConnectWait: TimeInterval { Double(ProcessInfo.processInfo.environment["SWIFTCODE_PAIR_CONNECT_WAIT_S"] ?? "") ?? 600 }

    func poll(_ seconds: TimeInterval, interval: Double = 5, cancelled: @MainActor () -> Bool = { false }, _ check: @MainActor () async -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while true {
            if await check() { return true }
            if cancelled() || Date() >= end { return false }
            try? await Task.sleep(for: .seconds(interval))
        }
    }

    func startRemoteWatchIfNeeded(_ watch: RemoteSimulator) -> Bool {
        guard !RemoteDeviceSessions.shared.isRunning(watch) else { return false }
        RemoteDeviceSessions.shared.output = { [weak self] line in self?.appendConsole(line + "\n", kind: .debugger) }
        appendConsole("SwiftCode: starting \(watch.destination.name) on \(watch.settings.destination)\n", kind: .debugger)
        return RemoteDeviceSessions.shared.start(watch)
    }

    public func installOnRemoteWatch(_ watchApp: URL, watch: RemoteSimulator, open: Bool,
                                     cancelled: @escaping @MainActor () -> Bool = { false }) async -> (Bool, String) {
        guard let app = AppBundle(url: watchApp) else { return (false, "\(watchApp.lastPathComponent) is not an application bundle") }
        let name = watch.destination.name
        appendConsole("SwiftCode: waiting for \(name) to be ready for apps\n", kind: .debugger)
        let up = await poll(Self.watchAgentWait, cancelled: cancelled) {
            let reply = await Task.detached { watch.control(["pairing", "state"]).1 }.value
            return RemoteSimulator.agentIsUp(stateReply: reply)
        }
        guard up else { return (false, cancelled() ? "stopped" : "\(name) did not become ready in \(Int(Self.watchAgentWait)) s") }
        do {
            try await Task.detached { try watch.stageApp(watchApp) }.value
        } catch {
            return (false, "the watch app could not be copied: \(error)")
        }
        appendConsole("SwiftCode: installing \(app.bundleID) on \(name) (directly on the watch)\n", kind: .debugger)
        var last = ""
        let installed = await poll(300, interval: 10, cancelled: cancelled) {
            let (s, out) = await Task.detached { watch.runRemote(watch.installAppCommand(watchApp)) }.value
            last = out.trimmingCharacters(in: .whitespacesAndNewlines)
            return s == 0 && last.hasPrefix("ok")
        }
        appendConsole("SwiftCode: installApp: \(last)\n", kind: .debugger)
        guard installed else { return (false, "installApp failed: \(last)") }
        guard open else { return (true, "installed \(app.bundleID)") }
        let opened = await poll(120, interval: 5, cancelled: cancelled) {
            let (s, out) = await Task.detached { watch.runRemote(watch.openAppCommand(bundleID: app.bundleID)) }.value
            last = out.trimmingCharacters(in: .whitespacesAndNewlines)
            return s == 0 && last.hasPrefix("ok")
        }
        appendConsole("SwiftCode: openApp: \(last)\n", kind: .debugger)
        return opened ? (true, "launched \(app.bundleID) on \(name)") : (false, "openApp failed: \(last)")
    }

    public func runOnRemoteWatch(app watchApp: URL, watch: RemoteSimulator) async {
        guard let app = AppBundle(url: watchApp) else {
            appendConsole("SwiftCode: \(watchApp.lastPathComponent) is not an application bundle.\n")
            return
        }
        guard watch.settings.isConfigured else {
            appendConsole("SwiftCode: set the remote simulator in Settings ▸ Simulators first.\n")
            return
        }
        let state = SimulatorRunState(target: .remote(destination: watch.settings.destination), app: app)
        state.remote = watch
        simulatorRun = state
        let device = watch.destination.name
        setActivity(.running(RemoteSimulator.status(.booting, app: app.executable, device: device)))
        _ = startRemoteWatchIfNeeded(watch)
        let (ok, message) = await installOnRemoteWatch(watchApp, watch: watch, open: true) { [weak state] in state?.stopRequested ?? true }
        guard ok else {
            appendConsole("SwiftCode: \(message)\n")
            if simulatorRun === state { simulatorRun = nil }
            setActivity(.finished(state.stopRequested ? WorkspaceSession.RunActivityText.finished(app.executable, on: device) : "Run failed"))
            return
        }
        appendConsole("SwiftCode: \(message)\n", kind: .debugger)
        setActivity(.running(RemoteSimulator.status(.running, app: app.executable, device: device)))
        _ = await poll(1e9, interval: 0.5) { [weak state] in
            guard let state else { return true }
            return state.stopRequested || !RemoteDeviceSessions.shared.isRunning(watch)
        }
        if state.stopRequested, RemoteDeviceSessions.shared.isRunning(watch) {
            setActivity(.running(RemoteSimulator.stoppingStatus(app: app.executable, saves: watch.settings.warmBoot)))
            await RemoteDeviceSessions.shared.shutDown(watch)
        }
        appendConsole("SwiftCode Simulator stopped\n")
        if simulatorRun === state { simulatorRun = nil }
        setActivity(.finished(WorkspaceSession.RunActivityText.finished(app.executable, on: device)))
    }

    public func runOnPairedRemoteSimulators(phone: RemoteSimulator, watch: RemoteSimulator, plan: RemoteWatchRunPlan) async {
        guard let iOSApp = plan.iOSApp, let ios = AppBundle(url: iOSApp) else {
            appendConsole("SwiftCode: no iOS app to install on \(phone.destination.name).\n")
            return
        }
        let startedWatch = startRemoteWatchIfNeeded(watch)
        await runOnRemoteSimulator(app: iOSApp, remote: phone)
        guard let state = simulatorRun, state.remote?.remoteDevicePath == phone.remoteDevicePath else {
            if startedWatch { await RemoteDeviceSessions.shared.shutDown(watch) }
            return
        }
        let watchName = watch.destination.name
        Task { [weak self, weak state] in
            guard let self else { return }
            let over: @MainActor () -> Bool = { [weak state] in state == nil || state?.stopRequested == true || self.simulatorRun !== state }
            let launched = await self.poll(1e9, interval: 1, cancelled: over) { self.console.contains("launched \(ios.bundleID)") }
            if launched {
                let connected = await self.poll(Self.pairConnectWait, interval: 5, cancelled: over) {
                    let pairs = await Task.detached { phone.readPairs() }.value
                    if let pairs { RemotePairsStore.shared.set(pairs) }
                    return pairs?.contains { $0.phoneDirectory == phone.deviceDirectoryName && $0.watchDirectory == watch.deviceDirectoryName && $0.connected } ?? false
                }
                if !connected, !over() { self.appendConsole("SwiftCode: \(watchName) is not connected to \(phone.destination.name) yet; installing the watch app anyway\n", kind: .debugger) }
                if !over() {
                    let (ok, message) = await self.installOnRemoteWatch(plan.watchApp, watch: watch, open: plan.launchWatchApp, cancelled: over)
                    self.appendConsole("SwiftCode: \(ok ? "" : "watch: ")\(message)\n", kind: .debugger)
                    if ok, plan.launchWatchApp, !over(), let w = AppBundle(url: plan.watchApp) {
                        self.setActivity(.running(RemoteSimulator.status(.running, app: w.executable, device: watchName)))
                    }
                }
            }
            _ = await self.poll(1e9, interval: 1) { self.simulatorRun !== state || state == nil }
            if startedWatch, RemoteDeviceSessions.shared.isRunning(watch) {
                self.appendConsole("SwiftCode: shutting down \(watchName) (started for the run)\n", kind: .debugger)
                await RemoteDeviceSessions.shared.shutDown(watch)
            }
        }
    }
}
