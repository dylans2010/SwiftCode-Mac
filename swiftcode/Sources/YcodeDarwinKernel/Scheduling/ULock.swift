import Foundation
import YcodeDarwinABI

final class ULockQueue {
    var opcode: UInt32
    let waiters = WaitQueue()
    var owner: ThreadContext?
    weak var pushedOwner: ThreadContext?

    init(opcode: UInt32) { self.opcode = opcode }
}

extension DarwinKernel {
    enum ULockFlag {
        static let wakeAll: UInt32 = 0x0000_0100
        static let wakeThread: UInt32 = 0x0000_0200
        static let wakeAllowNonOwner: UInt32 = 0x0000_0400
        static let waitWorkqDataContention: UInt32 = 0x0001_0000
        static let waitCancelPoint: UInt32 = 0x0002_0000
        static let waitAdaptiveSpin: UInt32 = 0x0004_0000
        static let noErrno: UInt32 = 0x0100_0000
        static let deadline: UInt32 = 0x0200_0000
        static let waitFlags = waitWorkqDataContention | waitCancelPoint | waitAdaptiveSpin | noErrno | deadline
        static let wakeFlags = wakeAll | wakeThread | wakeAllowNonOwner | noErrno
    }

    static let EINTR: Int32 = 4
    static let EDOM: Int32 = 33
    static let EALREADY: Int32 = 37
    static let EOWNERDEAD: Int32 = 105

    private static let ulockOpcodes: Set<UInt32> = [1, 2, 3, 5, 6]

    private func ulockResult(_ e: Int32, noErrno: Bool) throws -> UInt64 {
        if noErrno { return UInt64(bitPattern: Int64(-e)) }
        throw Failure(errno: e)
    }

    func hostDeadline(machTicks deadline: UInt64) -> UInt64 {
        let now = counter()
        guard deadline > now else { return KernelClock.now() }
        return KernelClock.deadline(afterNanoseconds: nanoseconds(ticks: deadline - now))
    }

    func nanoseconds(ticks: UInt64) -> UInt64 {
        let f = max(counterFrequency, 1)
        let (hi, lo) = ticks.multipliedFullWidth(by: 1_000_000_000)
        guard hi < f else { return UInt64.max }
        return f.dividingFullWidth((hi, lo)).quotient
    }

    func ulockWait(_ n: Int, _ a: [UInt64], _ call: inout CallText, _ mem: any KernelGuestMemory) throws -> UInt64 {
        try withEvents { try ulockWaitLocked(n, a, &call, mem) }
    }

    private func ulockWaitLocked(_ n: Int, _ a: [UInt64], _ call: inout CallText, _ mem: any KernelGuestMemory) throws -> UInt64 {
        eventLock?.checkHeld("the ulock queues")
        let operation = UInt32(truncatingIfNeeded: a[0])
        let op = operation & ULock.opMask
        let flags = operation & ~ULock.opMask
        let noErrno = flags & ULockFlag.noErrno != 0
        let isWait2 = n == BSD2.ulockWait2
        let addr = a[1]
        call.set("\(isWait2 ? "__ulock_wait2" : "__ulock_wait")(op=\(hx(operation)), addr=\(hx(addr)), "
            + "value=\(hx(a[2])), timeout=\(isWait2 ? "\(a[3]) ns" : "\(UInt32(truncatingIfNeeded: a[3])) us"))")
        guard flags & ~ULockFlag.waitFlags == 0, Self.ulockOpcodes.contains(op) else {
            return try ulockResult(Errno.EINVAL, noErrno: noErrno)
        }
        let wide = op == ULock.compareAndWait64 || op == ULock.compareAndWait64Shared
        guard addr != 0, addr % (wide ? 8 : 4) == 0 else { return try ulockResult(Errno.EINVAL, noErrno: noErrno) }
        if let q = ulocks[addr], !q.waiters.isEmpty, q.opcode != op {
            return try ulockResult(Self.EDOM, noErrno: noErrno)
        }
        let word: UInt64
        do {
            word = wide ? try readU64(addr, mem) : UInt64(try mem.read(va: addr, count: 4).readLE(UInt32.self, at: 0))
        } catch {
            return try ulockResult(Errno.EFAULT, noErrno: noErrno)
        }
        if word != a[2] {
            let waiting = ulocks[addr]?.waiters.count ?? 0
            call += " [value changed: \(hx(word)); \(waiting) waiting]"
            return UInt64(waiting)
        }
        var owner: ThreadContext?
        if op == ULock.unfairLock {
            let name = UInt32(truncatingIfNeeded: a[2]) | 3
            if name != UInt32.max {
                guard let t = threadsByPort[name] else {
                    call += " [owner \(hx(name)) is not a thread]"
                    return try ulockResult(Self.EOWNERDEAD, noErrno: noErrno)
                }
                guard t !== current else {
                    call += " [owner is the caller]"
                    return try ulockResult(Self.EDEADLK, noErrno: noErrno)
                }
                owner = t
            }
        }
        var deadline: UInt64?
        if isWait2 {
            if a[3] != 0 {
                deadline = flags & ULockFlag.deadline != 0 ? hostDeadline(machTicks: a[3])
                    : KernelClock.deadline(afterNanoseconds: a[3])
            }
        } else {
            let us = UInt64(UInt32(truncatingIfNeeded: a[3]))
            if us != 0 { deadline = KernelClock.deadline(afterNanoseconds: us &* 1000) }
        }
        let queue = ulocks[addr] ?? ULockQueue(opcode: op)
        queue.opcode = op
        if op == ULock.unfairLock { queue.owner = owner }
        ulocks[addr] = queue
        let inherit = SchedPolicy.qosEnabled && op == ULock.unfairLock
        let result = queue.waiters.wait(on: eventWaitLock, deadline: deadline, tag: 0,
                                        beforeSleeping: inherit ? { [unowned self] in self.refreshULockPush(addr: addr, queue: queue) } : nil)
        if inherit { refreshULockPush(addr: addr, queue: queue) }
        let remaining = queue.waiters.count
        if remaining == 0, ulocks[addr] === queue { ulocks[addr] = nil }
        switch result {
        case .woken:
            call += " [woken; \(remaining) waiting]"
            return UInt64(remaining)
        case .timedOut:
            call += " [timed out]"
            return try ulockResult(Self.ETIMEDOUT, noErrno: noErrno)
        case .interrupted:
            call += " [interrupted]"
            return try ulockResult(Self.EINTR, noErrno: noErrno)
        }
    }

