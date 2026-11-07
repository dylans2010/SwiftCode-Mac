import Foundation
import Testing
import YcodeProfiler
@testable import YcodeIDECore

@MainActor
@Suite(.serialized) struct GaugeWindowTests {
    @Test func remoteProfileCommands() {
        let s = RemoteSimulatorSettings(destination: "user@host", dataDirectory: "/data", runtimeRoot: "/rr", simdPath: "/bin/swiftcode-sim")
        let remote = RemoteSimulator(settings: s)
        let app = URL(fileURLWithPath: "/build/Release-iphonesimulator/Demo.app")
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let p = remote.profile(app: app, rate: 500, date: date)
        #expect(p.remotePath.hasPrefix("/data/profiles/Demo-") && p.remotePath.hasSuffix(".gaugetrace"))
        #expect(p.localURL.path.hasSuffix("Library/Developer/SwiftCode/Gauge/" + (p.remotePath as NSString).lastPathComponent))
        let cmd = remote.runCommand(app: app, bundleID: "dev.swiftcode.Demo", profile: p)
        #expect(cmd.contains(" --launch 'dev.swiftcode.Demo' --environment-overrides --profile '\(p.remotePath)' --profile-rate '500'"))
        #expect(!remote.runCommand(app: app, bundleID: "dev.swiftcode.Demo").contains("--profile"))
        #expect(remote.fetchArguments(p) == ["-az", "-e", "/usr/bin/ssh -o BatchMode=yes", "user@host:" + p.remotePath, p.localURL.path])
        #expect(GaugeSettings.tracePaths(["/a.xcodeproj", "/t.gaugetrace"]) == (["/t.gaugetrace"], ["/a.xcodeproj"]))
    }

    @Test func profileMenuItemsAreWired() {
        let items = CommandTable.productMenu
        func selector(_ title: String, in list: [MenuItemSpec]) -> String? {
            for i in list {
                switch i {
                case .submenu(_, let sub): if let s = selector(title, in: sub) { return s }
                case .command(let c): if c.title == title { return c.action }
                default: break
                }
            }
            return nil
        }
        #expect(selector("Profile", in: items) == "profileProduct:")
        #expect(selector("Profile…", in: items) == "profileProductEditingScheme:")
        #expect(selector("Profile Without Building", in: items) == "profileWithoutBuilding:")
    }
}
