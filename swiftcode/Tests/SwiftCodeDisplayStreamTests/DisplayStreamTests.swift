import CSwiftCodeCodec
import Foundation
import Testing
@testable import SwiftCodeDisplayStream

struct DisplayStreamTests {
    static let hello = DisplayServerHello(deviceName: "SwiftCode", model: "iPhone19,4", pixelWidth: 1398, pixelHeight: 2034, scale: 3,
                                          encodings: ["jpeg", "zlib"], touch: true, keyboard: false, buttons: ["home", "lock"],
                                          rotation: false)

    static let samples: [DisplayMessage] = [
        .hello(hello),
        .status(DisplayStatus(phase: "booting", uptimeMilliseconds: 1234, guestFrames: 0, message: nil)),
        .frame(DisplayFrame(sequence: 7, guestFrame: 99, serverNanoseconds: 1 << 40, inputSequence: 3, width: 699, height: 1017,
                            encoding: .jpeg, isFull: true,
                            tiles: [DisplayTile(x: 0, y: 0, width: 699, height: 1017, data: [0xFF, 0xD8, 1, 2]),
                                    DisplayTile(x: 32, y: 64, width: 16, height: 16, data: [])])),
        .pong(token: 42, serverNanoseconds: 99),
        .screenshot(token: 5, png: [0x89, 0x50]),
        .notice("hello, viewer"),
        .clientHello(DisplayClientHello(client: "test", maxFPS: 30, encoding: "zlib", quality: 60, downscale: 2)),
        .input(.touch(sequence: 1, contacts: [TouchContact(finger: 0, phase: .began, x: 10.5, y: 20.25),
                                              TouchContact(finger: 1, phase: .moved, x: 400, y: 600)])),
        .input(.key(sequence: 2, down: true, usagePage: 7, usage: 0x04)),
        .input(.button(sequence: 3, button: .home, down: false)),
        .ping(token: 0xDEAD_BEEF),
        .keyframeRequest,
        .screenshotRequest(token: 9),
        .rotate(orientation: 3),
        .frameTiming(DisplayFrameTiming(sequence: 7, recordSeen: 1, captureStart: 2, encodeEnd: 3, sendEnd: 1 << 40)),
        .audio(DisplayAudio(playTime: 123_456_789, codec: .opus, frames: 240, data: [1, 2, 3])),
        .audio(DisplayAudio(playTime: 9, codec: .pcm16, channels: 2, frames: 2, sampleRate: 48000, data: [0, 1, 2, 3, 4, 5, 6, 7])),
        .frame(DisplayFrame(sequence: 8, guestFrame: 100, serverNanoseconds: 5, inputSequence: 0, width: 1206, height: 2622,
                            encoding: .h264, isFull: true, tiles: [DisplayTile(x: 0, y: 0, width: 1206, height: 2622, data: [0, 0, 0, 1, 0x67])])),
    ]

    @Test func roundTrip() throws {
        for m in Self.samples {
            let bytes = m.encoded()
            let n = Int(bytes[0]) | Int(bytes[1]) << 8 | Int(bytes[2]) << 16 | Int(bytes[3]) << 24
            #expect(n == bytes.count - 4)
            #expect(bytes[4] == m.type.rawValue)
            let back = try DisplayMessage.decode(type: bytes[4], payload: bytes[5...])
            #expect(back == m)
        }
    }

    @Test func helloPoints() {
        #expect(Self.hello.pointWidth == 466 && Self.hello.pointHeight == 678)
    }

    @Test func parserSplitsAndSkipsUnknown() throws {
        var stream: [UInt8] = []
        for m in Self.samples { stream += m.encoded() }
        stream.insert(contentsOf: [3, 0, 0, 0, 0x7E, 1, 2], at: Self.samples[0].encoded().count)
        var parser = DisplayMessageParser()
        var out: [DisplayMessage] = []
        for b in stream {
            parser.append([b])
            while let m = try parser.next() { out.append(m) }
        }
        #expect(out == Self.samples)
    }

    @Test func parserRejectsHugeLength() {
        var parser = DisplayMessageParser()
        parser.append([0xFF, 0xFF, 0xFF, 0x7F, 1])
        #expect(throws: DisplayStreamError.self) { _ = try parser.next() }
    }

    @Test func truncatedFrame() {
        let bytes = DisplayMessage.frame(DisplayFrame(sequence: 1, guestFrame: 1, serverNanoseconds: 1, inputSequence: 0, width: 4,
                                                      height: 4, encoding: .zlibBGRA, isFull: false,
                                                      tiles: [DisplayTile(x: 0, y: 0, width: 4, height: 4, data: [1, 2, 3])])).encoded()
        #expect(throws: DisplayStreamError.self) { _ = try DisplayMessage.decode(type: bytes[4], payload: bytes[5..<(bytes.count - 1)]) }
    }

    @Test func addresses() {
        #expect(DisplayAddress("unix:/tmp/x.sock") == .unix("/tmp/x.sock"))
        #expect(DisplayAddress("/tmp/x.sock") == .unix("/tmp/x.sock"))
        #expect(DisplayAddress("4711") == .tcp(host: "127.0.0.1", port: 4711))
        #expect(DisplayAddress("0.0.0.0:80") == .tcp(host: "0.0.0.0", port: 80))
        #expect(DisplayAddress(":81") == .tcp(host: "127.0.0.1", port: 81))
        #expect(DisplayAddress("unix:") == nil)
        #expect(DisplayAddress("nonsense") == nil)
    }

