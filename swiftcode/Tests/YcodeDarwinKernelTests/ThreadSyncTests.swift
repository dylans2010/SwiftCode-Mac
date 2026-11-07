import Foundation
import Testing
import YcodeDarwinABI
@testable import YcodeDarwinKernel

@Suite(.serialized) struct ThreadSyncTests {
    static let noErrno: UInt64 = 0x0100_0000
    func errno(_ v: UInt64) -> Int64 { -Int64(bitPattern: v) }

    @Test func createSetsTheExactRegisterState() throws {
        let t = try T2Env()
        let region = t.map(0x2_0000)
        let pthread = region + 0x1_0000, stack = region + 0x1_0000
        let flags: UInt64 = 0x0100_0000 | 0x2000_0000
        let (o, f) = t.svc(360, [0x5000, 0x6000, stack, pthread, flags])
        #expect(o == .resume && !f.carry && f.x[0] == pthread)
        #expect(t.host.starts.isEmpty)
        let ctx = try #require(t.kernel.liveThreads.first { $0.kind == .pthread })
        #expect(ctx.portName & 3 == 3 && ctx.portName != 0x203)
        #expect(t.u64(pthread + 224 + 24) == UInt64(ctx.portName))
        #expect(t.kernel.resumeSuspendedThread(port: ctx.portName))
        let s = try #require(t.host.starts.first)
        #expect(s.context === ctx)
        #expect(s.state.pc == T2Env.threadStart && s.state.sp == stack && s.state.tpidrro == pthread + 224)
        #expect(Array(s.state.x[0..<6]) == [pthread, UInt64(ctx.portName), 0x5000, 0x6000, stack, 0x1100_0000])
        #expect(s.state.x[6...].allSatisfy { $0 == 0 } && s.state.tpidr == 0)
        let frame = s.state.frame
        #expect(frame.elr == T2Env.threadStart && frame.spEL0 == stack && frame.spsr == 0)
        #expect(t.x0(372) == 1)
        #expect(t.x0(372, context: ctx) == ctx.threadID && ctx.threadID > 1)
        let (other, _) = t.createThread()
        #expect(other.threadID != ctx.threadID && other.portName != ctx.portName)
        #expect(t.kernel.thread(port: other.portName) === other)
    }

    @Test func createErrors() throws {
        let unregistered = try T2Env(register: false)
        let (_, a) = unregistered.svc(360, [0x5000, 0, Env.scratch + 0x8000, Env.scratch + 0x8000, 0x0100_0000])
        #expect(a.carry && a.x[0] == 22)
        let t = try T2Env()
        let region = t.map(0x2_0000)
        let p = region + 0x1_0000
        #expect(t.svc(360, [0x5000, 0, p, p, 0]).1.x[0] == 22)
        #expect(t.svc(360, [0x5000, 0, p, p, 0x0900_0000]).1.x[0] == 22)
        #expect(!t.svc(360, [0x5000, 0, p, p, 0x0900_00FF | 0x1000]).1.carry)
        t.host.limit = t.host.starts.count
        let before = t.kernel.liveThreads.count
        let (_, e) = t.svc(360, [0x5000, 0, p, p, 0x0100_0000])
        #expect(e.carry && e.x[0] == 35)
        #expect(t.kernel.liveThreads.count == before)
        t.kernel.threadHost = nil
        #expect(t.svc(360, [0x5000, 0, p, p, 0x0100_0000]).1.x[0] == 35)
    }

    @Test func terminateFreesTheStackAndThePort() throws {
        let t = try T2Env()
        let (ctx, _) = t.createThread()
        let stack = t.map(0x8000)
        #expect(t.isMapped(stack))
        let (o, _) = t.svc(361, [stack, 0x8000, UInt64(ctx.portName), 0], context: ctx)
        #expect(o == .threadExit)
        #expect(!t.isMapped(stack))
        #expect(t.kernel.thread(port: ctx.portName) == nil && !ctx.isAlive)
        #expect(t.svc(328, [UInt64(ctx.portName), 0]).1.x[0] == 3)
    }

    @Test func joinGateWakesTheJoinerAfterTheThreadIsGone() throws {
        let t = try T2Env()
        let (ctx, _) = t.createThread()
        let gate = Env.scratch + 0x100
        t.put32(ctx.portName, at: gate)
        let join = t.spawn { t.svc(515, [2 | Self.noErrno, gate, UInt64(ctx.portName), 0]).1.x[0] }
        #expect(t.eventually { t.blocked(t.main) })
        let (o, _) = t.svc(361, [0, 0, UInt64(ctx.portName), gate], context: ctx)
        #expect(o == .threadExit)
        #expect(join() == 0)
        #expect(t.u32(gate) == ctx.portName & ~3)
        #expect(t.x0(515, [2 | Self.noErrno, gate, UInt64(ctx.portName), 0]) == 0)
    }

