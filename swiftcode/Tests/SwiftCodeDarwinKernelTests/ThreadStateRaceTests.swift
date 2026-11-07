import Foundation
import Synchronization
import Testing
import SwiftCodeDarwinABI
@testable import SwiftCodeDarwinKernel

@Suite struct ThreadStateRaceTests {
    @Test func threadGetStateWhileTargetsTakeFastPaths() throws {
        let w = SplitWorld()
        let t = try w.add(pid: 610)
        let targets = (0..<2).map { _ in t.kernel.lock.withLock { t.kernel.makeThread(kind: .pthread, pthread: 0) } }
        let ports = targets.map { _ in w.allocate(t) }
        let seconds = 3.0
        let deadline = Date().addingTimeInterval(seconds)
        let stop = Atomic<Bool>(false)

        var targetWaits: [() -> Int?] = []
        for (i, ctx) in targets.enumerated() {
            let port = ports[i]
            let buffer = SplitWorld.scratch + 0x1000 * UInt64(i + 1)
            targetWaits.append(spawnThread(seconds: seconds + 60) {
                var n = 0
                while !stop.load(ordering: .relaxed) {
                    let code = w.kr(t, ctx, -31, [buffer, MachMsgOption.rcvMsg | MachMsgOption.rcvTimeout, 0, 0x200,
                                                  UInt64(port), 0, 0], fast: true)
                    guard code == MachMsgReturn.rcvTimedOut else { return -1 }
                    n += 1
                }
                return n
            })
        }

        let flavor: UInt64 = 6
        var readerWaits: [() -> (ok: Int, running: Int, bad: Int)?] = []
        for r in 0..<3 {
            let ctx = w.thread(t)
            let state = SplitWorld.scratch + 0x10000 + 0x1000 * UInt64(r)
            let count = state + 0x800
            readerWaits.append(spawnThread(seconds: seconds + 60) {
                var ok = 0, running = 0, bad = 0, k = r
                w.put(t, le32(68), at: count)
                while Date() < deadline {
                    k += 1
                    let i = k % targets.count
                    let code = w.kr(t, ctx, Int64(MachIPC.Routine.threadGetState),
                                    [UInt64(targets[i].portName), flavor, state, count], fast: k % 2 == 0)
                    switch code {
                    case MachKern.success:
                        let s = w.read(t, state, 34 * 8)
                        if s.readLE(UInt64.self, at: 16 * 8) == UInt64(bitPattern: -31),
                           s.readLE(UInt64.self, at: 4 * 8) == UInt64(ports[i]) {
                            ok += 1
                        } else {
                            bad += 1
                        }
                    case MachKern.failure:
                        running += 1
                    default:
                        bad += 1
                    }
                }
                return (ok, running, bad)
            })
        }

        var reads = (ok: 0, running: 0, bad: 0)
        for wait in readerWaits {
            let r = wait()
            #expect(r != nil)
            if let r { reads = (reads.ok + r.ok, reads.running + r.running, reads.bad + r.bad) }
        }
        stop.store(true, ordering: .relaxed)
        var traps = 0
        for wait in targetWaits {
            let n = wait()
            #expect(n != nil && n! > 0)
            traps += n ?? 0
        }
        #expect(reads.bad == 0)
        #expect(reads.ok > 0)
        #expect(w.fastCount.load(ordering: .relaxed) >= traps)
        print("thread_get_state race: \(traps) fast traps, \(reads.ok) frames read, \(reads.running) between traps")
    }

    @Test func entryFrameReadUnderL0WhileTargetTakesFastPaths() throws {
        let w = SplitWorld()
        let t = try w.add(pid: 611)
        let ctx = t.kernel.lock.withLock { t.kernel.makeThread(kind: .pthread, pthread: 0) }
        let port = w.allocate(t)
        let stop = Atomic<Bool>(false)
        let target = spawnThread(seconds: 60) {
            var n = 0
            while !stop.load(ordering: .relaxed) {
                _ = w.kr(t, ctx, -31, [SplitWorld.scratch + 0x1000, MachMsgOption.rcvMsg | MachMsgOption.rcvTimeout, 0, 0x200,
                                       UInt64(port), 0, 0], fast: true)
                n += 1
            }
            return n
        }
        var seen = 0, bad = 0
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            t.kernel.lock.withLock {
                for _ in 0..<100 {
                    guard let f = ctx.entryFrame else { continue }
                    if f.x[16] == UInt64(bitPattern: -31), f.x[4] == UInt64(port) { seen += 1 } else { bad += 1 }
                }
            }
        }
        stop.store(true, ordering: .relaxed)
        #expect((target() ?? 0) > 0)
        #expect(seen > 0)
        #expect(bad == 0)
        print("entry frame copies under L0: \(seen) frames read")
    }
}
