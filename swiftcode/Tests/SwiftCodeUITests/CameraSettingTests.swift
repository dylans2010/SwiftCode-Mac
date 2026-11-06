import AppKit
import Foundation
import Testing
@testable import SwiftCodeIDECore
@testable import SwiftCodeUI

/// Settings ▸ Simulators ▸ Camera (specs/simulator/camera.md "SwiftCode
/// implementation", specs/ide/run.md): off by default and not passed; once
/// chosen, every run passes `--camera <mode>` (the device keeps the last value).
@MainActor @Suite struct CameraSettingTests {
    @Test func cameraIsOffAndUnsaidUntilChosen() throws {
        let t = TestDefaults("camera-setting")
        defer { t.remove() }
        let prefs = Preferences(defaults: t.defaults)
        let pane = SimulatorsSettingsPane(prefs: prefs)
        _ = pane.view
        pane.update { $0.destination = "u@h"; $0.dataDirectory = "/d"; $0.runtimeRoot = "/r"; $0.simdPath = "/s" }
        let app = URL(fileURLWithPath: "/tmp/Probe.app")
        var s = RemoteSimulatorSettings.load(t.defaults)
        #expect(s.camera == "off" && !s.cameraChosen)
        #expect(!RemoteSimulator(settings: s).runCommand(app: app, bundleID: "dev.swiftcode.CameraProbe").contains("--camera"))
        #expect(pane.rowTitles.contains("Camera"))
        pane.choose("Host webcam", inRow: "Camera")
        s = RemoteSimulatorSettings.load(t.defaults)
        #expect(s.camera == "on" && s.cameraChosen)
        #expect(RemoteSimulator(settings: s).runCommand(app: app, bundleID: "dev.swiftcode.CameraProbe")
            .hasSuffix(" '--camera' 'on'"))
        pane.choose("Synthetic pattern", inRow: "Camera")
        #expect(RemoteSimulatorSettings.load(t.defaults).camera == "synthetic")
        // Turned off again: said explicitly, so the device forgets its camera.
        pane.choose("Off", inRow: "Camera")
        s = RemoteSimulatorSettings.load(t.defaults)
        #expect(s.camera == "off" && s.cameraChosen)
        #expect(RemoteSimulator(settings: s).cameraArguments == ["--camera", "off"])
        // An unknown stored value reads as off.
        t.defaults.set("bogus", forKey: "SwiftCode.remote.camera")
        #expect(RemoteSimulatorSettings.load(t.defaults).camera == "off")
    }
}

/// Device Hub ▸ a SwiftCode simulator ▸ Settings ▸ Camera (specs/ide/devices.md
/// §Camera): the same setting as Settings ▸ Simulators, on SwiftCode rows only.
@MainActor @Suite struct CameraDevicesTests {
    @Test func swiftcodeRowsShowTheSharedCameraSetting() {
        let t = TestDefaults("camera-devices")
        defer { t.remove() }
        var s = RemoteSimulatorSettings(destination: "u@h", dataDirectory: "/d", runtimeRoot: "/r/iOS-27.1-24A94401/RuntimeRoot", simdPath: "/s")
        s.save(t.defaults)
        let swiftcode = DeviceRow(name: "iPhone 18 Pro (SwiftCode)", identifier: "u@h:/d/devices/x", platform: "iOS", osVersion: "27.1",
                              state: "Shutdown", model: "SwiftCode Simulator (Linux)", isAvailable: true, isSwiftCodeRemote: true)
        let other = DeviceRow(name: "iPhone", identifier: "UDID", platform: "iOS", osVersion: "27.1", state: "Shutdown",
                              model: "iPhone", isAvailable: true)
        let c = DevicesController(devices: [], simulators: [swiftcode, other])
        c.cameraSetting = DevicesController.cameraSetting(t.defaults)
        c.show(.simulators)
        c.select(row: 0)
        _ = c.view
        #expect(c.cameraControlsShown && c.cameraTitle == "Off" && c.inspectorTab == .settings)
        let box = c.cameraControls()
        #expect(box.identifier?.rawValue == "camera-controls")
        let card = (box as? NSStackView)?.arrangedSubviews.compactMap { $0 as? InspectorCard }.first
        let popUp = card?.subviews.compactMap { $0 as? NSPopUpButton }.first
        #expect(popUp?.itemTitles == DevicesController.cameraTitles && popUp?.titleOfSelectedItem == "Off")
        c.chooseCamera("Host webcam")
        s = RemoteSimulatorSettings.load(t.defaults)
        #expect(s.camera == "on" && s.cameraChosen && c.cameraTitle == "Host webcam")
        #expect(RemoteSimulator(settings: s).cameraArguments == ["--camera", "on"])
        // The hub's Start passes it too.
        #expect(RemoteSimulator(settings: s).startCommand.hasSuffix(" '--camera' 'on'"))
        c.chooseCamera("Nonsense")
        #expect(RemoteSimulatorSettings.load(t.defaults).camera == "on")
        c.chooseCamera("Off")
        #expect(RemoteSimulatorSettings.load(t.defaults).camera == "off")
        // Other simulators have no SwiftCode camera.
        c.select(row: 1)
        #expect(!c.cameraControlsShown)
    }
}
