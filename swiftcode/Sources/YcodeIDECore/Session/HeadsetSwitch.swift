import Foundation

public enum HeadsetViewerPhase: String, Sendable, Equatable, Codable {
    case waitingForHeadset
    case streaming
    case stopped
    case absent
}

public struct HeadsetViewerState: Sendable, Equatable, Codable {
    public var phase: HeadsetViewerPhase
    public var pid: Int32?
    public var message: String?
    public init(phase: HeadsetViewerPhase, pid: Int32? = nil, message: String? = nil) {
        self.phase = phase
        self.pid = pid
        self.message = message
    }
}

public protocol HeadsetViewerLauncher: Sendable {
    func start() async throws
    func state() async -> HeadsetViewerState
    func stop() async
}

@MainActor
public protocol HeadsetDesktopStream: AnyObject {
    func holdForHeadset()
    func returnFromHeadset()
}

public enum HeadsetSwitchState: Sendable, Equatable {
    case desktop
    case enteringHeadset
    case inHeadset
    case returningToDesktop
}

public enum HeadsetSwitchAction: Sendable, Equatable {
    case holdDesktopStream, startViewer, stopViewer, resumeDesktopStream, notice(String)
}

public enum HeadsetSwitchEvent: Sendable, Equatable {
    case viewInHeadset, backToDesktop
    case viewerStarted, viewerFailed(String)
    case viewerPhase(HeadsetViewerPhase)
    case timeout
    case viewerStoppedConfirmed
    case deviceStopped
}

public struct HeadsetSwitch: Sendable, Equatable {
    public private(set) var state = HeadsetSwitchState.desktop
    public init() {}

    public static let enterTimeout: TimeInterval = 45

    public var isInHeadset: Bool { state == .inHeadset || state == .enteringHeadset }

    public mutating func handle(_ e: HeadsetSwitchEvent) -> [HeadsetSwitchAction] {
        switch (state, e) {
        case (.desktop, .viewInHeadset):
            state = .enteringHeadset
            return [.holdDesktopStream, .startViewer]
        case (.enteringHeadset, .viewerFailed(let why)):
            state = .desktop
            return [.resumeDesktopStream, .notice("The headset view could not start: \(why)")]
        case (.enteringHeadset, .viewerPhase(.streaming)):
            state = .inHeadset
            return []
        case (.enteringHeadset, .viewerPhase(.stopped)), (.enteringHeadset, .viewerPhase(.absent)):
            state = .desktop
            return [.resumeDesktopStream, .notice("The headset view ended before it started.")]
        case (.enteringHeadset, .timeout):
            state = .returningToDesktop
            return [.stopViewer, .resumeDesktopStream, .notice("The headset did not join in time. Put it on, check that WiVRn's app is connected, and try again.")]
        case (.enteringHeadset, .backToDesktop), (.inHeadset, .backToDesktop):
            state = .returningToDesktop
            return [.resumeDesktopStream, .stopViewer]
        case (.inHeadset, .viewerPhase(.stopped)), (.inHeadset, .viewerPhase(.absent)):
            state = .desktop
            return [.resumeDesktopStream, .notice("The headset view ended; back on the desktop.")]
        case (.returningToDesktop, .viewerStoppedConfirmed):
            state = .desktop
            return []
        case (_, .deviceStopped):
            let was = state
            state = .desktop
            return was == .desktop ? [] : [.stopViewer]
        default:
            return []
        }
    }
}

@MainActor
public final class HeadsetSwitchController {
    public private(set) var machine = HeadsetSwitch()
    public let launcher: any HeadsetViewerLauncher
    public weak var desktop: (any HeadsetDesktopStream)?
    public var onNotice: (String) -> Void = { _ in }
    public var onChange: (HeadsetSwitchState) -> Void = { _ in }
    public var pollInterval: TimeInterval = 0.2
    public var enterTimeout = HeadsetSwitch.enterTimeout
    private var poll: Task<Void, Never>?
    private var enteredAt = Date()
    public private(set) var lastSwitch: (requested: Date, done: Date?)?

