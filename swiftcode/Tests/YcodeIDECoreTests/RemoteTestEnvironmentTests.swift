import Foundation
import Testing
@testable import YcodeIDECore

@Suite struct RemoteTestEnvironmentTests {
    @Test func variablesFollowTheRunSettings() {
        var s = RemoteSimulatorSettings(destination: "<user>@<host>", dataDirectory: "/data", runtimeRoot: "/rt/iOS 27.0/RuntimeRoot",
                                        simdPath: "/bin/swiftcode-sim", deviceName: "phone")
        s.additionalArguments = "--timeout-ms 5 '--x y'"
        s.leanBoot = true
        s.keepServices = "com.a, com.b"
        let env = RemoteSimulator(settings: s).testEnvironment
        #expect(env["SWIFTCODE_SIM_HOST"] == "<user>@<host>" && env["SWIFTCODE_SIM_DATA"] == "/data")
        #expect(env["SWIFTCODE_SIM_RUNTIME"] == "/rt/iOS 27.0/RuntimeRoot" && env["SWIFTCODE_SIM_SIMD"] == "/bin/swiftcode-sim")
        #expect(env["SWIFTCODE_SIM_OPTIONS"]?.contains("'--timeout-ms' '5' '--x y'") == true)
        #expect(env["SWIFTCODE_SIM_ENV"] == "SWIFTCODE_WARM_BOOT=1 SWIFTCODE_LEAN_BOOT=daemons SWIFTCODE_LEAN_BOOT_KEEP='com.a,com.b'")
        #expect(env["SWIFTCODE_SSH"] == nil)
        #expect(RemoteSimulator.testDestination == "platform=iOS Simulator,name=SwiftCode Simulator,arch=arm64")
        s.warmBoot = false
        s.leanBoot = false
        s.ssh = "/tmp/fake-ssh"
        let off = RemoteSimulator(settings: s).testEnvironment
        #expect(off["SWIFTCODE_SIM_ENV"] == "SWIFTCODE_WARM_BOOT=0" && off["SWIFTCODE_SSH"] == "/tmp/fake-ssh")
    }
}
