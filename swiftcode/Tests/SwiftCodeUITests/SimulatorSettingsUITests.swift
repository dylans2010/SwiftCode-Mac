import AppKit
import Foundation
import Testing
@testable import SwiftCodeIDECore
import SwiftCodeSimFeatures
@testable import SwiftCodeUI

@MainActor
@Suite(.serialized) struct SimulatorSettingsUITests {
    static let reply = """
        ok appearance dark
        liquid-glass 0.40 tinted
        content-size extra-large
        larger-accessibility-sizes off
        color-filter deuteranopia 0.50
        reduce-motion on
        increase-contrast off
        show-borders on
        reduce-transparency off
        voiceover off
        voiceover-running no
        volume 35
        output none
        input system
        agent pid 109
        changes 3
        """

    func row(booted: Bool) -> DeviceRow {
        DeviceRow(name: "iPhone Duo (SwiftCode)", identifier: "h:/data/swiftcode/devices/swiftcode-device", platform: "iOS", osVersion: "27.1",
                  state: booted ? "Booted" : "Shutdown", model: "SwiftCode Simulator (Linux)", isAvailable: true,
                  isSwiftCodeRemote: true, isFoldable: false)
    }

    @Test func boxesOfARunningDevice() async {
        let c = DevicesController(devices: [], simulators: [row(booted: true)])
        var sent: [[String]] = []
        var failures: [(String, String)] = []
        c.presentSettingsFailure = { failures.append(($0, $1)) }
        c.deviceSettings = { _, words in
            sent.append(words)
            if words == ["settings"] { return (true, Self.reply) }
            if words.first == "location" { return (false, "error: the device's settings agent is not connected") }
            return (true, "ok")
        }
        c.show(.simulators)
        c.select(row: 0)
        await c.settingsTask?.value
        #expect(sent == [["settings"]] && c.settingsSnapshot?.state.appearance == .dark)
        #expect(c.settingsControlsShown && c.settingsControlsEnabled)
        let boxes = c.settingsControls()
        #expect(boxes.identifier?.rawValue == "settings-controls")
        let cards = (boxes as? NSStackView)?.arrangedSubviews.compactMap { $0 as? InspectorCard } ?? []
        #expect(cards.map(\.rows.count) == [9, 1, 3])
        let heights: [CGFloat] = cards.map(\.frame.height)
        let expected: [CGFloat] = [386, 42, 128]
        #expect(heights == expected)
        let controls: [NSControl] = cards.flatMap(\.rows).compactMap { $0.control as? NSControl }
        #expect(controls.count == 13 && controls.allSatisfy(\.isEnabled))
        #expect(DevicesController.stoppedNote(in: boxes) == nil)
        await c.applySetting(["ui", "appearance", "light"], failureTitle: "Failed to Set Appearance")?.value
        #expect(sent.suffix(2) == [["ui", "appearance", "light"], ["settings"]] && failures.isEmpty)
        let sw = NSSwitch()
        sw.tag = AccessibilitySwitch.allCases.firstIndex(of: .voiceOver)!
        sw.state = .on
        c.accessibilitySwitched(sw)
        await c.settingsTask?.value
        #expect(sent.suffix(2).first == ["accessibility", "voiceover", "on"])
        let slider = NSSlider()
        slider.minValue = 0
        slider.maxValue = 11
        slider.integerValue = 11
        c.textSizeMoved(slider)
        await c.settingsTask?.value
        #expect(sent.suffix(2).first == ["ui", "content_size", "accessibility-extra-extra-extra-large"])
        let popup = NSPopUpButton()
        for choice in DevicesController.locationChoices where choice.title != "-" {
            let item = NSMenuItem(title: choice.title, action: nil, keyEquivalent: "")
            item.representedObject = choice.words
            popup.menu?.addItem(item)
        }
        popup.selectItem(withTitle: "Tokyo, Japan")
        c.locationChosen(popup)
        await c.settingsTask?.value
        #expect(sent.suffix(2).first == ["location", "set", "35.6762,139.6503"])
        #expect(failures.count == 1 && failures[0].0 == "Failed to Set Location" && failures[0].1 == "the device's settings agent is not connected")
        #expect(c.chosenLocations[row(booted: true).identifier] == "Tokyo, Japan")
    }

