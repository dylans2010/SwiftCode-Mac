import Foundation
import Testing
import YcodeProject
@testable import YcodeIDECore

@MainActor
@Suite(.serialized) struct WindowIdentityR38Tests {

    @Test func welcomeGateWaitsForOpensRequestedAtLaunch() {
        func run(_ steps: [(inout WelcomeLaunchGate) -> Bool]) -> [Bool] {
            var g = WelcomeLaunchGate()
            return steps.map { $0(&g) }
        }
        let request: (inout WelcomeLaunchGate) -> Bool = { $0.openRequested(); return false }
        func check(_ n: Int) -> (inout WelcomeLaunchGate) -> Bool { { $0.launchCheck(openDocuments: n) } }
        func finish(_ n: Int) -> (inout WelcomeLaunchGate) -> Bool { { $0.openFinished(openDocuments: n) } }
        #expect(run([request, check(0), finish(1), request, finish(0)]) == [false, false, false, false, false])
        #expect(run([request, check(0), finish(0)]) == [false, false, true])
        #expect(run([request, finish(1), check(1)]) == [false, false, false])
        #expect(run([check(0)]) == [true])
        #expect(run([check(2)]) == [false])
    }
}
