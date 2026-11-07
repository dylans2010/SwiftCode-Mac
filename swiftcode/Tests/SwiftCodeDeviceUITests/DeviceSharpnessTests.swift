#if os(macOS)
import AppKit
import Testing
import SwiftCodeDeviceModel
@testable import SwiftCodeDeviceUI

@MainActor
struct DeviceSharpnessTests {
    @Test func oneToOneIsDetected() {
        #expect(DeviceView.showsPixelsOneToOne(image: CGSize(width: 1206, height: 2622), view: CGSize(width: 603, height: 1311), backing: 2))
        #expect(!DeviceView.showsPixelsOneToOne(image: CGSize(width: 1206, height: 2622), view: CGSize(width: 604, height: 1312), backing: 2))
        #expect(!DeviceView.showsPixelsOneToOne(image: CGSize(width: 1206, height: 2622), view: CGSize(width: 402, height: 874), backing: 2))
    }

    @Test func theScreenKeepsItsPixelSize() {
        let r = DeviceFrameView.pixelAligned(CGRect(x: 18.75, y: 18.75, width: 603, height: 1311), backing: 2)
        #expect(r == CGRect(x: 19, y: 19, width: 603, height: 1311))
        let odd = DeviceFrameView.pixelAligned(CGRect(x: 10.2, y: 3.3, width: 100.26, height: 50), backing: 2)
        #expect(odd.minX * 2 == (odd.minX * 2).rounded() && odd.width * 2 == (odd.width * 2).rounded())
    }

    @Test func aOneToOneScreenIsUnfiltered() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 1400), styleMask: [.borderless], backing: .buffered, defer: true)
        let frame = DeviceFrameView(geometry: DeviceFrameGeometry(spec: .iPhone18Pro))
        window.contentView?.addSubview(frame)
        let backing = window.backingScaleFactor
        frame.scale = 3 / backing
        frame.frame = CGRect(origin: CGPoint(x: 10, y: 10), size: frame.intrinsicContentSize)
        frame.layoutSubtreeIfNeeded()
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: nil, width: 1206, height: 2622, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
        frame.screen.image = ctx.makeImage()
        frame.screen.layoutSubtreeIfNeeded()
        #expect(frame.screen.bounds.width * backing == 1206 && frame.screen.bounds.height * backing == 2622)
        #expect(frame.screen.layer?.magnificationFilter == .nearest && frame.screen.layer?.minificationFilter == .nearest)
        frame.scale = 1
        frame.frame = CGRect(origin: CGPoint(x: 10, y: 10), size: frame.intrinsicContentSize)
        frame.layoutSubtreeIfNeeded()
        frame.screen.layoutSubtreeIfNeeded()
        #expect(frame.screen.layer?.magnificationFilter == .linear)
    }
}
#endif
