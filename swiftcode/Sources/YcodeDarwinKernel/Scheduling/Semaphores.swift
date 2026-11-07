import Foundation
import YcodeDarwinABI

public final class KernelSemaphore: @unchecked Sendable {
    public private(set) var count: Int32
    public private(set) var isDestroyed = false
    let waiters = WaitQueue()

    public init(value: Int32) {
        count = max(0, value)
    }

    public var waiterCount: Int { waiters.count }

    public func signal() {
        if waiters.wake(count: 1) == 0 { count &+= 1 }
    }

    public func signalAll() {
        waiters.wakeAll()
    }

    public func signal(thread: ThreadContext) -> Bool {
        waiters.wake(limit: 1) { c, _ in c === thread } == 1
    }

    public func destroy() {
        isDestroyed = true
        waiters.wakeAll()
    }

    func wait(lock: KernelLock, deadline: UInt64?, beforeSleeping: (() -> Void)? = nil) -> UInt64 {
        if isDestroyed { return DarwinKernel.KernReturn.terminated }
        if count > 0 {
            count -= 1
            beforeSleeping?()
            return DarwinKernel.KernReturn.success
        }
        if let deadline, deadline <= KernelClock.now() {
            beforeSleeping?()
            return DarwinKernel.KernReturn.operationTimedOut
        }
        switch waiters.wait(on: lock, deadline: deadline, tag: 0, beforeSleeping: beforeSleeping) {
        case .woken: return isDestroyed ? DarwinKernel.KernReturn.terminated : DarwinKernel.KernReturn.success
        case .timedOut: return DarwinKernel.KernReturn.operationTimedOut
        case .interrupted: return DarwinKernel.KernReturn.aborted
        }
    }
}

extension DarwinKernel {
    public func semaphore(named name: UInt32) -> KernelSemaphore? {
        machIPC?.semaphore(named: name)
    }

    static let debugSemaphoresProcess = getenv("SWIFTCODE_DEBUG_SEMAPHORES").map { String(cString: $0) }

    func debugSemaphore(_ text: @autoclosure () -> String) {
        guard let want = Self.debugSemaphoresProcess, let comm = processRecord?.comm, comm == want else { return }
        let n = debugSemaphoreLines.add(1, ordering: .relaxed).newValue
        guard n <= 5000 else { return }
        FileHandle.standardError.write(Data("swiftcode-semaphore: pid \(pid) (\(comm)) thread \(current.threadID): \(text())\n".utf8))
    }

    func handleSemaphoreTrap(_ n: Int, _ frame: inout TrapFrame) -> Outcome? {
        guard (Mach.semaphoreTimedwaitSignal...Mach.semaphoreSignal).contains(n) else { return nil }
        let a = frame.x.prefixArray(8)
        func port(_ i: Int) -> UInt32 { UInt32(truncatingIfNeeded: a[i]) }
        var call = CallText(tracing, "")
        func kr(_ value: UInt64, _ extra: String = "") -> Outcome {
            frame.x[0] = value
            trace("trap mach \(n) \(call) -> \(KernReturn.name(value))\(extra)")
            if value != KernReturn.success, Self.debugSemaphoresProcess != nil {
                debugSemaphore("trap \(n) (\(hx(port(0))), \(hx(port(1)))) -> \(KernReturn.name(value))")
            }
            return .resume
        }
        func timeout(_ sec: UInt64, _ nsec: UInt64) -> UInt64 {
            let ns = UInt64(UInt32(truncatingIfNeeded: sec)) &* 1_000_000_000
                &+ UInt64(max(0, Int64(Int32(truncatingIfNeeded: nsec))))
            return KernelClock.deadline(afterNanoseconds: ns)
        }

        switch n {
        case Mach.semaphoreSignal, Mach.semaphoreSignalAll:
            call.set("\(n == Mach.semaphoreSignal ? "semaphore_signal" : "semaphore_signal_all")(\(hx(port(0))))")
            guard let s = semaphore(named: port(0)) else { return kr(KernReturn.invalidName) }
            if s.isDestroyed { return kr(KernReturn.terminated) }
            let waiting = s.waiterCount
            if n == Mach.semaphoreSignal { s.signal() } else { s.signalAll() }
            return kr(KernReturn.success, " [count \(s.count), woke \(n == Mach.semaphoreSignal ? min(waiting, 1) : waiting)]")

        case Mach.semaphoreSignalThread:
            call.set("semaphore_signal_thread(\(hx(port(0))), thread=\(hx(port(1))))")
            guard let s = semaphore(named: port(0)) else { return kr(KernReturn.invalidName) }
            if s.isDestroyed { return kr(KernReturn.terminated) }
            if port(1) == 0 {
                return kr(s.waiters.wake(count: 1) == 1 ? KernReturn.success : KernReturn.notWaiting)
            }
            guard let t = thread(port: port(1)) else { return kr(KernReturn.invalidArgument) }
            return kr(s.signal(thread: t) ? KernReturn.success : KernReturn.notWaiting)

        case Mach.semaphoreWait, Mach.semaphoreTimedwait:
            let timed = n == Mach.semaphoreTimedwait
            call.set(timed
                ? "semaphore_timedwait(\(hx(port(0))), sec=\(UInt32(truncatingIfNeeded: a[1])), nsec=\(Int32(truncatingIfNeeded: a[2])))"
                : "semaphore_wait(\(hx(port(0))))")
            guard let s = semaphore(named: port(0)) else { return kr(KernReturn.invalidName) }
            let r = s.wait(lock: lock, deadline: timed ? timeout(a[1], a[2]) : nil)
            return kr(r, " [count \(s.count)]")

        case Mach.semaphoreWaitSignal, Mach.semaphoreTimedwaitSignal:
            let timed = n == Mach.semaphoreTimedwaitSignal
            call.set(timed
                ? "semaphore_timedwait_signal(wait=\(hx(port(0))), signal=\(hx(port(1))), sec=\(UInt32(truncatingIfNeeded: a[2])), nsec=\(Int32(truncatingIfNeeded: a[3])))"
                : "semaphore_wait_signal(wait=\(hx(port(0))), signal=\(hx(port(1))))")
            guard let w = semaphore(named: port(0)), let s = semaphore(named: port(1)) else {
                return kr(KernReturn.invalidName)
            }
            if s.isDestroyed { return kr(KernReturn.terminated) }
            let r = w.wait(lock: lock, deadline: timed ? timeout(a[2], a[3]) : nil, beforeSleeping: { s.signal() })
            return kr(r, " [count \(w.count)]")

        default:
            return nil
        }
    }
}
