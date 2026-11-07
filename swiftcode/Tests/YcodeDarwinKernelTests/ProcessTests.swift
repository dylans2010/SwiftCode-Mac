import Foundation
import Testing
import YcodeDarwinABI
@testable import YcodeDarwinKernel

@Suite struct ProcessTests {
    typealias At = ProcEnv.At

    @Test func rootProcessAndIdentifiers() throws {
        let env = try ProcEnv()
        let k = env.rootKernel!
        #expect(k.pid == 100)
        #expect(env.system.kernel(forPID: 100) === k)
        #expect(env.launcher.launches.count == 1)
        #expect(env.bsd(k, 20) == 100)
        #expect(env.bsd(k, 39) == 1)
        #expect(env.bsd(k, 81) == 100)
        #expect(env.bsd(k, 310, [0]) == 100)
        #expect(env.bsd(k, 151, [0]) == 100)
        #expect(env.bsd(k, 151, [4242]) == -3)
        #expect(env.bsd(k, 147) == -1)
        #expect(env.bsd(k, 7, [UInt64(bitPattern: -1), 0, 0, 0]) == -10)
        #expect(k.pidVersion != 0)
    }

    @Test func spawnExitAndWait() throws {
        let env = try ProcEnv()
        let root = env.rootKernel!
        let r = env.spawn(from: root, argv: ["probe", "child", "42"])
        #expect(r.outcome == .resume && r.errno == 0 && r.pid == 101)
        let launch = try #require(env.launcher.launches.last)
        #expect(launch.request.argv == ["probe", "child", "42"])
        #expect(launch.request.executablePath == env.exe)
        let child = try #require(env.kernel(101))
        #expect(child === launch.kernel)
        #expect(env.bsd(child, 20) == 101)
        #expect(env.bsd(child, 39) == 100)
        #expect(env.bsd(child, 81) == 100)
        #expect(child.pidVersion != root.pidVersion)
        #expect(env.wait4(root, 101, options: 1).0 == 0)
        #expect(env.svc(child, 1, [42]).0 == .exit(status: 42))
        #expect(child.isTerminating)
        #expect(env.exits.last?.pid == 101 && env.exits.last?.status == 42 << 8)
        #expect(env.system.kernel(forPID: 101) == nil)
        #expect(env.system.process(pid: 101)?.isZombie == true)
        let (pid, status) = env.wait4(root, -1)
        #expect(pid == 101 && status == 42 << 8)
        #expect(env.system.process(pid: 101) == nil)
        #expect(env.wait4(root, -1).0 == -10)
        #expect(env.svc(child, 20).0 == .exit(status: 42))
    }

    @Test func killGivesSignaledStatus() throws {
        let env = try ProcEnv()
        let root = env.rootKernel!
        let pid = env.spawn(from: root).pid
        let child = try #require(env.kernel(pid))
        #expect(env.bsd(root, 37, [UInt64(pid), 0, 1]) == 0)
        #expect(env.bsd(root, 37, [UInt64(pid), 15, 1]) == 0)
        #expect(child.isTerminating)
        guard case let .fatal(status, _) = env.svc(child, 20).0 else { Issue.record("not fatal"); return }
        #expect(status == 128 + 15)
        let (reaped, st) = env.wait4(root, pid)
        #expect(reaped == Int64(pid) && st == 15)
        #expect(env.bsd(root, 37, [UInt64(pid), 15, 1]) == -3)
        #expect(env.bsd(root, 37, [1, 15, 1]) == -1)
        #expect(env.bsd(root, 37, [UInt64(pid), 32, 1]) == -22)
    }

    @Test func ignoredAndCaughtSignals() throws {
        let env = try ProcEnv()
        let root = env.rootKernel!
        let pid = env.spawn(from: root).pid
        let child = try #require(env.kernel(pid))
        env.sigaction(child, 15, handler: 1)
        #expect(env.bsd(root, 37, [UInt64(pid), 15, 1]) == 0)
        #expect(!child.isTerminating)
        env.sigaction(child, 30, handler: 0x1_0000_4000)
        #expect(env.bsd(root, 37, [UInt64(pid), 30, 1]) == 0)
        #expect(!child.isTerminating)
        #expect(env.bsd(child, 52, [At.out]) == 0)
        #expect(env.u32(child, At.out) == 1 << 29)
        #expect(env.bsd(root, 37, [UInt64(pid), 20, 1]) == 0)
        #expect(!child.isTerminating)
        #expect(env.bsd(root, 37, [UInt64(pid), 9, 1]) == 0)
        #expect(child.isTerminating)
        #expect(env.wait4(root, pid).1 == 9)
    }