    public init(launcher: any HeadsetViewerLauncher, desktop: (any HeadsetDesktopStream)?) {
        self.launcher = launcher
        self.desktop = desktop
    }

    public var state: HeadsetSwitchState { machine.state }

    public func viewInHeadset() async { lastSwitch = (Date(), nil); await send(.viewInHeadset) }
    public func backToDesktop() async { lastSwitch = (Date(), nil); await send(.backToDesktop) }
    public func deviceStopped() async { await send(.deviceStopped) }

    func send(_ e: HeadsetSwitchEvent) async {
        let before = machine.state
        let actions = machine.handle(e)
        if machine.state != before {
            if machine.state == .enteringHeadset { enteredAt = Date() }
            if machine.state == .inHeadset || machine.state == .desktop, let l = lastSwitch, l.done == nil { lastSwitch = (l.requested, Date()) }
            onChange(machine.state)
        }
        for a in actions { await perform(a) }
        updatePolling()
    }

    private func perform(_ a: HeadsetSwitchAction) async {
        switch a {
        case .holdDesktopStream: desktop?.holdForHeadset()
        case .resumeDesktopStream: desktop?.returnFromHeadset()
        case .notice(let text): onNotice(text)
        case .startViewer:
            do {
                try await launcher.start()
                await send(.viewerStarted)
            } catch {
                await send(.viewerFailed("\(error)"))
            }
        case .stopViewer:
            await launcher.stop()
            await send(.viewerStoppedConfirmed)
        }
    }

    private func updatePolling() {
        let wants = machine.state == .enteringHeadset || machine.state == .inHeadset
        if wants, poll == nil {
            poll = Task { [weak self] in
                while let self, !Task.isCancelled, self.machine.state == .enteringHeadset || self.machine.state == .inHeadset {
                    let wait = self.machine.state == .enteringHeadset ? self.pollInterval : max(self.pollInterval, 1)
                    try? await Task.sleep(nanoseconds: UInt64(wait * 1e9))
                    await self.tick()
                }
                self?.poll = nil
            }
        } else if !wants {
            poll?.cancel()
            poll = nil
        }
    }

    public func tick() async {
        guard machine.state == .enteringHeadset || machine.state == .inHeadset else { return }
        let s = await launcher.state()
        guard machine.state == .enteringHeadset || machine.state == .inHeadset else { return }
        if machine.state == .enteringHeadset, s.phase == .waitingForHeadset || s.phase == .absent && Date().timeIntervalSince(enteredAt) < 3 {
            if Date().timeIntervalSince(enteredAt) > enterTimeout { await send(.timeout) }
            return
        }
        await send(.viewerPhase(s.phase))
    }
}

public struct ScriptHeadsetViewerLauncher: HeadsetViewerLauncher {
    public var runner: any HeadsetCommandRunner
    public var plan: HeadsetViewerPlan

    public init(runner: any HeadsetCommandRunner, plan: HeadsetViewerPlan) {
        self.runner = runner
        self.plan = plan
    }

    public struct Failure: Error, CustomStringConvertible { public let description: String }

    public func start() async throws {
        let r = await runner.run(plan.startCommand)
        guard r.ok else { throw Failure(description: r.output.trimmed.isEmpty ? "the viewer host refused (status \(r.status))" : r.output.trimmed) }
    }

    public func state() async -> HeadsetViewerState {
        let r = await runner.run(plan.stateCommand)
        return HeadsetViewerPlan.parseState(r.output)
    }

    public func stop() async { _ = await runner.run(plan.stopCommand) }
}

public struct HeadsetViewerPlan: Sendable, Equatable {
    public var device: String
    public var route: HeadsetRoute
    public var viewerPath: String
    public var options: [String]
    public var runtimeManifest: String?

    public init(device: String, route: HeadsetRoute, viewerPath: String = "swiftcode-xr-viewer", options: [String] = [],
                runtimeManifest: String? = HeadsetChecker.wivrnManifest) {
        self.device = device
        self.route = route
        self.viewerPath = viewerPath
        self.options = options
        self.runtimeManifest = runtimeManifest
    }

