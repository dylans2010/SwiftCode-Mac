import Foundation
import Testing
import YcodeDeviceModel
import YcodeDisplayStream
@testable import YcodeRemoteViewer

struct WindowFitTests {
    struct Refused: Error {}

    func connected(_ spec: DeviceFrameSpec) -> RemoteDeviceSession {
        let s = RemoteDeviceSession(client: DisplayStreamClient(settings: DisplayClientHello(client: "t"), connect: { throw Refused() }))
        s.windowWidth = 460
        s.windowHeight = 900
        let p = spec.panels[0]
        var h = DisplayServerHello(deviceName: "SwiftCode", model: spec.modelIdentifier, pixelWidth: p.pixelWidth, pixelHeight: p.pixelHeight,
                                   scale: p.scale, encodings: ["jpeg"], touch: true, keyboard: true, buttons: ["home", "lock"], rotation: false)
        h.deviceType = spec.typeID
        s.post(.hello(h))
        s.drain()
        return s
    }

    @Test func noFitBeforeTheHello() {
        let s = RemoteDeviceSession(client: DisplayStreamClient(settings: DisplayClientHello(client: "t"), connect: { throw Refused() }))
        #expect(s.windowFitIfNeeded() == nil)
    }

    @Test func theWindowFitsTheDeviceOnConnectOnce() throws {
        let s = connected(.iPhoneDuo)
        let scale = s.layout.scale
        let size = try #require(s.windowFitIfNeeded())
        let g = s.geometry
        #expect(abs(size.width - (Double(g.size.width) * scale + 2 * ViewerLayout.margin)) < 1e-9)
        #expect(abs(size.height - (Double(g.size.height) * scale + 2 * ViewerLayout.margin + ViewerLayout.controlBar)) < 1e-9)
        #expect(ViewerLayout.controlBar == 36.5 + 8)
        #expect(size.width < 460 || size.height < 900)
        s.windowWidth = size.width
        s.windowHeight = size.height
        #expect(abs(s.layout.scale - scale) < 1e-9)
        #expect(s.windowFitIfNeeded() == nil)
        s.windowWidth = 700
        #expect(s.windowFitIfNeeded() == nil)
    }
}