    @Test func noteExitWithSIGCHLDIgnored() throws {
        let env = try ProcEnv()
        let root = env.rootKernel!
        env.sigaction(root, 20, handler: 1)
        let pid = env.spawn(from: root).pid
        let child = try #require(env.kernel(pid))
        let kq = Int32(env.bsd(root, 362))
        #expect(kq >= 0)
        let add = ProcEnv.kevent64(ident: UInt64(pid), filter: -5, flags: 0x1,
                                   fflags: NoteProc.exit | NoteProc.exitStatus)
        #expect(env.kevent64(root, kq: kq, changes: [add], nevents: 0).0 == 0)
        #expect(env.kevent64(root, kq: kq, changes: [], nevents: 4).0 == 0)
        #expect(env.svc(child, 1, [7]).0 == .exit(status: 7))
        let (n, events) = env.kevent64(root, kq: kq, changes: [], nevents: 4)
        #expect(n == 1)
        let e = try #require(events.first)
        #expect(e.ident == UInt64(pid) && e.filter == -5)
        #expect(e.fflags & NoteProc.exit != 0 && e.data == 0x700)
        #expect(e.flags & 0x8000 != 0 && e.flags & 0x10 != 0)
        #expect(env.wait4(root, pid).0 == -10)
        #expect(env.kevent64(root, kq: kq, changes: [], nevents: 4).0 == 0)
        let bad = ProcEnv.kevent64(ident: 4242, filter: -5, flags: 0x1, fflags: NoteProc.exit)
        let (_, errs) = env.kevent64(root, kq: kq, changes: [bad], nevents: 1)
        #expect(errs.first?.flags ?? 0 & 0x4000 != 0 && errs.first?.data == 3)
    }

    @Test func noteForkAndSignalEvents() throws {
        let env = try ProcEnv()
        let root = env.rootKernel!
        let kq = Int32(env.bsd(root, 362))
        let watchSelf = ProcEnv.kevent64(ident: 100, filter: -5, flags: 0x1, fflags: NoteProc.fork | NoteProc.signal)
        env.sigaction(root, 30, handler: 1)
        let sig = ProcEnv.kevent64(ident: 30, filter: -6, flags: 0x1)
        #expect(env.kevent64(root, kq: kq, changes: [watchSelf, sig], nevents: 0).0 == 0)
        let pid = env.spawn(from: root).pid
        let child = try #require(env.kernel(pid))
        #expect(env.bsd(child, 37, [100, 30, 1]) == 0)
        #expect(env.bsd(child, 37, [100, 30, 1]) == 0)
        let (n, events) = env.kevent64(root, kq: kq, changes: [], nevents: 4)
        #expect(n == 2)
        let proc = try #require(events.first { $0.filter == -5 })
        #expect(proc.fflags == NoteProc.fork | NoteProc.signal)
        let s = try #require(events.first { $0.filter == -6 })
        #expect(s.ident == 30 && s.data == 2)
        #expect(!root.isTerminating)
    }

    @Test func blockedWait4WakesOnChildExit() throws {
        let env = try ProcEnv()
        let root = env.rootKernel!
        let pid = env.spawn(from: root).pid
        let child = try #require(env.kernel(pid))
        let done = DispatchSemaphore(value: 0)
        let box = T2Box<(Int64, Int32)>()
        let t = Thread {
            box.value = env.wait4(env.rootKernel, pid)
            done.signal()
        }
        t.start()
        let end = Date().addingTimeInterval(5)
        while Date() < end, !env.system.lock.withLock({ root.mainThread.blockedInKernel }) { Thread.sleep(forTimeInterval: 0.002) }
        #expect(env.system.lock.withLock { root.mainThread.blockedInKernel })
        #expect(env.svc(child, 1, [3]).0 == .exit(status: 3))
        #expect(done.wait(timeout: .now() + 5) == .success)
        #expect(box.value?.0 == Int64(pid) && box.value?.1 == 3 << 8)
    }