    @Test func semaphoreFormSignalsAtExit() throws {
        let t = try T2Env()
        t.svc(0x7963_2003, [0x103, Env.scratch, 0, 0])
        let sem = t.u32(Env.scratch)
        let (ctx, _) = t.createThread()
        #expect(t.svc(361, [0, 0, UInt64(ctx.portName), UInt64(sem)], context: ctx).0 == .threadExit)
        #expect(t.kernel.semaphore(named: sem)?.count == 1)
    }

    @Test func mainThreadExitDoesNotEndTheProcess() throws {
        let t = try T2Env()
        let (ctx, _) = t.createThread()
        let mainStack = t.map(0x1_0000)
        #expect(t.svc(361, [mainStack, 0x1_0000, 0x203, 0]).0 == .threadExit)
        #expect(t.isMapped(mainStack))
        #expect(t.kernel.lock.withLock { t.space.region(containing: mainStack)?.protection } == [])
        #expect(t.svc(361, [0, 0, UInt64(ctx.portName), 0], context: ctx).0 == .exit(status: 0))
    }

    @Test func pthreadKillToAnotherThreadIsDropped() throws {
        let t = try T2Env()
        let (ctx, _) = t.createThread()
        let (o, f) = t.svc(328, [UInt64(ctx.portName), 15])
        #expect(o == .resume && !f.carry)
        #expect(t.env.sink.lines.contains { $0.contains("no cross-thread signal delivery") })
        #expect(t.svc(328, [0x9993, 15]).1.x[0] == 3)
    }

    @Test func waitAndWakeAcrossThreads() throws {
        let t = try T2Env()
        let w = Env.scratch + 0x200
        t.put32(0, at: w)
        let threads = (0..<3).map { _ in t.createThread().0 }
        let waits = threads.map { c in t.spawn { t.svc(515, [1 | Self.noErrno, w, 0, 0], context: c).1.x[0] } }
        #expect(t.eventually { threads.allSatisfy { t.blocked($0) } })
        #expect(t.x0(516, [1 | Self.noErrno, w, 0]) == 0)
        let firstDone = t.eventually { threads.filter { t.blocked($0) }.count == 2 }
        #expect(firstDone)
        #expect(t.x0(516, [1 | 0x100 | Self.noErrno, w, 0]) == 0)
        let results = waits.compactMap { $0() }
        #expect(results.count == 3)
        #expect(results.sorted() == [0, 0, 2])
        #expect(errno(t.x0(516, [1 | Self.noErrno, w, 0])) == 2)
    }

    @Test func pingPongLosesNoWakeups() throws {
        let t = try T2Env()
        let w = Env.scratch + 0x300
        t.put32(0, at: w)
        let (other, _) = t.createThread()
        let rounds: UInt32 = 300
        @Sendable func waitFor(_ want: UInt32, _ c: ThreadContext) {
            while true {
                let v = t.u32(w)
                if v == want { return }
                _ = t.svc(515, [1 | Self.noErrno, w, UInt64(v), 0], context: c)
            }
        }
        let peer = t.spawn { () -> Bool in
            for i in 0..<rounds {
                waitFor(2 * i + 1, other)
                t.put32(2 * i + 2, at: w)
                t.svc(516, [1 | 0x100 | Self.noErrno, w, 0], context: other)
            }
            return true
        }
        for i in 0..<rounds {
            t.put32(2 * i + 1, at: w)
            t.svc(516, [1 | 0x100 | Self.noErrno, w, 0])
            waitFor(2 * i + 2, t.main)
        }
        #expect(peer() == true)
        #expect(t.u32(w) == 2 * rounds)
    }

