import AppKit
import Foundation
import Testing
import YcodeDeviceModel
@testable import YcodeIDECore
@testable import YcodeUI

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

    func row(foldable: Bool, booted: Bool, name: String = "iPhone Duo (SwiftCode)") -> DeviceRow {
        DeviceRow(name: name, identifier: "h:/data/swiftcode/devices/\(name)", platform: "iOS", osVersion: "27.1",
                  state: booted ? "Booted" : "Shutdown", model: "SwiftCode Simulator (Linux)", isAvailable: true,
                  isSwiftCodeRemote: true, isFoldable: foldable)
    }

    @Test func controlsForAFoldableRowOnly() async {
        let duo = row(foldable: true, booted: true), pad = row(foldable: false, booted: true, name: "iPad (A16) (SwiftCode)")
        let c = DevicesController(devices: [], simulators: [duo, pad])
        var sent: [[String]] = []
        c.foldDevice = { _, words in
            sent.append(words)
            return words == ["state"] ? (true, "ok angle 0° (Closed), cover side, portrait; showing LCD") : (true, "ok " + words.joined(separator: " "))
        }
        c.show(.simulators)
        c.select(row: 0)
        await c.foldTask?.value
        #expect(c.foldControlsShown && c.foldControlsEnabled)
        #expect(sent == [["state"]] && c.hingeAngle == 0)
        await c.fold(to: 180)?.value
        #expect(sent.last == ["fold", "180"] && c.hingeAngle == 180 && c.foldStatus == "At 180°")
        let menu = c.contextMenu(forRow: 0)
        #expect(menu.items.map(\.title) == ["Shut Down", "Restart", "Force Shut Down", "", "Open in New Window", "",
                                            "Closed", "Partially Open", "Open", "Rotate Left", "Rotate Right", "", DevicesController.eraseTitle])
        let item = { (t: String) in menu.items.first { $0.title == t }! }
        #expect(item("Open").state == .on && item("Closed").state == .off && item("Closed").isEnabled)
        await c.rotate(left: true)?.value
        #expect(sent.last == ["rotate", "left"])
        #expect(c.detailRows.contains { $0.0 == "Fold" && $0.1 == "180° (Open)" })
        #expect(c.performWithoutDisplay(.posePartiallyOpen))
        await c.foldTask?.value
        #expect(sent.last == ["fold", "90"] && c.hingeAngle == 90)
        c.select(row: 1)
        #expect(!c.foldControlsShown && !c.foldControlsEnabled)
        #expect(c.contextMenu(forRow: 1).items.map(\.title) == ["Shut Down", "Restart", "Force Shut Down", "", "Open in New Window", "",
                                                                DevicesController.eraseTitle])
        #expect(c.fold(to: 90) == nil && !c.performWithoutDisplay(.poseOpen))
    }

    @Test func aStoppedDeviceStartsClosedAndCannotFold() async {
        let c = DevicesController(devices: [], simulators: [row(foldable: true, booted: true)])
        c.foldDevice = { _, w in (true, w == ["state"] ? "ok angle 90° (Half Open)" : "ok") }
        c.show(.simulators)
        await c.foldTask?.value
        #expect(c.hingeAngle == 90)
        c.setSwiftCodeRemote(rows: [row(foldable: true, booted: false)])
        #expect(c.hingeAngle == nil && c.foldControlsShown && !c.foldControlsEnabled)
        #expect(c.detailRows.contains { $0.0 == "Fold" && $0.1 == "Closed when it boots" })
        #expect(c.contextMenu(forRow: 0).items.filter { DevicePosture.allCases.map(\.title).contains($0.title) }.allSatisfy { !$0.isEnabled })
        _ = c.view
        #expect(c.canvas.stateDescription == "stopped")
    }
}
