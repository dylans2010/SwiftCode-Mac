import Foundation
import Testing
import SwiftCodeDarwinABI
@testable import SwiftCodeDarwinKernel

@Suite struct WorkIntervalTests {
    static let getFlags: UInt64 = 9, join: UInt64 = 5, destroy: UInt64 = 2, notify: UInt64 = 3
    static let create: UInt64 = 1, create2: UInt64 = 4
    let out = TaskWorld.out

    func ctl(_ t: TaskWorld.Task, _ op: UInt64, _ id: UInt64, _ arg: UInt64 = 0, _ len: UInt64 = 0) -> (UInt64, Bool) {
        var f = TrapFrame()
        f.kind = TrapFrame.Kind.svc.rawValue
        f.x[16] = UInt64(WorkIntervalABI.syscall)
        f.x[0] = op
        f.x[1] = id
        f.x[2] = arg
        f.x[3] = len
        _ = t.kernel.handleTrying(&f, context: t.kernel.mainThread, memory: t.space)
        return (f.x[0], f.carry)
    }

    let EINVAL = UInt64(DarwinKernel.Errno.EINVAL), ENOTSUP = UInt64(DarwinKernel.Errno.ENOTSUP)
    let ENOSYS = UInt64(DarwinKernel.Errno.ENOSYS)

    @Test func aGuestJoinsTheHostsWorkgroup() throws {
        let w = TaskWorld()
        let g = try w.add(pid: 100)
        let host = w.system.hostTask
        let flags = WorkIntervalABI.typeCoreAudio | WorkIntervalABI.flagGroup
        let hostName = try host.makeWorkIntervalPort(flags: flags)
        let wi = try #require(host.workInterval(named: hostName))
        #expect(wi.id > 1 && wi.createFlags == flags | WorkIntervalABI.flagJoinable && wi.creatorPID == 0)
        let other = try host.makeWorkIntervalPort(flags: 0)
        #expect(other != hostName && host.workInterval(named: other)?.id != wi.id)
        let name = try host.give(hostName, disposition: MachMsgType.copySend, to: g.ipc)
        #expect(g.ipc.kernelObjectKind(of: name).map { if case .workInterval = $0 { true } else { false } } == true)

        w.put(g, [UInt8](repeating: 0xEE, count: 16), at: out)
        #expect(ctl(g, Self.getFlags, UInt64(name), out, 16) == (0, false))
        let record = w.read(g, out, 16)
        #expect(record.readLE(UInt64.self, at: 0) == 0 && record.readLE(UInt32.self, at: 8) == name
                && record.readLE(UInt32.self, at: 12) == flags | WorkIntervalABI.flagJoinable)
        #expect(ctl(g, Self.getFlags, UInt64(name), 0, 16) == (EINVAL, true))
        #expect(ctl(g, Self.getFlags, UInt64(name), out, 8) == (EINVAL, true))
        #expect(ctl(g, Self.getFlags, 0x103, out, 16) == (EINVAL, true))
        #expect(ctl(g, Self.getFlags, 0, out, 16) == (EINVAL, true))
        #expect(ctl(g, Self.getFlags, 0xDEAD_0103, out, 16) == (EINVAL, true))

        #expect(g.kernel.mainThread.workInterval == nil)
        #expect(ctl(g, Self.join, UInt64(name), out) == (EINVAL, true))
        #expect(ctl(g, Self.join, UInt64(name)) == (0, false))
        #expect(g.kernel.mainThread.workInterval === wi)
        #expect(ctl(g, Self.join, 0x103) == (EINVAL, true))
        #expect(g.kernel.mainThread.workInterval === wi)
        w.put(g, [UInt8](repeating: 0, count: 40), at: out)
        #expect(ctl(g, Self.notify, wi.id, out, 40) == (EINVAL, true))
        #expect(ctl(g, Self.destroy, wi.id + 1) == (EINVAL, true))
        #expect(ctl(g, Self.join, 0) == (0, false))
        #expect(g.kernel.mainThread.workInterval == nil)
        #expect(ctl(g, Self.join, 0) == (0, false))
        #expect(ctl(g, Self.join, UInt64(name)) == (0, false))
        #expect(ctl(g, Self.destroy, wi.id) == (0, false))
        #expect(g.kernel.mainThread.workInterval == nil)

        try host.deallocate(hostName)
        #expect(ctl(g, Self.getFlags, UInt64(name), out, 16) == (0, false))
        #expect(g.ipc.portDeallocate(name) == 0)
        #expect(ctl(g, Self.getFlags, UInt64(name), out, 16) == (EINVAL, true))
    }

    @Test func creationIsNotModeled() throws {
        let w = TaskWorld()
        let g = try w.add(pid: 100)
        w.put(g, [UInt8](repeating: 0, count: 16), at: out)
        #expect(ctl(g, Self.create, 0, out, 16) == (ENOTSUP, true))
        #expect(ctl(g, Self.create2, 0, out, 16) == (ENOSYS, true))
        #expect(ctl(g, 0x0A, 1, out, 16) == (ENOTSUP, true))
    }

    @Test func notifyFromTheCreatingProcess() throws {
        let w = TaskWorld()
        let g = try w.add(pid: 100)
        let (wi, name) = try #require(w.system.lock.withLock { g.ipc.makeWorkIntervalName(flags: 1, creatorPID: 100) })
        #expect(ctl(g, Self.join, UInt64(name)) == (0, false))
        w.put(g, [UInt8](repeating: 0, count: 40), at: out)
        #expect(ctl(g, Self.notify, wi.id, out, 40) == (0, false))
        #expect(ctl(g, Self.notify, wi.id, out, 32) == (EINVAL, true))
        #expect(ctl(g, Self.notify, wi.id, 0, 40) == (EINVAL, true))
    }
}
