import Foundation
import Testing
import YcodeDarwinABI
@testable import YcodeDarwinKernel

@Suite struct SystemControlTests {
    let s = Env.scratch + 0x1000

    @Test func threadGetStateOfTheCaller() throws {
        let env = try Env()
        var f = TrapFrame()
        f.x[20] = 0x2020
        f.elr = 0x1_0000_4444
        f.spEL0 = 0x16FD_F000
        try env.put(le32(68), at: s + 0x400)
        env.svc(0x7963_2011, [UInt64(WellKnownPort.thread), 6, s, s + 0x400], frame: &f)
        #expect(f.x[0] == 0)
        let st = try env.space.read(va: s, count: 272)
        #expect(st.readLE(UInt64.self, at: 0) == UInt64(WellKnownPort.thread))
        #expect(st.readLE(UInt64.self, at: 8 * 20) == 0x2020)
        #expect(st.readLE(UInt64.self, at: 248) == 0x16FD_F000 && st.readLE(UInt64.self, at: 256) == 0x1_0000_4444)
        #expect(try env.u32(s + 0x400) == 68)
        try env.put(le32(10), at: s + 0x400)
        #expect(env.svc(0x7963_2011, [UInt64(WellKnownPort.thread), 6, s, s + 0x400]).1.x[0] == 4)
        try env.put(le32(200), at: s + 0x400)
        #expect(env.svc(0x7963_2011, [UInt64(WellKnownPort.thread), 17, s, s + 0x400]).1.x[0] == 4)
        #expect(env.svc(0x7963_2011, [UInt64(WellKnownPort.task), 6, s, s + 0x400]).1.x[0] == 4)
        #expect(env.svc(0x7963_2011, [UInt64(WellKnownPort.thread), 1, s, s + 0x400]).1.x[0] == 0)
        #expect(try env.u32(s) == 6 && env.u32(s + 4) == 68 && env.u32(s + 0x400) == 70)
    }

    @Test func threadExceptionPorts() throws {
        let env = try Env()
        let thread = UInt64(WellKnownPort.thread), task = UInt64(WellKnownPort.task)
        let get: UInt64 = 0x7963_2012, set: UInt64 = 0x7963_2013
        func getAll() -> UInt64 {
            try? env.put(le32(14), at: s + 0x100)
            return env.svc(get, [thread, 0x3FFE, s, s + 0x100, s + 0x200, s + 0x300, s + 0x400]).1.x[0]
        }
        #expect(getAll() == 0)
        #expect(try env.u32(s + 0x100) == 0)
        #expect(env.svc(set, [thread, 0x6, task, 1, 6]).1.x[0] == 0)
        #expect(getAll() == 0)
        #expect(try env.u32(s + 0x100) == 2)
        #expect(try env.u32(s) == 0x6 && env.u32(s + 4) == 0x3FF8)
        #expect(try env.u32(s + 0x200) != 0 && env.u32(s + 0x204) == 0)
        #expect(try env.u32(s + 0x300) == 1 && env.u32(s + 0x400) == 6)
        #expect(env.svc(set, [thread, 0x2, task, 99, 6]).1.x[0] == 4)
        #expect(env.svc(set, [thread, 0x1, task, 1, 6]).1.x[0] == 4)
        #expect(env.svc(set, [task, 0x2, task, 1, 6]).1.x[0] == 4)
    }

    @Test func vmReadCopiesIntoNewMemory() throws {
        let env = try Env()
        let task = UInt64(WellKnownPort.task)
        try env.put([9, 8, 7, 6, 5], at: s + 0x123)
        #expect(env.svc(0x7963_2014, [task, s + 0x123, 5, s + 0x800, s + 0x808]).1.x[0] == 0)
        let data = try env.u64(s + 0x800)
        #expect(data & 0x3FFF == (s + 0x123) & 0x3FFF && data != s + 0x123)
        #expect(try env.space.read(va: data, count: 5) == [9, 8, 7, 6, 5])
        #expect(try env.u32(s + 0x808) == 5)
        #expect(env.svc(0x7963_2014, [task, 0x10, 5, s + 0x800, s + 0x808]).1.x[0] == 1)
        #expect(env.svc(0x7963_2014, [UInt64(WellKnownPort.thread), s, 5, s + 0x800, s + 0x808]).1.x[0] == 4)
    }

