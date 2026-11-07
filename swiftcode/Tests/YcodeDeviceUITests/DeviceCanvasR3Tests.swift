#if os(macOS)
import AppKit
import Testing
import YcodeDeviceModel
import YcodeDisplayStream
@testable import YcodeDeviceUI

@MainActor
@Suite(.serialized) struct DeviceCanvasR3Tests {
    let helper = DeviceWindowTests()

    func canvas() -> DeviceCanvasView {
        let c = DeviceCanvasView(mode: .hub)
        c.frame = NSRect(x: 0, y: 0, width: 820.5, height: 800)
        c.topInset = 52
        return c
    }

    @Test func capsulesHaveTheMeasuredSizesAndFloatAtTheBottom() {
        let c = canvas()
        let s = helper.session(type: "iphone-duo")
        c.show(session: s)
        helper.live(s, .iPhoneDuo, foldable: true)
        c.layoutSubtreeIfNeeded()
        let caps = c.controls.capsules
        #expect(caps.count == 2)
        #expect(caps.map(\.frame.width) == [108, 145.5] && caps.allSatisfy { $0.frame.height == 36.5 })
        let pair = c.controls.frame
        #expect(caps[1].frame.minX - caps[0].frame.maxX == 7.5)
        #expect(pair.maxY == 800 - 8 && pair.height == 36.5 && pair.width == 261)
        #expect(abs(pair.midX - c.bounds.midX) <= 0.5)
        let device = c.frameView.convert(c.frameView.bounds, to: c)
        #expect(abs(device.midY - (52 + pair.minY) / 2) <= 1 && abs(device.midX - c.bounds.midX) <= 1)
        #expect(device.maxY < pair.minY)
        s.close()
    }

    @Test func buttonsAreInTheSpecsOrderAndCarryTheirCommands() {
        let c = canvas()
        let s = helper.session(type: "iphone-duo")
        c.show(session: s)
        helper.live(s, .iPhoneDuo, foldable: true)
        c.layoutSubtreeIfNeeded()
        let order: [DeviceCommand] = [.home, .screenshot, .recordScreen, .rotateLeft, .poseClosed, .posePartiallyOpen, .poseOpen]
        #expect(c.controls.groups.flatMap { $0 } == order)
        let xs = order.compactMap { c.controls.button(for: $0) }.map { $0.convert($0.bounds, to: c).midX }
        #expect(xs.count == order.count && zip(xs, xs.dropFirst()).allSatisfy { $1 > $0 })
        let steps = zip(xs, xs.dropFirst()).map { $1 - $0 }
        #expect(steps == [34, 34, 7.5 + 20 + 20, 37.5, 34, 34])
        #expect(c.controls.highlightedPose == .poseClosed)
        var got: [DeviceCommand] = []
        c.commandFallback = { got.append($0); return true }
        s.connection(s.connection, status: DisplayStatus(phase: "booting", uptimeMilliseconds: 1000, guestFrames: 0))
        for cmd in order {
            let b = c.controls.button(for: cmd)!
            _ = b.sendAction(b.action, to: b.target)
        }
        #expect(got == order)
        s.close()
    }

    @Test func aWatchAndAVisionProHaveTheirOwnCapsules() {
        let c = canvas()
        let s = helper.session(type: "vision-pro")
        c.show(session: s)
        c.layoutSubtreeIfNeeded()
        #expect(c.controls.groups == [[.home, .screenshot, .recordScreen], [.resetCamera]])
        #expect(c.controls.capsules.map(\.frame.width) == [108, 40])
        s.close()
    }

    @Test func aStoppedDeviceHasNoLabelAndStartWhereTheControlsFloat() {
        let c = canvas()
        var started = false
        c.onAction = { started = true }
        c.showStopped(spec: .iPhone18Pro, name: "iPhone 18 Pro (SwiftCode)", os: "iOS 27.1", action: "Start")
        c.layoutSubtreeIfNeeded()
        let texts = Self.visibleTexts(in: c)
        #expect(!texts.contains { $0.contains("iPhone 18 Pro") || $0.contains("iOS 27.1") })
        #expect(texts == ["Start"], "\(texts)")
        let cap = c.statusActionCapsule.frame
        #expect(cap.maxY == 800 - 8 && cap.height == 36.5 && abs(cap.midX - c.bounds.midX) <= 0.5)
        let device = c.frameView.convert(c.frameView.bounds, to: c)
        #expect(abs(device.midY - (52 + (800 - 8 - 36.5)) / 2) <= 1)
        c.statusActionButton.performClick(nil)
        #expect(started)
        c.showStopped(spec: .iPhone18Pro, name: "iPhone 18 Pro (SwiftCode)", os: "iOS 27.1", action: nil, busy: true)
        c.layoutSubtreeIfNeeded()
        #expect(Self.visibleTexts(in: c) == ["Starting…"] && !c.statusActionCapsule.isHidden)
        c.showStopped(spec: .iPhone18Pro, name: "iPhone 17", os: "iOS 26.4", action: nil)
        c.layoutSubtreeIfNeeded()
        #expect(Self.visibleTexts(in: c).isEmpty && c.statusActionCapsule.isHidden)
    }

    static func visibleTexts(in v: NSView) -> [String] {
        var out: [String] = []
        func walk(_ v: NSView) {
            guard !v.isHidden else { return }
            if let t = v as? NSTextField, !t.stringValue.isEmpty { out.append(t.stringValue) }
            if let b = v as? NSButton {
                if !b.title.isEmpty { out.append(b.title) }
                return
            }
            v.subviews.forEach(walk)
        }
        walk(v)
        return out
    }
}
#endif