    @Test func timeoutsAndErrors() throws {
        let t = try T2Env()
        let w = Env.scratch + 0x400
        t.put64(0, at: w)
        #expect(errno(t.x0(515, [1 | Self.noErrno, w, 0, 2000])) == 60)
        #expect(errno(t.x0(544, [5 | Self.noErrno, w, 0, 2_000_000, 0])) == 60)
        let soon = MachTimebase.now() + MachTimebase.ticks(fromNanoseconds: 2_000_000)
        #expect(errno(t.x0(544, [1 | 0x0200_0000 | Self.noErrno, w, 0, soon, 0])) == 60)
        let (_, f) = t.svc(515, [1, w, 0, 1000])
        #expect(f.carry && f.x[0] == 60)
        #expect(errno(t.x0(515, [4 | Self.noErrno, w, 0, 1])) == 22)
        #expect(errno(t.x0(515, [1 | 0x100 | Self.noErrno, w, 0, 1])) == 22)
        #expect(errno(t.x0(515, [1 | Self.noErrno, 0, 0, 1])) == 22)
        #expect(errno(t.x0(515, [5 | Self.noErrno, w + 4, 0, 1])) == 22)
        #expect(errno(t.x0(516, [1 | 0x200 | 0x100 | Self.noErrno, w, 0])) == 22)
        #expect(errno(t.x0(516, [2 | 0x200 | Self.noErrno, w, 0])) == 22)
        #expect(errno(t.x0(516, [1 | 0x400 | Self.noErrno, w, 0])) == 22)
        t.put32(0x1234_5670, at: w)
        #expect(errno(t.x0(515, [2 | Self.noErrno, w, 0x1234_5670, 1000])) == 105)
        t.put32(0xFFFF_FFFC, at: w)
        #expect(errno(t.x0(515, [2 | Self.noErrno, w, 0xFFFF_FFFC, 1000])) == 60)
        t.put32(0x200, at: w)
        #expect(errno(t.x0(515, [2 | Self.noErrno, w, 0x200, 1000])) == 11)
        #expect(t.x0(515, [1 | Self.noErrno, w, 9, 0]) == 0)
    }

    @Test func opcodeMismatchWakeThreadAndOwnerRule() throws {
        let t = try T2Env()
        let w = Env.scratch + 0x500
        t.put64(0, at: w)
        let (a, _) = t.createThread()
        let (b, _) = t.createThread()
        let wa = t.spawn { t.svc(515, [1 | Self.noErrno, w, 0, 0], context: a).1.x[0] }
        #expect(t.eventually { t.blocked(a) })
        #expect(errno(t.x0(515, [5 | Self.noErrno, w, 0, 1000])) == 33)
        #expect(errno(t.x0(516, [5 | Self.noErrno, w, 0])) == 33)
        #expect(errno(t.x0(516, [1 | 0x200 | Self.noErrno, w, UInt64(b.portName)])) == 37)
        #expect(errno(t.x0(516, [1 | 0x200 | Self.noErrno, w, 0x203])) == 3)
        #expect(t.x0(516, [1 | 0x200 | Self.noErrno, w, UInt64(a.portName)]) == 0)
        #expect(wa() == 0)

        let lockWord = Env.scratch + 0x600
        t.put32(a.portName | 1, at: lockWord)
        let wb = t.spawn { t.svc(515, [2 | Self.noErrno, lockWord, UInt64(a.portName | 1), 0], context: b).1.x[0] }
        #expect(t.eventually { t.blocked(b) })
        #expect(t.x0(516, [2 | Self.noErrno, lockWord, 0]) == 0)
        Thread.sleep(forTimeInterval: 0.02)
        #expect(t.blocked(b))
        #expect(t.x0(516, [2 | Self.noErrno, lockWord, 0], context: a) == 0)
        #expect(wb() == 0)
        let wb2 = t.spawn { t.svc(515, [2 | Self.noErrno, lockWord, UInt64(a.portName | 1), 0], context: b).1.x[0] }
        #expect(t.eventually { t.blocked(b) })
        #expect(t.x0(516, [2 | 0x400 | Self.noErrno, lockWord, 0]) == 0)
        #expect(wb2() == 0)
    }

    func semaphore(_ t: T2Env, _ value: UInt64 = 0, at slot: UInt64 = 0) -> UInt64 {
        t.svc(0x7963_2003, [0x103, Env.scratch + 0x700 + slot, 0, value])
        return UInt64(t.u32(Env.scratch + 0x700 + slot))
    }

    @Test func semaphoreWaitBlocksUntilSignalled() throws {
        let t = try T2Env()
        let s = semaphore(t)
        let (a, _) = t.createThread()
        let (b, _) = t.createThread()
        let wa = t.spawn { t.x0(t.mach(-36), [s], context: a) }
        let wb = t.spawn { t.x0(t.mach(-36), [s], context: b) }
        #expect(t.eventually { t.blocked(a) && t.blocked(b) })
        #expect(t.x0(t.mach(-35), [s, UInt64(b.portName)]) == 0)
        #expect(wb() == 0)
        #expect(t.blocked(a))
        #expect(t.x0(t.mach(-35), [s, UInt64(b.portName)]) == 24)
        #expect(t.x0(t.mach(-35), [s, 0x9993]) == 4)
        #expect(t.x0(t.mach(-33), [s]) == 0)
        #expect(wa() == 0)
        #expect(t.kernel.semaphore(named: UInt32(s))?.count == 0)
    }