    @Test func vmRegionDescribesMappings() throws {
        let env = try Env()
        let task = UInt64(WellKnownPort.task)
        let call: UInt64 = 0x7963_2015
        try env.space.write(va: s, bytes: le64(s + 0x10))
        try env.space.write(va: s + 0x10, bytes: le32(9))
        #expect(env.svc(call, [task, s, s + 0x8, 9, s + 0x100, s + 0x10, s + 0x18]).1.x[0] == 0)
        #expect(try env.u64(s) == Env.scratch && env.u64(s + 0x8) >= Env.scratchSize)
        #expect(try env.u32(s + 0x100) == 3 && env.u32(s + 0x10) == 9)
        try env.space.write(va: s, bytes: le64(s))
        try env.space.write(va: s + 0x10, bytes: le32(9))
        #expect(env.svc(call, [task, s, s + 0x8, 13, s + 0x100, s + 0x10, 0]).1.x[0] == 0)
        #expect(try env.space.read(va: s + 0x100 + 31, count: 1) == [2])
        try env.space.write(va: s + 0x10, bytes: le32(4))
        #expect(env.svc(call, [task, s, s + 0x8, 9, s + 0x100, s + 0x10, 0]).1.x[0] == 4)
        try env.space.write(va: s + 0x10, bytes: le32(20))
        #expect(env.svc(call, [task, s, s + 0x8, 99, s + 0x100, s + 0x10, 0]).1.x[0] == 4)
        try env.space.write(va: s, bytes: le64(0x7FFF_0000_0000))
        #expect(env.svc(call, [task, s, s + 0x8, 9, s + 0x100, s + 0x10, 0]).1.x[0] == 1)
    }

    @Test func controlsAnsweredAsOnTheMac() throws {
        let env = try Env()
        #expect(env.svc(440, [1, 100, 0, 0, 0]).1.x[0] == 1)
        #expect(env.svc(440, [18, 100, 0, 0, 0]).1.x[0] == 22)
        #expect(env.svc(165, [s, 0x300, 501, 0]).1.x[0] == 45)
        #expect(env.svc(89, []).1.x[0] == 256)
        try env.put(le32(1) + le32(3) + le32(1), at: s + 0x600)
        #expect(!env.svc(322, [0, s + 0x600]).1.carry)
        try env.put(le32(1) + le32(3) + le32(0), at: s + 0x600)
        #expect(!env.svc(322, [1, s + 0x600]).1.carry)
        #expect(try env.u32(s + 0x608) == 1)
        try env.put(le32(0) + le32(3) + le32(7), at: s + 0x600)
        #expect(!env.svc(322, [1, s + 0x600]).1.carry)
        #expect(try env.u32(s + 0x608) == 0)
        try env.put(le32(5) + le32(3) + le32(0), at: s + 0x600)
        #expect(env.svc(322, [1, s + 0x600]).1.x[0] == 22)
        try env.put(le32(0x10), at: s)
        #expect(env.svc(483, [0, s, 4]).1.x[0] == 1)
        try env.put(le32(0xFFFF), at: s)
        #expect(!env.svc(483, [1, s, 4]).1.carry)
        #expect(try env.u32(s) == 0)
        try env.put(le32(1), at: s + 8)
        #expect(env.svc(494, [6, 0, s + 0x100, s, s + 8, 0]).1.x[0] == 3)
        #expect(env.svc(494, [1, 0, s + 0x100, s, s + 8, 0]).1.x[0] == 1)
        #expect(!env.svc(494, [7, 0, s + 0x100, s, s + 8, 0]).1.carry)
        #expect(try env.u64(s + 8) == 0)
        #expect(!env.svc(75, [Env.scratch, 0x4000, 3]).1.carry)
        #expect(env.svc(75, [Env.scratch, 0x4000, 99]).1.x[0] == 22)
        try env.put([1, 2, 3, 4], at: s + 0x800)
        #expect(!env.svc(75, [s + 0x800, 4, 11]).1.carry)
        #expect(try env.space.read(va: s + 0x800, count: 4) == [0, 0, 0, 0])
    }

