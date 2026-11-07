import Foundation
import Testing
@testable import YcodeDarwinABI

private func errnoOf(_ body: () throws -> Void) -> Int32? {
    do { try body() } catch let e as DarwinErrnoError { return e.errno } catch { return -1 }
    return nil
}

@Suite struct FileSystemGuardTests {
    private func fixture() throws -> (TempTree, DarwinFileSystem) {
        let tree = try TempTree()
        try tree.mkdir("w/jobs")
        let fs = DarwinFileSystem(prefixes: [.init(guestPath: "/W", hostPath: tree.host("w"), writable: true)],
                                  console: { _, _ in })
        return (tree, fs)
    }

    @Test func openRulesAndGuardChecks() throws {
        let (tree, fs) = try fixture()
        defer { withExtendedLifetime(tree) {} }
        var violations: [(Int32, UInt32)] = []
        fs.guardViolation = { fd, flavor, _ in violations.append((fd, flavor)) }
        let cloexec = DarwinOpen.O_CLOEXEC
        #expect(errnoOf { _ = try fs.openGuarded("/W/jobs", flags: 0, mode: 0, guard: 1, guardFlags: DarwinGuard.dup) }
                == DarwinErrnoCode.EINVAL)
        #expect(errnoOf { _ = try fs.openGuarded("/W/jobs", flags: cloexec, mode: 0, guard: 1, guardFlags: DarwinGuard.close) }
                == DarwinErrnoCode.EINVAL)
        #expect(errnoOf { _ = try fs.openGuarded("/W/jobs", flags: cloexec, mode: 0, guard: 1, guardFlags: 0x23) }
                == DarwinErrnoCode.EINVAL)
        #expect(errnoOf { _ = try fs.openGuarded("/W/jobs", flags: cloexec, mode: 0, guard: 0, guardFlags: DarwinGuard.dup) }
                == DarwinErrnoCode.EINVAL)
        let all = DarwinGuard.close | DarwinGuard.dup | DarwinGuard.socketIPC | DarwinGuard.fileport
        let fd = try fs.openGuarded("/W/jobs", flags: 0x0100_8000, mode: 0, guard: 0xfeed, guardFlags: all)
        #expect(try fs.guardState(of: fd) == DescriptorGuard(value: 0xfeed, flags: all))
        #expect(try fs.closeOnExec(fd))
        #expect(try fs.file(for: fd).isDirectory)
        #expect(errnoOf { try fs.close(fd) } == DarwinErrnoCode.EPERM)
        #expect(errnoOf { _ = try fs.dup(fd) } == DarwinErrnoCode.EPERM)
        #expect(errnoOf { try fs.dup2(fd, 20) } == DarwinErrnoCode.EPERM)
        #expect(errnoOf { try fs.dup2(1, fd) } == DarwinErrnoCode.EPERM)
        #expect(errnoOf { try fs.setCloseOnExec(fd, false) } == DarwinErrnoCode.EPERM)
        try fs.setCloseOnExec(fd, true)
        #expect(violations.map(\.1) == [DarwinGuard.exceptionClose, DarwinGuard.exceptionDup, DarwinGuard.exceptionDup,
                                         DarwinGuard.exceptionClose, DarwinGuard.exceptionNoCloexec])
        #expect(try fs.guardState(of: fd) != nil)
        #expect(errnoOf { try fs.guardedClose(fd, guard: 1) } == DarwinErrnoCode.EPERM)
        #expect(errnoOf { try fs.guardedClose(1, guard: 1) } == DarwinErrnoCode.EINVAL)
        try fs.guardedClose(fd, guard: 0xfeed)
        #expect(errnoOf { _ = try fs.guardState(of: fd) } == DarwinErrnoCode.EBADF)
    }

    @Test func writeGuardAndExecAndChildren() throws {
        let (tree, fs) = try fixture()
        defer { withExtendedLifetime(tree) {} }
        let fd = try fs.openGuarded("/W/f", flags: DarwinOpen.O_RDWR | DarwinOpen.O_CREAT | DarwinOpen.O_CLOEXEC,
                                    mode: 0o644, guard: 7, guardFlags: DarwinGuard.dup | DarwinGuard.write)
        #expect(errnoOf { _ = try fs.write(fd, [1]) } == DarwinErrnoCode.EPERM)
        #expect(errnoOf { _ = try fs.pwrite(fd, [1], offset: 0) } == DarwinErrnoCode.EPERM)
        #expect(try fs.write(fd, [1, 2], guardChecked: true) == 2)
        #expect(errnoOf { try fs.checkGuardValue(fd, 8) } == DarwinErrnoCode.EPERM)
        try fs.close(fd)
        let g = try fs.openGuarded("/W/jobs", flags: DarwinOpen.O_CLOEXEC, mode: 0, guard: 9,
                                   guardFlags: DarwinGuard.dup | DarwinGuard.close)
        let child = fs.makeChildCopy()
        #expect(try child.guardState(of: g)?.value == 9)
        child.closeOnExecDescriptors()
        #expect(!child.openDescriptors.contains(g))
        fs.closeAll()
        #expect(fs.openDescriptors.isEmpty)
    }

    @Test func changeFdguard() throws {
        let (tree, fs) = try fixture()
        defer { withExtendedLifetime(tree) {} }
        let fd = try fs.open("/W/jobs", flags: DarwinOpen.O_RDONLY, mode: 0)
        let dc = DarwinGuard.dup | DarwinGuard.close
        #expect(errnoOf { try fs.changeGuard(fd, old: 1, oldFlags: 0, new: 5, newFlags: dc, fdFlags: 0) } == DarwinErrnoCode.EINVAL)
        #expect(errnoOf { try fs.changeGuard(fd, old: nil, oldFlags: 0, new: nil, newFlags: 0, fdFlags: 0) } == DarwinErrnoCode.EINVAL)
        #expect(errnoOf { try fs.changeGuard(fd, old: nil, oldFlags: 0, new: 0, newFlags: dc, fdFlags: 0) } == DarwinErrnoCode.EINVAL)
        #expect(errnoOf { try fs.changeGuard(fd, old: nil, oldFlags: 0, new: 5, newFlags: DarwinGuard.close, fdFlags: 0) } == DarwinErrnoCode.EINVAL)
        try fs.changeGuard(fd, old: nil, oldFlags: 0, new: 5, newFlags: dc, fdFlags: 0)
        #expect(try fs.guardState(of: fd) == DescriptorGuard(value: 5, flags: dc) && fs.closeOnExec(fd))
        #expect(errnoOf { try fs.changeGuard(fd, old: nil, oldFlags: dc, new: 6, newFlags: dc, fdFlags: 0) } == DarwinErrnoCode.EINVAL)
        #expect(errnoOf { try fs.changeGuard(fd, old: 0, oldFlags: dc, new: 6, newFlags: dc, fdFlags: 0) } == DarwinErrnoCode.EPERM)
        #expect(errnoOf { try fs.changeGuard(fd, old: 4, oldFlags: dc, new: 6, newFlags: dc, fdFlags: 0) } == DarwinErrnoCode.EPERM)
        #expect(errnoOf { try fs.changeGuard(fd, old: 5, oldFlags: DarwinGuard.dup, new: 6, newFlags: dc, fdFlags: 0) } == DarwinErrnoCode.EPERM)
        try fs.changeGuard(fd, old: 5, oldFlags: dc, new: 6, newFlags: DarwinGuard.dup, fdFlags: 0)
        #expect(try fs.guardState(of: fd)?.value == 6)
        #expect(errnoOf { try fs.changeGuard(fd, old: 6, oldFlags: DarwinGuard.dup, new: nil, newFlags: 1, fdFlags: 0) } == DarwinErrnoCode.EINVAL)
        try fs.changeGuard(fd, old: 6, oldFlags: DarwinGuard.dup, new: nil, newFlags: 0, fdFlags: 0)
        #expect(try fs.guardState(of: fd) == nil && !fs.closeOnExec(fd))
        _ = try fs.dup(fd)
    }
}