    @Test func terminationDoesNotInterruptOtherProcesses() throws {
        let env = try ProcEnv()
        let root = env.rootKernel!
        let pid = env.spawn(from: root).pid
        let child = try #require(env.kernel(pid))
        let kq = Int32(env.bsd(root, 362))
        let done = DispatchSemaphore(value: 0)
        let box = T2Box<Int64>()
        let t = Thread {
            box.value = env.kevent64(env.rootKernel, kq: kq, changes: [], nevents: 1, timeoutNs: 300_000_000).0
            done.signal()
        }
        t.start()
        let end = Date().addingTimeInterval(5)
        while Date() < end, !env.system.lock.withLock({ root.mainThread.blockedInKernel }) { Thread.sleep(forTimeInterval: 0.002) }
        env.system.lock.withLock { child.postSignal(9) }
        #expect(child.isTerminating)
        #expect(done.wait(timeout: .now() + 5) == .success)
        #expect(box.value == 0)
        #expect(!root.isTerminating)
    }

    @Test func spawnFailuresLeaveNoTrace() throws {
        let env = try ProcEnv()
        let root = env.rootKernel!
        let before = env.system.allProcesses.count
        #expect(env.spawn(from: root, path: env.root + "/missing").errno == 2)
        try Data("#!/bin/sh\n".utf8).write(to: URL(fileURLWithPath: env.root + "/script"))
        #expect(env.spawn(from: root, path: env.root + "/script").errno == 8)
        try Data(ProcEnv.machO(cpu: 0x0100_0007)).write(to: URL(fileURLWithPath: env.root + "/x86"))
        #expect(env.spawn(from: root, path: env.root + "/x86").errno == 86)
        try Data(ProcEnv.machO(platform: 1)).write(to: URL(fileURLWithPath: env.root + "/mac"))
        #expect(env.spawn(from: root, path: env.root + "/mac").errno == 86)
        try Data(ProcEnv.machO(platform: 9, subtype: 2)).write(to: URL(fileURLWithPath: env.root + "/arm64e"))
        #expect(env.spawn(from: root, path: env.root + "/arm64e").errno == 86)
        let device = ProcEnv.fat([(0x0100_000C, 0x8000_0002, ProcEnv.machO(platform: 4, subtype: 0x8000_0002)),
                                  (0x0100_000C, 0x8000_000C, ProcEnv.machO(platform: 4, subtype: 0x8000_000C))])
        try Data(device).write(to: URL(fileURLWithPath: env.root + "/powerexperienced"))
        #expect(env.spawn(from: root, path: env.root + "/powerexperienced").errno == 86)
        let device9 = ProcEnv.fat([(0x0100_000C, 2, ProcEnv.machO(platform: 9, subtype: 2))])
        try Data(device9).write(to: URL(fileURLWithPath: env.root + "/fat-arm64e"))
        #expect(env.spawn(from: root, path: env.root + "/fat-arm64e").errno == 86)
        #expect(env.spawn(from: root, path: env.root).errno == 13)
        env.launcher.failNext = 12
        #expect(env.spawn(from: root).errno == 12)
        #expect(env.system.allProcesses.count == before)
        #expect(env.wait4(root, -1).0 == -10)
        let close = SpawnFileAction(type: 1, fd: 77)
        #expect(env.spawn(from: root, fileActions: [close]).errno == 9)
        #expect(env.system.allProcesses.count == before)
    }

    @Test func watchOSSimulatorExecutablesSpawn() throws {
        let env = try ProcEnv()
        let root = env.rootKernel!
        try Data(ProcEnv.machO(platform: 9)).write(to: URL(fileURLWithPath: env.root + "/watch"))
        let thin = env.spawn(from: root, path: env.root + "/watch")
        #expect(thin.errno == 0 && thin.pid > 0)
        let mixed = ProcEnv.fat([(0x0100_000C, 2, ProcEnv.machO(platform: 9, subtype: 2)),
                                 (0x0100_000C, 0, ProcEnv.machO(platform: 9))])
        try Data(mixed).write(to: URL(fileURLWithPath: env.root + "/watch-fat"))
        let fat = env.spawn(from: root, path: env.root + "/watch-fat")
        #expect(fat.errno == 0 && fat.pid > 0)
    }

