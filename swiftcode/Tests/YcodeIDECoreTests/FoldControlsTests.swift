import Foundation
import Testing
import YcodeDeviceModel
@testable import YcodeIDECore

@MainActor
@Suite(.serialized) struct FoldControlsTests {
    func settings() -> RemoteSimulatorSettings {
        var s = RemoteSimulatorSettings(destination: "tester@sim-host", dataDirectory: "/data/swiftcode",
                                        runtimeRoot: "/rt/iOS-27.1-24A94401/RuntimeRoot", simdPath: "/data/swiftcode/bin/swiftcode-sim")
        s.otherRuntimeRoots = ["/rt/iOS-27.0-24A434/RuntimeRoot"]
        s.runtimeVersion = "27.1"
        s.runtimeVersions = ["/rt/iOS-27.1-24A94401/RuntimeRoot": "27.1", "/rt/iOS-27.0-24A434/RuntimeRoot": "27.0"]
        return s
    }

    @Test func onlyTheIPhoneDuoFolds() {
        let all = RemoteSimulator.all(settings())
        let foldable = all.filter(\.isFoldable).map { $0.target!.deviceType.id }
        #expect(foldable == ["iphone-duo"])
        let rows = all.map { DeviceRow.swiftcodeRemote($0, running: true) }
        #expect(rows.filter(\.isFoldable).map(\.name) == ["iPhone Duo (SwiftCode)"])
    }

    @Test func controlCommandAndStateReply() {
        let duo = RemoteSimulator.all(settings()).first { $0.isFoldable }!
        #expect(duo.controlCommand(["fold", "half"])
            == "exec '/data/swiftcode/bin/swiftcode-sim' --device '\(duo.remoteDevicePath)' --control 'fold' 'half'")
        #expect(RemoteSimulator.hingeAngle(stateReply: "ok angle 180° (Open Flat), inner side, portrait; showing LCD-1") == 180)
        #expect(RemoteSimulator.hingeAngle(stateReply: "error: this device type does not fold") == nil)
    }
}
