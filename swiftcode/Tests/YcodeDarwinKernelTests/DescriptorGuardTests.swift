import Foundation
import Testing
import YcodeDarwinABI
@testable import YcodeDarwinKernel

@Suite(.serialized) struct DescriptorGuardTests {
    @Test func guardedOpenOfADirectoryAndGetdirentries() throws {
        let e = try DEnv()
        try FileManager.default.createDirectory(atPath: e.writable + "/jobs", withIntermediateDirectories: true)
        try Data("x".utf8).write(to: URL(fileURLWithPath: e.writable + "/jobs/a.plist"))
        let p = DEnv.scratch + 0x100, g = DEnv.scratch + 0x200
        e.putString(e.writable + "/jobs", at: p)
        e.put(leBytes(0x1234_5678), at: g)
        let r = e.call(441, [p, g, 0xF, 0x0100_8000, 0])
        #expect(r.value != nil)
        let fd = r.fd
        #expect(e.call(92, [r.x0, 1, 0]).value == 1)
        let n = try #require(e.call(344, [r.x0, DEnv.scratch + 0x10000, 0x4000, DEnv.scratch + 0x300]).value)
        let bytes = e.get(DEnv.scratch + 0x10000, Int(n))
        #expect(String(decoding: bytes, as: UTF8.self).contains("a.plist"))
        #expect(e.call(6, [r.x0]).errno == 1)
        #expect(e.call(41, [r.x0]).errno == 1)
        #expect(e.call(92, [r.x0, 2, 0]).errno == 1)
        #expect(e.sink.lines.contains { $0.hasPrefix("guard exception: EXC_GUARD on fd \(fd)") })
        e.put(leBytes(1), at: g + 8)
        #expect(e.call(442, [r.x0, g + 8]).errno == 1)
        #expect(e.call(442, [r.x0, g]).value == 0)
        #expect(e.call(6, [r.x0]).errno == 9)
        #expect(e.call(441, [p, g, 0xF, 0x0000_8000, 0]).errno == 22)
        #expect(e.call(441, [p, g, 0x1, 0x0100_0000, 0]).errno == 22)
        #expect(e.call(441, [p, 0, 0x2, 0x0100_0000, 0]).errno == 14)
    }

    @Test func guardedWritesKqueueAndChange() throws {
        let e = try DEnv()
        let p = DEnv.scratch + 0x100, g = DEnv.scratch + 0x200
        e.putString(e.writable + "/log", at: p)
        e.put(leBytes(77), at: g)
        let r = e.call(441, [p, g, 0x12, 0x0100_0201, 0o644])
        #expect(r.value != nil)
        #expect(e.write(r.fd, "plain").errno == 1)
        e.put(Array("guarded".utf8), at: DEnv.scratch + 0x1000)
        #expect(e.call(485, [r.x0, g, DEnv.scratch + 0x1000, 7]).value == 7)
        #expect(e.call(486, [r.x0, g, DEnv.scratch + 0x1000, 1, 0]).value == 1)
        e.put(leBytes(DEnv.scratch + 0x1000) + leBytes(3), at: DEnv.scratch + 0x900)
        #expect(e.call(487, [r.x0, g, DEnv.scratch + 0x900, 1]).value == 3)
        e.put(leBytes(78), at: g + 8)
        #expect(e.call(485, [r.x0, g + 8, DEnv.scratch + 0x1000, 7]).errno == 1)
        #expect(e.call(485, [1, g, DEnv.scratch + 0x1000, 7]).errno == 22)
        #expect(try String(contentsOfFile: e.writable + "/log", encoding: .utf8) == "guardedgua")
        let (pr, _) = e.pipe()
        e.put([UInt8](repeating: 0, count: 4), at: DEnv.scratch + 0x300)
        #expect(e.call(444, [UInt64(pr), 0, 0, g, 0x6, DEnv.scratch + 0x300]).value == 0)
        #expect(e.u32(DEnv.scratch + 0x300) == 0)
        #expect(e.call(92, [UInt64(pr), 1, 0]).value == 1)
        e.put([UInt8](repeating: 0, count: 8), at: DEnv.scratch + 0x400)
        e.call(135, [1, 1, 0, DEnv.scratch + 0x400])
        let a = e.i32(DEnv.scratch + 0x400)
        let base = DEnv.scratch + 0x8000
        e.put(Array("x".utf8), at: base + 0x100)
        e.put(leBytes(base + 0x100) + leBytes(1), at: base + 0x80)
        var c: [UInt8] = []
        c.appendLE(UInt32(16)); c.appendLE(Int32(0xFFFF)); c.appendLE(Int32(1)); c.appendLE(pr)
        e.put(c, at: base + 0x200)
        var h = [UInt8](repeating: 0, count: 48)
        h.putLE(base + 0x80, at: 16); h.putLE(Int32(1), at: 24); h.putLE(base + 0x200, at: 32); h.putLE(UInt32(16), at: 40)
        e.put(h, at: base)
        #expect(e.call(28, [UInt64(a), base, 0]).errno == 1)
        #expect(e.call(444, [UInt64(pr), g, 0x6, 0, 0, 0]).value == 0)
        #expect(e.call(41, [UInt64(pr)]).value != nil)
        let k = e.call(443, [g, 0x3])
        #expect(k.value != nil)
        #expect(try e.kernel.fileSystem.guardState(of: k.fd)?.value == 77)
        #expect(e.call(6, [k.x0]).errno == 1)
        #expect(e.call(442, [k.x0, g]).value == 0)
        #expect(e.call(443, [g, 0x1]).errno == 22)
    }
}
