import AppKit
import Foundation
import Testing
import YcodeBuild
import YcodeDeviceModel
@testable import YcodeIDECore
@testable import YcodeUI

@MainActor
@Suite(.serialized) struct WatchHubTests {
    static let watchRoot = "/rt/watchOS-27.0-24R362/RuntimeRoot"

    func settings() -> RemoteSimulatorSettings {
        var s = RemoteSimulatorSettings(destination: "tester@sim-host", dataDirectory: "/data/swiftcode",
                                        runtimeRoot: "/rt/iOS-27.1-24A94401/RuntimeRoot", simdPath: "/data/swiftcode/bin/swiftcode-sim")
        s.otherRuntimeRoots = [Self.watchRoot]
        s.runtimeVersion = "27.1"
        s.runtimeVersions = ["/rt/iOS-27.1-24A94401/RuntimeRoot": "27.1", Self.watchRoot: "27.0"]
        return s
    }

    @Test func aWatchRuntimeGivesHubDevicesAndWatchDestinations() {
        let s = settings()
        #expect(s.runtimePlatform(forRoot: Self.watchRoot) == "watchOS")
        #expect(s.runtimePlatform(forRoot: "/rt/iOS-27.1-24A94401/RuntimeRoot") == "iOS")
        #expect(s.targets.allSatisfy { $0.runtimeRoot != Self.watchRoot && $0.deviceType.platform == "iOS" })
        #expect(RemoteSimulator.destinations(s).count == s.targets.count + s.watchTargets.count)
        #expect(RemoteSimulator.destinations(s).dropFirst(s.targets.count).allSatisfy { $0.platform == "watchOS" })
        let hub = s.hubTargets
        #expect(Array(hub.prefix(s.targets.count)) == s.targets)
        let watches = hub.dropFirst(s.targets.count)
        #expect(watches.map(\.deviceType.id).first == "apple-watch-series-12-46mm" && watches.count == 5)
        #expect(watches.allSatisfy { $0.runtimeRoot == Self.watchRoot && !$0.isPrimary && $0.runtimeVersion == "27.0" })
        #expect(watches.first?.deviceDirectoryName == "swiftcode-device-apple-watch-series-12-46mm-27.0")
        #expect(watches.first?.name == "Apple Watch Series 12 (46mm) (SwiftCode)")
        let remote = RemoteSimulator.hub(s)[s.targets.count]
        #expect(remote.startCommand.contains("'--device-type' 'apple-watch-series-12-46mm'"), "\(remote.startCommand)")
        #expect(remote.startCommand.contains(Self.watchRoot))
        #expect(WorkspaceWindowController.previewSimulators(s).allSatisfy { $0.runtimeRoot != Self.watchRoot })
    }
}
