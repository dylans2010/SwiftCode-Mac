import Foundation
import Testing
import YcodeDarwinABI
@testable import YcodeDarwinKernel

@Suite struct MachIPCNotificationTests {
    let S = MachPortType.send, R = MachPortType.receive, SO = MachPortType.sendOnce, DN = MachPortType.deadName

    func note(_ env: IPCEnv, _ port: UInt32) -> Received? {
        let (code, raw) = env.receive(port, options: MachMsgOption.rcvMsg | MachMsgOption.rcvTimeout | 3 << 24)
        return code == 0 ? Received(raw) : nil
    }

    @Test func sendOnceNotification() throws {
        let env = try IPCEnv()
        let p = env.allocate()
        #expect(env.insertRight(0x7003, p, MachMsgType.makeSendOnce) == 0)
        #expect(env.deallocate(0x7003) == 0)
        let n = try #require(note(env, p))
        #expect(n.id == MachNotify.sendOnce && n.size == 24 && n.bits == 0x1200 && n.local == p && n.remote == 0)
        #expect(n.trailer(12) == 0 && n.trailer(16) == 1)
        #expect((0..<8).allSatisfy { n.trailer(20 + 4 * $0) == 0 })
        #expect(env.ipc.portCounters(p)?.sorights == 0)
        #expect(env.insertRight(0x7003, p, MachMsgType.makeSendOnce) == 0)
        #expect(env.modRefs(0x7003, MachPortRight.sendOnce, -1) == 0)
        #expect(note(env, p)?.id == MachNotify.sendOnce)
        #expect(env.insertRight(0x7103, p, MachMsgType.makeSendOnce) == 0)
        #expect(env.modRefs(p, MachPortRight.receive, -1) == 0)
        #expect(env.deallocate(0x7103) == 0)
    }

    @Test func noSendersImmediateAndArmed() throws {
        let env = try IPCEnv()
        let p = env.allocate(), n = env.allocate()
        #expect(env.requestNotification(p, MachNotify.noSenders, sync: 0, notify: n) == (0, 0))
        let first = try #require(note(env, n))
        #expect(first.id == MachNotify.noSenders && first.u32(32) == 0)
        #expect(env.insertRight(p, p, MachMsgType.makeSend) == 0)
        #expect(env.requestNotification(p, MachNotify.noSenders, sync: 1, notify: n) == (0, 0))
        let (k, previous) = env.requestNotification(p, MachNotify.noSenders, sync: 1, notify: n)
        #expect(k == 0 && env.type(previous) == (0, SO))
        #expect(env.deallocate(previous) == 0)
        #expect(note(env, n)?.id == MachNotify.sendOnce)
        #expect(env.deallocate(p) == 0)
        let fired = try #require(note(env, n))
        #expect(fired.id == MachNotify.noSenders && fired.u32(32) == 1)
        #expect(note(env, n) == nil)
        #expect(env.insertRight(p, p, MachMsgType.makeSend) == 0)
        #expect(env.requestNotification(p, MachNotify.noSenders, sync: 5, notify: n).0 == 0)
        #expect(env.modRefs(p, MachPortRight.receive, -1) == 0)
        #expect(note(env, n)?.id == MachNotify.sendOnce)
    }

    @Test func deadNameAndPortDeleted() throws {
        let env = try IPCEnv()
        let p = env.allocate(), n = env.allocate()
        #expect(env.insertRight(0x7003, p, MachMsgType.makeSendOnce) == 0)
        #expect(env.insertRight(0x7103, p, MachMsgType.makeSendOnce) == 0)
        #expect(env.requestNotification(0x7003, MachNotify.deadName, notify: n) == (0, 0))
        #expect(env.requestNotification(0x7103, MachNotify.deadName, notify: n) == (0, 0))
        #expect(env.type(0x7003) == (0, SO | MachPortType.dnRequest))
        #expect(env.deallocate(0x7103) == 0)
        let deleted = try #require(note(env, n))
        #expect(deleted.id == MachNotify.portDeleted && deleted.size == 36 && deleted.u32(32) == 0x7103)
        #expect(note(env, p)?.id == MachNotify.sendOnce)
        #expect(env.modRefs(p, MachPortRight.receive, -1) == 0)
        let dead = try #require(note(env, n))
        #expect(dead.id == MachNotify.deadName && dead.size == 36 && dead.u32(32) == 0x7003)
        #expect(Array(dead.raw[24..<32]) == machNDRRecord)
        #expect(env.type(0x7003) == (0, DN) && env.urefs(0x7003) == 2)
        #expect(env.requestNotification(0x7003, MachNotify.deadName, notify: n).0 == MachKern.invalidArgument)
    }