    @Test func setexecKeepsThePid() throws {
        let env = try ProcEnv()
        let root = env.rootKernel!
        let pid = env.spawn(from: root).pid
        let a = try #require(env.kernel(pid))
        let version = a.pidVersion
        let r = env.spawn(from: a, argv: ["probe", "b", "\(pid)"], flags: 0x40)
        #expect(r.outcome == .imageReplaced)
        #expect(a.isTerminating)
        let b = try #require(env.kernel(pid))
        #expect(b !== a)
        #expect(b.pidVersion != version)
        #expect(env.launcher.launches.last?.request.argv == ["probe", "b", "\(pid)"])
        #expect(env.bsd(b, 20) == Int64(pid))
        #expect(env.bsd(b, 39) == 100)
        #expect(env.svc(a, 20).0 == .imageReplaced)
        #expect(env.exits.isEmpty)
        #expect(env.svc(b, 1, [5]).0 == .exit(status: 5))
        #expect(env.wait4(root, pid) == (Int64(pid), 5 << 8))
        let pid2 = env.spawn(from: root).pid
        let c = try #require(env.kernel(pid2))
        env.putString(c, env.root + "/nope", at: At.path)
        #expect(env.bsd(c, 59, [At.path, 0, 0]) == -2)
        #expect(!c.isTerminating && env.kernel(pid2) === c)
        env.putString(c, env.exe, at: At.path)
        #expect(env.svc(c, 59, [At.path, 0, 0]).0 == .imageReplaced)
        #expect(env.kernel(pid2) !== c)
    }

    @Test func orphansGoToInit() throws {
        let env = try ProcEnv()
        let root = env.rootKernel!
        let mid = env.spawn(from: root).pid
        let m = try #require(env.kernel(mid))
        let leaf = env.spawn(from: m).pid
        let l = try #require(env.kernel(leaf))
        #expect(env.bsd(l, 39) == Int64(mid))
        #expect(env.svc(m, 1, [0]).0 == .exit(status: 0))
        #expect(env.bsd(l, 39) == 1)
        #expect(env.svc(l, 1, [0]).0 == .exit(status: 0))
        #expect(env.system.process(pid: leaf) == nil)
        #expect(env.wait4(root, mid).0 == Int64(mid))
    }

    @Test func groupsAndSessions() throws {
        let env = try ProcEnv()
        let root = env.rootKernel!
        let pid = env.spawn(from: root).pid
        let c = try #require(env.kernel(pid))
        #expect(env.bsd(root, 82, [UInt64(pid), 0]) == -13)
        #expect(env.bsd(c, 82, [0, 0]) == 0)
        #expect(env.bsd(c, 81) == Int64(pid))
        #expect(env.bsd(c, 147) == -1)
        let pid2 = env.spawn(from: root).pid
        let c2 = try #require(env.kernel(pid2))
        #expect(env.bsd(c2, 147) == Int64(pid2))
        #expect(env.bsd(c2, 310, [0]) == Int64(pid2))
        #expect(env.bsd(c2, 82, [0, 100]) == -1)
        let pid3 = env.spawn(from: root, flags: 0x2).pid
        #expect(env.bsd(try #require(env.kernel(pid3)), 81) == Int64(pid3))
        #expect(env.bsd(root, 37, [UInt64(UInt32(bitPattern: -pid3)), 15, 1]) == 0)
        #expect(env.kernel(pid3) == nil)
        #expect(env.bsd(root, 37, [UInt64(UInt32(bitPattern: -4242)), 15, 1]) == -3)
    }

