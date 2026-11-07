import Foundation
import Testing
import YcodeDarwinABI
@testable import YcodeDarwinKernel

@Suite struct FileLockTests {
    typealias At = ProcEnv.At
    static let flockArea = ProcEnv.scratch + 0xA000

    func flock(_ type: Int16, _ start: Int64, _ len: Int64, whence: Int16 = 0, pid: Int32 = 0) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: 24)
        b.putLE(start, at: 0)
        b.putLE(len, at: 8)
        b.putLE(pid, at: 16)
        b.putLE(type, at: 20)
        b.putLE(whence, at: 22)
        return b
    }

    func lockCall(_ env: ProcEnv, _ k: DarwinKernel, _ fd: Int64, _ cmd: UInt64, _ f: [UInt8],
                  timeoutNanoseconds: Int64? = nil) -> Int64 {
        var bytes = f
        if let t = timeoutNanoseconds {
            var ts = [UInt8](repeating: 0, count: 16)
            ts.putLE(t / 1_000_000_000, at: 0)
            ts.putLE(t % 1_000_000_000, at: 8)
            bytes += ts
        }
        env.put(k, bytes, at: Self.flockArea)
        return env.bsd(k, 92, [UInt64(bitPattern: fd), cmd, Self.flockArea])
    }

    func open(_ env: ProcEnv, _ k: DarwinKernel, _ path: String, _ flags: UInt64) -> Int64 {
        env.putString(k, path, at: At.out + 0x800)
        return env.bsd(k, 5, [At.out + 0x800, flags, 0o644])
    }

    @Test func posixRecordLocksAcrossProcesses() throws {
        let env = try ProcEnv()
        let root = env.rootKernel!
        let path = env.root + "/db.sqlite"
        let fd = open(env, root, path, 0x202)
        #expect(fd >= 0)
        #expect(lockCall(env, root, fd, 8, flock(3, 0, 10)) == 0)
        #expect(lockCall(env, root, fd, 8, flock(1, 100, 0)) == 0)
        let (_, _, child) = env.spawn(from: root)
        let c = try #require(env.kernel(child))
        let cfd = open(env, c, path, 0x2)
        #expect(lockCall(env, c, cfd, 8, flock(3, 5, 2)) == -35)
        #expect(lockCall(env, c, cfd, 8, flock(1, 200, 1)) == 0)
        #expect(lockCall(env, c, cfd, 8, flock(3, 10, 5)) == 0)
        #expect(lockCall(env, c, cfd, 7, flock(3, 0, 1)) == 0)
        let got = env.read(c, Self.flockArea, 24)
        #expect(got.readLE(Int16.self, at: 20) == 3 && got.readLE(Int32.self, at: 16) == 100)
        #expect(got.readLE(Int64.self, at: 0) == 0 && got.readLE(Int64.self, at: 8) == 10)
        #expect(lockCall(env, root, fd, 7, flock(3, 0, 1)) == 0)
        #expect(env.read(root, Self.flockArea, 24).readLE(Int16.self, at: 20) == 2)
        #expect(lockCall(env, root, fd, 8, flock(2, 4, 2)) == 0)
        #expect(lockCall(env, c, cfd, 8, flock(3, 4, 2)) == 0)
        #expect(lockCall(env, c, cfd, 8, flock(3, 3, 1)) == -35)
        let rfd = open(env, root, path, 0x0)
        #expect(lockCall(env, root, rfd, 8, flock(3, 50, 1)) == -9)
        #expect(lockCall(env, root, fd, 8, flock(7, 50, 1)) == -22)
        #expect(lockCall(env, root, fd, 8, flock(3, 0, -1)) == -22)
        #expect(lockCall(env, c, cfd, 10, flock(3, 0, 1), timeoutNanoseconds: 5_000_000) == -60)
        #expect(env.bsd(root, 6, [UInt64(rfd)]) == 0)
        #expect(lockCall(env, c, cfd, 8, flock(3, 0, 4)) == 0)
        #expect(lockCall(env, root, fd, 8, flock(1, 0, 1)) == -35)
    }

    @Test func flockAndOFDLocksBelongToTheDescription() throws {
        let env = try ProcEnv()
        let root = env.rootKernel!
        let path = env.root + "/store"
        let fd = open(env, root, path, 0x202)
        #expect(env.bsd(root, 131, [UInt64(fd), 2]) == 0)
        let (_, _, child) = env.spawn(from: root)
        let c = try #require(env.kernel(child))
        #expect(env.bsd(c, 131, [UInt64(fd), 2 | 4]) == 0)
        let other = open(env, c, path, 0x2)
        #expect(env.bsd(c, 131, [UInt64(other), 1 | 4]) == -35)
        #expect(env.bsd(root, 131, [UInt64(fd), 8]) == 0)
        #expect(env.bsd(c, 131, [UInt64(other), 1 | 4]) == 0)
        #expect(env.bsd(c, 6, [UInt64(other)]) == 0)
        let third = open(env, c, path, 0x2)
        #expect(env.bsd(c, 131, [UInt64(third), 2 | 4]) == 0)
        let ofd1 = open(env, root, path, 0x2), ofd2 = open(env, root, path, 0x2)
        #expect(lockCall(env, root, ofd1, 90, flock(3, 0, 0)) == -35)
        #expect(env.bsd(c, 131, [UInt64(third), 8]) == 0)
        #expect(lockCall(env, root, ofd1, 90, flock(3, 0, 0)) == 0)
        #expect(lockCall(env, root, ofd2, 90, flock(1, 0, 1)) == -35)
        #expect(lockCall(env, root, ofd2, 92, flock(1, 0, 1)) == 0)
        #expect(env.read(root, Self.flockArea, 24).readLE(Int32.self, at: 16) == -1)
        #expect(env.bsd(root, 6, [UInt64(ofd1)]) == 0)
        #expect(lockCall(env, root, ofd2, 90, flock(1, 0, 1)) == 0)
        env.put(root, [UInt8](repeating: 0, count: 8), at: At.out)
        let pipe = env.bsd(root, 42, [])
        #expect(pipe >= 0)
        #expect(env.bsd(root, 131, [UInt64(pipe), 2]) == -45)
    }

    @Test func protectionClassesAndPreallocate() throws {
        let env = try ProcEnv()
        let root = env.rootKernel!
        let dir = env.root + "/Containers"
        env.putString(root, dir, at: At.out + 0x800)
        #expect(env.bsd(root, 136, [At.out + 0x800, 0o755]) == 0)
        let dfd = open(env, root, dir, 0x0)
        #expect(env.bsd(root, 92, [UInt64(dfd), 63, 0]) == 0)
        #expect(env.bsd(root, 92, [UInt64(dfd), 64, 4]) == 0)
        #expect(env.bsd(root, 92, [UInt64(dfd), 63, 0]) == 3)
        #expect(env.bsd(root, 92, [UInt64(dfd), 64, 1]) == 0)
        #expect(env.bsd(root, 92, [UInt64(dfd), 64, 5]) == -22)
        let f = open(env, root, dir + "/a", 0x202)
        #expect(env.bsd(root, 92, [UInt64(f), 63, 0]) == 1)
        #expect(env.bsd(root, 92, [UInt64(f), 64, 0]) == -22)
        #expect(env.bsd(root, 92, [UInt64(f), 64, 6]) == -1)
        env.putString(root, dir + "/b", at: At.out + 0x800)
        let b = env.bsd(root, 216, [At.out + 0x800, 0x202, 2, 0, 0o644])
        #expect(b >= 0 && env.bsd(root, 92, [UInt64(b), 63, 0]) == 2)
        var store = [UInt8](repeating: 0, count: 32)
        store.putLE(Int32(3), at: 4)
        store.putLE(Int64(8192), at: 16)
        env.put(root, store, at: Self.flockArea)
        #expect(env.bsd(root, 92, [UInt64(f), 42, Self.flockArea]) == 0)
        #expect(env.read(root, Self.flockArea, 32).readLE(Int64.self, at: 24) == 8192)
        store.putLE(Int32(1), at: 4)
        env.put(root, store, at: Self.flockArea)
        #expect(env.bsd(root, 92, [UInt64(f), 42, Self.flockArea]) == -22)
        let pipe = env.bsd(root, 42, [])
        #expect(env.bsd(root, 92, [UInt64(pipe), 63, 0]) == -9)
    }

    @Test func syncAndConfinedDescriptors() throws {
        let env = try ProcEnv()
        let root = env.rootKernel!
        let path = env.root + "/db"
        let plain = open(env, root, path, 0x202)
        #expect(env.bsd(root, 95, [UInt64(plain)]) == 0)
        #expect(env.bsd(root, 187, [UInt64(plain)]) == 0)
        #expect(env.bsd(root, 95, [77]) == -9)
        let pipe = env.bsd(root, 42, [])
        #expect(env.bsd(root, 95, [UInt64(pipe)]) == -45)
        #expect(env.bsd(root, 92, [UInt64(plain), 95, 1]) == -9)
        let confined = open(env, root, path, 0x0800_0002)
        #expect(env.bsd(root, 92, [UInt64(confined), 1, 0]) == 2)
        let dup = env.bsd(root, 41, [UInt64(confined)])
        #expect(env.bsd(root, 92, [UInt64(confined), 95, 1]) == -35)
        #expect(env.bsd(root, 6, [UInt64(dup)]) == 0)
        #expect(env.bsd(root, 92, [UInt64(confined), 95, 1]) == 0)
        #expect(env.bsd(root, 92, [UInt64(confined), 96, 0]) == 1)
        #expect(env.bsd(root, 92, [UInt64(confined), 95, 0]) == -1)
        let (_, _, child) = env.spawn(from: root)
        let c = try #require(env.kernel(child))
        #expect(env.bsd(c, 92, [UInt64(confined), 1, 0]) == -9)
        #expect(env.bsd(c, 92, [UInt64(plain), 1, 0]) == 0)
    }

    @Test func purgeableControl() throws {
        let env = try ProcEnv()
        let root = env.rootKernel!
        let state = ProcEnv.scratch + 0xB000
        func purgable(_ control: UInt64, _ value: Int32) -> (Int64, Int32) {
            env.put(root, withUnsafeBytes(of: value.littleEndian) { Array($0) }, at: state)
            let (_, f) = env.svc(root, UInt64(bitPattern: -11), [0x103, ProcEnv.scratch, control, state])
            return (Int64(f.x[0]), env.read(root, state, 4).readLE(Int32.self, at: 0))
        }
        #expect(purgable(1, 9) == (0, 0))
        #expect(purgable(0, 1) == (0, 0))
        #expect(purgable(1, 9) == (0, 1))
        #expect(purgable(0, 0) == (0, 1))
        #expect(purgable(0, 2).0 == 4)
        #expect(purgable(7, 0).0 == 4)
    }
}

