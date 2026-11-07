import Foundation
import Testing
@testable import SwiftCodeDarwinABI

final class TempTree {
    let root: String

    init() throws {
        let base = FileManager.default.temporaryDirectory.path
        root = base + "/swiftcode-vfs-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(atPath: root) }

    func host(_ relative: String) -> String { relative.isEmpty ? root : root + "/" + relative }

    func mkdir(_ relative: String) throws {
        try FileManager.default.createDirectory(atPath: host(relative), withIntermediateDirectories: true)
    }

    func writeFile(_ relative: String, _ bytes: [UInt8]) throws {
        let path = host(relative)
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent,
                                                withIntermediateDirectories: true)
        guard FileManager.default.createFile(atPath: path, contents: Data(bytes)) else {
            throw DarwinErrnoError(DarwinErrnoCode.EIO)
        }
    }

    func symlink(_ relative: String, to target: String) throws {
        try FileManager.default.createSymbolicLink(atPath: host(relative), withDestinationPath: target)
    }

    func contents(_ relative: String) -> [UInt8]? {
        FileManager.default.contents(atPath: host(relative)).map { [UInt8]($0) }
    }
}

private func errno(of body: () throws -> Void) -> Int32? {
    do { try body() } catch let e as DarwinErrnoError { return e.errno } catch { return -1 }
    return nil
}

private final class Fixture {
    let tree: TempTree
    let fs: DarwinFileSystem
    let outputBox = OutputBox()

    init() throws {
        tree = try TempTree()
        try tree.writeFile("runtime/usr/lib/dyld_sim", Array("DYLD".utf8) + [UInt8](repeating: 7, count: 100))
        try tree.writeFile("runtime/System/Library/Caches/com.apple.dyld/dyld_sim_shared_cache_arm64", Array(repeating: 1, count: 0x5000))
        try tree.symlink("runtime/usr/lib/libalias.dylib", to: "dyld_sim")
        try tree.symlink("runtime/abs-link", to: "/Runtime/usr/lib")
        try tree.symlink("runtime/escape", to: "../outside/secret")
        try tree.symlink("runtime/escape-abs", to: tree.host("outside/secret"))
        try tree.symlink("runtime/loop", to: "loop")
        try tree.writeFile("outside/secret", Array("secret".utf8))
        try tree.writeFile("apps/hello", Array("hello-binary".utf8))
        try tree.mkdir("run/tmp")
        let box = outputBox
        fs = DarwinFileSystem(prefixes: [
            .init(guestPath: "/Runtime", hostPath: tree.host("runtime"), writable: false),
            .init(guestPath: "/Apps/", hostPath: tree.host("apps") + "/", writable: false),
            .init(guestPath: "/tmp", hostPath: tree.host("run/tmp"), writable: true),
        ], console: { fd, bytes in box.items.append((fd, bytes)) })
    }

    final class OutputBox { var items: [(Int32, [UInt8])] = [] }
}

@Suite struct FileSystemTests {
    @Test func openFileSizeFollowsWrites() throws {
        let f = try Fixture()
        let fd = try f.fs.open("/tmp/grown", flags: DarwinOpen.O_RDWR | DarwinOpen.O_CREAT | DarwinOpen.O_EXCL, mode: 0o600)
        #expect(try f.fs.file(for: fd).size == 0)
        _ = try f.fs.write(fd, [UInt8](repeating: 9, count: 20_000))
        #expect(try f.fs.file(for: fd).size == 20_000)
        #expect(try f.fs.file(for: fd).stat.size == 0)
    }

