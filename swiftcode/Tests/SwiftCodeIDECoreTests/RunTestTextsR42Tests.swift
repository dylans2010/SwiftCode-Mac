import Foundation
import Testing
import SwiftCodeBuild
import SwiftCodeProject
@testable import SwiftCodeIDECore

@MainActor
@Suite(.serialized, .timeLimit(.minutes(5))) struct RunTestTextsR42Tests {
    func sim(_ name: String, _ version: String, type: String? = nil) -> Destination {
        Destination(name: name, specifier: "platform=iOS Simulator,id=\(name)-\(version)", platform: "iOS", kind: .simulator,
                    osVersion: version, identifier: "\(name)-\(version)",
                    deviceType: type.map { "com.apple.CoreSimulator.SimDeviceType.\($0)" })
    }

    func remoteRow(_ type: SwiftCodeSimulatorDeviceType, _ version: String?, root: String = "/rr") -> Destination {
        RemoteSimulatorTarget(runtimeRoot: root, runtimeVersion: version, deviceType: type, deviceDirectoryName: "d", isPrimary: false).destination
    }

    func pick(_ sims: [Destination], target: String = "18.0", families: Set<String>? = nil, mac: Bool = false) -> Destination {
        DestinationCatalog.defaultDestination(platform: "iOS", deploymentTarget: target, simulators: sims, supportsMacOS: mac,
                                              deviceFamilies: families, order: DestinationMenuModel.orderedSimulators)
    }

    var observedSet: [Destination] {
        [sim("Phone X", "27.1"), sim("iPhone Duo", "27.1"),
         sim("iPhone 18 Pro", "27.0"), sim("iPhone 18 Pro Max", "27.0"), sim("iPhone Air", "27.0"), sim("iPhone 17e", "27.0"),
         sim("iPhone 17 Pro", "27.0"), sim("iPad Air 11-inch (M4)", "27.0"),
         sim("iPhone 18 Pro", "26.5"), sim("iPhone 17 Pro", "26.5")]
    }

    @Test func newestProIPhoneOnTheNewestRuntimeThatHasOne() {
        let d = pick(observedSet)
        #expect(d.name == "iPhone 18 Pro" && d.osVersion == "27.0")
        #expect(DestinationMenuModel.submenuTitle(d) == "iPhone 18 Pro 27.0")
        let noPro = observedSet.filter { DestinationCatalog.proIPhoneGeneration(of: $0) == nil }
        #expect(pick(noPro) == DestinationMenuModel.orderedSimulators(noPro).first)
        #expect(pick(noPro).name == "iPhone Duo" && pick(noPro).osVersion == "27.1")
        #expect(pick(observedSet, target: "27.1").name == "iPhone Duo")
        #expect(pick(observedSet + [sim("iPhone 17 Pro", "27.1")], target: "27.1").name == "iPhone 17 Pro")
        #expect(pick([], target: "18.0").name == "Any iOS Simulator Device")
    }

    @Test func proGenerationsComeFromTheDeviceType() {
        #expect(DestinationCatalog.proIPhoneGeneration(of: sim("iPhone 18 Pro", "27.0")) == 18)
        for name in ["iPhone 18 Pro Max", "iPhone Air", "iPhone 17e", "iPhone 18", "Phone X", "iPad Pro 13-inch (M5)"] {
            #expect(DestinationCatalog.proIPhoneGeneration(of: sim(name, "27.0")) == nil, "\(name)")
        }
        #expect(DestinationCatalog.proIPhoneGeneration(of: sim("Work phone", "27.0", type: "iPhone-18-Pro")) == 18)
        #expect(DestinationCatalog.proIPhoneGeneration(of: sim("iPhone 19 Pro", "27.0", type: "iPhone-Air")) == nil)
        let renamed = [sim("iPhone 17 Pro", "27.0", type: "iPhone-17-Pro"), sim("Work phone", "26.5", type: "iPhone-18-Pro")]
        #expect(pick(renamed).name == "Work phone")
        #expect(DestinationCatalog.deviceFamily(of: sim("Work phone", "26.5", type: "iPhone-18-Pro")) == "iPhone")
        #expect(DestinationCatalog.deviceFamily(of: sim("Tablet", "26.5", type: "iPad-Pro-13-inch-M5")) == "iPad")
        #expect(DestinationCatalog.deviceFamily(of: sim("Phone X", "27.1")) == nil)
        let json = Data("""
        {"devices": {"com.apple.CoreSimulator.SimRuntime.iOS-27-0": [
          {"udid": "U1", "name": "Mine", "isAvailable": true, "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro"}]}}
        """.utf8)
        let listed = DestinationCatalog.simulators(fromSimctlJSON: json)
        #expect(listed.first?.deviceType == "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro")
        #expect(pick(listed + [sim("iPhone 17 Pro", "27.0")]).name == "Mine")
    }

    @Test func deviceFamiliesTheProductSupports() {
        #expect(DestinationCatalog.deviceFamilies(targetedDeviceFamily: "1,2") == ["iPhone", "iPad"])
        #expect(DestinationCatalog.deviceFamilies(targetedDeviceFamily: "2") == ["iPad"])
        #expect(DestinationCatalog.deviceFamilies(targetedDeviceFamily: nil) == nil)
        #expect(DestinationCatalog.deviceFamilies(targetedDeviceFamily: "7") == nil)
        let named = observedSet.filter { $0.name != "Phone X" }
        #expect(pick(named, families: ["iPad"]).name == "iPad Air 11-inch (M4)")
        #expect(pick([sim("Phone X", "27.1"), sim("iPad Air", "27.0")], families: ["iPad"]).name == "Phone X")
    }

    @Test func swiftcodeSimulatorRowsRankWithLocalSimulators() {
        let swiftcode18 = remoteRow(.iPhone18Pro, "27.0"), duo = remoteRow(.iPhoneDuo, "27.1", root: "/rr2"), ipad = remoteRow(.iPadA16, "27.0")
        #expect(swiftcode18.name == "iPhone 18 Pro (SwiftCode)" && DestinationCatalog.proIPhoneGeneration(of: swiftcode18) == 18)
        #expect(DestinationCatalog.proIPhoneGeneration(of: duo) == nil && DestinationCatalog.deviceFamily(of: ipad) == "iPad")
        #expect(pick([swiftcode18, duo, ipad, sim("iPhone 18 Pro", "27.0")]).identifier == "iPhone 18 Pro-27.0")
        let d = pick([swiftcode18, duo, ipad, sim("iPhone 18 Pro", "26.5"), sim("iPhone 17 Pro", "26.5")])
        #expect(d.isSwiftCodeRemoteSimulator && d.name == "iPhone 18 Pro (SwiftCode)")
        #expect(pick([duo, ipad]).name == "iPhone Duo (SwiftCode)")
        let unread = remoteRow(.iPhone18Pro, nil)
        #expect(pick([unread, sim("iPhone 18 Pro", "26.5"), sim("iPhone 17", "27.0")]).isSwiftCodeRemoteSimulator)
        #expect(pick([unread, sim("iPhone 18 Pro", "27.0")]).identifier == "iPhone 18 Pro-27.0")
    }

    @Test func multiplatformAppDefaultsToMyMac() {
        #expect(pick(observedSet, mac: true) == .myMac)
        #expect(DestinationCatalog.defaultDestination(platform: "macOS", deploymentTarget: nil, simulators: observedSet) == .myMac)
        #expect(DestinationCatalog.defaultDestination(platform: nil, deploymentTarget: nil, simulators: observedSet) == .myMac)
    }

    @Test func runTextsHaveNoCounters() {
        #expect(WorkspaceSession.RunActivityText.launching("Tour") == "Launching Tour")
        #expect(WorkspaceSession.RunActivityText.configuringDebugger == "Configuring Debugger Actions")
        #expect(WorkspaceSession.RunActivityText.running("Tour", on: "iPhone 18 Pro") == "Running Tour on iPhone 18 Pro")
        #expect(WorkspaceSession.RunActivityText.finished("Tour", on: "iPhone 18 Pro") == "Finished running Tour on iPhone 18 Pro")
        #expect(DebugPresentation.runningTitle("Tour") == "Running Tour" && DebugPresentation.finishedTitle("Tour") == "Finished running Tour")
        for p: RemoteSimulator.Phase in [.booting, .launching(retries: 0), .launching(retries: 2)] {
            #expect(RemoteSimulator.status(p, app: "Tour", device: "iPhone Duo (SwiftCode)") == "Launching Tour")
        }
        #expect(RemoteSimulator.status(.running, app: "Tour", device: "iPhone Duo (SwiftCode)") == "Running Tour on iPhone Duo (SwiftCode)")
        #expect(WorkspaceSession.BuildActivityText.accepted(.test) == "Test" && WorkspaceSession.BuildActivityText.accepted(.analyze) == "Analyze")
        #expect(WorkspaceSession.BuildPresentation(action: .analyze, subject: "Tour").running == "Analyze")
        #expect(WorkspaceSession.BuildActivityText.isBuild("Analyze"))
    }

    func app(in root: URL, id: String = "dev.swiftcode.tour", exe: String = "Tour") throws -> URL {
        let app = root.appendingPathComponent("build/\(exe).app")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id, "CFBundleExecutable": exe], format: .xml, options: 0)
        try plist.write(to: app.appendingPathComponent("Info.plist"))
        try "binary".write(to: app.appendingPathComponent(exe), atomically: true, encoding: .utf8)
        return app
    }

    @Test func testProgressMovesForwardThroughTheTestTexts() {
        let p = TestActivityProgress(subject: "Calc")
        #expect(p.text == "Test")
        let lines = ["Building for debugging...", "[1/3] Compiling Calc Calc.swift", "[2/3] Compiling CalcTests CalcTests.swift",
                     "[3/3] Linking CalcPackageTests", "Build complete! (0.52s)", "Test Suite 'All tests' started at 2026-10-27",
                     "Test Case '-[CalcTests.CalcTests testAdds]' started.", "[9/9] not a build step any more"]
        let texts = lines.compactMap { p.feed($0) }
        #expect(texts == ["Building \u{2022} 0/3", "Building \u{2022} 1/3", "Building \u{2022} 2/3", "Configuring Debugger Actions", "Testing Calc"])
        #expect(p.phase == .testing)
        let x = TestActivityProgress(subject: "App")
        let xt = ["CompileSwift normal arm64 /p/A.swift", "Ld /p/App normal", "** TEST BUILD SUCCEEDED **", "Testing started",
                  "Test Suite 'All tests' started"].compactMap { x.feed($0) }
        #expect(xt == ["Building \u{2022} 0/1", "Building \u{2022} 1/2", "Configuring Debugger Actions", "Testing App"])
        let s = TestActivityProgress(subject: "Pkg")
        #expect(["\u{25C7} Test run started."].compactMap { s.feed($0) } == ["Testing Pkg"])
    }

    @Test func testFinishedTexts() {
        #expect(WorkspaceSession.testFinishedText(selected: true, passed: true) == "Test Completed")
        #expect(WorkspaceSession.testFinishedText(selected: true, passed: false) == "Test Completed")
        #expect(WorkspaceSession.testFinishedText(selected: false, passed: true) == "Test Succeeded")
        #expect(WorkspaceSession.testFinishedText(selected: false, passed: false) == "Test Failed")
    }
}