@Suite struct PosixSemaphoreTests {
    @Test func namedSemaphores() throws {
        let env = try ProcEnv()
        let root = env.rootKernel!
        let name = ProcEnv.At.out + 0x100
        env.putString(root, "/passd.firstlaunch", at: name)
        #expect(env.bsd(root, 268, [name, 0, 0, 0]) == -2)
        let sem = env.bsd(root, 268, [name, 0x200, 0o644, 1])
        #expect(sem >= 0)
        #expect(env.bsd(root, 268, [name, 0xA00, 0o644, 0]) == -17)
        #expect(env.bsd(root, 272, [UInt64(sem)]) == 0)
        #expect(env.bsd(root, 272, [UInt64(sem)]) == -35)
        #expect(env.bsd(root, 273, [UInt64(sem)]) == 0)
        #expect(env.bsd(root, 271, [UInt64(sem)]) == 0)
        #expect(env.bsd(root, 273, [99]) == -9)
        let (_, _, child) = env.spawn(from: root)
        let c = try #require(env.kernel(child))
        env.putString(c, "/passd.firstlaunch", at: name)
        let other = env.bsd(c, 268, [name, 0, 0, 0])
        #expect(other >= 0)
        #expect(env.bsd(c, 273, [UInt64(other)]) == 0)
        #expect(env.bsd(root, 272, [UInt64(sem)]) == 0)
        env.putString(root, String(repeating: "x", count: 32), at: name + 0x100)
        #expect(env.bsd(root, 268, [name + 0x100, 0x200, 0o644, 0]) == -63)
        #expect(env.bsd(root, 268, [name, 0x200, 0o644, 40000]) >= 0)
        #expect(env.bsd(root, 270, [name]) == 0)
        #expect(env.bsd(root, 270, [name]) == -2)
        env.putString(root, "/new", at: name + 0x200)
        #expect(env.bsd(root, 268, [name + 0x200, 0x200, 0o644, 40000]) == -22)
        #expect(env.bsd(root, 269, [UInt64(sem)]) == 0)
        #expect(env.bsd(root, 269, [UInt64(sem)]) == -9)
    }
}
