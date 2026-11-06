import Foundation
import Testing
import SwiftCodeBuild
import SwiftCodeProject
@testable import SwiftCodeIDECore

/// IOS27 (`specs/ide/run.md` §Runtimes and device types): SwiftCode's remote
/// simulator with more than one runtime root, one destination row per
/// runtime and device type, each with its own device directory, and the
/// run command naming the runtime and the type. No network.
@MainActor
@Suite(.serialized) struct RemoteRuntimesTests {
    func settings() -> RemoteSimulatorSettings {
        var s = RemoteSimulatorSettings(destination: "tester@sim-host", dataDirectory: "/data/swiftcode",
                                        runtimeRoot: "/rt/iOS-27.1-24A94401/RuntimeRoot", simdPath: "/data/swiftcode/bin/swiftcode-sim")
        s.otherRuntimeRoots = ["/rt/iOS-27.0-24A434/RuntimeRoot"]
        s.runtimeVersion = "27.1"
        s.runtimeVersions = ["/rt/iOS-27.1-24A94401/RuntimeRoot": "27.1", "/rt/iOS-27.0-24A434/RuntimeRoot": "27.0"]
        return s
    }

    @Test func deviceTypesPerRuntimeVersion() {
        #expect(SwiftCodeSimulatorDeviceType.supported(onRuntimeVersion: "27.1").map(\.id) == ["iphone-duo", "ipad-a16", "ipad-pro-13-m5"])
        // iPhone Duo's minRuntimeVersion is 27.1: on 27.0 the iPhone is the 18 Pro (iphone-types.md §5 I3).
        #expect(SwiftCodeSimulatorDeviceType.supported(onRuntimeVersion: "27.0").map(\.id) == ["iphone-18-pro", "ipad-a16", "ipad-pro-13-m5"])
        #expect(SwiftCodeSimulatorDeviceType.supported(onRuntimeVersion: nil).count == SwiftCodeSimulatorDeviceType.all.count)
        #expect(SwiftCodeSimulatorDeviceType.supported(onRuntimeVersion: "18.3").map(\.id) == ["ipad-a16"])
    }

