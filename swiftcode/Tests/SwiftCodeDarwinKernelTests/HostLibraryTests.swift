import Foundation
import Testing
import SwiftCodeDarwinABI
@testable import SwiftCodeDarwinKernel

@Suite struct HostLibraryTests {
    @Test func mainThreadBlockLayout() {
        let base: UInt64 = 0x3_1001_0000
        let block = MainThreadBlock(address: base)
        let b = block.bytes
        #expect(b.count == 8192 && MainThreadBlock.byteCount >= 6368)
        #expect(block.tsdBase == base + 224)
        #expect(u64(b, 216) == 1)
        #expect(u64(b, 224) == base)
        #expect(u64(b, 232) == base + 172)
        #expect(u64(b, 248) == 0x203)
        #expect(u64(b, 256) == 0x8FF)
        #expect(u64(b, 280) == 0)
        #expect(u64(b, 224 - 48) == 0x1_6FE0_0000)
        #expect(u64(b, 224 - 40) == 0x1_6FE0_0000 - (8 << 20))
        let set: Set<Int> = [176, 184, 216, 224, 232, 248, 256]
        for o in stride(from: 0, to: b.count, by: 8) where !set.contains(o) {
            #expect(u64(b, o) == 0, "offset \(o)")
        }
        #expect(Stage3Layout.mainThreadPage % 16 == 0)
        #expect(Stage3Layout.mainThreadPage >= HostPageLayout.base + HostPageLayout.size)
        #expect(Stage3Layout.mainThreadPage + Stage3Layout.mainThreadPageSize <= Stage3Layout.anonymousBase)
        let other = MainThreadBlock(address: 0x1000, threadID: 7, threadPort: 0x1203, stackTop: 0x9000, stackSize: 0x1000)
        #expect(u64(other.bytes, 216) == 7 && u64(other.bytes, 248) == 0x1203 && u64(other.bytes, 184) == 0x8000)
        let munged = MainThreadBlock(address: base, qos: 0x15FF, ptrMunge: 0xABCD_1234)
        #expect(u64(munged.bytes, 256) == 0x15FF && u64(munged.bytes, 280) == 0xABCD_1234)
    }

    @Test func unimplementedLibraryFunctionTrap() throws {
        let env = try Env()
        try env.putString("_mach_port_request_notification", at: Env.scratch)
        var f = TrapFrame()
        f.x[1] = 0x55
        let o = env.svc(0x7963_0F00, [Env.scratch], frame: &f)
        #expect(o == .unimplementedLibraryFunction(name: "_mach_port_request_notification"))
        #expect(f.x[0] == Env.scratch && f.x[1] == 0x55)
        #expect(env.sink.lines.contains("trap yc 0xf00 unimplemented libfunc _mach_port_request_notification"))
        #expect(DarwinKernel.unimplementedLibraryFunctionExitStatus == 73)
        let (o2, _) = env.svc(0x7963_0F00, [0x10])
        guard case let .unimplementedLibraryFunction(name) = o2 else { Issue.record("expected libfunc"); return }
        #expect(name.contains("unreadable"))
    }

    @Test func bsdthreadRegister() throws {
        let env = try Env()
        let rec = Env.scratch + 0x100
        var r = [UInt8](repeating: 0xAA, count: 56)
        r.putLE(UInt64(56), at: 0)
        r.putLE(UInt64(160), at: 8)
        r.putLE(UInt32(224), at: 24)
        r.putLE(UInt32(40), at: 28)
        r.putLE(UInt32(24), at: 32)
        r.putLE(UInt32(392), at: 48)
        r.putLE(UInt32(960), at: 52)
        try env.put(r, at: rec)
        let (o, f) = env.svc(366, [0x2_0000_1000, 0x2_0000_2000, 16384, rec, 56, 160])
        #expect(o == .resume)
        #expect(!f.carry && f.x[0] == 0x4000_00DF)
        #expect(f.x[0] & 0x4000_001E == 0x4000_001E)
        let back = try env.space.read(va: rec, count: 56)
        #expect(u64(back, 0) == 56)
        #expect(u64(back, 16) == 0x8FF)
        #expect(u64(back, 36) == 0x1_6FE0_0000)
        #expect(u32(back, 44) == 0)
        #expect(u32(back, 24) == 224 && u32(back, 52) == 960)
        let reg = try #require(env.kernel.threadRegistration)
        #expect(reg.threadStart == 0x2_0000_1000 && reg.startWorkqueueThread == 0x2_0000_2000)
        #expect(reg.pthreadSize == 16384 && reg.tsdOffset == 224 && reg.dispatchQueueOffset == 160)
        #expect(reg.returnToKernelOffset == 40 && reg.machThreadSelfOffset == 24 && reg.quantumExpiryOffset == 960)
        let (_, g) = env.svc(366, [1, 2, 16384, rec, 56, 160])
        #expect(g.carry && g.x[0] == 22)
    }