    @Test func unixSocketLoopback() throws {
        let path = NSTemporaryDirectory() + "swiftcode-ds-\(getpid()).sock"
        let listener = try DisplayListener(address: .unix(path))
        defer { listener.close() }
        #expect(throws: DisplaySocketError.self) { _ = try DisplayListener(address: .unix(path)) }
        let accepted = Thread {
            for _ in 0..<2 {
                guard let c = listener.accept() else { break }
                try? c.send(DisplayStreamTests.samples[0])
                Thread.sleep(forTimeInterval: 0.2)
                c.close()
            }
        }
        accepted.start()
        let client = try DisplayConnection.connect(to: .unix(path))
        var parser = DisplayMessageParser()
        var got: DisplayMessage?
        while got == nil, let bytes = client.receive() {
            parser.append(bytes)
            got = try parser.next()
        }
        #expect(got == Self.samples[0])
        client.close()
    }

    @Test func zlibAndDownscale() throws {
        guard swiftcodec_zlib_available() != 0 else { return }
        let input = [UInt8](repeating: 7, count: 10_000)
        var cap = swiftcodec_zlib_bound(input.count)
        var out = [UInt8](repeating: 0, count: cap)
        let r = out.withUnsafeMutableBufferPointer { swiftcodec_zlib_compress(input, input.count, 6, $0.baseAddress, &cap) }
        #expect(r == 0 && cap < 200 && out[0] == 0x78)
        var src = [UInt8](repeating: 0, count: 3 * 3 * 4)
        for i in 0..<9 { src[i * 4] = UInt8(i * 10) }
        var dst = [UInt8](repeating: 0, count: 2 * 2 * 4)
        swiftcodec_downscale_bgra(src, 12, 3, 3, 2, &dst, 8)
        #expect(dst[0] == 20)
        #expect(dst[4] == 35)
        #expect(dst[8] == 65)
        #expect(dst[12] == 80)
    }

    @Test func jpegWhenAvailable() {
        guard swiftcodec_jpeg_available() != 0 else { return }
        let w = 64, h = 48
        var px = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) { px[i * 4 + 2] = UInt8(i % 256) }
        var out: UnsafeMutablePointer<UInt8>?
        var size = 0
        #expect(swiftcodec_jpeg_encode_bgra(px, Int32(w), Int32(h), w * 4, 80, &out, &size) == 0)
        #expect(size > 100 && out?[0] == 0xFF && out?[1] == 0xD8)
        swiftcodec_free(out)
    }
}

struct DisplayStreamFoldTests {
    func roundTrip(_ m: DisplayMessage) throws -> DisplayMessage? {
        var p = DisplayMessageParser()
        p.append(m.encoded())
        return try p.next()
    }

    @Test func messages() throws {
        let st = DisplayPanelState(display: "LCD-1", pixelWidth: 2007, pixelHeight: 2853, scale: 3, rotation: 90, hingeAngle: 180,
                                   targetAngle: nil, posture: "openFlat", orientation: "portrait")
        #expect(try roundTrip(.displayState(st)) == .displayState(st))
        #expect(try roundTrip(.fold(angle: 90, instant: false)) == .fold(angle: 90, instant: false))
        #expect(try roundTrip(.fold(angle: 180, instant: true)) == .fold(angle: 180, instant: true))
        #expect(DisplayMessage.fold(angle: 1, instant: false).encoded() == [4, 0, 0, 0, 0x89, 1, 0, 0])
        #expect(try roundTrip(.command(token: 7, text: "ui appearance dark")) == .command(token: 7, text: "ui appearance dark"))
        #expect(try roundTrip(.commandReply(token: 7, text: "ok\nline")) == .commandReply(token: 7, text: "ok\nline"))
        #expect(DisplayMessage.command(token: 1, text: "a").encoded() == [6, 0, 0, 0, 0x90, 1, 0, 0, 0, 0x61])
        #expect(DisplayMessage.commandReply(token: 2, text: "").encoded() == [5, 0, 0, 0, 0x10, 2, 0, 0, 0])
        let old = #"{"buttons":[],"deviceName":"SwiftCode","encodings":["jpeg"],"keyboard":true,"model":"iPhone19,4","orientation":"portrait","pixelHeight":2034,"pixelWidth":1398,"pointHeight":678,"pointWidth":466,"protocol":"swiftcode-display/1","rotation":false,"scale":3,"touch":true}"#
        let h = try JSONDecoder().decode(DisplayServerHello.self, from: Data(old.utf8))
        #expect(h.foldable == nil && h.displays == nil)
    }

    @Test func turnedPanelTouches() {
        var st = DisplayPanelState(display: "LCD-1", pixelWidth: 2007, pixelHeight: 2853, scale: 3, rotation: 90, hingeAngle: 180,
                                   targetAngle: nil, posture: "openFlat", orientation: "portrait")
        #expect(st.shownPointSize.width == 951 && st.shownPointSize.height == 669)
        #expect(st.nativePoint(shownX: 0, shownY: 0) == (0, 951))
        #expect(st.nativePoint(shownX: 951, shownY: 669) == (669, 0))
        st.rotation = 270
        #expect(st.nativePoint(shownX: 0, shownY: 0) == (669, 0))
        st.rotation = 180
        #expect(st.nativePoint(shownX: 0, shownY: 0) == (669, 951))
        st.rotation = 0
        #expect(st.nativePoint(shownX: 5, shownY: 6) == (5, 6))
    }
}