    func ulockWake(_ a: [UInt64], _ call: inout CallText) throws -> UInt64 {
        let operation = UInt32(truncatingIfNeeded: a[0])
        call.set("__ulock_wake(op=\(hx(operation)), addr=\(hx(a[1])), wake_value=\(hx(a[2])))")
        let noErrno = operation & ULockFlag.noErrno != 0
        let (e, woke) = ulockWakeCore(operation: operation, addr: a[1], wakeValue: a[2])
        if let e {
            call += " [\(Errno.name(e))]"
            return try ulockResult(e, noErrno: noErrno)
        }
        call += " [woke \(woke)]"
        return 0
    }

    func ulockWakeCore(operation: UInt32, addr: UInt64, wakeValue: UInt64) -> (Int32?, Int) {
        withEvents { ulockWakeCoreLocked(operation: operation, addr: addr, wakeValue: wakeValue) }
    }

    private func ulockWakeCoreLocked(operation: UInt32, addr: UInt64, wakeValue: UInt64) -> (Int32?, Int) {
        eventLock?.checkHeld("the ulock queues")
        let op = operation & ULock.opMask
        let flags = operation & ~ULock.opMask
        guard flags & ~ULockFlag.wakeFlags == 0, Self.ulockOpcodes.contains(op), addr != 0 else { return (Errno.EINVAL, 0) }
        let wakeThread = flags & ULockFlag.wakeThread != 0
        let wakeAll = flags & ULockFlag.wakeAll != 0
        let nonOwner = flags & ULockFlag.wakeAllowNonOwner != 0
        if wakeThread && (wakeAll || op == ULock.unfairLock) { return (Errno.EINVAL, 0) }
        if nonOwner && op != ULock.unfairLock { return (Errno.EINVAL, 0) }
        var target: ThreadContext?
        if wakeThread {
            guard let t = threadsByPort[UInt32(truncatingIfNeeded: wakeValue)], t !== current else { return (Errno.ESRCH, 0) }
            target = t
        }
        guard let queue = ulocks[addr], !queue.waiters.isEmpty else { return (Errno.ENOENT, 0) }
        guard queue.opcode == op else { return (Self.EDOM, 0) }
        if let target {
            let n = queue.waiters.wake(limit: 1) { c, _ in c === target }
            return n == 1 ? (nil, 1) : (Self.EALREADY, 0)
        }
        if wakeAll {
            let n = queue.waiters.wakeAll()
            if op == ULock.unfairLock { refreshULockPush(addr: addr, queue: queue) }
            return (nil, n)
        }
        if op == ULock.unfairLock && !nonOwner, let owner = queue.owner, owner.isAlive, owner !== current {
            return (nil, 0)
        }
        var woken: ThreadContext?
        let n = queue.waiters.wake(limit: 1) { c, _ in woken = c; return true }
        if op == ULock.unfairLock {
            queue.owner = woken
            refreshULockPush(addr: addr, queue: queue)
        }
        return (nil, n)
    }
}