    @Test func waitidStatus() throws {
        let env = try ProcEnv()
        let root = env.rootKernel!
        let pid = env.spawn(from: root).pid
        let c = try #require(env.kernel(pid))
        #expect(env.svc(c, 1, [0x1234_5678]).0 == .exit(status: 0x78))
        #expect(env.bsd(root, 173, [1, UInt64(pid), At.out, 0x24]) == 0)
        let info = env.read(root, At.out, 104)
        #expect(info.readLE(Int32.self, at: 0) == 20 && info.readLE(Int32.self, at: 8) == 1)
        #expect(info.readLE(Int32.self, at: 12) == pid)
        #expect(info.readLE(UInt32.self, at: 20) == 0x1200_0078)
        #expect(env.system.process(pid: pid) != nil)
        #expect(env.bsd(root, 173, [1, UInt64(pid), At.out, 0x4]) == 0)
        #expect(env.system.process(pid: pid) == nil)
        #expect(env.bsd(root, 173, [1, UInt64(pid), At.out, 0]) == -22)
    }

    @Test func fileActionsAndCloseOnExec() throws {
        let env = try ProcEnv()
        let root = env.rootKernel!
        try Data("abc".utf8).write(to: URL(fileURLWithPath: env.root + "/f"))
        env.putString(root, env.root + "/f", at: At.out)
        let fd = Int32(env.bsd(root, 5, [At.out, 0, 0]))
        let cloexec = Int32(env.bsd(root, 5, [At.out, 0x100_0000, 0]))
        #expect(fd >= 0 && cloexec > fd)
        let pid = env.spawn(from: root, fileActions: [SpawnFileAction(type: 2, fd: fd, newfd: 9)]).pid
        let c = try #require(env.kernel(pid))
        let open = c.fileSystem.openDescriptors
        #expect(open.contains(fd) && open.contains(9) && !open.contains(cloexec))
        let pid2 = env.spawn(from: root, flags: 0x4000, fileActions: [SpawnFileAction(type: 2, fd: fd, newfd: 9)]).pid
        let c2 = try #require(env.kernel(pid2))
        #expect(c2.fileSystem.openDescriptors == [9])
        #expect(try c2.fileSystem.read(9, count: 3) == Array("abc".utf8))
    }

