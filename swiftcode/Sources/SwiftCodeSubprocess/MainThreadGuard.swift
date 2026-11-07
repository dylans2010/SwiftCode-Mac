import Foundation

public enum MainThreadGuard {
    public struct Violation: Sendable, CustomStringConvertible {
        public var operation: String
        public var location: String
        public var stack: [String]
        public var description: String { "\(operation) at \(location)" }
    }

    public enum Mode: String, Sendable {
        case off, log, trap
    }

    public static let mode: Mode = {
        #if DEBUG
        return ProcessInfo.processInfo.environment["SWIFTCODE_MAIN_THREAD_GUARD"].flatMap(Mode.init(rawValue:)) ?? .off
        #else
        return .off
        #endif
    }()

    private static let lock = NSLock()
    nonisolated(unsafe) private static var recorders = 0
    nonisolated(unsafe) private static var recorded: [Violation] = []

    @inline(__always)
    public static func blockingCall(_ operation: @autoclosure () -> String, fileID: StaticString = #fileID, line: UInt = #line) {
        #if DEBUG
        guard Thread.isMainThread else { return }
        report(operation(), location: "\(fileID):\(line)")
        #endif
    }

    #if DEBUG
    private static func report(_ operation: String, location: String) {
        lock.lock()
        let recording = recorders > 0
        lock.unlock()
        guard recording || mode != .off else { return }
        let v = Violation(operation: operation, location: location, stack: Array(Thread.callStackSymbols.dropFirst(2)))
        if recording {
            lock.lock()
            recorded.append(v)
            lock.unlock()
        }
        guard mode != .off else { return }
        let text = "SwiftCode main-thread guard: blocking call on the main thread: \(v)\n" + v.stack.map { "    \($0)\n" }.joined()
        FileHandle.standardError.write(Data(text.utf8))
        if mode == .trap { fatalError("blocking call on the main thread: \(v)") }
    }
    #endif

    public static func violations(during body: () throws -> Void) rethrows -> [Violation] {
        lock.lock()
        if recorders == 0 { recorded = [] }
        recorders += 1
        lock.unlock()
        defer {
            lock.lock()
            recorders -= 1
            lock.unlock()
        }
        let start: Int = { lock.lock(); defer { lock.unlock() }; return recorded.count }()
        try body()
        lock.lock()
        defer { lock.unlock() }
        return Array(recorded[start...])
    }
}