    @Test func auditTokenOfAnotherTask() throws {
        let env = try ProcEnv()
        let k = env.rootKernel!
        let at = ProcEnv.At.out
        let pid = env.spawn(from: k).pid
        _ = env.svc(k, UInt64(bitPattern: -44), [UInt64(WellKnownPort.task), UInt64(pid), at])
        let name = env.u32(k, at)
        #expect(name != 0)
        env.put(k, le32(8), at: at + 0x40)
        let r = env.svc(k, 0x7963_0006, [UInt64(name), 15, at + 0x100, at + 0x40]).1
        #expect(r.x[0] == 0)
        let token = env.read(k, at + 0x100, 32)
        #expect(Int32(bitPattern: token.readLE(UInt32.self, at: 20)) == pid)
        #expect(env.svc(k, 0x7963_0006, [UInt64(WellKnownPort.host), 15, at + 0x100, at + 0x40]).1.x[0] == 4)
    }

    @Test func setAttributeList() throws {
        let env = try ProcEnv()
        let k = env.rootKernel!
        let at = ProcEnv.At.out
        let file = env.root + "/f"
        try Data("x".utf8).write(to: URL(fileURLWithPath: file))
        env.putString(k, file, at: at)
        var alist = [UInt8](repeating: 0, count: 24)
        alist.putLE(UInt16(5), at: 0)
        alist.putLE(UInt32(0x400 | 0x4000 | 0x20000), at: 4)
        env.put(k, alist, at: at + 0x200)
        var buf: [UInt8] = []
        buf.appendLE(Int64(3_000_000)); buf.appendLE(Int64(0))
        var finder = [UInt8](repeating: 0, count: 32)
        finder[0] = 0x54
        buf += finder
        buf.appendLE(UInt32(0o600))
        env.put(k, buf, at: at + 0x300)
        #expect(env.bsd(k, 221, [at, at + 0x200, at + 0x300, UInt64(buf.count), 0]) == 0)
        let attrs = try FileManager.default.attributesOfItem(atPath: file)
        #expect(Int((attrs[.modificationDate] as! Date).timeIntervalSince1970) == 3_000_000)
        #expect((attrs[.posixPermissions] as! Int) == 0o600)
        alist.putLE(UInt32(0x4000), at: 4)
        env.put(k, alist, at: at + 0x200)
        #expect(env.bsd(k, 220, [at, at + 0x200, at + 0x400, 64, 0]) == 0)
        #expect(env.read(k, at + 0x404, 1) == [0x54])
        alist.putLE(UInt32(0x1), at: 4)
        env.put(k, alist, at: at + 0x200)
        #expect(env.bsd(k, 221, [at, at + 0x200, at + 0x300, 64, 0]) == -22)
        alist.putLE(UInt32(0), at: 4)
        alist.putLE(UInt32(0x8000_2000), at: 8)
        env.put(k, alist, at: at + 0x200)
        #expect(env.bsd(k, 221, [at, at + 0x200, at + 0x300, 64, 0]) == -30)
        alist.putLE(UInt32(0x400), at: 4)
        alist.putLE(UInt32(0), at: 8)
        env.put(k, alist, at: at + 0x200)
        #expect(env.bsd(k, 221, [at, at + 0x200, at + 0x300, 8, 0]) == -22)
    }
}