    @Test func targetsRowsAndDeviceDirectories() {
        let s = settings()
        let t = s.targets
        #expect(t.map(\.name) == ["iPhone Duo (SwiftCode)", "iPad (A16) (SwiftCode)", "iPad Pro 13-inch (M5) (SwiftCode)",
                                  "iPhone 18 Pro (SwiftCode)", "iPad (A16) (SwiftCode)", "iPad Pro 13-inch (M5) (SwiftCode)"])
        #expect(t.map(\.runtimeVersion) == ["27.1", "27.1", "27.1", "27.0", "27.0", "27.0"])
        // The primary target keeps the identifier and device of a single runtime.
        #expect(t[0].isPrimary && t[0].identifier == RemoteSimulator.identifier && t[0].deviceDirectoryName == "swiftcode-device")
        #expect(!t.dropFirst().contains { $0.isPrimary })
        #expect(t.map(\.deviceDirectoryName) == ["swiftcode-device", "swiftcode-device-ipad-a16-27.1", "swiftcode-device-ipad-pro-13-m5-27.1",
                                                 "swiftcode-device-iphone-18-pro-27.0", "swiftcode-device-ipad-a16-27.0", "swiftcode-device-ipad-pro-13-m5-27.0"])
        #expect(Set(t.map(\.identifier)).count == t.count)
        #expect(t[3].identifier == "swiftcode-remote-simulator:iphone-18-pro@/rt/iOS-27.0-24A434/RuntimeRoot")
        let rows = RemoteSimulator.destinations(s)
        #expect(rows.allSatisfy { $0.isSwiftCodeRemoteSimulator })
        let titles = rows.map { DestinationMenuModel.submenuTitle($0) }
        #expect(titles[3] == "iPhone 18 Pro (SwiftCode) 27.0")
        // A destination finds its target; an unknown one falls back to the primary.
        #expect(s.target(for: rows[5])?.deviceDirectoryName == "swiftcode-device-ipad-pro-13-m5-27.0")
        #expect(s.target(for: nil)?.isPrimary == true)
        var stale = rows[5]
        stale.identifier = "swiftcode-remote-simulator:ipad-a16@/gone"
        #expect(s.target(for: stale)?.isPrimary == true)
    }

    @Test func runCommandNamesTheRuntimeTheTypeAndTheDevice() {
        let s = settings()
        let app = URL(fileURLWithPath: "/tmp/Tour.app")
        let primary = RemoteSimulator(settings: s).runCommand(app: app, bundleID: "org.swiftcode.Tour")
        #expect(primary.contains("--device '/data/swiftcode/devices/swiftcode-device' --runtime-root '/rt/iOS-27.1-24A94401/RuntimeRoot' --install-app"))
        #expect(!primary.contains("--device-type"))
        let pad = RemoteSimulator(settings: s, destination: RemoteSimulator.destinations(s)[5])
        let cmd = pad.runCommand(app: app, bundleID: "org.swiftcode.Tour")
        #expect(cmd.contains("--device '/data/swiftcode/devices/swiftcode-device-ipad-pro-13-m5-27.0' --runtime-root '/rt/iOS-27.0-24A434/RuntimeRoot' '--device-type' 'ipad-pro-13-m5' --install-app"))
        #expect(pad.eraseCommand == "exec '/data/swiftcode/bin/swiftcode-sim' --erase --device '/data/swiftcode/devices/swiftcode-device-ipad-pro-13-m5-27.0'")
        #expect(pad.runtimeVersionCommand == "cat '/rt/iOS-27.0-24A434/RuntimeRoot/System/Library/CoreServices/SystemVersion.plist'")
        let phone = RemoteSimulator(settings: s, destination: RemoteSimulator.destinations(s)[3])
        #expect(phone.runCommand(app: app, bundleID: "org.swiftcode.Tour").contains("--device '/data/swiftcode/devices/swiftcode-device-iphone-18-pro-27.0' --runtime-root '/rt/iOS-27.0-24A434/RuntimeRoot' '--device-type' 'iphone-18-pro' --install-app"))
        // Every row boots every service by default; Lean boot, when on, applies to every row (run.md).
        for d in RemoteSimulator.destinations(s) {
            #expect(!RemoteSimulator(settings: s, destination: d).runCommand(app: app, bundleID: "org.swiftcode.Tour").contains("SWIFTCODE_LEAN_BOOT"))
        }
        var lean = s
        lean.leanBoot = true
        #expect(RemoteSimulator(settings: lean, destination: RemoteSimulator.destinations(lean)[5]).runCommand(app: app, bundleID: "org.swiftcode.Tour")
            .contains("exec env SWIFTCODE_WARM_BOOT=1 SWIFTCODE_LEAN_BOOT=daemons '/data/swiftcode/bin/swiftcode-sim' --device '/data/swiftcode/devices/swiftcode-device-ipad-pro-13-m5-27.0'"))
    }

    @Test func otherRuntimeRootsArePersistedAndVersionsKeptPerRoot() {
        let t = TestDefaults("ios27-roots")
        defer { t.remove() }
        var s = settings()
        s.runtimeVersions = [:]
        s.save(t.defaults)
        #expect(RemoteSimulatorSettings.runtimeRoots(fromText: " /a ,/b\n/c,, ") == ["/a", "/b", "/c"])
        var loaded = RemoteSimulatorSettings.load(t.defaults)
        #expect(loaded.otherRuntimeRoots == ["/rt/iOS-27.0-24A434/RuntimeRoot"])
        #expect(loaded.allRuntimeRoots == ["/rt/iOS-27.1-24A94401/RuntimeRoot", "/rt/iOS-27.0-24A434/RuntimeRoot"])
        // No version known and none in the path: every type is offered.
        loaded.otherRuntimeRoots = ["/rt/other"]
        #expect(loaded.targets.filter { $0.runtimeRoot == "/rt/other" }.map(\.deviceType.id) == ["iphone-duo", "iphone-18-pro", "ipad-a16", "ipad-pro-13-m5"])
        #expect(loaded.targets.last?.deviceDirectoryName == "swiftcode-device-ipad-pro-13-m5-other")
        // Versions read from the host are kept per root.
        #expect(!RemoteSimulatorSettings.hasRuntimeVersion(for: "/rt/iOS-27.0-24A434/RuntimeRoot", t.defaults))
        RemoteSimulatorSettings.saveRuntimeVersion("27.0", root: "/rt/iOS-27.0-24A434/RuntimeRoot", t.defaults, primary: false)
        RemoteSimulatorSettings.saveRuntimeVersion("27.1", root: "/rt/iOS-27.1-24A94401/RuntimeRoot", t.defaults)
        #expect(RemoteSimulatorSettings.hasRuntimeVersion(for: "/rt/iOS-27.0-24A434/RuntimeRoot", t.defaults))
        let again = RemoteSimulatorSettings.load(t.defaults)
        #expect(again.runtimeVersion == "27.1" && again.runtimeVersion(forRoot: "/rt/iOS-27.0-24A434/RuntimeRoot") == "27.0")
    }
}