    @Test func aStoppedDeviceShowsTheMessage() {
        let c = DevicesController(devices: [], simulators: [row(booted: false)])
        c.deviceSettings = { _, _ in (true, "ok") }
        c.show(.simulators)
        #expect(c.settingsControlsShown && !c.settingsControlsEnabled && c.settingsTask == nil)
        let v = c.settingsControls()
        #expect(DevicesController.stoppedNote(in: v)?.stringValue == DevicesController.settingsStoppedMessage)
        let cards = (v as? NSStackView)?.arrangedSubviews.compactMap { $0 as? InspectorCard } ?? []
        let controls: [NSControl] = cards.flatMap(\.rows).compactMap { $0.control as? NSControl }
        #expect(cards.count == 3 && controls.count == 13 && !controls.contains(where: \.isEnabled))
        #expect(c.applySetting(["ui", "appearance", "dark"], failureTitle: "x") == nil)
    }

    @Test func locationChoicesFollowTheReference() {
        let titles = DevicesController.locationChoices.map(\.title)
        #expect(titles.first == "None" && titles.contains("Cupertino, CA, USA") && titles.last == "Custom Coordinates…")
        #expect(titles.firstIndex(of: "Trips")! < titles.firstIndex(of: "City Run")! && titles.firstIndex(of: "Freeway Drive")! < titles.firstIndex(of: "Apple")!)
        #expect(DevicesController.locationChoices.first { $0.title == "City Bicycle Ride" }?.words == ["run", "City Bicycle Ride"])
    }

    @Test func environmentOverridesGoToTheRunningApp() async {
        let d = DebugAreaController()
        var runKey: String? = "dev.x#10"
        var sent: [EnvironmentOverrides] = []
        d.simulatorRunKey = { runKey }
        d.applyEnvironmentOverrides = { o in sent.append(o); return (true, "ok") }
        d.syncWithRun()
        let panel = EnvironmentOverridesController(debugArea: d)
        await panel.set(.init(appearance: .dark, dynamicType: .small, accessibility: [.reduceMotion: true]))?.value
        #expect(sent.last?.values[.appearance] == "dark" && sent.last?.values[.dynamicType] == "small")
        #expect(sent.last?.values[.reduceMotion] == "on" && sent.last?.values[.grayscale] == "off")
        #expect(d.environmentOverrides == sent.last && panel.status == "Applied to the running app")
        #expect(panel.appearanceSwitch.state == .on && panel.appearanceControl.selectedSegment == 1)
        #expect(panel.checks[.reduceMotion]?.state == .on && panel.typeLabel.stringValue == "Small")
        await panel.set(.init())?.value
        #expect(sent.last?.isEmpty == true && sent.last?.commandWords(bundleID: "dev.x") == ["overrides", "dev.x", "clear"])
        d.environmentOverrides = EnvironmentOverrides(values: [.boldText: "on"])
        runKey = "dev.x#11"
        d.syncWithRun()
        #expect(d.environmentOverrides.isEmpty)
    }

    @Test func simulateLocationMenu() async {
        let d = DebugAreaController()
        #expect(d.simulateLocationMenu().items.last?.title == "Location simulation needs a run on the SwiftCode simulator")
        var words: [[String]] = []
        d.simulatorRunKey = { "dev.x#1" }
        d.simulateLocationHandler = { w in words.append(w); return (true, "ok") }
        let menu = d.simulateLocationMenu()
        #expect(menu.items.first?.title == "Don't Simulate Location" && menu.items.first?.state == .on)
        let paris = menu.items.first { $0.title == "Paris, France" }!
        #expect(paris.isEnabled)
        d.simulatedLocationChosen(paris)
        for _ in 0..<50 where words.isEmpty { await Task.yield(); try? await Task.sleep(nanoseconds: 10_000_000) }
        #expect(words == [["set", "48.8566,2.3522"]] && d.simulatedLocation == "Paris, France")
        #expect(d.simulateLocationMenu().items.first { $0.title == "Paris, France" }?.state == .on)
        #expect(menu.items.contains { $0.title == "City Run" })
    }
}
