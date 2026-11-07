import Foundation
import Testing
import SwiftCodeDisplayStream
@testable import SwiftCodeRemoteViewer

struct DeviceWindowNoticeTests {
    struct Refused: Error {}

    @Test func aNoticeShowsThenGoes() {
        let session = RemoteDeviceSession(client: DisplayStreamClient(settings: DisplayClientHello(client: "t"), connect: { throw Refused() }))
        let t = viewerNanoseconds() + 1_000_000_000
        session.showNotice("Screenshot Saved to Desktop", now: t)
        #expect(session.notice?.text == "Screenshot Saved to Desktop")
        session.tick(now: t + 1_500_000_000)
        #expect(session.notice != nil)
        session.tick(now: t + 2_100_000_000)
        #expect(session.notice == nil)
    }
}

extension DeviceWindowNoticeTests {
    @Test func startingUntilTheScreenLights() {
        let session = RemoteDeviceSession(client: DisplayStreamClient(settings: DisplayClientHello(client: "t"), connect: { throw Refused() }))
        let t: UInt64 = 1_000_000_000_000
        #expect(session.startingText(now: t) == nil)
        session.noteStarted(uptimeMilliseconds: 4_000, now: t)
        #expect(session.startingText(now: t + 56_000_000_000) == "Starting... 60 s")
        session.noteScreen(lit: false)
        #expect(session.startingText(now: t + 116_000_000_000) == "Starting... 120 s")
        session.noteScreen(lit: true)
        session.noteScreen(lit: false)
        #expect(session.startingText(now: t + 120_000_000_000) == nil)
    }
}