    @Test func flagAndErrnoValues() {
        #expect(DarwinOpen.O_RDONLY == 0 && DarwinOpen.O_WRONLY == 1 && DarwinOpen.O_RDWR == 2)
        #expect(DarwinOpen.O_CREAT == 0x200 && DarwinOpen.O_TRUNC == 0x400 && DarwinOpen.O_EXCL == 0x800)
        #expect(DarwinOpen.O_CLOEXEC == 0x100_0000 && DarwinOpen.O_DIRECTORY == 0x10_0000)
        let table: [(Int32, Int32)] = [
            (DarwinErrnoCode.ENOENT, 2), (DarwinErrnoCode.EBADF, 9), (DarwinErrnoCode.ENOMEM, 12), (DarwinErrnoCode.EACCES, 13),
            (DarwinErrnoCode.EFAULT, 14), (DarwinErrnoCode.EEXIST, 17), (DarwinErrnoCode.ENOTDIR, 20), (DarwinErrnoCode.EISDIR, 21),
            (DarwinErrnoCode.EINVAL, 22), (DarwinErrnoCode.EMFILE, 24), (DarwinErrnoCode.ENOTTY, 25), (DarwinErrnoCode.EROFS, 30),
            (DarwinErrnoCode.ERANGE, 34), (DarwinErrnoCode.ENOSYS, 78), (DarwinErrnoCode.ENOTSUP, 45), (DarwinErrnoCode.ENAMETOOLONG, 63),
        ]
        for (a, b) in table { #expect(a == b) }
        #expect(DarwinErrnoCode.name(30) == "EROFS")
        #expect(DarwinErrnoError(2).description.contains("ENOENT"))
    }

    @Test func stat64Encoding() {
        let st = DarwinStat(dev: 0x1122_3344, mode: 0o100644, nlink: 3, ino: 0x0102_0304_0506_0708, uid: 501, gid: 20,
                            rdev: 0xAABB_CCDD, atime: .init(sec: 1, nsec: 2), mtime: .init(sec: 0x6000_0000, nsec: 999),
                            ctime: .init(sec: 5, nsec: 6), birthtime: .init(sec: 7, nsec: 8), size: 0x1234_5678_9A,
                            blocks: 0x99, blksize: 4096, flags: 0x20, gen: 0x77)
        let b = st.encodedStat64()
        #expect(b.count == 144)
        func u64(_ o: Int) -> UInt64 { (0..<8).reduce(0) { $0 | UInt64(b[o + $1]) << (8 * UInt64($1)) } }
        func u32(_ o: Int) -> UInt32 { (0..<4).reduce(0) { $0 | UInt32(b[o + $1]) << (8 * UInt32($1)) } }
        func u16(_ o: Int) -> UInt16 { UInt16(b[o]) | UInt16(b[o + 1]) << 8 }
        #expect(u32(0) == 0x1122_3344)
        #expect(u16(4) == 0o100644)
        #expect(u16(6) == 3)
        #expect(u64(8) == 0x0102_0304_0506_0708)
        #expect(u32(16) == 501 && u32(20) == 20)
        #expect(u32(24) == 0xAABB_CCDD)
        #expect(u32(28) == 0)
        #expect(u64(32) == 1 && u64(40) == 2)
        #expect(u64(48) == 0x6000_0000 && u64(56) == 999)
        #expect(u64(64) == 5 && u64(72) == 6)
        #expect(u64(80) == 7 && u64(88) == 8)
        #expect(u64(96) == 0x1234_5678_9A)
        #expect(u64(104) == 0x99)
        #expect(u32(112) == 4096)
        #expect(u32(116) == 0x20 && u32(120) == 0x77)
        #expect(b[124..<144].allSatisfy { $0 == 0 })
        #expect(DarwinStat(decodingStat64: b) == st)
        #expect(DarwinStat(decodingStat64: Array(b.prefix(100))) == nil)
    }

    @Test func normalization() throws {
        let f = try Fixture()
        let fs = f.fs
        #expect(fs.normalize("/a//b/./c/", cwd: "/") == "/a/b/c")
        #expect(fs.normalize("/a/b/../../..", cwd: "/") == "/")
        #expect(fs.normalize("x/../y", cwd: "/Runtime/usr") == "/Runtime/usr/y")
        #expect(fs.normalize("..", cwd: "/") == "/")
        #expect(fs.normalize("", cwd: "/tmp") == "/tmp")
        #expect(fs.prefixes.map(\.guestPath) == ["/Runtime", "/Apps", "/tmp"])
        #expect(fs.cwd == "/")
        fs.cwd = "/Runtime/usr/./lib/"
        #expect(fs.cwd == "/Runtime/usr/lib")
        #expect(try fs.stat("dyld_sim", followSymlinks: true).size == 104)
        fs.cwd = ".."
        #expect(fs.cwd == "/Runtime/usr")
        #expect(try fs.stat("/Apps/../Runtime/usr/lib/dyld_sim", followSymlinks: true).size == 104)
    }

    @Test func allowlist() throws {
        let f = try Fixture()
        let fs = f.fs
        #expect(try fs.stat("/Runtime", followSymlinks: true).isDirectory)
        #expect(try fs.stat("/Apps/hello", followSymlinks: true).isRegularFile)
        #expect(try fs.stat("/", followSymlinks: true).isDirectory)
        #expect(errno { _ = try fs.open("/", flags: 0, mode: 0) } == DarwinErrnoCode.EACCES)
        for p in ["/etc/passwd", f.tree.host("outside/secret"), "/Runtimes", "/Runtime/../outside/secret", ""] {
            #expect(errno { _ = try fs.stat(p, followSymlinks: true) } == DarwinErrnoCode.ENOENT, "\(p)")
            #expect(errno { _ = try fs.open(p, flags: 0, mode: 0) } == DarwinErrnoCode.ENOENT, "\(p)")
        }
        #expect(errno { _ = try fs.stat("/Runtime/usr/lib/missing", followSymlinks: true) } == DarwinErrnoCode.ENOENT)
        #expect(errno { _ = try fs.stat("/Runtime/missing/x", followSymlinks: true) } == DarwinErrnoCode.ENOENT)
        #expect(errno { _ = try fs.stat("/Apps/hello/x", followSymlinks: true) } == DarwinErrnoCode.ENOTDIR)
        #expect(errno { _ = try fs.stat("/Runtime/" + String(repeating: "a", count: 300), followSymlinks: true) } == DarwinErrnoCode.ENAMETOOLONG)
        #expect(errno { _ = try fs.stat("/Runtime/" + String(repeating: "a/", count: 600), followSymlinks: true) } == DarwinErrnoCode.ENAMETOOLONG)
    }

    @Test func symlinksStayInsideAllowlist() throws {
        let f = try Fixture()
        let fs = f.fs
        #expect(try fs.stat("/Runtime/usr/lib/libalias.dylib", followSymlinks: true).size == 104)
        #expect(try fs.stat("/Runtime/usr/lib/libalias.dylib", followSymlinks: false).isSymbolicLink)
        #expect(try fs.stat("/Runtime/abs-link/dyld_sim", followSymlinks: true).size == 104)
        #expect(try fs.realpath("/Runtime/abs-link/libalias.dylib") == "/Runtime/usr/lib/dyld_sim")
        #expect(try fs.realpath("/Runtime/usr/../usr/lib") == "/Runtime/usr/lib")
        #expect(errno { _ = try fs.stat("/Runtime/escape", followSymlinks: true) } == DarwinErrnoCode.ENOENT)
        #expect(errno { _ = try fs.stat("/Runtime/escape-abs", followSymlinks: true) } == DarwinErrnoCode.ENOENT)
        #expect(errno { _ = try fs.open("/Runtime/escape", flags: 0, mode: 0) } == DarwinErrnoCode.ENOENT)
        #expect(errno { _ = try fs.realpath("/Runtime/escape") } == DarwinErrnoCode.ENOENT)
        #expect(errno { _ = try fs.stat("/Runtime/loop", followSymlinks: true) } == DarwinErrnoCode.ELOOP)
        #expect(errno { _ = try fs.realpath("/Runtime/usr/lib/nothing") } == DarwinErrnoCode.ENOENT)
        #expect(try fs.stat("/Runtime/escape", followSymlinks: false).isSymbolicLink)
        #expect(errno { _ = try fs.open("/Runtime/usr/lib/libalias.dylib", flags: DarwinOpen.O_NOFOLLOW, mode: 0) } == DarwinErrnoCode.ELOOP)
    }

    @Test func openReadAndDescriptors() throws {
        let f = try Fixture()
        let fs = f.fs
        #expect(fs.openDescriptors == [0, 1, 2])
        let fd = try fs.open("/Runtime/usr/lib/libalias.dylib", flags: DarwinOpen.O_RDONLY | DarwinOpen.O_CLOEXEC, mode: 0)
        #expect(fd == 3)
        #expect(try fs.closeOnExec(fd))
        try fs.setCloseOnExec(fd, false)
        #expect(try !fs.closeOnExec(fd))
        #expect(try fs.statusFlags(fd) == DarwinOpen.O_RDONLY)
        #expect(try fs.path(for: fd) == "/Runtime/usr/lib/dyld_sim")
        #expect(try fs.read(fd, count: 4) == Array("DYLD".utf8))
        #expect(try fs.read(fd, count: 2) == [7, 7])
        #expect(try fs.pread(fd, count: 4, offset: 0) == Array("DYLD".utf8))
        #expect(try fs.read(fd, count: 1000).count == 98)
        #expect(try fs.read(fd, count: 10) == [])
        #expect(try fs.pread(fd, count: 10, offset: 1000) == [])
        let st = try fs.fstat(fd)
        #expect(st.size == 104 && st.isRegularFile)
        let file = try fs.file(for: fd)
        #expect(file.guestPath == "/Runtime/usr/lib/dyld_sim" && file.size == 104 && file.stat.ino == st.ino)
        #expect(try fs.stat("/Runtime/usr/lib/dyld_sim", followSymlinks: true) == st)
        #expect(st.uid == 501 && st.gid == 20)
        #expect(st.mtime.sec > 0)
        #expect(errno { _ = try fs.write(fd, [1]) } == DarwinErrnoCode.EBADF)
        let fd2 = try fs.open("/Apps/hello", flags: 0, mode: 0)
        #expect(fd2 == 4)
        try fs.close(fd)
        #expect(try fs.open("/Apps/hello", flags: 0, mode: 0) == 3)
        #expect(try file.read(count: 4, offset: 0) == Array("DYLD".utf8))
        for bad: Int32 in [fd2 + 10, -1, 99] {
            #expect(errno { _ = try fs.read(bad, count: 1) } == DarwinErrnoCode.EBADF)
            #expect(errno { _ = try fs.path(for: bad) } == DarwinErrnoCode.EBADF)
            #expect(errno { _ = try fs.fstat(bad) } == DarwinErrnoCode.EBADF)
            #expect(errno { try fs.close(bad) } == DarwinErrnoCode.EBADF)
            #expect(errno { try fs.setCloseOnExec(bad, true) } == DarwinErrnoCode.EBADF)
            #expect(errno { _ = try fs.file(for: bad) } == DarwinErrnoCode.EBADF)
        }
        try fs.close(fd2)
        #expect(errno { try fs.close(fd2) } == DarwinErrnoCode.EBADF)
    }

    @Test func directories() throws {
        let f = try Fixture()
        let fs = f.fs
        let dir = try fs.open("/Runtime/System/Library/Caches/com.apple.dyld/", flags: DarwinOpen.O_DIRECTORY, mode: 0)
        #expect(try fs.path(for: dir) == "/Runtime/System/Library/Caches/com.apple.dyld")
        #expect(try fs.fstat(dir).isDirectory)
        let cache = try fs.open(try fs.path(for: dir) + "/dyld_sim_shared_cache_arm64", flags: 0, mode: 0)
        #expect(try fs.fstat(cache).size == 0x5000)
        #expect(try fs.pread(cache, count: 0x4000, offset: 0).count == 0x4000)
        #expect(errno { _ = try fs.read(dir, count: 1) } == DarwinErrnoCode.EISDIR)
        #expect(errno { _ = try fs.open("/Apps/hello", flags: DarwinOpen.O_DIRECTORY, mode: 0) } == DarwinErrnoCode.ENOTDIR)
        #expect(errno { _ = try fs.open("/tmp", flags: DarwinOpen.O_RDWR, mode: 0) } == DarwinErrnoCode.EISDIR)
    }

    @Test func readOnlyPrefixesAreEROFS() throws {
        let f = try Fixture()
        let fs = f.fs
        let ro = "/Runtime/usr/lib/dyld_sim"
        #expect(errno { _ = try fs.open(ro, flags: DarwinOpen.O_WRONLY, mode: 0) } == DarwinErrnoCode.EROFS)
        #expect(errno { _ = try fs.open(ro, flags: DarwinOpen.O_RDWR, mode: 0) } == DarwinErrnoCode.EROFS)
        #expect(errno { _ = try fs.open(ro, flags: DarwinOpen.O_TRUNC, mode: 0) } == DarwinErrnoCode.EROFS)
        #expect(errno { _ = try fs.open("/Apps/new", flags: DarwinOpen.O_CREAT | DarwinOpen.O_WRONLY, mode: 0o644) } == DarwinErrnoCode.EROFS)
        #expect(errno { _ = try fs.open("/Apps/new", flags: DarwinOpen.O_CREAT, mode: 0o644) } == DarwinErrnoCode.EROFS)
        let fd = try fs.open(ro, flags: DarwinOpen.O_CREAT, mode: 0o644)
        #expect(try fs.read(fd, count: 4) == Array("DYLD".utf8))
        #expect(errno { _ = try fs.open(ro, flags: DarwinOpen.O_CREAT | DarwinOpen.O_EXCL, mode: 0o644) } == DarwinErrnoCode.EEXIST)
        #expect(f.tree.contents("apps/new") == nil)
        #expect(errno { _ = try fs.open(ro, flags: 3, mode: 0) } == DarwinErrnoCode.EINVAL)
    }

    @Test func writableTmp() throws {
        let f = try Fixture()
        let fs = f.fs
        let fd = try fs.open("/tmp/out.txt", flags: DarwinOpen.O_CREAT | DarwinOpen.O_RDWR, mode: 0o600)
        #expect(try fs.write(fd, Array("abc".utf8)) == 3)
        #expect(try fs.write(fd, Array("de".utf8)) == 2)
        #expect(f.tree.contents("run/tmp/out.txt") == Array("abcde".utf8))
        #expect(try fs.pread(fd, count: 10, offset: 1) == Array("bcde".utf8))
        #expect(try fs.fstat(fd).size == 5)
        try fs.close(fd)
        #expect(errno { _ = try fs.open("/tmp/out.txt", flags: DarwinOpen.O_CREAT | DarwinOpen.O_EXCL | DarwinOpen.O_WRONLY, mode: 0o600) } == DarwinErrnoCode.EEXIST)
        let app = try fs.open("/tmp/out.txt", flags: DarwinOpen.O_WRONLY | DarwinOpen.O_APPEND, mode: 0)
        #expect(try fs.statusFlags(app) == DarwinOpen.O_WRONLY | DarwinOpen.O_APPEND)
        _ = try fs.write(app, Array("!".utf8))
        #expect(f.tree.contents("run/tmp/out.txt") == Array("abcde!".utf8))
        #expect(errno { _ = try fs.read(app, count: 1) } == DarwinErrnoCode.EBADF)
        let tr = try fs.open("/tmp/out.txt", flags: DarwinOpen.O_WRONLY | DarwinOpen.O_TRUNC, mode: 0)
        #expect(try fs.fstat(tr).size == 0)
        #expect(errno { _ = try fs.open("/tmp/nodir/x", flags: DarwinOpen.O_CREAT | DarwinOpen.O_WRONLY, mode: 0o600) } == DarwinErrnoCode.ENOENT)
        #expect(try fs.realpath("/tmp/./out.txt") == "/tmp/out.txt")
    }

    @Test func console() throws {
        let f = try Fixture()
        let fs = f.fs
        #expect(try fs.write(1, Array("hi\n".utf8)) == 3)
        #expect(try fs.write(2, Array("err".utf8)) == 3)
        #expect(f.outputBox.items.map(\.0) == [1, 2])
        #expect(f.outputBox.items.map(\.1) == [Array("hi\n".utf8), Array("err".utf8)])
        #expect(try fs.read(0, count: 10) == [])
        #expect(try fs.fstat(1).fileType == DarwinStat.S_IFCHR)
        #expect(try fs.path(for: 1) == DarwinFileSystem.consolePath)
        #expect(errno { _ = try fs.file(for: 1) } == DarwinErrnoCode.ENODEV)
        #expect(errno { _ = try fs.pread(0, count: 1, offset: 0) } == DarwinErrnoCode.ESPIPE)
        try fs.close(0)
        #expect(errno { _ = try fs.read(0, count: 1) } == DarwinErrnoCode.EBADF)
        #expect(try fs.open("/Apps/hello", flags: 0, mode: 0) == 0)
    }

    @Test func descriptorLimit() throws {
        let f = try Fixture()
        let fs = f.fs
        fs.maxDescriptors = 5
        _ = try fs.open("/Apps/hello", flags: 0, mode: 0)
        _ = try fs.open("/Apps/hello", flags: 0, mode: 0)
        #expect(errno { _ = try fs.open("/Apps/hello", flags: 0, mode: 0) } == DarwinErrnoCode.EMFILE)
    }

    @Test func hostErrnoTranslation() {
        #expect(DarwinErrnoCode.fromHost(2) == 2)
        #expect(DarwinErrnoCode.fromHost(EAGAIN) == DarwinErrnoCode.EAGAIN)
        #expect(DarwinErrnoCode.fromHost(ENAMETOOLONG) == DarwinErrnoCode.ENAMETOOLONG)
        #expect(DarwinErrnoCode.fromHost(ELOOP) == DarwinErrnoCode.ELOOP)
        #expect(DarwinErrnoCode.fromHost(ENOSYS) == DarwinErrnoCode.ENOSYS)
    }
}
