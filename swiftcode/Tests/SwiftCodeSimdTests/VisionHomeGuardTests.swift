import Foundation
import Testing
@testable import swiftcode_simd

@Suite struct VisionHomeGuardTests {
    @Test func pressesOnlyWhenTheHomeViewWasNotLaunched() {
        var p = VisionHomeGuardPolicy(delay: 60, maxPresses: 2)
        #expect(p.step(secondsSinceRoom: nil, launcherRunning: false) == .wait)
        #expect(p.step(secondsSinceRoom: 59, launcherRunning: false) == .wait)
        #expect(p.step(secondsSinceRoom: 60, launcherRunning: false) == .press)
        #expect(p.step(secondsSinceRoom: 61, launcherRunning: false) == .wait)
        #expect(p.step(secondsSinceRoom: 120, launcherRunning: false) == .press)
        #expect(p.step(secondsSinceRoom: 200, launcherRunning: false) == .stop)
        #expect(p.presses == 2)

        var q = VisionHomeGuardPolicy(delay: 60, maxPresses: 2)
        #expect(q.step(secondsSinceRoom: 30, launcherRunning: true) == .stop)
        #expect(q.presses == 0)
        var r = VisionHomeGuardPolicy()
        #expect(r.step(secondsSinceRoom: 61, launcherRunning: false) == .press)
        #expect(r.step(secondsSinceRoom: 75, launcherRunning: true) == .stop)
    }

    @Test func environmentAndLauncherPath() {
        #expect(VisionHomeGuardPolicy.fromEnvironment([:]) == VisionHomeGuardPolicy())
        #expect(VisionHomeGuardPolicy.fromEnvironment(["SWIFTCODE_VISIONOS_HOME_GUARD": "0"]) == nil)
        #expect(VisionHomeGuardPolicy.fromEnvironment(["SWIFTCODE_VISIONOS_HOME_GUARD_S": "45"])?.delay == 45)
        #expect(VisionHomeGuardPolicy.isLauncher("/RR/Applications/RealityLauncher.app/RealityLauncher"))
        #expect(!VisionHomeGuardPolicy.isLauncher("/RR/Applications/RealityLauncherHelper.app/RealityLauncherHelper"))
    }

    @Test func shellReadyHoldLabels() {
        #expect(VisionHomeGuardPolicy.shellReadyHoldLabels([:]) == ["com.apple.assistantd"])
        #expect(VisionHomeGuardPolicy.shellReadyHoldLabels(["SWIFTCODE_VISIONOS_SHELL_HOLD": "0"]).isEmpty)
        #expect(VisionHomeGuardPolicy.shellReadyHoldLabels(["SWIFTCODE_VISIONOS_SHELL_HOLD": "a.b, c.d"]) == ["a.b", "c.d"])
    }
}