    @Test func procInfo() throws {
        let env = try ProcEnv()
        let root = env.rootKernel!
        let pid = env.spawn(from: root).pid
        #expect(env.bsd(root, 336, [1, 1, 0, 0, 0, 0]) == Int64((3 + 20) * 4))
        let n = env.bsd(root, 336, [1, 1, 0, 0, At.out, 256])
        #expect(n == 12)
        let pids = env.read(root, At.out, 12)
        #expect([0, 4, 8].map { pids.readLE(Int32.self, at: $0) } == [1, 100, pid])
        #expect(env.bsd(root, 336, [1, 6, 100, 0, At.out, 256]) == 4)
        #expect(env.bsd(root, 336, [2, UInt64(pid), 3, 0, At.out, 136]) == 136)
        let info = env.read(root, At.out, 136)
        #expect(info.readLE(Int32.self, at: 12) == pid && info.readLE(Int32.self, at: 16) == 100)
        #expect(String(decoding: info[48..<53], as: UTF8.self) == "probe")
        #expect(info.readLE(UInt32.self, at: 0) & 0x10 != 0)
        #expect(env.bsd(root, 336, [2, UInt64(pid), 3, 0, At.out, 100]) == -12)
        #expect(env.bsd(root, 336, [2, 4242, 3, 0, At.out, 136]) == -3)
        let version = UInt64(try #require(env.kernel(pid)).pidVersion)
        #expect(env.bsd(root, 545, [2, UInt64(pid), 13, 0x1, version, 0, At.out, 64]) == 64)
        #expect(env.bsd(root, 545, [2, UInt64(pid), 13, 0x1, version + 1, 0, At.out, 64]) == -3)
        #expect(env.bsd(root, 336, [2, UInt64(pid), 11, 0, At.out, 1024]) == 0)
        #expect(String(decoding: env.read(root, At.out, 1024).prefix { $0 != 0 }, as: UTF8.self) == env.exe)
        let c = try #require(env.kernel(pid))
        let uuid: [UInt8] = Array(0x10...0x1F)
        c.executableUUID = uuid
        #expect(env.bsd(root, 336, [2, UInt64(pid), 17, 0, At.out, 56]) == 56)
        #expect(env.read(root, At.out + 32, 4).readLE(UInt32.self, at: 0) == c.pidVersion)
        #expect(env.read(root, At.out, 16) == uuid)
        #expect(env.bsd(root, 336, [2, UInt64(pid), 18, 0, At.out, 192]) == 192)
        #expect(env.read(root, At.out + 136, 16) == uuid)
        _ = env.svc(c, 1, [9])
        #expect(env.bsd(root, 336, [2, UInt64(pid), 17, 1, At.out, 56]) == 56)
        #expect(env.read(root, At.out, 16) == uuid)
        #expect(env.bsd(root, 336, [2, UInt64(pid), 21, UInt64(NoteProc.exitStatus), At.out, 4]) == 4)
        #expect(env.u32(root, At.out) == 9 << 8)
        env.put(root, le32(1) + le32(14) + le32(1) + le32(UInt32(bitPattern: pid)), at: At.out + 0x800)
        env.put(root, le64(648), at: At.out + 0x900)
        #expect(env.bsd(root, 202, [At.out + 0x800, 4, At.out, At.out + 0x900, 0, 0]) == 0)
        let kp = env.read(root, At.out, 648)
        #expect(kp.readLE(Int32.self, at: 40) == pid && kp.readLE(Int32.self, at: 560) == 100)
        #expect(String(decoding: kp[243..<248], as: UTF8.self) == "probe")
        env.put(root, le32(1) + le32(14) + le32(1) + le32(4242), at: At.out + 0x800)
        env.put(root, le64(648), at: At.out + 0x900)
        #expect(env.bsd(root, 202, [At.out + 0x800, 4, At.out, At.out + 0x900, 0, 0]) == 0)
        #expect(env.read(root, At.out + 0x900, 8).readLE(UInt64.self, at: 0) == 0)
        #expect(env.bsd(root, 336, [9, UInt64(pid), 0, 0, At.out, 0]) == 0)
        let ru = env.read(root, At.out, 96)
        let start = ru.readLE(UInt64.self, at: 80), end = ru.readLE(UInt64.self, at: 88)
        #expect(start != 0 && end >= start)
        #expect(Array(ru[0..<16]) == uuid)
        #expect(env.bsd(root, 336, [2, UInt64(pid), 25, 0, At.out, 24]) == -2)
        #expect(env.bsd(root, 336, [2, UInt64(pid), 24, 0, At.out, 40]) == -2)
        #expect(env.bsd(root, 336, [2, UInt64(pid), 25, 0, At.out, 16]) == -12)
        let pid2 = env.spawn(from: root).pid
        let c2 = try #require(env.kernel(pid2))
        #expect(env.bsd(c2, 336, [8, UInt64(pid2), 1, 0x3, 0, 0]) == 0)
        #expect(env.bsd(root, 336, [8, UInt64(pid2), 3, 0, 0, 0]) == 0x3)
        #expect(env.bsd(root, 336, [7, UInt64(pid2), 0, 0, 0, 0]) == 9)
        #expect(c2.isTerminating)
        #expect(env.bsd(root, 336, [7, 100, 0, 0, 0, 0]) == -1)
    }

    @Test func readinessOfAPipeAcrossProcesses() throws {
        let env = try ProcEnv()
        let root = env.rootKernel!
        let before = Set(root.fileSystem.openDescriptors)
        let (_, f) = env.svc(root, 42)
        #expect(!f.carry)
        let fds = Set(root.fileSystem.openDescriptors).subtracting(before)
        #expect(fds.count == 2)
        let r = Int32(truncatingIfNeeded: f.x[0])
        let w = try #require(fds.first { $0 != r })
        let pid = env.spawn(from: root).pid
        let child = try #require(env.kernel(pid))
        let kq = Int32(env.bsd(root, 362))
        let read = ProcEnv.kevent64(ident: UInt64(r), filter: -1, flags: 0x1)
        let write = ProcEnv.kevent64(ident: UInt64(w), filter: -2, flags: 0x1 | 0x8)
        #expect(env.kevent64(root, kq: kq, changes: [read, write], nevents: 0).0 == 0)
        #expect(env.kevent64(root, kq: kq, changes: [], nevents: 4).0 == 0)
        env.putString(child, "hi", at: At.out)
        #expect(env.bsd(child, 4, [UInt64(w), At.out, 2]) == 2)
        let (n, events) = env.kevent64(root, kq: kq, changes: [], nevents: 4)
        #expect(n == 1 && events.first?.ident == UInt64(r) && events.first?.data == 2)
        #expect(env.svc(child, 1, [0]).0 == .exit(status: 0))
        #expect(env.bsd(root, 6, [UInt64(w)]) == 0)
        _ = env.bsd(root, 3, [UInt64(r), At.out, 16])
        let (n2, events2) = env.kevent64(root, kq: kq, changes: [], nevents: 4)
        #expect(n2 == 1 && (events2.first?.flags ?? 0) & 0x8000 != 0)
        #expect(env.bsd(root, 6, [UInt64(r)]) == 0)
        #expect(env.kevent64(root, kq: kq, changes: [], nevents: 4).0 == 0)
        #expect(env.kevent64(root, kq: kq, changes: [ProcEnv.kevent64(ident: UInt64(r), filter: -1, flags: 0x2)],
                             nevents: 1).1.first?.data == 2)
        let pid2 = env.spawn(from: root).pid
        #expect(!(try #require(env.kernel(pid2))).fileSystem.openDescriptors.contains(kq))
        #expect(env.bsd(root, 6, [UInt64(kq)]) == 0)
        #expect(env.kevent64(root, kq: kq, changes: [], nevents: 4).0 == -9)
    }

    @Test func rootWithAnExitedChild() throws {
        let system = DarwinSystem()
        let launcher = FakeLauncher()
        system.launcher = launcher
        let fs = DarwinFileSystem(prefixes: [], console: { _, _ in })
        let root = try system.spawnInitialProcess(
            ProcessImageRequest(executablePath: "/sbin/launchd_sim", hostExecutablePath: "/nonexistent",
                                argv: ["launchd_sim"], envp: ["A=1"]),
            fileSystem: fs, exitedChildEnvironmentKey: "XPC_SIMULATOR_HOLDING_TANK_HACK")
        defer { system.terminateAllProcesses() }
        #expect(root.pid == 100)
        #expect(launcher.launches.count == 1)
        #expect(launcher.launches[0].request.envp == ["A=1", "XPC_SIMULATOR_HOLDING_TANK_HACK=101"])
        let child = try #require(system.process(pid: 101))
        #expect(child.isZombie && child.ppid == 100 && child.pgid == 100)
        #expect(system.kernel(forPID: 101) == nil)
        let space = GuestAddressSpace(backing: FakePhysicalBacking())
        let scratch: UInt64 = 0x1_0000_0000
        _ = try space.mapAnonymous(at: scratch, size: 0x4000, protection: .readWrite, hint: nil)
        try system.lock.withLock { try space.write(va: scratch, bytes: [0xEE, 0xEE, 0xEE, 0xEE]) }
        var f = TrapFrame()
        f.kind = TrapFrame.Kind.svc.rawValue
        f.x[16] = 7
        f.x[0] = 101
        f.x[1] = scratch
        f.x[2] = 1
        #expect(root.handle(&f, memory: space) == .resume)
        #expect(!f.carry && f.x[0] == 101)
        #expect(try system.lock.withLock { try space.read(va: scratch, count: 4) } == [0, 0, 0, 0])
        #expect(system.process(pid: 101) == nil)
        let other = DarwinSystem()
        other.launcher = launcher
        _ = try other.spawnInitialProcess(
            ProcessImageRequest(executablePath: "/x", hostExecutablePath: "/nonexistent", argv: [], envp: []),
            fileSystem: DarwinFileSystem(prefixes: [], console: { _, _ in }))
        defer { other.terminateAllProcesses() }
        #expect(other.allProcesses.map(\.pid) == [100])
    }

    @Test func oneProcessMachineIsUnchanged() throws {
        let env = try Env()
        #expect(env.svc(39).1.x[0] == 1)
        #expect(env.svc(336, [2, 100, 13, 0, Env.scratch, 64]).1.x[0] == 45)
        guard case .unimplemented = env.svc(244, [0, 0, 0, 0, 0]).0 else { Issue.record("spawn"); return }
        #expect(env.kernel.system.allProcesses.isEmpty)
    }
}