    @Test func semaphoreSignalAllDestroyAndTimedWait() throws {
        let t = try T2Env()
        let s = semaphore(t)
        let threads = (0..<3).map { _ in t.createThread().0 }
        let waits = threads.map { c in t.spawn { t.x0(t.mach(-36), [s], context: c) } }
        #expect(t.eventually { threads.allSatisfy { t.blocked($0) } })
        #expect(t.x0(t.mach(-34), [s]) == 0)
        #expect(waits.compactMap { $0() } == [0, 0, 0])
        #expect(t.kernel.semaphore(named: UInt32(s))?.count == 0)
        #expect(t.x0(t.mach(-38), [s, 0, 3_000_000]) == 49)
        let tw = t.spawn { t.x0(t.mach(-38), [s, 5, 0], context: threads[0]) }
        #expect(t.eventually { t.blocked(threads[0]) })
        #expect(t.x0(t.mach(-33), [s]) == 0)
        #expect(tw() == 0)
        let wd = t.spawn { t.x0(t.mach(-36), [s], context: threads[1]) }
        #expect(t.eventually { t.blocked(threads[1]) })
        #expect(t.x0(0x7963_2004, [0x103, s]) == 0)
        #expect(wd() == 37)
    }

    @Test func waitSignalIsAtomic() throws {
        let t = try T2Env()
        let w = semaphore(t, 0, at: 0), s = semaphore(t, 0, at: 4)
        let (a, _) = t.createThread()
        let wa = t.spawn { t.x0(t.mach(-37), [w, s], context: a) }
        #expect(t.x0(t.mach(-36), [s]) == 0)
        #expect(t.x0(t.mach(-33), [w]) == 0)
        #expect(wa() == 0)
        #expect(t.x0(t.mach(-39), [w, s, 0, 0]) == 49)
        #expect(t.kernel.semaphore(named: UInt32(s))?.count == 1)
    }

    @Test func semwaitSignalAndThreadSwitch() throws {
        let t = try T2Env()
        let s = semaphore(t)
        let (a, _) = t.createThread()
        let wa = t.spawn { t.svc(334, [s, 0, 0, 0, 0, 0], context: a).1 }
        #expect(t.eventually { t.blocked(a) })
        t.svc(t.mach(-33), [s])
        let f = try #require(wa())
        #expect(!f.carry && f.x[0] == 0)
        #expect(t.x0(t.mach(-61), [0, 0, 0]) == 0)
        #expect(t.x0(t.mach(-61), [0, 2, 1]) == 0)
        #expect(t.x0(t.mach(-59), [0, 0]) == 0)
        let sleeper = t.spawn { t.svc(334, [0, 0, 0, 0, 0, 0], context: a).0 }
        #expect(t.eventually { t.blocked(a) })
        t.svc(1, [7])
        #expect(sleeper() == .exit(status: 7))
    }
}

@Suite(.serialized) struct SigsuspendTests {
    @Test func blocksWithTheMaskUntilInterrupted() throws {
        let t = try T2Env()
        let (a, _) = t.createThread()
        let wait = t.spawn { t.svc(410, [0x0000_0100 | 0x0001_0000], context: a).1 }
        #expect(t.eventually { t.blocked(a) })
        Thread.sleep(forTimeInterval: 0.02)
        #expect(t.blocked(a))
        #expect(t.kernel.lock.withLock { t.kernel.extended.signalMask } == 0)
        #expect(t.kernel.lock.withLock { t.kernel.lock.interrupt(a) })
        let f = try #require(wait())
        #expect(f.carry && f.x[0] == 4)
        #expect(t.kernel.lock.withLock { t.kernel.extended.signalMask } == 0)
    }

    @Test func maskIsAppliedAndRestored() throws {
        let t = try T2Env()
        let (a, _) = t.createThread()
        let wait = t.spawn { t.svc(111, [0x4], context: a).1 }
        #expect(t.eventually { t.blocked(a) })
        #expect(t.kernel.lock.withLock { t.kernel.extended.signalMask } == 0x4)
        t.kernel.lock.withLock { _ = t.kernel.lock.interrupt(a) }
        #expect(wait()?.x[0] == 4)
        #expect(t.kernel.lock.withLock { t.kernel.extended.signalMask } == 0)
    }

    @Test func processExitWakesIt() throws {
        let t = try T2Env()
        let (a, _) = t.createThread()
        let wait = t.spawn { t.svc(410, [0], context: a).0 }
        #expect(t.eventually { t.blocked(a) })
        #expect(t.svc(1, [3]).0 == .exit(status: 3))
        #expect(wait() == .exit(status: 3))
    }
}
