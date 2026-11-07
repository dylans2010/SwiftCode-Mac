import Foundation

struct VisionHomeGuardPolicy: Equatable {
    var delay: Double = 60
    var maxPresses = 2

    enum Action: Equatable {
        case wait
        case press
        case stop
    }

    private(set) var presses = 0
    private var lastPress: Double?

    init(delay: Double = 60, maxPresses: Int = 2) {
        self.delay = delay
        self.maxPresses = maxPresses
    }

    mutating func step(secondsSinceRoom: Double?, launcherRunning: Bool) -> Action {
        if launcherRunning { return .stop }
        guard let t = secondsSinceRoom else { return .wait }
        if presses >= maxPresses { return .stop }
        let due = (lastPress ?? 0) + delay
        guard t >= due else { return .wait }
        presses += 1
        lastPress = t
        return .press
    }

    static func fromEnvironment(_ env: [String: String] = ProcessInfo.processInfo.environment) -> VisionHomeGuardPolicy? {
        if env["SWIFTCODE_VISIONOS_HOME_GUARD"] == "0" { return nil }
        var p = VisionHomeGuardPolicy()
        if let s = env["SWIFTCODE_VISIONOS_HOME_GUARD_S"].flatMap(Double.init), s > 0 { p.delay = s }
        return p
    }

    static func shellReadyHoldLabels(_ env: [String: String] = ProcessInfo.processInfo.environment) -> Set<String> {
        guard let v = env["SWIFTCODE_VISIONOS_SHELL_HOLD"] else { return ["com.apple.assistantd"] }
        if v == "0" || v.isEmpty { return [] }
        return Set(v.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    static func isLauncher(_ path: String) -> Bool { path.hasSuffix("/RealityLauncher.app/RealityLauncher") }
}

#if os(Linux) && arch(arm64)
import SwiftCodeDarwinKernel
import SwiftCodeHostServices
import SwiftCodeHypervisor

enum VisionHomeGuard {
    static func start(policy: VisionHomeGuardPolicy?, statePath: String, surfaces: IOSurfaceHostService,
                      hid: HIDHostService?, system: DarwinSystem) {
        let thread = Thread {
            let guarding = policy != nil && hid != nil
            var policy = policy ?? VisionHomeGuardPolicy()
            let reader = FrameRecordReader(path: statePath)
            var last = reader.read()
            var lit = 0, firstLit: UInt64 = 0, lastCheck: UInt64 = 0, lastLauncherCheck: UInt64 = 0
            let deadline = monotonicNanoseconds() &+ 3_600_000_000_000
            while monotonicNanoseconds() < deadline {
                if firstLit == 0 {
                    usleep(20_000)
                    let now0 = monotonicNanoseconds()
                    if now0 &- lastLauncherCheck >= 1_000_000_000 {
                        lastLauncherCheck = now0
                        if system.allProcesses.contains(where: { !$0.isZombie && VisionHomeGuardPolicy.isLauncher($0.executablePath) }) {
                            system.markShellReady(reason: "the home view runs")
                        }
                    }
                    guard let r = reader.read(), r != last else { continue }
                    last = r
                    let now = monotonicNanoseconds()
                    guard now &- lastCheck >= 100_000_000 else { continue }
                    lastCheck = now
                    guard let c = FrameProfile.checkSurface(r.surface, surfaces: surfaces) else { continue }
                    lit = c.dark < 900 ? lit + 1 : 0
                    if lit >= 2 {
                        firstLit = now
                        system.markShellReady(reason: "the room's first lit frame")
                        if !guarding { return }
                    }
                    continue
                }
                usleep(500_000)
                let since = Double(monotonicNanoseconds() &- firstLit) / 1e9
                let running = system.allProcesses.contains { !$0.isZombie && VisionHomeGuardPolicy.isLauncher($0.executablePath) }
                switch policy.step(secondsSinceRoom: since, launcherRunning: running) {
                case .wait:
                    continue
                case .stop:
                    if !running {
                        stderrLine("swiftcode-simd: visionOS home guard: RealityLauncher still not launched after \(policy.presses) Home presses")
                    } else if policy.presses > 0 {
                        stderrLine("swiftcode-simd: visionOS home guard: RealityLauncher launched after \(policy.presses) Home press(es)")
                    }
                    return
                case .press:
                    stderrLine("swiftcode-simd: visionOS home guard: the shell has not launched the home view "
                        + String(format: "%.0f", since) + " s after the room's first frame; pressing Home "
                        + "(press \(policy.presses) of \(policy.maxPresses); visionos.md §10.21)")
                    _ = hid?.send(.button(usagePage: 0x0C, usage: 0x40, down: true))
                    usleep(100_000)
                    _ = hid?.send(.button(usagePage: 0x0C, usage: 0x40, down: false))
                }
            }
        }
        thread.name = "swiftcode visionOS shell watch"
        thread.start()
    }
}
#endif