    @Test func portDeletedOnMove() throws {
        let env = try IPCEnv()
        let p = env.allocate(), n = env.allocate(), dst = env.allocate()
        #expect(env.insertRight(0x7003, p, MachMsgType.makeSendOnce) == 0)
        #expect(env.requestNotification(0x7003, MachNotify.deadName, notify: n).0 == 0)
        #expect(env.send(TestMessage(remote: dst, remoteDisposition: MachMsgType.makeSend,
                                     descriptors: [TestMessage.port(0x7003, MachMsgType.moveSendOnce)]).bytes) == 0)
        let deleted = try #require(note(env, n))
        #expect(deleted.id == MachNotify.portDeleted && deleted.u32(32) == 0x7003)
    }

    @Test func portDestroyedReturnsTheReceiveRight() throws {
        let env = try IPCEnv()
        let p = env.allocate(), n = env.allocate()
        #expect(env.insertRight(p, p, MachMsgType.makeSend) == 0)
        #expect(env.send(TestMessage(remote: p, remoteDisposition: MachMsgType.copySend, id: 11).bytes) == 0)
        #expect(env.requestNotification(p, MachNotify.portDestroyed, sync: 1, notify: n).0 == MachKern.invalidValue)
        #expect(env.requestNotification(p, MachNotify.portDestroyed, notify: n) == (0, 0))
        #expect(env.requestNotification(p, MachNotify.portDestroyed, notify: n).0 == MachKern.failure)
        #expect(env.ipc.portCounters(n)?.sorights == 1)
        #expect(env.modRefs(p, MachPortRight.receive, -1) == 0)
        #expect(env.type(p) == (0, S))
        let destroyed = try #require(note(env, n))
        #expect(destroyed.id == MachNotify.portDestroyed && destroyed.size == 40)
        #expect(destroyed.bits == 0x8000_1200)
        #expect(destroyed.u32(24) == 1 && destroyed.raw[28 + 10] == 16)
        let back = destroyed.u32(28)
        #expect(back == p && env.type(p) == (0, S | R))
        let (code, raw) = env.receive(p)
        #expect(code == 0 && Received(raw).id == 11)
        let srp = UInt32(env.trap(-50))
        #expect(env.requestNotification(srp, MachNotify.portDestroyed, notify: n).0 == MachKern.failure)
    }

    @Test func requestErrors() throws {
        let env = try IPCEnv()
        let p = env.allocate(), n = env.allocate()
        #expect(env.requestNotification(0, MachNotify.deadName, notify: n).0 == MachKern.invalidArgument)
        #expect(env.requestNotification(p, MachNotify.deadName, notify: MachPortName.dead).0
                == MachKern.invalidCapability)
        #expect(env.requestNotification(p, 99, notify: n).0 == MachKern.invalidValue)
        #expect(env.ipc.portCounters(n)?.sorights == 0)
        #expect(env.requestNotification(p, MachNotify.deadName, notify: n, poly: MachMsgType.makeSend).0
                == MachMsgReturn.sendInvalidDest)
        #expect(env.requestNotification(p, MachNotify.deadName, notify: 0x55503).0 == MachKern.invalidName)
        #expect(env.requestNotification(0x103, MachNotify.noSenders, notify: n).0 == MachKern.invalidRight)
        let set = env.allocate(MachPortRight.portSet)
        #expect(env.requestNotification(set, MachNotify.deadName, notify: n).0 == MachKern.invalidRight)
        #expect(env.requestNotification(0x103, MachNotify.sendPossible, sync: 1, notify: n).0 == 0)
        #expect(note(env, n)?.id == MachNotify.sendPossible)
        #expect(env.insertRight(0x7003, n, MachMsgType.makeSendOnce) == 0)
        #expect(env.requestNotification(p, MachNotify.deadName, notify: 0x7003, poly: MachMsgType.moveSendOnce).0 == 0)
        #expect(env.type(0x7003).0 == MachKern.invalidName)
    }

    @Test func portDeathDestroysQueuedMessages() throws {
        let env = try IPCEnv()
        let p = env.allocate(), reply = env.allocate(), x = env.allocate()
        #expect(env.send(TestMessage(remote: p, remoteDisposition: MachMsgType.makeSend, local: reply,
                                     localDisposition: MachMsgType.makeSendOnce,
                                     descriptors: [TestMessage.port(x, MachMsgType.moveReceive)]).bytes) == 0)
        #expect(env.ipc.portCounters(reply)?.sorights == 1)
        #expect(env.modRefs(p, MachPortRight.receive, -1) == 0)
        #expect(note(env, reply)?.id == MachNotify.sendOnce)
        #expect(env.ipc.nameCount == 5)
    }

    @Test func taskPortRequestsUseTheSameRules() throws {
        let env = try IPCEnv()
        let n = env.allocate()
        let t = env.ipc.allocateThreadPort()
        #expect(env.requestNotification(t, MachNotify.deadName, notify: n).0 == 0)
        let context = ThreadContext(threadID: 9, portName: t, vcpuIndex: 2, kind: .pthread)
        #expect(env.modRefs(t, MachPortRight.send, 1) == 0)
        env.ipc.threadTerminated(context)
        let dead = try #require(note(env, n))
        #expect(dead.id == MachNotify.deadName && dead.u32(32) == t)
        #expect(env.type(t) == (0, DN) && env.urefs(t) == 2)
    }

    @Test func sendPossibleDelayedArmedAndFired() throws {
        let env = try IPCEnv()
        let SP = MachPortType.spRequest, DELAYED = MachPortType.spRequestDelayed, DNR = MachPortType.dnRequest
        let n = env.allocate()
        let (_, p) = env.construct(flags: MachPortConstruct.qlimit | MachPortConstruct.insertSendRight, qlimit: 1)
        #expect(env.requestNotification(p, MachNotify.sendPossible, sync: 0, notify: n) == (0, 0))
        #expect(note(env, n) == nil)
        #expect(env.type(p).1 & (DNR | SP | DELAYED) == DNR | SP | DELAYED)
        let (k, previous) = env.requestNotification(p, MachNotify.sendPossible, sync: 0, notify: n)
        #expect(k == 0 && previous != 0 && env.type(previous) == (0, SO))
        #expect(env.deallocate(previous) == 0)
        #expect(note(env, n)?.id == MachNotify.sendOnce)
        #expect(env.send(TestMessage(remote: p, remoteDisposition: MachMsgType.copySend, id: 1).bytes) == 0)
        #expect(env.receive(p).0 == 0)
        #expect(note(env, n) == nil)
        #expect(env.send(TestMessage(remote: p, remoteDisposition: MachMsgType.copySend, id: 2).bytes) == 0)
        let notifySend = MachMsgOption.sendMsg | MachMsgOption.sendTimeout | MachMsgOption.sendNotify
        #expect(env.send(TestMessage(remote: p, remoteDisposition: MachMsgType.copySend, id: 3).bytes,
                         options: notifySend) == MachMsgReturn.sendTimedOut)
        #expect(env.type(p).1 & (SP | DELAYED) == SP)
        #expect(Received(env.receive(p).1).id == 2)
        let fired = try #require(note(env, n))
        #expect(fired.id == MachNotify.sendPossible && fired.size == 36 && fired.u32(32) == p)
        #expect(env.type(p).1 & (DNR | SP) == 0)
        #expect(note(env, n) == nil)
        #expect(env.requestNotification(p, MachNotify.sendPossible, sync: 1, notify: n).0 == 0)
        #expect(note(env, n)?.id == MachNotify.sendPossible)
        #expect(env.send(TestMessage(remote: p, remoteDisposition: MachMsgType.copySend, id: 4).bytes) == 0)
        #expect(env.requestNotification(p, MachNotify.sendPossible, sync: 1, notify: n).0 == 0)
        #expect(note(env, n) == nil && env.type(p).1 & (SP | DELAYED) == SP)
        #expect(env.receive(p).0 == 0)
        #expect(note(env, n)?.id == MachNotify.sendPossible)
        let q = env.allocate()
        #expect(env.insertRight(q, q, MachMsgType.makeSend) == 0)
        #expect(env.requestNotification(q, MachNotify.sendPossible, sync: 0, notify: n).0 == 0)
        #expect(env.modRefs(q, MachPortRight.receive, -1) == 0)
        let dead = try #require(note(env, n))
        #expect(dead.id == MachNotify.deadName && dead.u32(32) == q)
        #expect(env.urefs(q) == 2)
        #expect(env.requestNotification(q, MachNotify.sendPossible, sync: 0, notify: n).0 == 0)
        #expect(note(env, n)?.id == MachNotify.deadName && env.urefs(q) == 3)
        #expect(env.requestNotification(p, MachNotify.sendPossible, sync: 0, notify: n).0 == 0)
        #expect(env.lock.withLock { env.ipc.portDestroy(p) } == 0)
        var ids: [Int32] = []
        while let m = note(env, n) { ids.append(m.id) }
        #expect(ids == [MachNotify.portDeleted], "\(ids)")
    }
}
