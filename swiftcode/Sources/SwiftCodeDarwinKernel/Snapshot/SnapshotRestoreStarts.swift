import Foundation

public final class SnapshotRestoreStartGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var released = false

    public init() {}

    public func waitForRelease() {
        condition.lock()
        while !released { condition.wait() }
        condition.unlock()
    }

    public func release() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }

    public var isReleased: Bool {
        condition.lock()
        defer { condition.unlock() }
        return released
    }

    public struct Starts<T> {
        public var started: [(thread: T, vcpu: Int)] = []
        public var skipped: [T] = []
    }

    public static func startAll<T>(_ threads: [T], start: (T) throws -> Int?, processEnded: (T) -> Bool,
                                   describe: (T) -> String) throws -> Starts<T> {
        var out = Starts<T>()
        for t in threads {
            if processEnded(t) {
                out.skipped.append(t)
                continue
            }
            if let index = try start(t) {
                out.started.append((t, index))
            } else if processEnded(t) {
                out.skipped.append(t)
            } else {
                throw SnapshotError(describe(t))
            }
        }
        return out
    }
}
