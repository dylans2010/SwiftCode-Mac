#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif
import Synchronization

public protocol GuestThreadGated: AnyObject {
    var gate: GuestThreadGate { get }
}

public final class GuestThreadGate: @unchecked Sendable {
    public enum ParkPoint: UInt8, Sendable, CustomStringConvertible {
        case start
        case guest
        case trapEntry
        case afterTrap

        public var description: String {
            switch self {
            case .start: "start"
            case .guest: "guest"
            case .trapEntry: "trap entry"
            case .afterTrap: "after trap"
            }
        }
    }

    private static let closedBit: UInt8 = 1
    private static let replacementBit: UInt8 = 2
    private static let stepBit: UInt8 = 4
    private static let flushBit: UInt8 = 8

    private let flags = Atomic<UInt8>(0)
    public let attached = Atomic<Bool>(false)
    public let parkCount = Atomic<UInt64>(0)

    private let mutex: UnsafeMutablePointer<pthread_mutex_t>
    private let cond: UnsafeMutablePointer<pthread_cond_t>
    private var parkedFrame: TrapFrame?
    private var parkedAt = ParkPoint.guest
    private var parkedChanged = false
    private var replacement: TrapFrame?
    private var released = false

    public init() {
        mutex = .allocate(capacity: 1)
        mutex.initialize(to: pthread_mutex_t())
        pthread_mutex_init(mutex, nil)
        cond = .allocate(capacity: 1)
        cond.initialize(to: pthread_cond_t())
        #if canImport(Glibc)
        var attr = pthread_condattr_t()
        pthread_condattr_init(&attr)
        pthread_condattr_setclock(&attr, CLOCK_MONOTONIC)
        pthread_cond_init(cond, &attr)
        pthread_condattr_destroy(&attr)
        #else
        pthread_cond_init(cond, nil)
        #endif
    }

    deinit {
        pthread_cond_destroy(cond)
        cond.deallocate()
        pthread_mutex_destroy(mutex)
        mutex.deallocate()
    }

    @inline(__always) private func locked<T>(_ body: () throws -> T) rethrows -> T {
        pthread_mutex_lock(mutex)
        defer { pthread_mutex_unlock(mutex) }
        return try body()
    }

    @inline(__always) public var needsAttention: Bool { flags.load(ordering: .relaxed) != 0 }

    @inline(__always) public var isClosed: Bool { flags.load(ordering: .acquiring) & Self.closedBit != 0 }

    public func close() {
        locked { _ = flags.bitwiseOr(Self.closedBit, ordering: .sequentiallyConsistent) }
    }

    public func open() {
        locked {
            _ = flags.bitwiseAnd(~Self.closedBit, ordering: .sequentiallyConsistent)
            pthread_cond_broadcast(cond)
        }
    }

    public func release() {
        locked {
            released = true
            pthread_cond_broadcast(cond)
        }
    }

    public var parked: (frame: TrapFrame, at: ParkPoint)? {
        locked { parkedFrame.map { ($0, parkedAt) } }
    }

    public var pendingReplacement: TrapFrame? { locked { replacement } }

    public func modifyParked(_ body: (inout TrapFrame) -> Void) -> Bool {
        locked {
            guard var f = parkedFrame, parkedAt != .trapEntry else { return false }
            body(&f)
            parkedFrame = f
            parkedChanged = true
            return true
        }
    }

    public func setReplacement(_ frame: TrapFrame) {
        locked {
            replacement = frame
            _ = flags.bitwiseOr(Self.replacementBit, ordering: .sequentiallyConsistent)
        }
    }

    public func waitUntilParked(deadline: UInt64) -> Bool {
        locked {
            while parkedFrame == nil {
                if Self.wait(cond, mutex, deadline: deadline) == ETIMEDOUT { break }
            }
            return parkedFrame != nil
        }
    }

    public func park(_ frame: TrapFrame, at point: ParkPoint) -> TrapFrame? {
        locked {
            guard !released, flags.load(ordering: .relaxed) & Self.closedBit != 0 else { return nil }
            parkedFrame = frame
            parkedAt = point
            parkedChanged = false
            parkCount.wrappingAdd(1, ordering: .relaxed)
            pthread_cond_broadcast(cond)
            while !released, flags.load(ordering: .relaxed) & Self.closedBit != 0 {
                pthread_cond_wait(cond, mutex)
            }
            let changed = parkedChanged ? parkedFrame : nil
            parkedFrame = nil
            parkedChanged = false
            return changed
        }
    }

    public func requestStep() {
        locked { _ = flags.bitwiseOr(Self.stepBit, ordering: .sequentiallyConsistent) }
    }

    public func cancelStep() {
        locked { _ = flags.bitwiseAnd(~Self.stepBit, ordering: .sequentiallyConsistent) }
    }

    public func takeStepRequest() -> Bool {
        guard flags.load(ordering: .acquiring) & Self.stepBit != 0 else { return false }
        return locked { flags.bitwiseAnd(~Self.stepBit, ordering: .sequentiallyConsistent).oldValue & Self.stepBit != 0 }
    }

    public func requestFlush() {
        locked { _ = flags.bitwiseOr(Self.flushBit, ordering: .sequentiallyConsistent) }
    }

    public func takeFlushRequest() -> Bool {
        guard flags.load(ordering: .acquiring) & Self.flushBit != 0 else { return false }
        return locked { flags.bitwiseAnd(~Self.flushBit, ordering: .sequentiallyConsistent).oldValue & Self.flushBit != 0 }
    }

    public func takeReplacement() -> TrapFrame? {
        guard flags.load(ordering: .acquiring) & Self.replacementBit != 0 else { return nil }
        return locked {
            _ = flags.bitwiseAnd(~Self.replacementBit, ordering: .sequentiallyConsistent)
            defer { replacement = nil }
            return replacement
        }
    }

    private static func wait(_ cond: UnsafeMutablePointer<pthread_cond_t>, _ mutex: UnsafeMutablePointer<pthread_mutex_t>,
                             deadline: UInt64) -> Int32 {
        var now = timespec()
        clock_gettime(CLOCK_MONOTONIC, &now)
        let nowNs = UInt64(now.tv_sec) * 1_000_000_000 + UInt64(now.tv_nsec)
        if nowNs >= deadline { return ETIMEDOUT }
        #if canImport(Darwin)
        let remaining = deadline - nowNs
        var ts = timespec(tv_sec: Int(remaining / 1_000_000_000), tv_nsec: Int(remaining % 1_000_000_000))
        return pthread_cond_timedwait_relative_np(cond, mutex, &ts)
        #else
        var ts = timespec(tv_sec: Int(deadline / 1_000_000_000), tv_nsec: Int(deadline % 1_000_000_000))
        return pthread_cond_timedwait(cond, mutex, &ts)
        #endif
    }

    public static func now() -> UInt64 {
        var t = timespec()
        clock_gettime(CLOCK_MONOTONIC, &t)
        return UInt64(t.tv_sec) * 1_000_000_000 + UInt64(t.tv_nsec)
    }
}

extension TrapFrame {
    public mutating func takeUserState(of other: TrapFrame) {
        x = other.x
        spEL0 = other.spEL0
        elr = other.elr
        spsr = (spsr & ~UInt64(0xF000_0000)) | (other.spsr & 0xF000_0000)
    }
}
