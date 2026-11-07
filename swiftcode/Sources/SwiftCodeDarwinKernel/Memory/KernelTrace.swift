#if canImport(Glibc)
import Glibc
#elseif canImport(Darwin)
import Darwin
#endif

public enum KernelTrace {
    nonisolated(unsafe) public static var wake: ((_ wakee: ThreadContext?) -> Void)?
    nonisolated(unsafe) public static var blocking: ((_ context: ThreadContext, _ sleeping: Bool) -> Void)?
    nonisolated(unsafe) public static var timerFired: ((_ pid: Int32, _ late: UInt64, _ kind: Int32) -> Void)?
    nonisolated(unsafe) public static var lockWaited: ((_ level: Int32, _ waited: UInt64) -> Void)?
}

extension DarwinKernel {
    static let timerThreadL0 = getenv("SWIFTCODE_TIMER_L0").map { String(cString: $0) == "1" } ?? false

    var timerThreadOnEventLock: Bool { eventLock != nil && !Self.timerThreadL0 }
}