    @Test func bsdthreadRegisterErrors() throws {
        let env = try Env()
        #expect(env.svc(366, [1, 2, 0x20000, 0, 0, 0]).1.x[0] == 22)
        #expect(env.svc(366, [1, 2, 16384, Env.scratch, 4, 0]).1.carry)
        try env.put(leBytes(48), at: Env.scratch)
        #expect(env.svc(366, [1, 2, 16384, Env.scratch, 56, 0]).1.carry)
        #expect(env.kernel.threadRegistration == nil)
        let (_, f) = env.svc(366, [1, 2, 16384, 0, 0, 0])
        #expect(!f.carry && f.x[0] == 0x4000_00DF)
    }

    @Test func cachePatchPlaceholderFault() throws {
        let env = try Env()
        var f = TrapFrame(kind: TrapFrame.Kind.el0Synchronous.rawValue)
        f.elr = 0xbad4007
        f.far = 0xbad4007
        #expect(DarwinKernel.isCachePatchPlaceholderFault(f))
        guard case let .fatal(status, message) = env.kernel.handle(&f, memory: env.space) else {
            Issue.record("expected fatal"); return
        }
        #expect(status == 70 && message.hasPrefix("missing host-library export (cache patch placeholder 0xbad4007)"))
        f.elr = 0x1_0000_4000
        f.far = 0xbad4007 + 16
        #expect(DarwinKernel.isCachePatchPlaceholderFault(f))
        f.far = 0xbad4007 - 16
        #expect(DarwinKernel.isCachePatchPlaceholderFault(f))
        f.far = 0xbad4007 + 17
        #expect(!DarwinKernel.isCachePatchPlaceholderFault(f))
        f.elr = 0xbad4000
        #expect(DarwinKernel.isCachePatchPlaceholderFault(f))
        var s = TrapFrame(kind: TrapFrame.Kind.svc.rawValue)
        s.elr = 0xbad4007
        #expect(!DarwinKernel.isCachePatchPlaceholderFault(s))
        var other = TrapFrame(kind: TrapFrame.Kind.el0Synchronous.rawValue)
        other.far = 0x10
        guard case let .fatal(_, m2) = env.kernel.handle(&other, memory: env.space) else { Issue.record("fatal"); return }
        #expect(!m2.contains("missing host-library export"))
    }

    @Test func singleFileHostLibraryPrefix() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).resolvingSymlinksInPath()
            .appendingPathComponent("swiftcode-hostlibs-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }
        var prefixes: [DarwinFileSystem.Prefix] = []
        for n in ["kernel", "platform", "pthread"] {
            let host = tmp.appendingPathComponent("libsystem_\(n).dylib")
            try Data(Array("lib \(n)".utf8)).write(to: host)
            prefixes.append(.init(guestPath: "/usr/lib/system/libsystem_\(n).dylib", hostPath: host.path, writable: false))
        }
        let fs = DarwinFileSystem(prefixes: prefixes, console: { _, _ in })
        let kernel = DarwinKernel(fileSystem: fs, pid: 100)
        let space = GuestAddressSpace(backing: FakePhysicalBacking())
        let scratch = Env.scratch
        _ = try space.mapAnonymous(at: scratch, size: Env.scratchSize, protection: .readWrite, hint: nil)
        func svc(_ x16: UInt64, _ args: [UInt64]) -> TrapFrame {
            var f = TrapFrame()
            f.kind = TrapFrame.Kind.svc.rawValue
            f.x[16] = x16
            for (i, v) in args.enumerated() { f.x[i] = v }
            _ = kernel.handle(&f, memory: space)
            return f
        }
        var identities: Set<[UInt64]> = []
        for n in ["kernel", "platform", "pthread"] {
            try space.write(va: scratch, bytes: Array("/usr/lib/system/libsystem_\(n).dylib".utf8) + [0])
            let st = svc(338, [scratch, scratch + 0x400])
            #expect(!st.carry)
            let a = try #require(DarwinStat(decodingStat64: try space.read(va: scratch + 0x400, count: DarwinStat.encodedSize)))
            #expect(a.isRegularFile && a.size == Int64("lib \(n)".utf8.count))
            let o = svc(5, [scratch, 0, 0])
            #expect(!o.carry)
            let fd = o.x[0]
            #expect(!svc(339, [fd, scratch + 0x600]).carry)
            let b = try #require(DarwinStat(decodingStat64: try space.read(va: scratch + 0x600, count: DarwinStat.encodedSize)))
            #expect(a.dev == b.dev && a.ino == b.ino && a.mtime == b.mtime)
            identities.insert([UInt64(a.dev), a.ino])
            let lv = svc(92, [fd, 98, 0])
            #expect(!lv.carry && lv.x[0] == 0)
            #expect(svc(5, [scratch, 2, 0]).carry)
        }
        #expect(identities.count == 3)
        for path in ["/usr/lib/system/libsystem_c.dylib", "/usr/lib/system", "/usr/lib/libSystem.B.dylib"] {
            try space.write(va: scratch, bytes: Array(path.utf8) + [0])
            let f = svc(338, [scratch, scratch + 0x400])
            #expect(f.carry && f.x[0] == 2, "\(path)")
        }
    }
}
