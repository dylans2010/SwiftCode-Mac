#if os(macOS)
import Foundation
import Testing
@testable import SwiftCodeIDECore
@testable import SwiftCodeUI

@Suite struct RemoteDebugTests {
    let remote = RemoteSimulator(settings: RemoteSimulatorSettings(destination: "tester@sim-host", dataDirectory: "/data/swiftcode",
                                                                   runtimeRoot: "/rr", simdPath: "/bin/swiftcode-sim", deviceName: "dev1"))

    @Test func runCommandServesTheStubOnlyUnderTheDebugger() {
        let app = URL(fileURLWithPath: "/build/Demo.app")
        let plain = remote.runCommand(app: app, bundleID: "dev.swiftcode.demo")
        #expect(!plain.contains("--debug-server"))
        let debug = remote.runCommand(app: app, bundleID: "dev.swiftcode.demo", debug: true)
        #expect(debug.contains(" '--debug-server' 'unix:/data/swiftcode/debug/dev1.sock'"))
        #expect(debug.hasPrefix(plain.components(separatedBy: " '--display-server'")[0]))
        #expect(remote.debugSocketPath == "/data/swiftcode/debug/dev1.sock")
    }

    @Test func forwardAndSettings() {
        #expect(remote.debugForwardArguments(localPort: 47_201) == [
            "-o", "BatchMode=yes", "-N", "-o", "ExitOnForwardFailure=yes", "-o", "ServerAliveInterval=15",
            "-L", "127.0.0.1:47201:/data/swiftcode/debug/dev1.sock", "tester@sim-host",
        ])
        let s = RemoteSimulator.debuggerSettings(appDirectory: "/build/Demo.app")
        #expect(s.contains("settings set target.exec-search-paths \"/build/Demo.app\""))
        #expect(s.contains("settings set target.process.memory-cache-line-size 16384"))
        #expect(s.contains("settings set target.enable-trampoline-support false"))
        let port = RemoteSimulator.freeLoopbackPort()
        #expect(port.map { $0 > 0 && $0 < 65_536 } == true)
    }

    @Test func attachesOnlyWhenTheStubListens() {
        #expect("swiftcode-simd: debug: gdb-remote stub listening on unix:/data/swiftcode/debug/dev1.sock"
            .contains(RemoteSimulator.debugStubListeningMarker))
        #expect(!"swiftcode-simd: app: ylaunch: launched dev.swiftcode.demo pid 9".contains(RemoteSimulator.debugStubListeningMarker))
        let t = TestDefaults("remote-debugger")
        defer { t.remove() }
        #expect(RemoteSimulator.attachesDebugger(t.defaults))
        t.defaults.set(false, forKey: "SwiftCode.remote.debugger")
        #expect(!RemoteSimulator.attachesDebugger(t.defaults))
    }
}
#endif