    public var directory: String {
        let safe = device.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || "-_.".unicodeScalars.contains($0) ? Character($0) : "_" }
        return "${XDG_RUNTIME_DIR:-/tmp}/swiftcode-headset/\(String(safe))"
    }

    public var viewerArguments: [String] {
        var a: [String]
        switch route {
        case .link(let device, let host): a = ["--link", device] + (host.map { ["--host", $0] } ?? [])
        case .sshSocket: a = ["--connect", "unix:$D/display.sock"]
        }
        return a + ["--state-file", "$D/state.json"] + options
    }

    private var viewerWords: String {
        viewerArguments.map { $0.contains("$D") ? "\"\($0)\"" : $0.shellQuoted }.joined(separator: " ")
    }

    public var startCommand: String {
        var s = "D=\(directory); mkdir -p \"$D\" && chmod 700 \"$D\" || exit 1; S=$(command -v setsid); "
        s += "if [ -f \"$D/viewer.pid\" ] && kill -0 \"$(cat \"$D/viewer.pid\")\" 2>/dev/null; then echo 'already running'; exit 0; fi; "
        s += "rm -f \"$D/state.json\" \"$D/display.sock\"; "
        if case .sshSocket(let dest, let socket) = route {
            s += "$S nohup ssh -N -o BatchMode=yes -o ExitOnForwardFailure=yes -o StreamLocalBindUnlink=yes -L \"$D/display.sock:\(socket)\" \(dest.shellQuoted) "
            s += "> \"$D/forward.log\" 2>&1 < /dev/null & echo $! > \"$D/forward.pid\"; "
            s += "i=0; while [ ! -S \"$D/display.sock\" ] && [ $i -lt 100 ]; do sleep 0.05; i=$((i+1)); done; "
            s += "[ -S \"$D/display.sock\" ] || { echo 'the forward to the simulator host did not start'; cat \"$D/forward.log\"; exit 1; }; "
        }
        let env = runtimeManifest.map { "if [ -f \($0.shellQuoted) ]; then export XR_RUNTIME_JSON=\($0.shellQuoted); fi; " } ?? ""
        s += env
        s += "$S nohup \(viewerPath.shellQuoted) \(viewerWords) > \"$D/viewer.log\" 2>&1 < /dev/null & echo $! > \"$D/viewer.pid\"; exit 0"
        return s
    }

    public var stateCommand: String {
        "D=\(directory); if [ -f \"$D/viewer.pid\" ] && kill -0 \"$(cat \"$D/viewer.pid\")\" 2>/dev/null; then cat \"$D/state.json\" 2>/dev/null || echo '{\"phase\":\"waitingForHeadset\"}'; "
            + "elif [ -f \"$D/state.json\" ]; then cat \"$D/state.json\"; else echo '{\"phase\":\"absent\"}'; fi"
    }

    public var stopCommand: String {
        let name = String((viewerPath as NSString).lastPathComponent.prefix(15))
        var s = "D=\(directory); p=$(cat \"$D/viewer.pid\" 2>/dev/null); "
        s += "if [ -n \"$p\" ] && [ \"$(cat /proc/$p/comm 2>/dev/null)\" = \(name.shellQuoted) ]; then kill -TERM \"$p\"; "
        s += "i=0; while kill -0 \"$p\" 2>/dev/null && [ $i -lt 100 ]; do sleep 0.05; i=$((i+1)); done; kill -0 \"$p\" 2>/dev/null && kill -KILL \"$p\"; fi; "
        s += "f=$(cat \"$D/forward.pid\" 2>/dev/null); if [ -n \"$f\" ] && [ \"$(cat /proc/$f/comm 2>/dev/null)\" = ssh ]; then kill -TERM \"$f\"; fi; "
        s += "rm -f \"$D/viewer.pid\" \"$D/forward.pid\" \"$D/display.sock\"; exit 0"
        return s
    }

    public static func parseState(_ text: String) -> HeadsetViewerState {
        guard let line = text.split(whereSeparator: \.isNewline).last(where: { $0.hasPrefix("{") }),
              let s = try? JSONDecoder().decode(HeadsetViewerState.self, from: Data(line.utf8)) else { return HeadsetViewerState(phase: .absent) }
        return s
    }
}
